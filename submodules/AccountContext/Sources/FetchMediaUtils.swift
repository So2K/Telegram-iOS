import Foundation
import UIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramUIPreferences
import RangeSet

// SuperGram: `isInteractive` puts the fetch in the FetchV2 interactive part lane instead of the much smaller
// background lane. It defaults to `true` here because every caller of these `…InteractiveFetched` helpers is a
// view that is on screen right now (the name is not decoration) — a *missing* annotation should degrade to
// "downloads faster than it needed to", never to "spins forever behind a 4-part global lane". The handful of
// genuinely background callers (preloading a sticker for a chat the user has not opened) pass `false`.
public func freeMediaFileInteractiveFetched(account: Account, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, isInteractive: Bool = true) -> Signal<FetchResourceSourceType, FetchResourceError> {
    return fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: userLocation, userContentType: MediaResourceUserContentType(file: fileReference.media), reference: fileReference.resourceReference(fileReference.media.resource), isInteractive: isInteractive)
}

public func freeMediaFileInteractiveFetched(fetchManager: FetchManager, fileReference: FileMediaReference, priority: FetchManagerPriority) -> Signal<Void, NoError> {
    let file = fileReference.media
    let mediaReference = AnyMediaReference.standalone(media: fileReference.media)
    return fetchManager.interactivelyFetched(category: fetchCategoryForFile(file), location: .chat(PeerId(0)), locationKey: .free, mediaReference: mediaReference, resourceReference: mediaReference.resourceReference(file.resource), ranges: RangeSet<Int64>(0 ..< Int64.max), statsCategory: statsCategoryForFileWithAttributes(file.attributes), elevatedPriority: false, userInitiated: false, priority: priority, storeToDownloadsPeerId: nil)
}

public func freeMediaFileResourceInteractiveFetched(account: Account, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, resource: MediaResource, isInteractive: Bool = true) -> Signal<FetchResourceSourceType, FetchResourceError> {
    return fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: userLocation, userContentType: MediaResourceUserContentType(file: fileReference.media), reference: fileReference.resourceReference(resource), isInteractive: isInteractive)
}

public func freeMediaFileResourceInteractiveFetched(postbox: Postbox, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, resource: MediaResource, range: (Range<Int64>, MediaBoxFetchPriority)? = nil, isInteractive: Bool = true) -> Signal<FetchResourceSourceType, FetchResourceError> {
    return fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: userLocation, userContentType: MediaResourceUserContentType(file: fileReference.media), reference: fileReference.resourceReference(resource), range: range, isInteractive: isInteractive)
}

private func fetchCategoryForFile(_ file: TelegramMediaFile) -> FetchManagerCategory {
    if file.isVoice || file.isInstantVideo {
        return .voice
    } else if file.isAnimated {
        return .animation
    } else {
        return .file
    }
}

public func messageMediaFileInteractiveFetched(context: AccountContext, message: Message, file: TelegramMediaFile, userInitiated: Bool, storeToDownloadsPeerId: EnginePeer.Id? = nil) -> Signal<Void, NoError> {
    return messageMediaFileInteractiveFetched(fetchManager: context.fetchManager, messageId: message.id, messageReference: MessageReference(message), file: file, userInitiated: userInitiated, priority: .userInitiated, storeToDownloadsPeerId: storeToDownloadsPeerId)
}

public func messageMediaFileInteractiveFetched(fetchManager: FetchManager, messageId: MessageId, messageReference: MessageReference, file: TelegramMediaFile, ranges: RangeSet<Int64> = RangeSet<Int64>(0 ..< Int64.max), userInitiated: Bool, priority: FetchManagerPriority, storeToDownloadsPeerId: EnginePeer.Id? = nil) -> Signal<Void, NoError> {
    let mediaReference = AnyMediaReference.message(message: messageReference, media: file)
    return fetchManager.interactivelyFetched(category: fetchCategoryForFile(file), location: .chat(messageId.peerId), locationKey: .messageId(messageId), mediaReference: mediaReference, resourceReference: mediaReference.resourceReference(file.resource), ranges: ranges, statsCategory: statsCategoryForFileWithAttributes(file.attributes), elevatedPriority: false, userInitiated: userInitiated, priority: priority, storeToDownloadsPeerId: storeToDownloadsPeerId)
}

public func messageMediaFileCancelInteractiveFetch(context: AccountContext, messageId: MessageId, file: TelegramMediaFile) {
    context.fetchManager.cancelInteractiveFetches(category: fetchCategoryForFile(file), location: .chat(messageId.peerId), locationKey: .messageId(messageId), resource: file.resource)
}

