#!/usr/bin/env python3
"""Execute V1/V2 cipher admission and sequential decryption with native AES.

The Swift bodies come from current (or saved --source) production source. The
Objective-C implementation is the repository's MTAes.m plus the actual
MTEncryption.m IGE/CTR entry functions, compiled against host CommonCrypto.
Network/account/time scheduling are controlled doubles; no app build or device
is involved. Invalid native calls are recorded and blocked by the test bridge so
the pre-fix snapshot can be exercised without an unsafe memory read.
"""
import argparse
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path)
parser.add_argument("--legacy-source", type=Path)
parser.add_argument("--expect-failure", action="store_true")
args = parser.parse_args()
fetch = (args.source or ROOT / "submodules/TelegramCore/Sources/Network/FetchV2.swift").read_text()
legacy = (args.legacy_source or ROOT / "submodules/TelegramCore/Sources/Network/MultipartFetch.swift").read_text()


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end] + "\n"


def between(source, first, last):
    return source.split(first, 1)[1].split(last, 1)[0]


encryption = (ROOT / "submodules/MtProtoKit/Sources/MTEncryption.m").read_text()
aes = (ROOT / "submodules/MtProtoKit/Sources/MTAes.m").read_text()
header = (ROOT / "submodules/MtProtoKit/PublicHeaders/MtProtoKit/MTEncryption.h").read_text()
native = "#import <Foundation/Foundation.h>\n"
native += "@interface MTAesCtr : NSObject\n" + between(header, "@interface MTAesCtr : NSObject", "@end") + "@end\n"
native += aes.replace('#import "MTAes.h"', "")
for marker in ["void MTAesEncryptBytesInplaceAndModifyIv(", "void MTAesDecryptBytesInplaceAndModifyIv(", "NSData *MTAesCtrDecrypt("]:
    native += block(encryption, marker)
native += r'''
void SGNativeIgeEncrypt(void *data, NSInteger count, NSData *key, void *iv) { MTAesEncryptBytesInplaceAndModifyIv(data, count, key, iv); }
void SGNativeIgeDecrypt(void *data, NSInteger count, NSData *key, void *iv) { MTAesDecryptBytesInplaceAndModifyIv(data, count, key, iv); }
NSData *SGNativeCtr(NSData *data, NSData *key, NSData *iv) { return MTAesCtrDecrypt(data, key, iv); }
'''
bridge = r'''
#import <Foundation/Foundation.h>
void SGNativeIgeEncrypt(void * _Nonnull data, NSInteger count, NSData * _Nonnull key, void * _Nonnull iv);
void SGNativeIgeDecrypt(void * _Nonnull data, NSInteger count, NSData * _Nonnull key, void * _Nonnull iv);
NSData * _Nonnull SGNativeCtr(NSData * _Nonnull data, NSData * _Nonnull key, NSData * _Nonnull iv);
'''
swift = r'''
import Foundation
var clockNow = 1.0
var nativeIgeCalls = 0
var nativeCtrCalls = 0
var unsafeNativeCalls = 0
var activeIgeIvCount = 32
var lastCtrIv: Data?
final class Logger { static let shared = Logger(); func log(_ tag: String, _ message: String) {} }
func fetchV2VerboseLog(_ message: String) {}
func MTAesDecryptBytesInplaceAndModifyIv(_ bytes: UnsafeMutablePointer<UInt8>, _ count: Int, _ key: Data, _ iv: UnsafeMutablePointer<UInt8>) {
    nativeIgeCalls += 1
    guard count > 0 && count % 16 == 0 && key.count == 32 && activeIgeIvCount == 32 else { unsafeNativeCalls += 1; return }
    SGNativeIgeDecrypt(bytes, count, key, iv)
}
func MTAesCtrDecrypt(_ data: Data, _ key: Data, _ iv: Data) -> Data? {
    nativeCtrCalls += 1
    lastCtrIv = iv
    guard key.count == 32 && iv.count == 16 else { unsafeNativeCalls += 1; return nil }
    return SGNativeCtr(data, key, iv)
}
final class Queue { var scheduled: [() -> Void] = []; func after(_ delay: Double, _ task: @escaping () -> Void) { scheduled.append(task) } }
'''
swift += "private enum FetchImpl {\n"
swift += "static let maxConsecutiveFailures = " + re.search(r"private static let maxConsecutiveFailures: Int = (\d+)", fetch).group(1) + "\n"
for marker in ["private final class DecryptionState {", "private final class PendingReadyPart {"]:
    swift += block(fetch, marker).replace("private final class", "final class", 1)
