import Foundation
import CryptoKit

private var timestamp = 1000.0
private func CFAbsoluteTimeGetCurrent() -> Double { timestamp }
private final class Logger {
    static let shared = Logger()
    func log(_ category: String, _ message: String) {}
}
private func fetchV2VerboseLog(_ message: @autoclosure () -> String) {}
private func MTSha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
private final class RetryQueue {
    var pending: [(Double, () -> Void)] = []
    func after(_ delay: Double, _ body: @escaping () -> Void) { pending.append((delay, body)) }
    func advance() {
        let callbacks = pending; pending.removeAll()
        for (delay, body) in callbacks { timestamp += delay + 0.1; body() }
    }
}
private struct Buffer {
    let bytes: Data
    var size: Int32 { Int32(bytes.count) }
    func makeData() -> Data { bytes }
}
private enum Api {
    struct FileHashData { let offset: Int64; let limit: Int32; let hash: Buffer }
    enum FileHash { case fileHash(FileHashData) }
}
private enum MediaResourceDataFetchResult {
    case resourceSizeUpdated(Int64)
    case dataPart(resourceOffset: Int64, data: Data, range: Range<Int64>, complete: Bool)
}
private enum FetchImpl {
    static let maxConsecutiveFailures: Int = // RETRY_LIMIT
    // READY_TYPE
    // HASH_TYPE
}
private typealias HashRangeData = FetchImpl.HashRangeData
private final class PendingHashRange {
    let range: Range<Int64>
    init(_ range: Range<Int64>) { self.range = range }
}
private final class PendingPart {}
private final class DecryptionState {
    let decryptedSize: Int64 = 4
    func tryDecrypt(data: Data, offset: Int, loggingIdentifier: String) -> Data? { nil }
    func canDecrypt(data: Data, offset: Int64) -> Bool { true }
}
private final class FetchingState {
    enum Location { case datacenter; case cdn }
    var fetchLocation: Location = .datacenter
    var decryptionState: DecryptionState?
    var pendingReadyParts: [FetchImpl.PendingReadyPart] = []
    var pendingHashRanges: [PendingHashRange] = []
    var pendingParts: [PendingPart] = []
    var completedRanges = RangeSet<Int64>()
    var completedHashRanges = RangeSet<Int64>()
    var hashRanges: [Int64: HashRangeData] = [:]
}
private enum State { case fetching(FetchingState) }
private struct VerifyPartHashData { let fetchedData: Data }
private final class FetchHarness {
    let queue = RetryQueue()
    let loggingIdentifier = "synthetic-cdn"
    var state: State?
    var knownSize: Int64?
    var consecutiveFailures = 0
    var fileReferenceRefreshCount = 0
    var retryNotBefore: Double?
    var progressCounter = 0
    var failed = false
    var didAcceptPart = false
    var results: [MediaResourceDataFetchResult] = []
    init(_ state: FetchingState) { self.state = .fetching(state) }
    func update() {}
    func failWithError(reason: String) { self.failed = true }
    func onNext(_ result: MediaResourceDataFetchResult) { self.results.append(result) }
    func processReady(_ state: FetchingState) {
        // VERIFY
    }
    func neededHashes(_ state: FetchingState) -> RangeSet<Int64> {
        // REQUIRED_HASH_RANGES
        return requiredHashRanges
    }
    func receiveHash(_ result: [Api.FileHash]?, state: FetchingState, hashRange: PendingHashRange) {
        let callback = { [weak self, weak state, weak hashRange] in
            // HASH_CALLBACK
        }
        callback()
    }
    func receivePartIdentity(state: FetchingState, part: PendingPart) {
        let callback = { [weak self, weak state, weak part] in
            // PART_IDENTITY
            self.didAcceptPart = true
        }
        callback()
    }
    func receiveData(_ data: Data, state: FetchingState, verified: Bool, request: Range<Int64> = 0 ..< 4) {
        let verifyPartHashData: VerifyPartHashData? = verified ? VerifyPartHashData(fetchedData: data) : nil
        let partRange = request
        let fetchRange = partRange
        let requestedLength = request.upperBound - request.lowerBound
        self.progressCounter += 1
        // DATA_CLASSIFICATION
    }
    // HASH_VALIDATOR
    func accepts(_ result: [Api.FileHash]?, offset: Int64) -> Bool { self.validatedHashRanges(result, requiredOffset: offset) != nil }
    // RETRY
    // COMMIT
}

