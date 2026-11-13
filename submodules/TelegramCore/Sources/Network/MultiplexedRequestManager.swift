import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

enum MultiplexedRequestTarget: Equatable, Hashable, CustomStringConvertible {
    case main(Int)
    case cdn(Int)
    
    var description: String {
        switch self {
        case let .main(id):
            return "dc\(id)"
        case let .cdn(id):
            return "cdn\(id)"
        }
    }
}

private struct MultiplexedRequestTargetKey: Equatable, Hashable {
    let target: MultiplexedRequestTarget
    let continueInBackground: Bool
}

private final class RequestData {
    let id: Int32
    let consumerId: Int64
    let resourceId: String?
    let target: MultiplexedRequestTarget
    let functionDescription: FunctionDescription
    let payload: Buffer
    let tag: MediaResourceFetchTag?
    let continueInBackground: Bool
    let automaticFloodWait: Bool
    let onFloodWaitError: ((String) -> Void)?
    let expectedResponseSize: Int32?
    let deserializeResponse: (Buffer) -> Any?
    let completed: (Any, NetworkResponseInfo) -> Void
    let error: (MTRpcError, Double) -> Void
    // SuperGram: request lane (-1 background, 0 default, 1 elevated, 2 maximum); effectivePriority also includes pushPriority
    let priority: Int
    var effectivePriority: Int
    var isStarted: Bool = false
    var isCancelled: Bool = false

    init(id: Int32, consumerId: Int64, resourceId: String?, target: MultiplexedRequestTarget, functionDescription: FunctionDescription, payload: Buffer, tag: MediaResourceFetchTag?, continueInBackground: Bool, automaticFloodWait: Bool, onFloodWaitError: ((String) -> Void)?, expectedResponseSize: Int32?, priority: Int, deserializeResponse: @escaping (Buffer) -> Any?, completed: @escaping (Any, NetworkResponseInfo) -> Void, error: @escaping (MTRpcError, Double) -> Void) {
        self.id = id
        self.consumerId = consumerId
        self.resourceId = resourceId
        self.target = target
        self.functionDescription = functionDescription
        self.tag = tag
        self.continueInBackground = continueInBackground
        self.automaticFloodWait = automaticFloodWait
        self.onFloodWaitError = onFloodWaitError
        self.expectedResponseSize = expectedResponseSize
        self.payload = payload
        self.priority = priority
        self.effectivePriority = priority
        self.deserializeResponse = deserializeResponse
        self.completed = completed
        self.error = error
    }
}

private final class ExecutingRequestData {
    let requestId: Int32
    let disposable: Disposable
    
    init(requestId: Int32, disposable: Disposable) {
        self.requestId = requestId
        self.disposable = disposable
    }
}

private final class RequestTargetContext {
    let id: Int32
    let worker: Download
    var requests: [ExecutingRequestData]
    
    init(id: Int32, worker: Download) {
        self.id = id
        self.worker = worker
        self.requests = []
    }
}

private struct MultiplexedRequestTargetTimerKey: Equatable, Hashable {
    let key: MultiplexedRequestTargetKey
    let id: Int32
}

private typealias SignalKitTimer = SwiftSignalKit.Timer

struct NetworkResponseInfo {
    var timestamp: Double
    var networkType: NetworkStatsContext.NetworkType
    var networkDuration: Double
}

private final class MultiplexedRequestManagerContext {
    final class RequestManagerPriorityContext {
        var resourceCounters: [String: Bag<Int>] = [:]
        // SuperGram: max pushed priority per resource, maintained on push/pop instead of per comparison
        var resourceMaxPriorities: [String: Int] = [:]

        func updateMaxPriority(resourceId: String) {
            if let counters = self.resourceCounters[resourceId], let maxPriority = counters.copyItems().max() {
                self.resourceMaxPriorities[resourceId] = maxPriority
            } else {
                self.resourceMaxPriorities.removeValue(forKey: resourceId)
            }
        }
    }
    
    private let queue: Queue
    private let takeWorker: (MultiplexedRequestTarget, MediaResourceFetchTag?, Bool) -> Download?
    
