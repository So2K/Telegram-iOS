#!/usr/bin/env python3
"""Exercise actual NSE account resolver, removal helper and four cleanup predicates.

PeerId, including its checked Id/Namespace constructors and packed roundtrip,
is extracted from production. NotificationCenter and message/account types
are deterministic doubles. This does not deliver push or compile the extension
against the iOS SDK.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / "Telegram/NotificationService/Sources/NotificationService.swift").read_text()
peer_source = (ROOT / "submodules/Postbox/Sources/Peer.swift").read_text()
namespace_source = (ROOT / "submodules/TelegramCore/Sources/SyncCore/SyncCore_Namespaces.swift").read_text()


def block(marker, start=0, text=source):
    beginning = text.index(marker, start)
    opening = text.index("{", beginning)
    depth, ending = 1, opening + 1
    while depth:
        depth += (text[ending] == "{") - (text[ending] == "}")
        ending += 1
    return text[beginning:ending] + "\n"


# Keep the actual constructor, checked scalar/namespace initializers, conversion,
# comparisons and Codable behavior. Buffer serialization is unrelated to this test.
peer_fixture = block("public struct PeerId:", text=peer_source)
for marker in ["public static func encodeArrayToBuffer(", "public static func decodeArrayFromBuffer(", "public func encodeToBuffer("]:
    peer_fixture = peer_fixture.replace(block(marker, text=peer_fixture).rstrip(), "")


swift = r'''
import Foundation
import CoreFoundation
'''
swift += peer_fixture
swift += r'''
struct MessageId: Equatable { let peerId: PeerId; let namespace: Int32; let id: Int32 }
struct AccountRecordId { let int64: Int64 }
enum Namespaces {
    enum Message { static let Cloud: Int32 = 0 }
'''
swift += block("public struct Peer {", text=namespace_source)
swift += r'''
}
final class UNNotificationContent {
    var userInfo: [AnyHashable: Any]
    var categoryIdentifier: String
    init(_ userInfo: [AnyHashable: Any], category: String) { self.userInfo = userInfo; categoryIdentifier = category }
}
final class UNNotificationRequest {
    let identifier: String
    let content: UNNotificationContent
    init(_ identifier: String, _ payload: [AnyHashable: Any], category: String = "r") {
        self.identifier = identifier; content = UNNotificationContent(payload, category: category)
    }
}
final class UNNotification {
    let request: UNNotificationRequest
    init(_ request: UNNotificationRequest) { self.request = request }
}
final class UNUserNotificationCenter {
    static let shared = UNUserNotificationCenter()
    static func current() -> UNUserNotificationCenter { shared }
    var delivered: [UNNotification] = []
    var pending: [UNNotificationRequest] = []
    var removedDelivered: [[String]] = []
    var removedPending: [[String]] = []
    func getDeliveredNotifications(completionHandler: ([UNNotification]) -> Void) { completionHandler(delivered) }
    func getPendingNotificationRequests(completionHandler: ([UNNotificationRequest]) -> Void) { completionHandler(pending) }
    func removeDeliveredNotifications(withIdentifiers ids: [String]) {
        removedDelivered.append(ids); delivered.removeAll { ids.contains($0.request.identifier) }
    }
    func removePendingNotificationRequests(withIdentifiers ids: [String]) {
        removedPending.append(ids); pending.removeAll { ids.contains($0.identifier) }
    }
    func reset(_ delivered: [UNNotificationRequest], _ pending: [UNNotificationRequest] = []) {
        self.delivered = delivered.map(UNNotification.init); self.pending = pending
        removedDelivered = []; removedPending = []
    }
}
'''
for marker in ["private func notificationCleanupInt64(", "private func notificationCleanupInt32(", "private struct NotificationCleanupIdentity"]:
    swift += block(marker)
expression_start = source.index("private let notificationCleanupMessageKeyExpr")
expression_end = source.index("@available", expression_start)
swift += source[expression_start:expression_end]
for marker in ["private func notificationCleanupIdentity(", "private func removeNotificationRequestsForAccount(", "private func notificationPayloadInt64(", "private func notificationPayloadInt32(", "private func notificationPackedPeerId(", "private func notificationPayloadPeerId("]:
    swift += block(marker)
swift += "func decodedPayloadPeer(_ payloadJson: [String: Any]) -> PeerId? {\nvar peerId: PeerId?\n"
decode_start = source.index('if let userIdValue = notificationPayloadInt64(payloadJson["from_id"])')
decode_end = source.index("#if DEBUG", decode_start)
swift += source[decode_start:decode_end]
swift += "return peerId\n}\n"

for name, action, parameters in [
    ("deleteMessages", ".deleteMessage(ids):", "ids: [MessageId]"),
    ("readReactions", ".readReactions(ids):", "ids: [MessageId]"),
    ("readMessages", ".readMessage(id):", "id: MessageId"),
    ("readStories", ".readStories(peerId, maxId):", "peerId: PeerId, maxId: Int32"),
]:
    swift += f"func {name}(recordId: AccountRecordId, {parameters}, completion: @escaping (Bool) -> Void) {{\n"
    swift += block("removeNotificationRequestsForAccount(accountId: recordId.int64, matching:", source.index(action)).rstrip()
    swift += ", completion: completion)\n}\n"

swift += r'''
var assertions = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) { assertions += 1; precondition(value(), message) }
let a = AccountRecordId(int64: 101)
let b = AccountRecordId(int64: -202)
let peer = PeerId(55)
let seven = MessageId(peerId: peer, namespace: 0, id: 7)
let six = MessageId(peerId: peer, namespace: 0, id: 6)
func payload(_ account: Any? = nil, peer: Any = "55", namespace: Any? = nil, message: Any? = "7", typedId: Any? = nil) -> [AnyHashable: Any] {
    var result: [AnyHashable: Any] = ["peerId": peer]
    result["accountId"] = account; result["msg_id"] = message
    result["messageId.namespace"] = namespace; result["messageId.id"] = typedId
    return result
}
func scoped(_ account: Int64, namespace: Int32 = 0, id: Int32 = 7, category: String = "r", metadata: Bool = true) -> UNNotificationRequest {
    UNNotificationRequest("a\(account):m55:\(namespace):\(id)", metadata ? payload("\(account)", namespace: namespace, message: id, typedId: id) : [:], category: category)
}
let center = UNUserNotificationCenter.shared

// Same channel/message in two accounts must remain two separate delivered and pending entries.
let da = scoped(a.int64)
let db = scoped(b.int64)
let pa = scoped(a.int64, id: 6)
let pb = scoped(b.int64, id: 6)
center.reset([da, db], [pa, pb])
var completionCount = 0
deleteMessages(recordId: a, ids: [six, seven]) { removed in completionCount += 1; check(removed, "matching cleanup reports removal") }
check(completionCount == 1, "delivered plus pending completes once")
check(center.delivered.map { $0.request.identifier } == [db.identifier], "same-message other account delivered notification is retained")
check(center.pending.map { $0.identifier } == [pb.identifier], "same-message other account pending notification is retained")

// New prefix can supply ownership, but every present known field must agree.
check(notificationCleanupIdentity(scoped(b.int64, metadata: false))?.accountId == b.int64, "signed scoped prefix supplies absent account metadata")
for badAccount: Any in ["wrong", "999", true, NSNumber(value: 1.5), "9223372036854775808"] {
    check(notificationCleanupIdentity(UNNotificationRequest(da.identifier, payload(badAccount))) == nil, "invalid/conflicting account metadata rejects scoped request")
}
for (key, badValue) in [("peerId", "56"), ("msg_id", "8"), ("messageId.namespace", "1"), ("messageId.id", "8")] {
    var fields = payload("101", namespace: 0, typedId: 7)
    fields[key] = badValue
    check(notificationCleanupIdentity(UNNotificationRequest(da.identifier, fields)) == nil, "conflicting scoped message metadata rejects " + key)
}
check(notificationCleanupIdentity(UNNotificationRequest(da.identifier, payload("101", namespace: 0))) == nil, "partial typed message metadata is retained conservatively")
check(notificationCleanupIdentity(UNNotificationRequest(da.identifier, payload("101", message: "bad"))) == nil, "invalid present message metadata cannot inherit prefix")
for identifier in ["aX:m55:0:7", "a101:m55:0:7_suffix", "a101:m55:0:7:extra", "a101:m55:2147483648:7", "a101:m55:0:2147483648", "a9223372036854775808:m55:0:7", "a101:m55::7", "a+101:m55:0:7", "a101:m+55:0:7", "a101:m55:0:+7"] {
    check(notificationCleanupIdentity(UNNotificationRequest(identifier, payload("101"))) == nil, "malformed scoped syntax is retained: " + identifier)
}

// Legacy and opaque APNs identifiers require explicit owner metadata, including opaque IDs starting a/m.
for identifier in ["m55:0:7", "m55:0:7_legacy", "opaque-apns-uuid", "a7f4d4fa-uuid", "message-opaque-uuid"] {
    check(notificationCleanupIdentity(UNNotificationRequest(identifier, payload("101")))?.messageId == seven, "known-account legacy/remote request resolves " + identifier)
    check(notificationCleanupIdentity(UNNotificationRequest(identifier, payload())) == nil, "unowned legacy/remote request is retained " + identifier)
}
for account: Any in [Int64(101), Int32(101), Int(101), NSNumber(value: 101), NSString(string: "101"), "101"] {
    check(notificationCleanupIdentity(UNNotificationRequest("opaque", payload(account)))?.accountId == a.int64, "valid integer/string account representations resolve")
}
check(notificationCleanupIdentity(UNNotificationRequest("m55:0:7_suffix", payload("101", peer: "56"))) == nil, "legacy message identity conflict is retained")
check(notificationCleanupIdentity(UNNotificationRequest("m55:0:bad", payload("101"))) == nil, "malformed legacy syntax is retained")

// Scalar protocol IDs are bounded before the actual checked PeerId.Id construction.
for (key, namespace) in [("from_id", Namespaces.Peer.CloudUser), ("chat_id", Namespaces.Peer.CloudGroup), ("channel_id", Namespaces.Peer.CloudChannel)] {
    for value in [Int64(-1), 0, Int64(1) << 56, Int64.max] {
        let fields: [AnyHashable: Any] = ["accountId": "101", key: value, "msg_id": "7"]
        check(notificationCleanupIdentity(UNNotificationRequest("opaque-scalar", fields)) == nil, "invalid scalar peer cannot assert or identify cleanup " + key)
    }
    let fields: [AnyHashable: Any] = ["accountId": "101", key: Int64(55), "msg_id": "7"]
    check(notificationCleanupIdentity(UNNotificationRequest("opaque-scalar", fields))?.messageId?.peerId == PeerId(namespace: namespace, id: PeerId.Id._internalFromInt64Value(55)), "valid scalar peer cleanup resolves " + key)
}
for (key, namespace) in [("from_id", Namespaces.Peer.CloudUser), ("chat_id", Namespaces.Peer.CloudGroup), ("channel_id", Namespaces.Peer.CloudChannel)] {
    for value in [Int64(-1), 0, Int64(1) << 56, Int64.max] {
        check(decodedPayloadPeer([key: value]) == nil, "decoded malformed scalar peer does not assert " + key)
    }
    check(decodedPayloadPeer([key: Int64(55)]) == PeerId(namespace: namespace, id: PeerId.Id._internalFromInt64Value(55)), "decoded valid scalar peer resolves " + key)
    check(decodedPayloadPeer([key: Int64(0x00ffffffffffffff)]) == PeerId(namespace: namespace, id: PeerId.Id._internalFromInt64Value(0x00ffffffffffffff)), "decoded 56-bit scalar boundary resolves " + key)
    let decodedBoundary = decodedPayloadPeer([key: Int64(0x00ffffffffffffff)])!
    check(PeerId(decodedBoundary.toInt64()) == decodedBoundary, "actual decoded cloud boundary roundtrips " + key)
}
for value in [Int64.min, Int64(Int32.min) - 1, 0, Int64(Int32.max) + 1, 0xffffffff, Int64.max] {
    check(decodedPayloadPeer(["encryption_id": value]) == nil, "secret chat ID must fit signed Int32 without zero")
}
for value in [Int64(Int32.min), -1, 1, Int64(Int32.max)] {
    let expected = PeerId(namespace: Namespaces.Peer.SecretChat, id: PeerId.Id._internalFromInt64Value(value))
    let decoded = decodedPayloadPeer(["encryption_id": value])
    check(decoded == expected, "actual signed secret chat ID resolves")
    check(decoded.map { PeerId($0.toInt64()) == $0 } == true, "actual signed secret chat ID roundtrips")
}
// Packed peer values must be canonical before the actual PeerId initializer can assert.
for value in [Int64.min, -1, Int64.max, Int64(0x0800000000000000), 0x0000000700000000, 0x7fffffff00000000, 0x7fffffff00000001] {
    check(notificationPackedPeerId(value) == nil, "unsafe or sentinel packed peer is rejected before checked construction")
    check(notificationPayloadPeerId(["peerId": value]) == nil, "old payload helper rejects unsafe packed peer")
    check(notificationCleanupIdentity(UNNotificationRequest("opaque-packed", ["accountId": "101", "peerId": value, "msg_id": "7"])) == nil, "payload packed peer cannot assert during cleanup")
    for identifier in ["a101:m\(value):0:7", "m\(value):0:7"] {
        check(notificationCleanupIdentity(UNNotificationRequest(identifier, ["accountId": "101"])) == nil, "scoped and legacy packed peers are validated before construction")
    }
}
for value: Int64 in [0, 1, 55, 0x00000003ffffffff, 0x0000000700000001, 0x0000000800000000, 0x07ffffffffffffff] {
    let actualPeer = PeerId(value)
    check(actualPeer.toInt64() == value, "real PeerId valid boundary roundtrips")
    check(notificationPackedPeerId(value) == actualPeer, "canonical boundary accepted by checked packed helper")
    check(notificationCleanupIdentity(UNNotificationRequest("opaque-packed", ["accountId": "101", "peerId": value, "msg_id": "7"]))?.messageId?.peerId == actualPeer, "valid packed boundary resolves remote payload")
    check(notificationCleanupIdentity(UNNotificationRequest("a101:m\(value):0:7", [:]))?.messageId?.peerId == actualPeer, "valid packed boundary resolves scoped identifier")
}
check(notificationPayloadPeerId(["peerId": Int64(0)]) == nil, "existing payload helper preserves zero peer rejection")

// The pools must be filtered separately even when a legacy identifier is identical across them.
let legacyA = UNNotificationRequest("m55:0:7", payload("101"))
let legacyB = UNNotificationRequest("m55:0:7", payload("-202"))
center.reset([legacyA], [legacyB, scoped(a.int64, id: 6)])
deleteMessages(recordId: a, ids: [six, seven]) { _ in }
check(center.delivered.isEmpty && center.pending.map { $0.identifier } == [legacyB.identifier], "delivered A identifier does not delete pending B with identical legacy ID")
check(center.removedPending.flatMap { $0 } == ["a101:m55:0:6"], "pending removal uses its own account-filtered IDs")

// Deletion is an exact set, while reading is a maximum within an account+peer+namespace.
center.reset([scoped(a.int64, id: 6), scoped(a.int64, id: 7), scoped(a.int64, id: 8)])
deleteMessages(recordId: a, ids: [seven]) { _ in }
check(center.delivered.map { $0.request.identifier } == ["a101:m55:0:6", "a101:m55:0:8"], "exact deletion does not erase earlier or later messages")
let otherNamespace = scoped(a.int64, namespace: 1, id: 1)
let otherPeer = UNNotificationRequest("a101:m56:0:1", ["accountId": "101", "peerId": "56", "msg_id": "1"])
let unknown = UNNotificationRequest("m55:0:1", payload(message: "1"))
center.reset([scoped(a.int64, id: 6), scoped(a.int64, id: 8), db, otherNamespace, otherPeer, unknown], [scoped(a.int64, id: 7), pb])
readMessages(recordId: a, id: seven) { _ in }
check(center.delivered.map { $0.request.identifier } == ["a101:m55:0:8", db.identifier, otherNamespace.identifier, otherPeer.identifier, unknown.identifier], "read maximum respects namespace/peer/account and retains unknown")
check(center.pending.map { $0.identifier } == [pb.identifier], "read maximum scopes pending pool")

// Reactions require category t in addition to account and exact message identity.
let reactionA = UNNotificationRequest("reaction-a", payload("101"), category: "t")
let reactionB = UNNotificationRequest("reaction-b", payload("-202"), category: "t")
let ordinaryA = UNNotificationRequest("ordinary-a", payload("101"), category: "r")
let reactionUnknown = UNNotificationRequest("reaction-unknown", payload(), category: "t")
center.reset([reactionA, reactionB, ordinaryA, reactionUnknown], [reactionA, reactionB])
readReactions(recordId: a, ids: [seven]) { _ in }
check(center.delivered.map { $0.request.identifier } == [reactionB.identifier, ordinaryA.identifier, reactionUnknown.identifier], "reaction cleanup preserves ordinary, foreign and unknown-account notifications")
check(center.pending.map { $0.identifier } == [reactionB.identifier], "reaction pending cleanup respects account")

func story(_ identifier: String, account: String?, id: Int32) -> UNNotificationRequest {
    var fields: [AnyHashable: Any] = ["peerId": "55", "story_id": id]
    fields["accountId"] = account
    return UNNotificationRequest(identifier, fields, category: "st")
}
let storyA = story("story-a", account: "101", id: 4)
let storyB = story("story-b", account: "-202", id: 4)
let storyUnknown = story("story-unknown", account: nil, id: 4)
let storyFuture = story("story-future", account: "101", id: 6)
center.reset([storyA, storyB, storyUnknown, storyFuture], [storyA, storyB])
readStories(recordId: a, peerId: peer, maxId: 5) { _ in }
check(center.delivered.map { $0.request.identifier } == [storyB.identifier, storyUnknown.identifier, storyFuture.identifier], "story cleanup respects account, threshold and unknown metadata")
check(center.pending.map { $0.identifier } == [storyB.identifier], "story pending cleanup respects account")

center.reset([], [scoped(a.int64)])
deleteMessages(recordId: a, ids: [seven]) { removed in check(removed, "pending-only matching cleanup reports removal") }
check(center.pending.isEmpty && center.removedDelivered.isEmpty, "pending-only cleanup does not manufacture delivered removal")
var emptyCompletions = 0
deleteMessages(recordId: a, ids: [seven]) { removed in emptyCompletions += 1; check(!removed, "empty repeated cleanup reports no removal") }
check(emptyCompletions == 1, "empty cleanup completes once")
print("PASS: \(assertions) actual-source NSE account identity and delivered/pending delete/read/reaction/story cleanup assertions")
'''

with tempfile.TemporaryDirectory(prefix="supergram-notification-account-") as temporary:
    swift_source = Path(temporary) / "main.swift"
    executable = Path(temporary) / "regression"
    swift_source.write_text(swift)
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", str(swift_source), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
