import Foundation

// Lightweight substitutes for unrelated account services. File and signal implementations above
// this fixture are the actual repository sources.
@_silgen_name("crc32") private func zlibCRC32(_ crc: UInt, _ bytes: UnsafeRawPointer, _ length: UInt32) -> UInt
func Crc32(_ bytes: UnsafeRawPointer, _ length: Int32) -> UInt32 {
    return UInt32(zlibCRC32(0, bytes, UInt32(length)))
}
func postboxLog(_ message: String) {}
private final class Logger {
    static let shared = Logger()
    func log(_ category: String, _ message: String) {}
}
func fetchV2VerboseLog(_ message: @autoclosure () -> String) {}
public final class StorageBox {
    func update(id: Data, size: Int64) {}
}
public final class TempBoxFile {
    public let path: String
    init(path: String) { self.path = path }
}
final class TempBox {
    static let shared = TempBox()
    func dispose(_ file: TempBoxFile) { try? FileManager.default.removeItem(atPath: file.path) }
}
final class WriteBuffer {
    var memory = malloc(64)!
    var length = 0
    private var capacity = 64
    deinit { free(self.memory) }
    func write(_ data: UnsafeRawPointer, offset: Int, length: Int) {
        if self.length + length > self.capacity {
            self.capacity = self.length + length + 64
            self.memory = realloc(self.memory, self.capacity)!
        }
        memcpy(self.memory.advanced(by: self.length), data.advanced(by: offset), length)
        self.length += length
    }
}

// PRODUCTION_MEDIA_TYPES
// PRODUCTION_ATTEMPT_TYPES

private typealias FetchManagerLocationEntryId = Int
private final class AttemptHarness {
    var activeContexts: [FetchManagerLocationEntryId: FetchManagerActiveContext] = [:]
    // PRODUCTION_ATTEMPT_CHECK
}

// The network test redirects time and queued retry callbacks without altering the production bodies.
private var testTimestamp: Double = 1000.0
private func CFAbsoluteTimeGetCurrent() -> Double { testTimestamp }
private final class RetryQueue {
    var pending: [(Double, () -> Void)] = []
    func after(_ delay: Double, _ f: @escaping () -> Void) { self.pending.append((delay, f)) }
    func advance() {
        let pending = self.pending
        self.pending.removeAll()
        for (delay, f) in pending {
            testTimestamp += delay + 0.1
            f()
        }
    }
}
private enum FetchImpl {
    static let maxConsecutiveFailures: Int = // PRODUCTION_RETRY_LIMIT
    struct PendingReadyPart {
        let partRange: Range<Int64>
        let fetchRange: Range<Int64>
        let fetchedData: Data
        let cleanData: Data
    }
}
private struct VerifyPartHashData {
    let fetchedData: Data
}
// This existing fixture tests staging/empty-result routing. Native cipher boundaries
// are exercised separately by fetch_cipher_regression.py using DecryptionState.
private final class DecryptionStageDouble {
    let decryptedSize: Int64 = 4
    func canDecrypt(data: Data, offset: Int64) -> Bool { true }
}
private final class FetchingState {
    enum Location { case datacenter; case cdn }
    var fetchLocation: Location = .datacenter
    var decryptionState: DecryptionStageDouble? = nil
    var pendingReadyParts: [FetchImpl.PendingReadyPart] = []
    var completedRanges = RangeSet<Int64>()
}
private final class EmptyFirstPartHarness {
    let queue = RetryQueue()
    let loggingIdentifier = "regression"
    var consecutiveFailures = 0
    var fileReferenceRefreshCount = 0
    var progressCounter = 0
    var retryNotBefore: Double?
    var knownSize: Int64?
    var failed = false
    var results: [MediaResourceDataFetchResult] = []
    let state = FetchingState()
    func update() {}
    func failWithError(reason: String) { self.failed = true }
    func onNext(_ result: MediaResourceDataFetchResult) { self.results.append(result) }
    func receive(_ data: Data, verified: Bool = false) {
        let verifyPartHashData: VerifyPartHashData? = verified ? VerifyPartHashData(fetchedData: data) : nil
        let state = self.state
        let fetchRange: Range<Int64> = 0 ..< 4
        let partRange = fetchRange
        let requestedLength: Int64 = 4
        self.progressCounter += 1
        // PRODUCTION_DATA_BRANCH
    }
    // PRODUCTION_RETRY
    // PRODUCTION_COMMIT
}