    private let priorityContext = RequestManagerPriorityContext()
    private var queuedRequests: [RequestData] = []
    private var nextId: Int32 = 0
    
    private var targetContexts: [MultiplexedRequestTargetKey: [RequestTargetContext]] = [:]
    private var emptyTargetDisposables: [MultiplexedRequestTargetTimerKey: Disposable] = [:]
    
    init(queue: Queue, takeWorker: @escaping (MultiplexedRequestTarget, MediaResourceFetchTag?, Bool) -> Download?) {
        self.queue = queue
        self.takeWorker = takeWorker
    }
    
    deinit {
        for targetContextList in self.targetContexts.values {
            for targetContext in targetContextList {
                for request in targetContext.requests {
                    request.disposable.dispose()
                }
            }
        }
        for disposable in emptyTargetDisposables.values {
            disposable.dispose()
        }
    }
    
    func pushPriority(resourceId: String, priority: Int) -> Disposable {
        let queue = self.queue
        
        let counters: Bag<Int>
        if let current = self.priorityContext.resourceCounters[resourceId] {
            counters = current
        } else {
            counters = Bag()
            self.priorityContext.resourceCounters[resourceId] = counters
        }
        
        let index = counters.add(priority)
        self.priorityContext.updateMaxPriority(resourceId: resourceId)
        self.updateQueuedRequestPriorities(resourceId: resourceId)

        self.updateState()

        return ActionDisposable { [weak self, weak counters] in
            queue.async {
                guard let `self` = self else {
                    return
                }

                if let current = self.priorityContext.resourceCounters[resourceId], current === counters {
                    current.remove(index)
                    if current.isEmpty {
                        self.priorityContext.resourceCounters.removeValue(forKey: resourceId)
                    }
                    self.priorityContext.updateMaxPriority(resourceId: resourceId)
                    self.updateQueuedRequestPriorities(resourceId: resourceId)
                    self.updateState()
                }
            }
        }
    }

    private func effectivePriority(resourceId: String?, priority: Int) -> Int {
        if !self.priorityContext.resourceMaxPriorities.isEmpty, let resourceId, let pushedPriority = self.priorityContext.resourceMaxPriorities[resourceId], pushedPriority > priority {
            return pushedPriority
        }
        return priority
    }

    private func updateQueuedRequestPriorities(resourceId: String) {
        for request in self.queuedRequests {
            if request.resourceId == resourceId {
                request.effectivePriority = self.effectivePriority(resourceId: resourceId, priority: request.priority)
            }
        }
    }
    
    func request(to target: MultiplexedRequestTarget, consumerId: Int64, resourceId: String?, data: (FunctionDescription, Buffer, (Buffer) -> Any?), tag: MediaResourceFetchTag?, continueInBackground: Bool, automaticFloodWait: Bool, onFloodWaitError: ((String) -> Void)? = nil, expectedResponseSize: Int32?, priority: Int = 0, completed: @escaping (Any, NetworkResponseInfo) -> Void, error: @escaping (MTRpcError, Double) -> Void) -> Disposable {
        let targetKey = MultiplexedRequestTargetKey(target: target, continueInBackground: continueInBackground)

        let requestId = self.nextId
        self.nextId += 1
        let requestData = RequestData(id: requestId, consumerId: consumerId, resourceId: resourceId, target: target, functionDescription: data.0, payload: data.1, tag: tag, continueInBackground: continueInBackground, automaticFloodWait: automaticFloodWait, onFloodWaitError: onFloodWaitError, expectedResponseSize: expectedResponseSize, priority: priority, deserializeResponse: { buffer in
            return data.2(buffer)
        }, completed: { result, info in
            completed(result, info)
        }, error: { e, timestamp in
            error(e, timestamp)
        })
        requestData.effectivePriority = self.effectivePriority(resourceId: resourceId, priority: priority)
        self.queuedRequests.append(requestData)

        self.updateState()

        let queue = self.queue
        return ActionDisposable { [weak self] in
            queue.async {
                guard let strongSelf = self else {
                    return
                }
                for i in 0 ..< strongSelf.queuedRequests.count {
                    if strongSelf.queuedRequests[i].id == requestId {
                        strongSelf.queuedRequests[i].isCancelled = true
                        strongSelf.queuedRequests.remove(at: i)
                        break
                    }
                }
                
                if strongSelf.targetContexts[targetKey] != nil {
                    outer: for targetContext in strongSelf.targetContexts[targetKey]! {
                        for i in 0 ..< targetContext.requests.count {
                            if targetContext.requests[i].requestId == requestId {
                                targetContext.requests[i].disposable.dispose()
                                targetContext.requests.remove(at: i)
                                break outer
                            }
                        }
                    }
                }
                
                strongSelf.updateState()
            }
        }
    }
    