private var assertions = 0
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1; precondition(condition(), message)
}
private func hash(_ offset: Int64, _ limit: Int32, _ data: Data) -> Api.FileHash {
    .fileHash(Api.FileHashData(offset: offset, limit: limit, hash: Buffer(bytes: data)))
}
private func ready(_ bytes: Data, request: Range<Int64> = 0 ..< 4) -> FetchImpl.PendingReadyPart {
    FetchImpl.PendingReadyPart(partRange: request, fetchRange: request, fetchedData: bytes, cleanData: bytes)
}
private func testTail() {
    let state = FetchingState(); let harness = FetchHarness(state)
    let bytes = Data([1, 2, 3, 4])
    state.pendingReadyParts = [ready(bytes, request: 0 ..< 131072)]
    expect(harness.neededHashes(state) == RangeSet<Int64>(0 ..< 4), "Short CDN EOF requested hashes beyond returned bytes")
    let token = PendingHashRange(0 ..< 1048576); state.pendingHashRanges = [token]
    harness.receiveHash([hash(0, 4, MTSha256(bytes))], state: state, hashRange: token)
    harness.processReady(state)
    expect(state.pendingReadyParts.isEmpty && !harness.failed, "Valid short CDN EOF remained pending")
    expect(harness.knownSize == 4, "Verified CDN EOF changed")
    expect(harness.results.count == 2, "Verified CDN EOF did not deliver size plus data exactly once")
    if case let .dataPart(offset, data, range, complete) = harness.results.last! {
        expect(offset == 0 && data == bytes && range == 0 ..< 4 && !complete, "Verified CDN bytes changed")
    } else { preconditionFailure("Missing verified data") }
    expect(harness.consecutiveFailures == 0, "Verified progress did not reset failures")
}
private func testMismatch() {
    let state = FetchingState(); let harness = FetchHarness(state)
    let bytes = Data([1, 2, 3, 4]); let wrong = MTSha256(Data([9, 9, 9, 9]))
    for attempt in 0 ... FetchImpl.maxConsecutiveFailures {
        harness.receiveData(bytes, state: state, verified: true)
        let token = PendingHashRange(0 ..< 1048576); state.pendingHashRanges = [token]
        harness.receiveHash([hash(0, 4, wrong)], state: state, hashRange: token)
        harness.processReady(state)
        expect(harness.results.isEmpty && state.completedRanges.isEmpty, "Unverified CDN bytes were delivered")
        expect(harness.consecutiveFailures == attempt + 1, "Data/hash success reset integrity failure count")
        if attempt < FetchImpl.maxConsecutiveFailures {
            expect(!harness.failed && harness.retryNotBefore != nil, "Hash mismatch must use existing retry backoff")
            harness.queue.advance()
        }
    }
    expect(harness.failed, "Repeated SHA mismatch never exhausted retries")
    let recoveredState = FetchingState(); let recovery = FetchHarness(recoveredState)
    recovery.consecutiveFailures = 3
    recoveredState.pendingReadyParts = [ready(bytes)]
    recoveredState.completedHashRanges.insert(contentsOf: 0 ..< 4)
    recoveredState.hashRanges[0] = HashRangeData(range: 0 ..< 4, data: MTSha256(bytes))
    recovery.processReady(recoveredState)
    expect(recovery.results.count == 1 && recovery.consecutiveFailures == 0, "Real verified progress did not recover failure accounting")
}
private func testOffTarget() {
    let state = FetchingState(); let harness = FetchHarness(state)
    for attempt in 0 ... FetchImpl.maxConsecutiveFailures {
        let token = PendingHashRange(0 ..< 1048576); state.pendingHashRanges = [token]
        harness.receiveHash([hash(16, 4, MTSha256(Data([1, 2, 3, 4])))], state: state, hashRange: token)
        expect(harness.progressCounter == 0 && state.hashRanges.isEmpty, "Off-target hashes were counted as progress")
        expect(harness.consecutiveFailures == attempt + 1 && state.pendingHashRanges.isEmpty, "Missing requested hashes did not retire request and back off")
        harness.queue.advance()
    }
    expect(harness.failed && harness.results.isEmpty, "Nonempty useless hashes caused an unbounded retry")
}
private func testLate() {
    let state = FetchingState(); let harness = FetchHarness(state)
    let retired = PendingHashRange(0 ..< 4), live = PendingHashRange(0 ..< 4)
    state.pendingHashRanges = [live]
    harness.consecutiveFailures = 2
    harness.receiveHash([hash(0, 4, MTSha256(Data([1, 2, 3, 4])))], state: state, hashRange: retired)
    expect(state.hashRanges.isEmpty && state.pendingHashRanges.first === live && harness.progressCounter == 0 && harness.consecutiveFailures == 2, "Late retired hash response altered replacement request")
    let retiredPart = PendingPart(), livePart = PendingPart()
    state.pendingParts = [livePart]
    harness.receivePartIdentity(state: state, part: retiredPart)
    expect(!harness.didAcceptPart && state.pendingParts.first === livePart, "Retired part callback was still accepted in the same fetch state")
    harness.receivePartIdentity(state: state, part: livePart)
    expect(harness.didAcceptPart, "Current part callback was incorrectly suppressed")
}
private func testBounds() {
    let state = FetchingState(); let harness = FetchHarness(state)
    let digest = MTSha256(Data([1, 2, 3, 4]))
    for values: (Int64, Int32, Data) in [(-1, 4, digest), (0, 0, digest), (0, -1, digest), (Int64.max - 1, 4, digest), (0, 4, Data(repeating: 0, count: 31)), (0, 4, Data(repeating: 0, count: 33))] {
        expect(!harness.accepts([hash(values.0, values.1, values.2)], offset: 0), "Malformed CDN hash descriptor was accepted")
    }
    expect(!harness.accepts(nil, offset: 0) && !harness.accepts([], offset: 0), "Empty hash response was accepted")
    expect(harness.accepts([hash(0, 4, digest), hash(4, 4, digest)], offset: 0), "Valid consecutive hash descriptors were rejected")
    expect(!harness.accepts([hash(0, 4, digest), hash(2, 4, digest)], offset: 0), "Overlapping master hash descriptors were accepted")
    for verified in [false, true] {
        let s = FetchingState(); let h = FetchHarness(s)
        h.receiveData(Data(repeating: 1, count: 5), state: s, verified: verified)
        expect(h.results.isEmpty && s.pendingReadyParts.isEmpty && h.consecutiveFailures == 1 && h.progressCounter == 0, "Oversized part bypassed bounds before staging")
    }
}
private func testDeclaredHashCoverage() {
    let bytes = Data(repeating: 7, count: 32)
    for ranges: [(Range<Int64>, Data)] in [
        [(0 ..< 64, MTSha256(bytes))],
        [(0 ..< 16, MTSha256(bytes.prefix(16))), (17 ..< 32, MTSha256(bytes.suffix(15)))],
        [(1 ..< 32, MTSha256(bytes.suffix(31)))],
        [(0 ..< 16, MTSha256(bytes.prefix(16)))],
        [(0 ..< 16, MTSha256(bytes.prefix(16))), (16 ..< 32, Data(repeating: 0, count: 32))]
    ] {
        let state = FetchingState(); let h = FetchHarness(state)
        state.pendingReadyParts = [ready(bytes, request: 0 ..< 64)]
        for (range, digest) in ranges {
            state.completedHashRanges.insert(contentsOf: range)
            state.hashRanges[range.lowerBound] = HashRangeData(range: range, data: digest)
        }
        h.processReady(state)
        expect(h.results.isEmpty && state.completedRanges.isEmpty, "Incomplete master hash coverage delivered CDN bytes")
        if ranges[0].0 == 0 ..< 64 {
            expect(h.consecutiveFailures == 1, "Hash of a short prefix accepted for a longer declared range")
        }
    }
    let state = FetchingState(); let h = FetchHarness(state)
    state.pendingReadyParts = [ready(bytes, request: 0 ..< 64)]
    for range in [Int64(0) ..< 16, Int64(16) ..< 32] {
        state.completedHashRanges.insert(contentsOf: range)
        state.hashRanges[range.lowerBound] = HashRangeData(range: range, data: MTSha256(bytes.subdata(in: Int(range.lowerBound) ..< Int(range.upperBound))))
    }
    h.processReady(state)
    expect(h.results.count == 2 && state.pendingReadyParts.isEmpty && h.knownSize == 32, "Complete exact master ranges did not verify a final CDN part")
}
private func testKnownSizeAdmission() {
    for empty in [false, true] {
        let state = FetchingState(); state.fetchLocation = .cdn
        let h = FetchHarness(state); h.knownSize = 64
        for _ in 0 ... FetchImpl.maxConsecutiveFailures {
            let data = empty ? Data() : Data(repeating: 7, count: 16)
            h.receiveData(data, state: state, verified: !empty, request: empty ? 16 ..< 48 : 0 ..< 32)
            expect(h.results.isEmpty && state.pendingReadyParts.isEmpty && h.knownSize == 64, "CDN response truncated a known file before authenticated EOF")
            h.queue.advance()
        }
        expect(h.failed, "Premature CDN EOF was not bounded by retry exhaustion")
    }
    let state = FetchingState(); state.fetchLocation = .cdn
    let h = FetchHarness(state); h.knownSize = 16
    let bytes = Data(repeating: 7, count: 16)
    h.receiveData(bytes, state: state, verified: true, request: 0 ..< 32)
    state.completedHashRanges.insert(contentsOf: 0 ..< 16)
    state.hashRanges[0] = HashRangeData(range: 0 ..< 16, data: MTSha256(bytes))
    h.processReady(state)
    expect(h.results.count == 2 && h.knownSize == 16 && !h.failed, "Correct known-size CDN final response was rejected")
    let ordinary = FetchingState(); let plain = FetchHarness(ordinary); plain.knownSize = 64
    plain.receiveData(bytes, state: ordinary, verified: false, request: 0 ..< 32)
    expect(plain.knownSize == 16 && !plain.failed, "CDN admission unexpectedly changed plain datacenter EOF policy")
}
let selected = CommandLine.arguments.dropFirst().first ?? "all"
if selected == "all" || selected == "tail" { testTail() }
if selected == "all" || selected == "mismatch" { testMismatch() }
if selected == "all" || selected == "offtarget" { testOffTarget() }
if selected == "all" || selected == "late" { testLate() }
if selected == "all" || selected == "bounds" { testBounds() }
if selected == "all" || selected == "bounds" { testDeclaredHashCoverage() }
if selected == "all" || selected == "bounds" { testKnownSizeAdmission() }
print("PASS: \(assertions) new actual-source CDN SHA/bounds/EOF/retry/retired-callback assertions")