private var assertionCount = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertionCount += 1
    precondition(condition(), message)
}
private func appendInteger<T>(_ value: T, to data: inout Data) {
    var value = value
    withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
}
private func mapBytes(modern: Bool, truncation: Int64 = -1, intervals: [(Int64, Int64)], count: Int32? = nil) -> Data {
    var payload = Data()
    if modern {
        appendInteger(truncation, to: &payload)
        for (offset, length) in intervals {
            appendInteger(offset, to: &payload)
            appendInteger(length, to: &payload)
        }
    } else {
        appendInteger(Int32(truncation), to: &payload)
        for (offset, length) in intervals {
            appendInteger(Int32(offset), to: &payload)
            appendInteger(Int32(length), to: &payload)
        }
    }
    var result = Data()
    if modern { appendInteger(UInt32(0x7bac1487), to: &result) }
    let crc = payload.withUnsafeBytes { Crc32($0.baseAddress!, Int32(payload.count)) }
    appendInteger(crc, to: &result)
    appendInteger(count ?? Int32(intervals.count), to: &result)
    result.append(payload)
    return result
}

private func testFileMaps() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("map").path
    let manager = MediaBoxFileManager(queue: nil)
    func decode(_ bytes: Data) throws -> MediaBoxFileMap {
        try bytes.write(to: URL(fileURLWithPath: path))
        return try MediaBoxFileMap.read(manager: manager, path: path)
    }
    func reject(_ bytes: Data, _ reason: String) throws {
        let decoded = try? decode(bytes)
        expect(decoded == nil, "Corrupt map accepted: \(reason)")
    }
    for modern in [false, true] {
        let decoded = try decode(mapBytes(modern: modern, truncation: 12, intervals: [(0, 4), (8, 4)]))
        expect(decoded.sum == 8 && decoded.truncationSize == 12, "Valid map changed")
        expect(decoded.contains(8 ..< 100) == 8 ..< 12, "EOF clipping changed")
        expect(decoded.contains(20 ..< 100) == 12 ..< 12, "Seek past EOF must return empty range")
        try reject(mapBytes(modern: modern, intervals: [], count: Int32.max), "overflowing count")
        try reject(mapBytes(modern: modern, intervals: [(0, 4), (2, 4)]), "overlapping intervals")
        try reject(mapBytes(modern: modern, intervals: [(-1, 4)]), "negative offset")
        try reject(mapBytes(modern: modern, intervals: [(0, -1)]), "negative length")
        try reject(mapBytes(modern: modern, truncation: -2, intervals: []), "negative truncation")
        var corrupted = mapBytes(modern: modern, intervals: [(0, 4)])
        corrupted[corrupted.count - 1] ^= 0xff
        try reject(corrupted, "bad checksum")
    }
    try reject(mapBytes(modern: true, intervals: [(Int64.max - 1, 4)]), "interval overflow")
    let legacyLarge = try decode(mapBytes(modern: false, intervals: [(0, 1_500_000_000), (1_500_000_000, 1_000_000_000)]))
    expect(legacyLarge.sum == 2_500_000_000, "Legacy map total must use 64-bit arithmetic")
    legacyLarge.serialize(manager: manager, to: path)
    let roundTrip = try MediaBoxFileMap.read(manager: manager, path: path)
    expect(roundTrip.sum == legacyLarge.sum && roundTrip.ranges == legacyLarge.ranges, "Map round-trip changed")
}

private func withContext(_ test: (MediaBoxFileContextV2Impl, Queue, String) -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let prefix = directory.appendingPathComponent("resource").path
    let queue = Queue(name: "MediaBox regression")
    let manager = MediaBoxFileManager(queue: queue)
    var context: MediaBoxFileContextV2Impl?
    queue.sync {
        context = MediaBoxFileContextV2Impl(queue: queue, manager: manager, storageBox: nil, resourceId: Data(), path: prefix, partialPath: prefix + "_partial", metaPath: prefix + "_partial.meta")!
    }
    test(context!, queue, prefix)
    queue.sync { context = nil }
}

private func testRetiredEvents() throws {
    for isError in [false, true] {
        try withContext { context, queue, prefix in
            var oldSubscriber: Subscriber<MediaResourceDataFetchResult, MediaResourceDataFetchError>?
            var newSubscriber: Subscriber<MediaResourceDataFetchResult, MediaResourceDataFetchError>?
            var oldErrors = 0
            var newErrors = 0
            var completed = false
            var oldRequest: Disposable?
            var newRequest: Disposable?
            queue.sync {
                oldRequest = context.fetchedFullRange(fetch: { _ in Signal { subscriber in
                    oldSubscriber = subscriber
                    return EmptyDisposable
                } }, error: { _ in oldErrors += 1 }, completed: {})
                // Hold the MediaBox queue while an old callback is enqueued from the network queue.
                let emitted = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    if isError { oldSubscriber!.putError(.generic) } else { oldSubscriber!.putNext(.reset) }
                    emitted.signal()
                }
                expect(emitted.wait(timeout: .now() + 3) == .success, "Network event did not enqueue")
                expect(context.resetFetchState(), "Expected active reset")
                newRequest = context.fetchedFullRange(fetch: { _ in Signal { subscriber in
                    newSubscriber = subscriber
                    return EmptyDisposable
                } }, error: { _ in newErrors += 1 }, completed: { completed = true })
                newSubscriber!.putNext(.dataPart(resourceOffset: 0, data: Data([1, 2, 3, 4]), range: 0 ..< 4, complete: false))
            }
            queue.sync {
                newSubscriber!.putNext(.dataPart(resourceOffset: 4, data: Data([5, 6, 7, 8]), range: 0 ..< 4, complete: true))
                expect(oldErrors == 1 && newErrors == 0, "Retired error failed replacement attempt")
                expect(completed, "Retired .reset erased replacement bytes")
                expect((try? Data(contentsOf: URL(fileURLWithPath: prefix))) == Data([1, 2, 3, 4, 5, 6, 7, 8]), "Replacement file contents changed")
                oldRequest?.dispose()
                newRequest?.dispose()
            }
        }
    }
}