    private func updateState() {
        // SuperGram: faster download speed modes use more parallel requests per connection and more
        // connections per datacenter (fewer round-trip bottlenecks on high-latency links)
        let maxRequestsPerWorker: Int
        let maxWorkersPerTarget: Int
        switch MediaDownloadRuntimeSettings.speedMode {
        case .standard:
            maxRequestsPerWorker = 3
            maxWorkersPerTarget = 4
        case .fast:
            maxRequestsPerWorker = 4
            maxWorkersPerTarget = 4
        case .maximum:
            maxRequestsPerWorker = 5
            maxWorkersPerTarget = 6
        }
        // SuperGram: request slots of every target that background-lane requests may not occupy,
        // so playback and user-initiated parts never wait behind a full target of preload parts
        let reservedNonBackgroundRequestsPerTarget = maxRequestsPerWorker

        if self.queuedRequests.isEmpty {
            self.checkEmptyContexts()
            return
        }

        // SuperGram: priority lanes instead of sorting the whole queue on every event. Requests are kept in FIFO
        // (id) order; walk the queue once per distinct priority, highest first, skipping saturated targets.
        var priorityLevels: [Int] = []
        for request in self.queuedRequests {
            if !priorityLevels.contains(request.effectivePriority) {
                priorityLevels.append(request.effectivePriority)
            }
        }
        if priorityLevels.count > 1 {
            priorityLevels.sort(by: >)
        }

        var saturatedTargets = Set<MultiplexedRequestTargetKey>()
        // SuperGram: targets for which no worker could ever be created — see the takeWorker failure below.
        var unroutableTargets = Set<MultiplexedRequestTargetKey>()
        var startedRequestCount = 0

        for priorityLevel in priorityLevels {
            for request in self.queuedRequests {
                if request.effectivePriority != priorityLevel || request.isStarted || request.isCancelled {
                    continue
                }

                let targetKey = MultiplexedRequestTargetKey(target: request.target, continueInBackground: request.continueInBackground)
                if !saturatedTargets.isEmpty && saturatedTargets.contains(targetKey) {
                    continue
                }

                if self.targetContexts[targetKey] == nil {
                    self.targetContexts[targetKey] = []
                }

                if priorityLevel < 0 {
                    var executingCount = 0
                    for targetContext in self.targetContexts[targetKey]! {
                        executingCount += targetContext.requests.count
                    }
                    if executingCount >= maxRequestsPerWorker * maxWorkersPerTarget - reservedNonBackgroundRequestsPerTarget {
                        // Levels are visited in descending order, so every remaining request for this target is background too
                        saturatedTargets.insert(targetKey)
                        continue
                    }
                }

                var selectedContext: RequestTargetContext?
                for targetContext in self.targetContexts[targetKey]! {
                    if targetContext.requests.count < maxRequestsPerWorker {
                        selectedContext = targetContext
                        break
                    }
                }
                if selectedContext == nil && self.targetContexts[targetKey]!.count < maxWorkersPerTarget {
                    if let worker = self.takeWorker(request.target, request.tag, request.continueInBackground) {
                        let contextId = self.nextId
                        self.nextId += 1
                        let targetContext = RequestTargetContext(id: contextId, worker: worker)
                        self.targetContexts[targetKey]!.append(targetContext)
                        selectedContext = targetContext
                    } else {
                        Logger.shared.log("MultiplexedRequestManager", "couldn't take worker for \(request.target)")
                        // SuperGram: takeWorker only returns nil for a target that can never be routed
                        // (datacenterId == 0 — a malformed resource) or for a Network that is being torn down.
                        // Leaving the request in queuedRequests meant it sat there for the rest of the session:
                        // no response, no error, and the FetchV2 part that issued it held its budget slot the
                        // whole time, so the media item spun forever. Fail it instead — the fetch then reports
                        // an error, MediaBox resets cleanly and FetchManager retries with backoff.
                        // Only when there is no worker at all for this target: if some already exist they are
                        // merely full, and the request will be served on a later pass.
                        if self.targetContexts[targetKey]!.isEmpty {
                            unroutableTargets.insert(targetKey)
                        }
                    }
                }
                guard let selectedContext = selectedContext else {
                    saturatedTargets.insert(targetKey)
                    continue
                }

                request.isStarted = true
                startedRequestCount += 1

                let disposable = MetaDisposable()
                let requestId = request.id
                selectedContext.requests.append(ExecutingRequestData(requestId: requestId, disposable: disposable))
                let queue = self.queue
                disposable.set(selectedContext.worker.rawRequest((request.functionDescription, request.payload, request.deserializeResponse), automaticFloodWait: request.automaticFloodWait, onFloodWaitError: request.onFloodWaitError, expectedResponseSize: request.expectedResponseSize).start(next: { [weak self, weak selectedContext] result, info in
                    queue.async {
                        guard let strongSelf = self else {
                            return
                        }
                        if let selectedContext = selectedContext {
                            for i in 0 ..< selectedContext.requests.count {
                                if selectedContext.requests[i].requestId == requestId {
                                    selectedContext.requests.remove(at: i)
                                    break
                                }
                            }
                        }
                        request.completed(result, info)
                        strongSelf.updateState()
                    }
                }, error: { [weak self, weak selectedContext] error, timestamp in
                    queue.async {
                        guard let strongSelf = self else {
                            return
                        }
                        request.error(error, timestamp)
                        if let selectedContext = selectedContext {
                            for i in 0 ..< selectedContext.requests.count {
                                if selectedContext.requests[i].requestId == requestId {
                                    selectedContext.requests.remove(at: i)
                                    break
                                }
                            }
                        }
                        strongSelf.updateState()
                    }
                }))
            }
        }

        if startedRequestCount != 0 {
            self.queuedRequests.removeAll(where: { $0.isStarted })
        }

        if !unroutableTargets.isEmpty {
            var failedRequests: [RequestData] = []
            for request in self.queuedRequests {
                if request.isStarted || request.isCancelled {
                    continue
                }
                if unroutableTargets.contains(MultiplexedRequestTargetKey(target: request.target, continueInBackground: request.continueInBackground)) {
                    failedRequests.append(request)
                }
            }
            if !failedRequests.isEmpty {
                let failedIds = Set(failedRequests.map({ $0.id }))
                self.queuedRequests.removeAll(where: { failedIds.contains($0.id) })

                let timestamp = CFAbsoluteTimeGetCurrent()
                // Dispatched rather than called inline: the error handlers run consumer code that may call
                // straight back into updateState(), and this is the middle of updateState().
                self.queue.justDispatch {
                    for request in failedRequests {
                        request.error(MTRpcError(errorCode: 500, errorDescription: "NETWORK_NO_WORKER"), timestamp)
                    }
                }
            }
        }

        self.checkEmptyContexts()
    }
    