public func messageMediaImageInteractiveFetched(context: AccountContext, message: Message, image: TelegramMediaImage, resource: MediaResource, range: Range<Int64>? = nil, userInitiated: Bool = true, storeToDownloadsPeerId: EnginePeer.Id?) -> Signal<Void, NoError> {
    return messageMediaImageInteractiveFetched(fetchManager: context.fetchManager, messageId: message.id, messageReference: MessageReference(message), image: image, resource: resource, range: range, userInitiated: userInitiated, priority: .userInitiated, storeToDownloadsPeerId: storeToDownloadsPeerId)
}

public func messageMediaImageInteractiveFetched(fetchManager: FetchManager, messageId: MessageId, messageReference: MessageReference, image: TelegramMediaImage, resource: MediaResource, range: Range<Int64>? = nil, userInitiated: Bool, priority: FetchManagerPriority, storeToDownloadsPeerId: EnginePeer.Id?) -> Signal<Void, NoError> {
    let mediaReference = AnyMediaReference.message(message: messageReference, media: image)
    let ranges: RangeSet<Int64>
    if let range = range {
        ranges = RangeSet(range.lowerBound ..< range.upperBound)
    } else {
        ranges = RangeSet(0 ..< Int64.max)
    }
    return fetchManager.interactivelyFetched(category: .image, location: .chat(messageId.peerId), locationKey: .messageId(messageId), mediaReference: mediaReference, resourceReference: mediaReference.resourceReference(resource), ranges: ranges, statsCategory: .image, elevatedPriority: false, userInitiated: userInitiated, priority: priority, storeToDownloadsPeerId: storeToDownloadsPeerId)
}

public func messageMediaImageCancelInteractiveFetch(context: AccountContext, messageId: MessageId, image: TelegramMediaImage, resource: MediaResource) {
    context.fetchManager.cancelInteractiveFetches(category: .image, location: .chat(messageId.peerId), locationKey: .messageId(messageId), resource: resource)
}

public func messageMediaFileStatus(context: AccountContext, messageId: MessageId, file: TelegramMediaFile, adjustForVideoThumbnail: Bool = false) -> Signal<MediaResourceStatus, NoError> {
    let fileStatus = context.fetchManager.fetchStatus(category: fetchCategoryForFile(file), location: .chat(messageId.peerId), locationKey: .messageId(messageId), resource: file.resource)
    if !adjustForVideoThumbnail {
        return fileStatus
    }
    
    var thumbnailStatus: Signal<MediaResourceStatus?, NoError> = .single(nil)
    if let videoThumbnail = file.videoThumbnails.first {
        thumbnailStatus = context.engine.resources.status(resource: EngineMediaResource(videoThumbnail.resource))
        |> map { $0._asStatus() }
        |> map(Optional.init)
    }
    
    return combineLatest(queue: context.fetchManager.queue,
        fileStatus,
        thumbnailStatus
    )
    |> map { fileStatus, thumbnailStatus -> MediaResourceStatus in
        guard let thumbnailStatus = thumbnailStatus else {
            return fileStatus
        }
        if case .Local = thumbnailStatus {
            return thumbnailStatus
        } else {
            return fileStatus
        }
    }
    |> distinctUntilChanged
}

public func messageMediaImageStatus(context: AccountContext, messageId: MessageId, image: TelegramMediaImage) -> Signal<MediaResourceStatus, NoError> {
    guard let representation = image.representations.last else {
        return .single(.Remote(progress: 0.0))
    }
    return context.fetchManager.fetchStatus(category: .image, location: .chat(messageId.peerId), locationKey: .messageId(messageId), resource: representation.resource)
}

// SuperGram: last-resort self-heal for media that is stuck showing a download spinner.
//
// Every remaining way a download can wedge ends in the same observable state: something believes a fetch is in
// progress while nothing will ever deliver another byte. Two components hold that belief — MediaBox (a file
// context with a live pending fetch) and FetchManager (an entry occupying a per-category slot, or one in an
// endless retry backoff). Both have to be reset together and in the right order, so the entry point is here
// rather than on either of them.
//
// FetchManagerImpl registers itself as a handler; the diagnostics UI calls `reset` and shows the count. It is a
// registry instead of a method on the `FetchManager` protocol so that adding it does not force every conformer
// (and every module that vends one) to change.
public final class MediaDownloadSelfHeal {
    public static let shared = MediaDownloadSelfHeal()