private struct CopyItem: MediaResourceDataFetchCopyLocalItem {
    let succeeds: Bool
    func copyTo(url: URL) -> Bool {
        if !succeeds { return false }
        do { try Data([1, 2, 3, 4]).write(to: url); return true } catch { return false }
    }
}
private func testTerminalSources() throws {
    try withContext { context, queue, _ in
        queue.sync {
            var errors = 0
            let request = context.fetchedFullRange(fetch: { _ in .complete() }, error: { _ in errors += 1 }, completed: {})
            expect(errors == 1, "Completed source left missing ranges waiting")
            request.dispose()
            var completed = false
            let retry = context.fetchedFullRange(fetch: { _ in .single(.copyLocalItem(CopyItem(succeeds: true))) }, error: { _ in errors += 1 }, completed: { completed = true })
            expect(completed && errors == 1, "Successful local copy did not complete range owners")
            retry.dispose()
        }
    }
    for result: MediaResourceDataFetchResult in [.copyLocalItem(CopyItem(succeeds: false)), .moveLocalFile(path: "/supergram-regression-missing-source"), .moveTempFile(file: TempBoxFile(path: "/supergram-regression-missing-temp"))] {
        try withContext { context, queue, _ in
            queue.sync {
                var errors = 0
                let request = context.fetchedFullRange(fetch: { _ in .single(result) }, error: { _ in errors += 1 }, completed: {})
                expect(errors == 1, "Failed local move/copy did not fail range owner")
                request.dispose()
            }
        }
    }
    try withContext { context, queue, _ in
        queue.sync {
            var subscriber: Subscriber<MediaResourceDataFetchResult, MediaResourceDataFetchError>?
            let request = context.fetchedFullRange(fetch: { _ in Signal { s in subscriber = s; return EmptyDisposable } }, error: { _ in }, completed: {})
            subscriber!.putNext(.dataPart(resourceOffset: 8, data: Data(repeating: 7, count: 8), range: 0 ..< 8, complete: false))
            subscriber!.putNext(.resourceSizeUpdated(12))
            var data: MediaResourceData?
            let reader = context.data(range: 8 ..< 100, waitUntilAfterInitialFetch: false, next: { data = $0 })
            expect(data?.complete == true && data?.offset == 8 && data?.size == 4, "Partial reader reported bytes past known EOF")
            reader.dispose()
            request.dispose()
        }
    }
}

private func testEmptyFirstParts() {
    for encrypted in [false, true] {
        let harness = EmptyFirstPartHarness()
        if encrypted { harness.state.decryptionState = DecryptionStageDouble() }
        for _ in 0 ..< FetchImpl.maxConsecutiveFailures + 1 {
            harness.receive(Data(), verified: encrypted)
            harness.queue.advance()
        }
        expect(harness.failed, "Empty first parts retried forever")
        expect(harness.progressCounter == 0, "Rejected parts counted as progress")
        expect(harness.state.pendingReadyParts.isEmpty, "Rejected first part entered encrypted/verified staging")
        expect(harness.results.isEmpty, "Rejected first part emitted a finished zero-byte file")
    }
    let harness = EmptyFirstPartHarness()
    harness.receive(Data())
    harness.queue.advance()
    harness.receive(Data([1, 2, 3, 4]))
    expect(!harness.failed && harness.consecutiveFailures == 0 && harness.results.count == 1, "Valid part did not recover after empty response")
}

private func testAttemptIdentity() {
    let harness = AttemptHarness()
    let context = FetchManagerActiveContext(userInitiated: false)
    harness.activeContexts[1] = context
    let retired = context.attempt
    expect(harness.isCurrentFetchAttempt(id: 1, attempt: retired), "Current attempt rejected")
    context.attempt = FetchManagerFetchAttempt()
    expect(!harness.isCurrentFetchAttempt(id: 1, attempt: retired), "Stale callback accepted after range restart")
    harness.activeContexts.removeValue(forKey: 1)
    harness.activeContexts[1] = FetchManagerActiveContext(userInitiated: false)
    expect(!harness.isCurrentFetchAttempt(id: 1, attempt: retired), "Stale callback accepted after entry reuse")
}

try testFileMaps()
try testRetiredEvents()
try testTerminalSources()
testEmptyFirstParts()
testAttemptIdentity()
print("PASS: \(assertionCount) media fetch regression assertions")