    private func checkEmptyContexts() {
        for (targetKey, contexts) in self.targetContexts {
            for context in contexts {
                let key = MultiplexedRequestTargetTimerKey(key: targetKey, id: context.id)
                if context.requests.isEmpty {
                    if self.emptyTargetDisposables[key] == nil {
                        let disposable = MetaDisposable()
                        self.emptyTargetDisposables[key] = disposable
                        
                        disposable.set((Signal<Never, NoError>.complete()
                        |> delay(20 * 60, queue: self.queue)
                        |> deliverOn(self.queue)).start(completed: { [weak self] in
                            guard let strongSelf = self else {
                                return
                            }
                            strongSelf.emptyTargetDisposables.removeValue(forKey: key)
                            if strongSelf.targetContexts[targetKey] != nil {
                                for i in 0 ..< strongSelf.targetContexts[targetKey]!.count {
                                    if strongSelf.targetContexts[targetKey]![i].id == key.id {
                                        strongSelf.targetContexts[targetKey]!.remove(at: i)
                                        break
                                    }
                                }
                            }
                        }))
                    }
                } else {
                    if let disposable = self.emptyTargetDisposables[key] {
                        disposable.dispose()
                        self.emptyTargetDisposables.removeValue(forKey: key)
                    }
                }
            }
        }
    }
}