    // A handler resets the state for one resource id (or for everything, when it is nil) and reports how many
    // resources it actually un-stuck. It is always invoked on the main queue.
    public typealias Handler = (String?, @escaping (Int) -> Void) -> Void

    // Handlers can take a while (they hop to the media data queue and back); do not leave the caller hanging if
    // one of them never reports.
    private static let handlerTimeout: Double = 10.0

    private var handlers: [Int: Handler] = [:]
    private var nextHandlerId: Int = 0

    private init() {
    }

    public func registerHandler(_ handler: @escaping Handler) -> Disposable {
        // `handlers` is main-queue-only state, and callers register from wherever they happen to be constructed.
        let disposable = MetaDisposable()
        Queue.mainQueue().async {
            let id = self.nextHandlerId
            self.nextHandlerId += 1
            self.handlers[id] = handler
            disposable.set(ActionDisposable {
                Queue.mainQueue().async {
                    self.handlers.removeValue(forKey: id)
                }
            })
        }
        return disposable
    }

    /// Resets the fetch state of `resourceId` (or of every resource when it is nil) and reports how many
    /// resources were actually reset. `completion` is called once, on the main queue.
    public func reset(resourceId: String? = nil, completion: @escaping (Int) -> Void) {
        Queue.mainQueue().async {
            let handlers = Array(self.handlers.values)
            if handlers.isEmpty {
                completion(0)
                return
            }

            var pending = handlers.count
            var total = 0
            var didComplete = false
            let report: () -> Void = {
                if didComplete {
                    return
                }
                didComplete = true
                completion(total)
            }

            for handler in handlers {
                var didReport = false
                handler(resourceId, { count in
                    Queue.mainQueue().async {
                        if didReport || didComplete {
                            return
                        }
                        didReport = true
                        total += count
                        pending -= 1
                        if pending == 0 {
                            report()
                        }
                    }
                })
            }

            Queue.mainQueue().after(MediaDownloadSelfHeal.handlerTimeout, {
                report()
            })
        }
    }
}

// SuperGram: bounded concurrency for best-effort media preloads (story preloads, chat list video prefetch).
// All bookkeeping happens on the main queue. Foreground jobs (e.g. the next story in an open viewer) preempt
// background jobs (chat list prefetch) when the shared budget is exhausted; a preempted job is re-queued and
// restarted later (MediaBox keeps the bytes it already has). Limits shrink under MediaDownloadPressure and the
// background lane is paused entirely at .critical.
public final class MediaPreloadGate {
    public enum Lane {
        case foreground
        case background
    }

    public struct Limits {
        public var normal: Int
        public var constrained: Int
        public var critical: Int

        public init(normal: Int, constrained: Int, critical: Int) {
            self.normal = normal
            self.constrained = constrained
            self.critical = critical
        }
    }

    private final class Job {
        let id: Int
        let lane: Lane
        let signal: Signal<Never, NoError>
        let completed: () -> Void
        var disposable: Disposable?
        var startTimestamp: Double = 0.0
        // When the job was first queued. A job that never gets a slot has to give up eventually: its caller
        // (StoryChatContent's preloadStoryResourceDisposables, PrefetchManager's fetchDisposable) treats an
        // un-completed signal as "still in flight" forever, so silent waiting is a leak, not patience.
        var enqueueTimestamp: Double = 0.0
        var isStalled: Bool = false

        init(id: Int, lane: Lane, signal: Signal<Never, NoError>, completed: @escaping () -> Void) {
            self.id = id
            self.lane = lane
            self.signal = signal
            self.completed = completed
        }
    }

    public static let stories = MediaPreloadGate(foregroundLimits: Limits(normal: 3, constrained: 2, critical: 1), backgroundLimits: Limits(normal: 3, constrained: 1, critical: 0))
    public static let chatListVideoPrefetch = MediaPreloadGate(foregroundLimits: Limits(normal: 2, constrained: 1, critical: 0), backgroundLimits: Limits(normal: 2, constrained: 1, critical: 0))