swift += "}\n"
swift += r'''
private struct VerifyPartHashData { let fetchRange: Range<Int64>; let fetchedData: Data }
private final class State {
    enum Location { case cdn; case datacenter }
    var fetchLocation: Location = .datacenter
    var decryptionState: FetchImpl.DecryptionState?
    var pendingReadyParts: [FetchImpl.PendingReadyPart] = []
}
private final class ResponseHarness {
    let state = State()
    let queue = Queue()
    let loggingIdentifier = "test"
    var consecutiveFailures = 0
    var fileReferenceRefreshCount = 0
    var progressCounter = 0
    var retryNotBefore: Double?
    var knownSize: Int64?
    var errors = 0
    var updates = 0
    var commits = 0
    func update() { updates += 1 }
    func failWithError(reason: String) { errors += 1 }
    func commitPendingReadyPart(state: State, partRange: Range<Int64>, fetchRange: Range<Int64>, data: Data) -> Bool { commits += 1; return true }
'''
swift += block(fetch, "private func scheduleRetryAfterFailure()").replace("CFAbsoluteTimeGetCurrent()", "clockNow")
swift += r'''
    func receive(_ data: Data, at offset: Int64 = 0, requestedLength: Int = 32, verified: Bool = false) {
        let state = self.state
        let partRange = offset ..< (offset + Int64(requestedLength))
        let fetchRange = partRange
        let verifyPartHashData: VerifyPartHashData? = verified ? .init(fetchRange: fetchRange, fetchedData: data) : nil
        progressCounter += 1
'''
swift += between(fetch, "case let .data(data, verifyPartHashData):", "case let .cdnRedirect(cdnData):")
swift += "}\n}\n"
swift += r'''
private struct Buffer { let data: Data; var size: Int { data.count }; func makeData() -> Data { data } }
private struct CdnFile { let bytes: Buffer }
private struct CdnData { let encryptionIv: Data; let encryptionKey: Data }
private enum FilePartResult { case data(data: Data, verifyPartHashData: VerifyPartHashData?); case failure }
private func cdnResult(data: Data, key: Data, iv: Data, at requestedOffset: Int64) -> FilePartResult {
    let cdnFileData = CdnFile(bytes: Buffer(data: data))
    let cdnData = CdnData(encryptionIv: iv, encryptionKey: key)
    let fetchRange = requestedOffset ..< requestedOffset
    let loggingIdentifier = "test"
'''
swift += between(fetch, "case let .cdnFile(cdnFileData):", "case let .cdnFileReuploadNeeded(cdnFileReuploadNeededData):")
swift += "}\n"
swift += r'''
private final class SecretFileEncryptionKey {
    let aesKey: Data; let aesIv: Data
    init(aesKey: Data, aesIv: Data) { self.aesKey = aesKey; self.aesIv = aesIv }
}
'''
swift += block(legacy, "private final class MultipartDownloadState {")
swift += r'''
private enum LegacyError { case generic }
private enum LegacySignal { case single((Data, Int)); case fail(LegacyError) }
private func legacyCdnResult(data: Data, key: Data, iv: Data, at offset: Int64) -> LegacySignal {
    let cdnFileData = CdnFile(bytes: Buffer(data: data))
    let info = 0
'''
swift += between(legacy, "case let .cdnFile(cdnFileData):", "\n                    }\n                }\n                \n                return combineLatest")
swift += "}\n"
swift += r'''
private final class LegacyAdmission {
    let state: MultipartDownloadState
    var errors = 0
    var accepted = false
    init(_ state: MultipartDownloadState) { self.state = state }
    func finishWithError(_ error: LegacyError) { errors += 1 }
    func receive(data: Data, offset: Int64, requestedLength: Int64) {
        let strongSelf = self
        let downloadRange = offset ..< (offset + requestedLength)
'''
if "guard strongSelf.state.canAcceptPart" in legacy:
    # Include the whole actual callback guard; its bare return is the callback's
    # terminal path, preceding all completeSize/fetchedParts mutations.
    guard_start = legacy.index("guard strongSelf.state.canAcceptPart")
    guard_end = legacy.index("\n                }", guard_start) + len("\n                }")
    swift += legacy[guard_start:guard_end] + "\n"