final class MultiplexedRequestManager {
    private let queue = Queue()
    private let context: QueueLocalObject<MultiplexedRequestManagerContext>
    
    init(takeWorker: @escaping (MultiplexedRequestTarget, MediaResourceFetchTag?, Bool) -> Download?) {
        let queue = self.queue
        self.context = QueueLocalObject(queue: self.queue, generate: {
            return MultiplexedRequestManagerContext(queue: queue, takeWorker: takeWorker)
        })
    }
    
    func pushPriority(resourceId: String, priority: Int) -> Disposable {
        let disposable = MetaDisposable()
        self.context.with { context in
            disposable.set(context.pushPriority(resourceId: resourceId, priority: priority))
        }
        return disposable
    }
    
    func request<T>(to target: MultiplexedRequestTarget, consumerId: Int64, resourceId: String?, data: (FunctionDescription, Buffer, DeserializeFunctionResponse<T>), tag: MediaResourceFetchTag?, continueInBackground: Bool, automaticFloodWait: Bool = true, onFloodWaitError: ((String) -> Void)? = nil, expectedResponseSize: Int32?, priority: Int = 0) -> Signal<T, MTRpcError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.context.with { context in
                disposable.set(context.request(to: target, consumerId: consumerId, resourceId: resourceId, data: (data.0, data.1, { buffer in
                    return data.2.parse(buffer)
                }), tag: tag, continueInBackground: continueInBackground, automaticFloodWait: automaticFloodWait, onFloodWaitError: onFloodWaitError, expectedResponseSize: expectedResponseSize, priority: priority, completed: { result, _ in
                    if let result = result as? T {
                        subscriber.putNext(result)
                        subscriber.putCompletion()
                    } else {
                        subscriber.putError(MTRpcError(errorCode: 500, errorDescription: "TL_VERIFICATION_ERROR"))
                    }
                }, error: { error, _ in
                    subscriber.putError(error)
                }))
            }
            return disposable
        }
    }
    
    func requestWithAdditionalInfo<T>(to target: MultiplexedRequestTarget, consumerId: Int64, resourceId: String?, data: (FunctionDescription, Buffer, DeserializeFunctionResponse<T>), tag: MediaResourceFetchTag?, continueInBackground: Bool, automaticFloodWait: Bool = true, onFloodWaitError: ((String) -> Void)? = nil, expectedResponseSize: Int32?, priority: Int = 0) -> Signal<(T, NetworkResponseInfo), (MTRpcError, Double)> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.context.with { context in
                disposable.set(context.request(to: target, consumerId: consumerId, resourceId: resourceId, data: (data.0, data.1, { buffer in
                    return data.2.parse(buffer)
                }), tag: tag, continueInBackground: continueInBackground, automaticFloodWait: automaticFloodWait, onFloodWaitError: onFloodWaitError, expectedResponseSize: expectedResponseSize, priority: priority, completed: { result, info in
                    if let result = result as? T {
                        subscriber.putNext((result, info))
                        subscriber.putCompletion()
                    } else {
                        subscriber.putError((MTRpcError(errorCode: 500, errorDescription: "TL_VERIFICATION_ERROR"), info.timestamp))
                    }
                }, error: { error, timestamp in
                    subscriber.putError((error, timestamp))
                }))
            }
            return disposable
        }
    }
}