    // A job that runs longer than this no longer occupies a slot (e.g. a stalled network fetch)
    private static let stallTimeout: Double = 30.0
    // SuperGram: a job that has waited this long without ever getting a slot is abandoned — completed without
    // running. These are best-effort preloads; by now whatever they were preloading for has scrolled away, and
    // holding the caller's disposable open forever is strictly worse than not preloading.
    private static let maxWaitTimeout: Double = 60.0
    // SuperGram: hard bound on the queue. Each waiting job retains its signal (and through it the postbox and
    // the resource reference), and chat-list prefetch can enqueue faster than the lanes drain.
    private static let maxWaitingPerLane: Int = 32
    // How often the gate re-evaluates itself while anything is waiting. A job enqueued into a lane that cannot
    // run it is abandoned synchronously in update(), so this only has to cover stall detection and the
    // wait timeout — it does not need to be frequent.
    private static let sweepInterval: Double = MediaPreloadGate.stallTimeout + 0.5

    private let foregroundLimits: Limits
    private let backgroundLimits: Limits

    private var pressureLevel: MediaDownloadPressure.Level = .normal
    private var pressureDisposable: Disposable?
    private var nextJobId: Int = 0
    private var waitingForeground: [Job] = []
    private var waitingBackground: [Job] = []
    private var running: [Job] = []
    private var isStallCheckScheduled: Bool = false

    public init(foregroundLimits: Limits, backgroundLimits: Limits) {
        self.foregroundLimits = foregroundLimits
        self.backgroundLimits = backgroundLimits
    }

    deinit {
        self.pressureDisposable?.dispose()
    }

    public func wrap(lane: Lane, _ signal: Signal<Never, NoError>) -> Signal<Never, NoError> {
        return Signal { [weak self] subscriber in
            guard let self else {
                return signal.start(completed: {
                    subscriber.putCompletion()
                })
            }

            self.ensurePressureSubscription()

            let jobId = self.nextJobId
            self.nextJobId += 1
            let job = Job(id: jobId, lane: lane, signal: signal, completed: {
                subscriber.putCompletion()
            })
            job.enqueueTimestamp = CFAbsoluteTimeGetCurrent()
            switch lane {
            case .foreground:
                self.waitingForeground.append(job)
            case .background:
                self.waitingBackground.append(job)
            }
            self.update()

            return ActionDisposable { [weak self] in
                Queue.mainQueue().async {
                    self?.cancelJob(id: jobId)
                }
            }
        }
        |> runOn(Queue.mainQueue())
    }

    private func ensurePressureSubscription() {
        if self.pressureDisposable != nil {
            return
        }
        self.pressureLevel = MediaDownloadPressure.shared.level
        self.pressureDisposable = (MediaDownloadPressure.shared.levelSignal
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { [weak self] level in
            guard let self else {
                return
            }
            if self.pressureLevel != level {
                self.pressureLevel = level
                self.update()
            }
        })
    }

    private func limit(lane: Lane) -> Int {
        let limits: Limits
        switch lane {
        case .foreground:
            limits = self.foregroundLimits
        case .background:
            limits = self.backgroundLimits
        }
        if self.pressureLevel == .critical {
            return limits.critical
        } else if self.pressureLevel == .constrained || self.pressureLevel == .reduced {
            // SuperGram: `reduced` (Low Power Mode, a brief thermal spike) trims exactly this kind of
            // best-effort preloading — that is the whole point of having it as a separate level.
            return limits.constrained
        } else {
            return limits.normal
        }
    }

    private func countedRunning(lane: Lane?) -> Int {
        var count = 0
        for job in self.running {
            if job.isStalled {
                continue
            }
            if let lane, job.lane != lane {
                continue
            }
            count += 1
        }
        return count
    }

    private func mostRecentRunningJob(lane: Lane) -> Job? {
        for job in self.running.reversed() {
            if job.lane == lane && !job.isStalled {
                return job
            }
        }
        return nil
    }

    private func start(job: Job, timestamp: Double) {
        job.startTimestamp = timestamp
        job.isStalled = false
        self.running.append(job)
        let jobId = job.id
        job.disposable = job.signal.start(completed: { [weak self] in
            Queue.mainQueue().async {
                self?.jobFinished(id: jobId)
            }
        })
    }

    private func suspend(job: Job) {
        job.disposable?.dispose()
        job.disposable = nil
        self.running.removeAll(where: { $0 === job })
        switch job.lane {
        case .foreground:
            self.waitingForeground.insert(job, at: 0)
        case .background:
            self.waitingBackground.insert(job, at: 0)
        }
    }

    private func jobFinished(id: Int) {
        guard let index = self.running.firstIndex(where: { $0.id == id }) else {
            return
        }
        let job = self.running.remove(at: index)
        job.disposable = nil
        job.completed()
        self.update()
    }

