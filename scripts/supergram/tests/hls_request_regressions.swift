import Foundation

final class TempBoxFile {
    let path: String
    init(path: String) { self.path = path }
}
final class TempBox {
    static let shared = TempBox()
    private let counts = Atomic<[String: Int]>(value: [:])
    func file(_ data: Data = Data([1, 2, 3, 4])) -> TempBoxFile {
        let path = NSTemporaryDirectory() + "supergram-hls-" + UUID().uuidString
        try! data.write(to: URL(fileURLWithPath: path))
        return TempBoxFile(path: path)
    }
    func dispose(_ file: TempBoxFile) {
        self.counts.modify { value in
            var value = value
            value[file.path, default: 0] += 1
            return value
        }
        try? FileManager.default.removeItem(atPath: file.path)
    }
    func count(_ file: TempBoxFile) -> Int { self.counts.with { $0[file.path, default: 0] } }
}

// PRODUCTION_OWNER_AND_REGISTRY

private final class SharedHLSVideoJSContext {
    private let sourceRequests = HLSJSXHRRequests()
    // PRODUCTION_RESPONSE_ERROR
    // PRODUCTION_START_REQUEST
    // PRODUCTION_SEND_ERROR
    // PRODUCTION_SEND_FILE

    func start<T>(id: Int, context: Int = 1, signal: Signal<T, NoError>, receive: @escaping (T, @escaping ([String: Any]) -> Void) -> Void, completion: @escaping ([String: Any]) -> Void) {
        self.startSourceRequest(id: id, contextId: context, signal: signal, receive: receive, completion: completion)
    }
    func abort(_ id: Int) { self.sourceRequests.cancel(id: id) }
    func teardown(_ context: Int) { self.sourceRequests.cancel(contextId: context) }
    func teardownAll() { self.sourceRequests.cancelAll() }
    func read(_ owner: HLSJSTemporaryFile, respond: @escaping ([String: Any]) -> Void) {
        Self.sendResponseFileAndClose(id: 1, file: owner, fileRange: 1..<4, range: 1..<3, totalSize: 4, completion: respond)
    }
}

private final class Adapter {
    var signal: Signal<(HLSJSTemporaryFile, Range<Int>, Int)?, NoError>!
    func ownedFileData(id: Int64, range: Range<Int>) -> Signal<(HLSJSTemporaryFile, Range<Int>, Int)?, NoError> { self.signal }
    // PRODUCTION_PROTOCOL_ADAPTER
}

func sourceId(accountId: Int64, fileId: Int64, instanceId: Int) -> String {
    return // PRODUCTION_SOURCE_ID
}
var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    precondition(condition(), message)
}
func pump(until condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.005))
    }
    check(condition(), "async condition reached deadline")
}

check(parseRange(from: "bytes=0-0") == 0..<0, "inclusive single-byte end retained for caller's +1")
check(parseRange(from: "bytes=1-3") == 1..<3, "normal HTTP range")
for value in ["bytes=9-4", "bytes=-1-5", "bytes=1--5", "bytes=1-", "bytes=-5", "bytes=1-2-3", "bytes=1-\(Int.max)", "bad=1-2"] {
    check(parseRange(from: value) == nil, "reject malformed/negative/overflow range: \(value)")
}
check(sourceId(accountId: 1, fileId: 2, instanceId: 3) != sourceId(accountId: 1, fileId: 2, instanceId: 4), "same media players have distinct local routing owners")

private let registry = HLSJSXHRRequests()
var disposed = 0
private let old = registry.begin(id: 7, contextId: 1)
old.disposable.set(ActionDisposable { disposed += 1 })
private let current = registry.begin(id: 7, contextId: 2)
check(disposed == 1, "replace cancels old request")
check(!registry.complete(id: 7, request: old), "late old completion rejected")
check(registry.startResponse(id: 7, request: current), "new request still live")
check(!registry.startResponse(id: 7, request: current), "duplicate next rejected")
registry.cancel(contextId: 1)
check(registry.complete(id: 7, request: current), "other context teardown preserves current request")
check(!registry.complete(id: 7, request: current), "completion exactly once")

// Reentrant disposal must not remove a replacement under the same numeric XHR id.
private var replacement: HLSJSXHRRequest?
private let reentrant = registry.begin(id: 8, contextId: 5)
reentrant.disposable.set(ActionDisposable { replacement = registry.begin(id: 8, contextId: 6) })
registry.cancel(contextId: 5)
check(registry.startResponse(id: 8, request: replacement!), "reentrant replacement survives context teardown")
registry.cancelAll()
check(!registry.complete(id: 8, request: replacement!), "full teardown cancels request")

let file = TempBox.shared.file()
do {
    let owner = HLSJSTemporaryFile(file: file)
    owner.dispose()
    owner.dispose()
}
check(TempBox.shared.count(file) == 1, "owner cleanup exactly once including deinit")
check(!FileManager.default.fileExists(atPath: file.path), "owner deletes file")