else:
    # The installed pre-fix callback has no encrypted-part admission gate.
    swift += "_ = strongSelf; _ = downloadRange\n"
swift += "self.accepted = true\n}\n}\n"
swift += r'''
private protocol TelegramMediaResource {}
private protocol TelegramCloudMediaResource: TelegramMediaResource {}
private final class CloudResource: TelegramCloudMediaResource {}
private final class SecretResource: TelegramMediaResource {}
private struct SelectionNetwork { let useExperimentalFeatures: Bool }
'''
common_parameters = "accountPeerId: Int, postbox: Int, network: SelectionNetwork, mediaReferenceRevalidationContext: Int, resource: TelegramMediaResource, datacenterId: Int, size: Int, intervals: Int, parameters: Int, encryptionKey: Int, decryptedSize: Int, continueInBackground: Int, useMainConnection: Int"
swift += "private func multipartFetchV2(" + common_parameters + ") -> Int { 2 }\n"
swift += "private func multipartFetchV1(" + common_parameters.replace("mediaReferenceRevalidationContext: Int,", "mediaReferenceRevalidationContext: Int, networkStatsContext: Int,") + ") -> Int { 1 }\n"
swift += r'''
private func selectedRoute(_ network: SelectionNetwork, _ resource: TelegramMediaResource) -> Int {
    let accountPeerId = 0, postbox = 0, mediaReferenceRevalidationContext = 0, networkStatsContext = 0
    let datacenterId = 0, size = 0, intervals = 0, parameters = 0, encryptionKey = 0, decryptedSize = 0, continueInBackground = 0, useMainConnection = 0
'''
selector = block(legacy, "func multipartFetch(")
swift += selector[selector.index("if network.useExperimentalFeatures"):selector.rindex("}")]
swift += "}\n"
swift += r'''
var assertions = 0
var failures = 0
func check(_ value: @autoclosure () -> Bool, _ description: String) { assertions += 1; if !value() { failures += 1; print("FAIL: " + description) } }
let key = Data((0 ..< 32).map(UInt8.init))
let originalIv = Data((32 ..< 64).map(UInt8.init))
let plaintext = Data((0 ..< 53).map { UInt8($0 * 3) })
var padded = plaintext
padded.append(contentsOf: [UInt8](repeating: 0xa5, count: 64 - plaintext.count))
var encryptionIv = originalIv
var ciphertext = padded
ciphertext.withUnsafeMutableBytes { data in encryptionIv.withUnsafeMutableBytes { iv in SGNativeIgeEncrypt(data.baseAddress!, ciphertext.count, key, iv.baseAddress!) } }
private let decoder = FetchImpl.DecryptionState(aesKey: key, aesIv: originalIv, decryptedSize: Int64(plaintext.count))
let beforeNative = nativeIgeCalls
check(decoder.tryDecrypt(data: ciphertext.subdata(in: 16 ..< 32), offset: 16, loggingIdentifier: "test") == nil, "out-of-order encrypted part must wait without modifying IV")
check(decoder.offset == 0 && decoder.aesIv == originalIv && nativeIgeCalls == beforeNative, "out-of-order rejection leaves cipher state untouched")
var clear = Data()
for range in [0 ..< 16, 16 ..< 32, 32 ..< 64] {
    let next = decoder.tryDecrypt(data: ciphertext.subdata(in: range), offset: range.lowerBound, loggingIdentifier: "test")
    check(next != nil, "legitimate sequential encrypted part must decrypt")
    clear.append(next ?? Data())
}
check(clear == plaintext, "actual native AES-IGE roundtrip preserves plaintext and trims final padding")
check(decoder.offset == plaintext.count && decoder.aesIv == encryptionIv, "actual native AES-IGE sequential IV and plaintext offset advance correctly")
check(nativeIgeCalls == beforeNative + 3, "valid sequential data enters real native AES once per part")
let eofNative = nativeIgeCalls
check(decoder.tryDecrypt(data: Data(), offset: plaintext.count, loggingIdentifier: "test") == Data(), "empty EOF is safe after plaintext completion")
check(nativeIgeCalls == eofNative && decoder.offset == plaintext.count, "empty EOF never enters native AES or changes offset")
check(decoder.tryDecrypt(data: ciphertext.prefix(16), offset: plaintext.count, loggingIdentifier: "test") == nil, "nonempty data beyond plaintext EOF is rejected")
check(nativeIgeCalls == eofNative, "data beyond plaintext EOF never enters native AES")
private let emptyBeforeEof = FetchImpl.DecryptionState(aesKey: key, aesIv: originalIv, decryptedSize: 64)
check(emptyBeforeEof.tryDecrypt(data: Data(), offset: 0, loggingIdentifier: "test") == nil, "empty encrypted data before declared plaintext EOF must reject")
check(emptyBeforeEof.offset == 0 && emptyBeforeEof.aesIv == originalIv && nativeIgeCalls == eofNative, "premature empty EOF preserves cipher state without native entry")

// A direct invalid ciphertext must not reach the native implementation. An IV-length
// spy uses the actual State value before calling tryDecrypt; the C entry takes only
// a raw pointer and cannot inspect its allocation length itself.
for count in [1, 15, 17, 31] {
    let state = FetchImpl.DecryptionState(aesKey: key, aesIv: originalIv, decryptedSize: 64)
    let nativeBefore = nativeIgeCalls
    check(state.tryDecrypt(data: Data(repeating: 1, count: count), offset: 0, loggingIdentifier: "test") == nil, "non-block ciphertext must be rejected")
    check(nativeIgeCalls == nativeBefore && state.offset == 0 && state.aesIv == originalIv, "non-block rejection never enters native or modifies sequential state")
}
for badKeyCount in [0, 16, 24, 31, 33] {
    let state = FetchImpl.DecryptionState(aesKey: Data(repeating: 1, count: badKeyCount), aesIv: originalIv, decryptedSize: 64)
    let nativeBefore = nativeIgeCalls
    check(state.tryDecrypt(data: ciphertext.prefix(16), offset: 0, loggingIdentifier: "test") == nil, "invalid IGE key size must reject")
    check(nativeIgeCalls == nativeBefore && state.offset == 0, "invalid IGE key never reaches native or advances offset")
}
// The bridge records/blocks a bad direct call before the raw C pointer can be read;
// current production must reject it without touching that bridge at all.
for badIvCount in [0, 1, 16, 31, 33] {
    let direct = FetchImpl.DecryptionState(aesKey: key, aesIv: Data(repeating: 1, count: badIvCount), decryptedSize: 64)
    let before = nativeIgeCalls
    activeIgeIvCount = badIvCount
    check(direct.tryDecrypt(data: ciphertext.prefix(16), offset: 0, loggingIdentifier: "test") == nil, "direct invalid IGE IV must reject")
    activeIgeIvCount = 32
    check(nativeIgeCalls == before && direct.offset == 0, "invalid direct IV never enters native IGE or advances offset")
    let h = ResponseHarness(); h.state.decryptionState = FetchImpl.DecryptionState(aesKey: key, aesIv: Data(repeating: 1, count: badIvCount), decryptedSize: 64)
    h.receive(ciphertext.prefix(16))
    check(h.state.pendingReadyParts.isEmpty && h.consecutiveFailures == 1 && h.progressCounter == 0, "invalid IGE IV must back off before any staged/native decrypt")
}
for size in [Int64(-1), Int64(0)] {
    let h = ResponseHarness(); h.state.decryptionState = FetchImpl.DecryptionState(aesKey: key, aesIv: originalIv, decryptedSize: size)
    h.receive(ciphertext.prefix(16))
    check(h.state.pendingReadyParts.isEmpty && h.consecutiveFailures == 1, "invalid plaintext extent must reject before staging")
}
private let malformed = ResponseHarness()
malformed.state.decryptionState = FetchImpl.DecryptionState(aesKey: key, aesIv: originalIv, decryptedSize: 64)
for _ in 0 ... FetchImpl.maxConsecutiveFailures {
    malformed.receive(Data(repeating: 1, count: 15))
    clockNow = (malformed.retryNotBefore ?? clockNow) + 0.1
    let scheduled = malformed.queue.scheduled
    malformed.queue.scheduled.removeAll()
    for task in scheduled { task() }
}
check(malformed.errors == 1 && malformed.consecutiveFailures == FetchImpl.maxConsecutiveFailures + 1, "repeated malformed encrypted responses exhaust bounded retry budget")
check(malformed.state.pendingReadyParts.isEmpty && malformed.commits == 0 && malformed.progressCounter == 0, "malformed encrypted data cannot become progress or delivered bytes")
private let valid = ResponseHarness(); valid.state.decryptionState = FetchImpl.DecryptionState(aesKey: key, aesIv: originalIv, decryptedSize: 64)
valid.receive(ciphertext.prefix(16))
// This request asks for exactly one complete nonfinal block.
private let validBlock = ResponseHarness(); validBlock.state.decryptionState = FetchImpl.DecryptionState(aesKey: key, aesIv: originalIv, decryptedSize: 64)
validBlock.receive(ciphertext.prefix(16), requestedLength: 16)
check(validBlock.state.pendingReadyParts.count == 1 && validBlock.consecutiveFailures == 0 && validBlock.progressCounter == 1, "complete nonfinal encrypted response retains staging and normal progress")
check(valid.state.pendingReadyParts.isEmpty && valid.consecutiveFailures == 1 && valid.progressCounter == 0, "short aligned ciphertext before declared plaintext EOF must retry rather than truncate")
private let emptyPart = ResponseHarness(); emptyPart.state.decryptionState = FetchImpl.DecryptionState(aesKey: key, aesIv: originalIv, decryptedSize: 64)
emptyPart.receive(Data(), at: 16, requestedLength: 32)
check(emptyPart.state.pendingReadyParts.isEmpty && emptyPart.consecutiveFailures == 1 && emptyPart.progressCounter == 0, "empty nonfirst ciphertext before declared plaintext EOF must retry")
private let validPaddedFinal = ResponseHarness(); validPaddedFinal.state.decryptionState = FetchImpl.DecryptionState(aesKey: key, aesIv: originalIv, decryptedSize: 53)
validPaddedFinal.receive(ciphertext.suffix(32), at: 32, requestedLength: 4096)
check(validPaddedFinal.state.pendingReadyParts.count == 1 && validPaddedFinal.consecutiveFailures == 0, "legitimate short final ciphertext covering plaintext plus padding remains accepted")
private let shortCdn = ResponseHarness(); shortCdn.state.fetchLocation = .cdn; shortCdn.knownSize = 64
shortCdn.receive(Data(repeating: 1, count: 16), requestedLength: 32, verified: true)
check(shortCdn.state.pendingReadyParts.isEmpty && shortCdn.consecutiveFailures == 1 && shortCdn.knownSize == 64 && shortCdn.progressCounter == 0, "known CDN suffix cannot be erased by a correctly hashed short prefix")
private let emptyCdn = ResponseHarness(); emptyCdn.state.fetchLocation = .cdn; emptyCdn.knownSize = 64
emptyCdn.receive(Data(), at: 16, requestedLength: 32)
check(emptyCdn.state.pendingReadyParts.isEmpty && emptyCdn.consecutiveFailures == 1 && emptyCdn.commits == 0 && emptyCdn.knownSize == 64, "empty CDN response before known EOF cannot commit or shrink resource")
private let fullNonfinalCdn = ResponseHarness(); fullNonfinalCdn.state.fetchLocation = .cdn; fullNonfinalCdn.knownSize = 64
fullNonfinalCdn.receive(Data(repeating: 1, count: 16), requestedLength: 16, verified: true)
check(fullNonfinalCdn.state.pendingReadyParts.count == 1 && fullNonfinalCdn.consecutiveFailures == 0, "full nonfinal CDN request remains admissible")
private let trueCdnEof = ResponseHarness(); trueCdnEof.state.fetchLocation = .cdn; trueCdnEof.knownSize = 64
trueCdnEof.receive(Data(repeating: 1, count: 16), at: 48, requestedLength: 32, verified: true)
check(trueCdnEof.state.pendingReadyParts.count == 1 && trueCdnEof.consecutiveFailures == 0, "short known CDN final response ending at true EOF remains admissible")
private let unknownCdnEof = ResponseHarness(); unknownCdnEof.state.fetchLocation = .cdn
unknownCdnEof.receive(Data(repeating: 1, count: 16), requestedLength: 32, verified: true)
check(unknownCdnEof.state.pendingReadyParts.count == 1 && unknownCdnEof.consecutiveFailures == 0, "unknown CDN size retains valid final response policy")
private let plainShort = ResponseHarness(); plainShort.knownSize = 64
plainShort.receive(Data(repeating: 1, count: 16), requestedLength: 32)
check(plainShort.commits == 1 && plainShort.consecutiveFailures == 0, "ordinary datacenter route retains its existing short-response policy")

let cdnIv = Data((64 ..< 80).map(UInt8.init))
let cdnPlain = Data((0 ..< 29).map { UInt8($0 + 20) })
for offset in [Int64(0), Int64(4096), Int64(Int32.max) * 16 + 16, Int64(UInt32.max) * 16] {
    var effectiveIv = cdnIv
    var counter = UInt32(offset / 16).bigEndian
    _ = effectiveIv.withUnsafeMutableBytes { memcpy($0.baseAddress!.advanced(by: 12), &counter, 4) }
    let encrypted = SGNativeCtr(cdnPlain, key, effectiveIv)
    let nativeBefore = nativeCtrCalls
    switch cdnResult(data: encrypted, key: key, iv: cdnIv, at: offset) {
    case let .data(data, verification):
        check(data == cdnPlain && verification?.fetchedData == encrypted, "actual native CDN CTR roundtrip retains bytes for later hash verification")
    case .failure: check(false, "valid CDN cipher rejected")
    }
    check(nativeCtrCalls == nativeBefore + 1 && lastCtrIv == effectiveIv, "valid CDN unsigned block offset is encoded exactly")
}
let invalidCdnParameters: [(Data, Data, Int64)] = [
    (Data(), cdnIv, Int64(0)), (key.prefix(31), cdnIv, 0), (key + Data([1]), cdnIv, 0),
    (key, Data(), 0), (key, cdnIv.prefix(4), 0), (key, cdnIv.prefix(15), 0), (key, cdnIv + Data([1]), 0),
    (key, cdnIv, -16), (key, cdnIv, 1), (key, cdnIv, Int64(UInt32.max) * 16 + 16), (key, cdnIv, Int64.max)
]
for (badKey, badIv, badOffset) in invalidCdnParameters {
    let before = nativeCtrCalls
    if case .failure = cdnResult(data: Data([1]), key: badKey, iv: badIv, at: badOffset) { check(true, "invalid CDN parameters fail") }
    else { check(false, "invalid CDN parameters must fail") }
    check(nativeCtrCalls == before, "invalid CDN parameters never reach native CTR")
}
let beforeEmpty = nativeCtrCalls
if case let .data(data, verification) = cdnResult(data: Data(), key: key, iv: cdnIv, at: 4096) {
    check(data.isEmpty && verification == nil, "empty later CDN response remains EOF candidate without crypto")
} else { check(false, "empty CDN response unexpectedly rejected") }
check(nativeCtrCalls == beforeEmpty && unsafeNativeCalls == 0, "all invalid/empty cipher paths avoid unsafe native entry")

// V1 is the actual fallback for secret resources, including with experiments on.
check(selectedRoute(SelectionNetwork(useExperimentalFeatures: true), CloudResource()) == 2, "experimental cloud resource selects V2")
check(selectedRoute(SelectionNetwork(useExperimentalFeatures: false), CloudResource()) == 1, "cloud resource without experiments selects V1")
check(selectedRoute(SelectionNetwork(useExperimentalFeatures: true), SecretResource()) == 1, "secret resource remains on V1 with experiments enabled")
check(selectedRoute(SelectionNetwork(useExperimentalFeatures: false), SecretResource()) == 1, "secret resource without experiments selects V1")
private let legacyDecoder = MultipartDownloadState(encryptionKey: SecretFileEncryptionKey(aesKey: key, aesIv: originalIv), decryptedSize: Int64(plaintext.count))
var legacyPlain = Data()
let legacyNativeBefore = nativeIgeCalls
for range in [0 ..< 16, 16 ..< 32, 32 ..< 64] {
    let next = legacyDecoder.transform(offset: Int64(range.lowerBound), data: ciphertext.subdata(in: range))
    check(next != nil, "V1 sequential encrypted part decrypts")
    legacyPlain.append(next ?? Data())
}
check(legacyPlain == plaintext && legacyDecoder.currentSize == Int64(plaintext.count), "V1 real native IGE preserves sequential plaintext and final padding trim")
check(legacyDecoder.aesIv == encryptionIv && nativeIgeCalls == legacyNativeBefore + 3, "V1 native IV advances exactly once per accepted part")
let legacyEofBefore = nativeIgeCalls
check(legacyDecoder.transform(offset: Int64(plaintext.count), data: Data()) == Data(), "V1 legitimate empty plaintext EOF is safe")
check(nativeIgeCalls == legacyEofBefore, "V1 empty EOF avoids native entry")
check(legacyDecoder.transform(offset: Int64(plaintext.count), data: ciphertext.prefix(16)) == nil, "V1 nonempty data after plaintext EOF rejects")
check(nativeIgeCalls == legacyEofBefore, "V1 post-EOF data never reaches native IGE")
private let unencrypted = MultipartDownloadState(encryptionKey: nil, decryptedSize: nil)
check(unencrypted.transform(offset: 123, data: Data([1, 2, 3])) == Data([1, 2, 3]), "V1 unencrypted non-block data retains passthrough")

for count in [1, 15, 17, 31] {
    let state = MultipartDownloadState(encryptionKey: SecretFileEncryptionKey(aesKey: key, aesIv: originalIv), decryptedSize: 64)
    let before = nativeIgeCalls
    check(state.transform(offset: 0, data: Data(repeating: 1, count: count)) == nil, "V1 non-block cipher rejects")
    check(nativeIgeCalls == before && state.currentSize == 0 && state.aesIv == originalIv, "V1 malformed part cannot enter native or advance cipher state")
}
for count in [0, 16, 24, 31, 33] {
    let state = MultipartDownloadState(encryptionKey: SecretFileEncryptionKey(aesKey: Data(repeating: 1, count: count), aesIv: originalIv), decryptedSize: 64)
    let before = nativeIgeCalls
    check(state.transform(offset: 0, data: ciphertext.prefix(16)) == nil, "V1 malformed supplied key is not treated as plaintext")
    check(nativeIgeCalls == before && state.currentSize == 0, "V1 malformed key never enters native")
}
for count in [0, 1, 16, 31, 33] {
    let state = MultipartDownloadState(encryptionKey: SecretFileEncryptionKey(aesKey: key, aesIv: Data(repeating: 1, count: count)), decryptedSize: 64)
    let before = nativeIgeCalls
    activeIgeIvCount = count
    check(state.transform(offset: 0, data: ciphertext.prefix(16)) == nil, "V1 direct malformed IV rejects")
    activeIgeIvCount = 32
    check(nativeIgeCalls == before && state.currentSize == 0, "V1 malformed IV never enters native or advances offset")
}
for (offset, requested, bytes) in [(Int64(0), Int64(32), Data(ciphertext.prefix(16))), (16, 32, Data()), (0, 16, Data(ciphertext.prefix(32))), (0, 32, Data(repeating: 1, count: 15))] {
    let state = MultipartDownloadState(encryptionKey: SecretFileEncryptionKey(aesKey: key, aesIv: originalIv), decryptedSize: 64)
    let admission = LegacyAdmission(state)
    admission.receive(data: bytes, offset: offset, requestedLength: requested)
    check(!admission.accepted && admission.errors == 1 && state.currentSize == 0, "V1 actual callback rejects malformed/truncated cipher before completing or staging")
}
private let legacyFinalAdmission = LegacyAdmission(MultipartDownloadState(encryptionKey: SecretFileEncryptionKey(aesKey: key, aesIv: originalIv), decryptedSize: 53))
legacyFinalAdmission.receive(data: ciphertext.suffix(32), offset: 32, requestedLength: 4096)
check(legacyFinalAdmission.accepted && legacyFinalAdmission.errors == 0, "V1 actual callback accepts legitimate padded short final part")
for badSize: Int64? in [nil, -1, 0] {
    let admission = LegacyAdmission(MultipartDownloadState(encryptionKey: SecretFileEncryptionKey(aesKey: key, aesIv: originalIv), decryptedSize: badSize))
    admission.receive(data: ciphertext.prefix(16), offset: 0, requestedLength: 16)
    check(!admission.accepted && admission.errors == 1, "V1 missing/invalid plaintext extent fails through actual callback")
}
private let legacyPrematureEmpty = MultipartDownloadState(encryptionKey: SecretFileEncryptionKey(aesKey: key, aesIv: originalIv), decryptedSize: 64)
check(legacyPrematureEmpty.transform(offset: 0, data: Data()) == nil, "V1 direct empty data before plaintext EOF rejects")
for offset in [Int64(0), Int64(4096), Int64(Int32.max) * 16 + 16, Int64(UInt32.max) * 16] {
    var effectiveIv = cdnIv
    var counter = UInt32(offset / 16).bigEndian
    _ = effectiveIv.withUnsafeMutableBytes { memcpy($0.baseAddress!.advanced(by: 12), &counter, 4) }
    let encrypted = SGNativeCtr(cdnPlain, key, effectiveIv)
    let before = nativeCtrCalls
    if case let .single((data, _)) = legacyCdnResult(data: encrypted, key: key, iv: cdnIv, at: offset) {
        check(data == cdnPlain, "V1 actual native CDN CTR roundtrip preserves plaintext")
    } else { check(false, "V1 valid CDN data rejected") }
    check(nativeCtrCalls == before + 1 && lastCtrIv == effectiveIv, "V1 unsigned CDN counter is encoded exactly")
}
for (badKey, badIv, badOffset) in invalidCdnParameters {
    let before = nativeCtrCalls
    if case .fail = legacyCdnResult(data: Data([1]), key: badKey, iv: badIv, at: badOffset) { check(true, "V1 invalid CDN fails") }
    else { check(false, "V1 invalid CDN parameters must fail") }
    check(nativeCtrCalls == before, "V1 malformed CDN never enters native CTR")
}
// Keep this at the end: the installed V1 implementation asserts for out-of-order
// input, and the optional baseline run must reproduce that safely in its child.
private let legacyOutOfOrder = MultipartDownloadState(encryptionKey: SecretFileEncryptionKey(aesKey: key, aesIv: originalIv), decryptedSize: 64)
let beforeReordered = nativeIgeCalls
check(legacyOutOfOrder.transform(offset: 16, data: ciphertext.prefix(16)) == nil, "V1 out-of-order direct transform returns failure instead of asserting")
check(legacyOutOfOrder.currentSize == 0 && legacyOutOfOrder.aesIv == originalIv && nativeIgeCalls == beforeReordered, "V1 out-of-order rejection preserves cipher state")
if failures > 0 { print("FAIL: \(failures) of \(assertions) actual-source cipher assertions"); exit(1) }
print("PASS: \(assertions) actual-source cipher admission/retry/native AES-IGE/CTR assertions")
'''
# Data exclusivity forbids querying its count inside a mutable-byte borrow.
swift = swift.replace("var ciphertext = padded\nciphertext.withUnsafeMutableBytes", "var ciphertext = padded\nlet ciphertextCount = ciphertext.count\nciphertext.withUnsafeMutableBytes").replace("data.baseAddress!, ciphertext.count, key", "data.baseAddress!, ciphertextCount, key")
with tempfile.TemporaryDirectory(prefix="supergram-fetch-cipher-") as temp:
    temporary = Path(temp)
    native_source, native_object = temporary / "native.m", temporary / "native.o"
    bridge_source, swift_source, binary = temporary / "native.h", temporary / "main.swift", temporary / "regression"
    native_source.write_text(native)
    bridge_source.write_text(bridge)
    swift_source.write_text(swift)
    subprocess.run(["xcrun", "clang", "-fobjc-arc", "-c", str(native_source), "-o", str(native_object)], check=True)
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", "-import-objc-header", str(bridge_source), str(swift_source), str(native_object), "-framework", "Foundation", "-o", str(binary)], check=True, timeout=60)
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
    if args.expect_failure:
        if result.returncode == 0:
            raise SystemExit("Expected pre-fix cipher failure was not reproduced")
        summary = next((line for line in reversed(result.stdout.splitlines()) if "actual-source cipher assertions" in line), "pre-fix child terminated")
        print(summary)
        print(f"PASS: pre-fix cipher fixture failed as expected (exit {result.returncode})")
    else:
        print(result.stdout, end="")
        if result.returncode:
            print(result.stderr)
            raise SystemExit(result.returncode)