    private func cancelJob(id: Int) {
        if let index = self.running.firstIndex(where: { $0.id == id }) {
            let job = self.running.remove(at: index)
            job.disposable?.dispose()
            job.disposable = nil
            self.update()
        } else {
            self.waitingForeground.removeAll(where: { $0.id == id })
            self.waitingBackground.removeAll(where: { $0.id == id })
        }
    }

    // SuperGram: drop waiting jobs that can never usefully run, completing their subscribers.
    //
    // Two ways a job could previously wait forever with no error and no completion:
    //  * its lane's limit is 0 (chatListVideoPrefetch has critical == 0 on *both* lanes), so update() started
    //    nothing, `running` stayed empty and the self-heal timer — armed only when `running` was non-empty —
    //    was never scheduled. Recovery depended entirely on a lower pressure level arriving;
    //  * the background lane is blocked behind a non-empty foreground queue indefinitely.
    // Either way the caller's disposable stayed live forever. These are best-effort preloads: giving up is a
    // correct outcome, hanging is not.
    private func abandonUnrunnableWaitingJobs(timestamp: Double) {
        var abandoned: [Job] = []

        for lane in [Lane.foreground, Lane.background] {
            let laneLimit = self.limit(lane: lane)
            var remaining: [Job] = []
            let waiting: [Job]
            switch lane {
            case .foreground:
                waiting = self.waitingForeground
            case .background:
                waiting = self.waitingBackground
            }
            for job in waiting {
                if laneLimit <= 0 || timestamp - job.enqueueTimestamp >= MediaPreloadGate.maxWaitTimeout {
                    abandoned.append(job)
                } else {
                    remaining.append(job)
                }
            }
            // Bound the queue: the oldest entries are the least likely to still be worth preloading.
            while remaining.count > MediaPreloadGate.maxWaitingPerLane {
                abandoned.append(remaining.removeFirst())
            }
            switch lane {
            case .foreground:
                self.waitingForeground = remaining
            case .background:
                self.waitingBackground = remaining
            }
        }

        for job in abandoned {
            job.completed()
        }
    }

    private func update() {
        let timestamp = CFAbsoluteTimeGetCurrent()

        for job in self.running {
            if !job.isStalled && timestamp - job.startTimestamp > MediaPreloadGate.stallTimeout {
                job.isStalled = true
            }
        }

        self.abandonUnrunnableWaitingJobs(timestamp: timestamp)

        let foregroundLimit = self.limit(lane: .foreground)
        let backgroundLimit = self.limit(lane: .background)
        let totalLimit = max(foregroundLimit, backgroundLimit)

        // Shed jobs above the (possibly reduced) limits, background first
        while self.countedRunning(lane: .background) > backgroundLimit, let job = self.mostRecentRunningJob(lane: .background) {
            self.suspend(job: job)
        }
        while self.countedRunning(lane: .foreground) > foregroundLimit, let job = self.mostRecentRunningJob(lane: .foreground) {
            self.suspend(job: job)
        }

        while !self.waitingForeground.isEmpty && self.countedRunning(lane: .foreground) < foregroundLimit {
            if self.countedRunning(lane: nil) >= totalLimit {
                guard let backgroundJob = self.mostRecentRunningJob(lane: .background) else {
                    break
                }
                self.suspend(job: backgroundJob)
            }
            let job = self.waitingForeground.removeFirst()
            self.start(job: job, timestamp: timestamp)
        }

        while !self.waitingBackground.isEmpty && self.countedRunning(lane: .background) < backgroundLimit && self.countedRunning(lane: nil) < totalLimit {
            if !self.waitingForeground.isEmpty {
                break
            }
            let job = self.waitingBackground.removeFirst()
            self.start(job: job, timestamp: timestamp)
        }

        // SuperGram: arm the sweep whenever anything is *waiting*, not only when something is also running.
        // The old condition (`!running.isEmpty && …`) was exactly backwards for the case that mattered: at
        // critical pressure nothing runs, so no timer was ever armed and the queue sat there forever.
        // It stays disarmed while nothing is waiting, so an idle gate costs nothing.
        if !self.isStallCheckScheduled && (!self.waitingForeground.isEmpty || !self.waitingBackground.isEmpty) {
            self.isStallCheckScheduled = true
            Queue.mainQueue().after(MediaPreloadGate.sweepInterval, { [weak self] in
                guard let self else {
                    return
                }
                self.isStallCheckScheduled = false
                self.update()
            })
        }
    }
}