let detached = TempBox.shared.file()
do {
    let adapter = Adapter()
    adapter.signal = Signal { subscriber in
        subscriber.putNext((HLSJSTemporaryFile(file: detached), 0..<4, 4))
        subscriber.putCompletion()
        return EmptyDisposable
    }
    let _ = adapter.fileData(id: 1, range: 0..<4).start(next: { result in
        check(result?.0 === detached, "protocol adapter preserves raw file API")
    })
}
check(TempBox.shared.count(detached) == 0, "protocol consumer owns detached file")
TempBox.shared.dispose(detached)

private let bridge = SharedHLSVideoJSContext()
var synchronousDisposed = 0
var synchronousResponses = 0
let synchronous = Signal<Int, NoError> { subscriber in
    subscriber.putNext(42)
    subscriber.putCompletion()
    return ActionDisposable { synchronousDisposed += 1 }
}
bridge.start(id: 10, signal: synchronous, receive: { value, respond in
    check(value == 42, "synchronous cache response")
    respond(["status": 200])
}, completion: { _ in synchronousResponses += 1 })
check(synchronousResponses == 1 && synchronousDisposed == 1, "synchronous completion cancels late-installed disposable")

var emptyStatus = 0
bridge.start(id: 11, signal: Signal<Int, NoError>.complete(), receive: { _, _ in
    preconditionFailure("empty source has no next")
}, completion: { emptyStatus = $0["status"] as! Int })
check(emptyStatus == 500, "completion without value closes XHR")

var abortDisposed = 0
bridge.start(id: 12, signal: Signal<Int, NoError> { _ in ActionDisposable { abortDisposed += 1 } }, receive: { _, _ in }, completion: { _ in preconditionFailure("aborted request responded") })
bridge.abort(12)
bridge.abort(12)
check(abortDisposed == 1, "abort disposes source once")

// Emit on a worker while main delivery remains queued. Abort before delivery.
let queuedFile = TempBox.shared.file()
let emitted = DispatchSemaphore(value: 0)
var queuedCallbacks = 0
private let queuedSignal = Signal<HLSJSTemporaryFile, NoError> { subscriber in
    Queue.concurrentDefaultQueue().async {
        subscriber.putNext(HLSJSTemporaryFile(file: queuedFile))
        subscriber.putCompletion()
        emitted.signal()
    }
    return EmptyDisposable
}
bridge.start(id: 13, signal: queuedSignal, receive: { _, _ in queuedCallbacks += 1 }, completion: { _ in queuedCallbacks += 1 })
check(emitted.wait(timeout: .now() + 5) == .success, "worker emitted owned segment")
check(FileManager.default.fileExists(atPath: queuedFile.path), "queued value retains file")
bridge.abort(13)
pump { TempBox.shared.count(queuedFile) == 1 }
check(queuedCallbacks == 0, "abort suppresses stale delivery without leaking file")

// The producer may emit after cancellation already terminated its subscriber.
let droppedFile = TempBox.shared.file()
private var producer: Subscriber<HLSJSTemporaryFile, NoError>?
bridge.start(id: 14, signal: Signal { subscriber in producer = subscriber; return EmptyDisposable }, receive: { _, _ in preconditionFailure("cancelled producer delivered") }, completion: { _ in preconditionFailure("cancelled producer answered") })
bridge.abort(14)
producer!.putNext(HLSJSTemporaryFile(file: droppedFile))
producer = nil
check(TempBox.shared.count(droppedFile) == 1, "terminated source drops value with cleanup")

// Keep identity through an asynchronous read. Reuse id before old read answers.
var pending: (([String: Any]) -> Void)?
var staleResponses = 0
bridge.start(id: 15, signal: Signal<Int, NoError>.single(1), receive: { _, respond in pending = respond }, completion: { _ in staleResponses += 1 })
bridge.start(id: 15, context: 2, signal: Signal<Int, NoError> { _ in EmptyDisposable }, receive: { _, _ in }, completion: { _ in staleResponses += 100 })
pending!(["status": 200])
check(staleResponses == 0, "late response cannot answer replacement XHR")
bridge.abort(15)
pending = nil

// Actual response reader retains owned file until read, cleans once, and bridges on main.
let responseFile = TempBox.shared.file(Data([10, 20, 30, 40]))
var response: [String: Any]?
bridge.start(id: 16, signal: Signal { subscriber in
    subscriber.putNext(HLSJSTemporaryFile(file: responseFile))
    subscriber.putCompletion()
    return EmptyDisposable
}, receive: { owner, respond in bridge.read(owner, respond: respond) }, completion: { value in
    check(Thread.isMainThread, "final bridge completion is main-only")
    response = value
})
pump { response != nil }
check(response?["status"] as? Int == 200, "reader succeeds")
check(Data(base64Encoded: response?["responseData"] as! String) == Data([20, 30, 40]), "reader preserves range and payload")
check(TempBox.shared.count(responseFile) == 1, "successful response file disposed once")

var contextDisposed = 0
for id in 20..<23 {
    bridge.start(id: id, context: id == 22 ? 2 : 1, signal: Signal<Int, NoError> { _ in ActionDisposable { contextDisposed += 1 } }, receive: { _, _ in }, completion: { _ in })
}
bridge.teardown(1)
check(contextDisposed == 2, "player teardown cancels its requests only")
bridge.teardownAll()
check(contextDisposed == 3, "JS teardown cancels remaining requests")

print("PASS: \(assertions) HLS request regression assertions")
