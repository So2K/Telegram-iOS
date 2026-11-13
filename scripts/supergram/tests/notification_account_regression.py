#!/usr/bin/env python3
"""Compile actual account notification parser/manager/bindings with platform doubles.

No account, notification delivery, permissions, device, or network is used. Queue
and notification-center snapshots are manually flushed to exercise overlapping
cleanup requests instead of making timing-dependent assertions.
"""
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    return source[start:end] + "\n"


manager_path = ROOT / "submodules/TelegramUI/Sources/ClearNotificationsManager.swift"
manager = manager_path.read_text()
bindings = (ROOT / "submodules/AccountContext/Sources/AccountContext.swift").read_text()
application = (ROOT / "submodules/TelegramUI/Sources/ApplicationContext.swift").read_text()
delegate = (ROOT / "submodules/TelegramUI/Sources/AppDelegate.swift").read_text()
shared = (ROOT / "submodules/TelegramUI/Sources/SharedNotificationManager.swift").read_text()
peer = (ROOT / "submodules/Postbox/Sources/Peer.swift").read_text()
namespace = (ROOT / "submodules/TelegramCore/Sources/SyncCore/SyncCore_Namespaces.swift").read_text()
peer_fixture = block(peer, "public struct PeerId:")
for marker in ["public static func encodeArrayToBuffer(", "public static func decodeArrayFromBuffer(", "public func encodeToBuffer("]:
    peer_fixture = peer_fixture.replace(block(peer_fixture, marker).rstrip(), "")

swift = r'''
import Foundation
import CoreFoundation
enum NoError: Error {}
struct Signal<T, E: Error> { let value: T; static func single(_ value: T) -> Signal { Signal(value: value) } }
protocol Disposable {}
struct EmptyDisposable: Disposable {}
final class Queue {
    static let main = Queue(); static var pending: [() -> Void] = []
    static func mainQueue() -> Queue { main }
    func async(_ f: @escaping () -> Void) { Self.pending.append(f) }
    static func flush() { while !pending.isEmpty { let f = pending.removeFirst(); f() } }
}
enum SwiftSignalKit { final class Timer {
    let completion: () -> Void
    init(timeout: Double, repeat: Bool, completion: @escaping () -> Void, queue: Queue) { self.completion = completion }
    func invalidate() {}; func start() {}
} }
'''
swift += peer_fixture
swift += r'''
struct MessageId: Hashable, Comparable {
    let peerId: PeerId; let namespace: Int32; let id: Int32
    static func <(l: Self, r: Self) -> Bool {
        if l.peerId != r.peerId { return l.peerId < r.peerId }
        if l.namespace != r.namespace { return l.namespace < r.namespace }
        return l.id < r.id
    }
}
enum EnginePeer { typealias Id = PeerId }
enum EngineMessage { typealias Id = MessageId }
enum Namespaces {
    enum Message { static let Cloud: Int32 = 0 }
'''
swift += block(namespace, "public struct Peer {")
swift += r'''
}
struct AccountRecordId { let int64: Int64; init(int64: Int64) { self.int64 = int64 }; init(rawValue: Int64) { self.int64 = rawValue } }
final class UIWindow {}; final class UIViewController {}; final class WindowHost {}
struct PresentationAppIcon {}; enum UIInterfaceOrientation { case portrait }
enum TelegramAppBuildType { case `internal`, `public` }
enum AccessType { case allowed }
final class TelegramApplicationOpenUrlCompletion {}
'''
swift += "\n".join(line for line in manager.splitlines() if not line.startswith("import ")) + "\n"
swift += block(bindings, "public final class TelegramApplicationBindings")
swift += r'''
struct UNNotification {
    struct Content { let userInfo: [AnyHashable: Any] }; struct Request { let content: Content }; let request: Request
    init(_ payload: [AnyHashable: Any]) { request = Request(content: Content(userInfo: payload)) }
}
enum SharedPayloadFixture {
'''
for marker in ["private func notificationPayloadInt64(", "private func notificationPayloadInt32(", "private func notificationPayloadPeerId("]:
    swift += block(shared, marker).replace("private func", "static func")
swift += "static func secret(_ payload: [AnyHashable: Any]) -> PeerId? { var peerId: EnginePeer.Id?\n"
swift += block(shared, 'if let encryptionId = notificationPayloadInt32(payload["encryption_id"])')
swift += "return peerId\n}\n}\n"
swift += "enum TapPayloadFixture {\n"
for marker in ["private func notificationPayloadInt64(", "private func notificationPayloadInt32(", "private func peerIdFromNotification("]:
    swift += block(delegate, marker).replace("private func", "static func")
swift += "static func account(_ notification: UNNotification) -> Signal<AccountRecordId?, NoError> {\n"
swift += block(delegate, 'if let rawId = notification.request.content.userInfo["accountId"]')
swift += "return .single(nil)\n}\n}\n"
swift += "func tapAction(_ payload: [AnyHashable: Any], accountId: AccountRecordId?) -> Bool {\nstruct Response { let notification: UNNotification }; let response = Response(notification: UNNotification(payload)); var opened = false; var completed = 0\nfunc completionHandler() { completed += 1 }\nfunc perform() {\n"
swift += block(delegate, 'if accountId == nil && response.notification.request.content.userInfo["accountId"] != nil')
swift += "opened = true\n}\nperform()\ncheck(completed == (opened ? 0 : 1), \"invalid account callback completes once\")\nreturn opened\n}\n"
push_condition_start = delegate.index('if let fromIdString = payloadJson["from_id"]')
push_condition = delegate[push_condition_start:delegate.index("{", push_condition_start)]
swift += "func pushCallPeer(_ payloadJson: [AnyHashable: Any]) -> PeerId? {\n" + push_condition + "{ _ = (groupCallId, messageId, fromTitle)\nreturn PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(fromId))\n}\nreturn nil\n}\n"
swift += r'''
var assertions = 0
func check(_ value: @autoclosure () -> Bool, _ label: String) { assertions += 1; precondition(value(), label) }
func mid(_ id: Int32, namespace: Int32 = 0, peer: Int64 = 7) -> MessageId { MessageId(peerId: PeerId(peer), namespace: namespace, id: id) }
func parsed(_ string: String, _ payload: [AnyHashable: Any] = [:]) -> NotificationManagedNotificationRequestId? { NotificationManagedNotificationRequestId(string: string, userInfo: payload) }
let accountA: Int64 = -101
let accountB: Int64 = 202
check(parsed("a-101:m7:-2:-3") == .messageId(mid(-3, namespace: -2), accountId: accountA), "signed account/message values with canonical peer")
check(parsed("a\(Int64.min):m\(0x07ffffffffffffff):\(Int32.min):\(Int32.max)") != nil, "account/namespace/message boundaries with real packed peer maximum")
for invalid: Int64 in [-1, Int64.min, Int64.max, 1 << 59, 0x0000000700000000, 0x7fffffff00000000] {
    check(parsed("a-101:m\(invalid):0:3") == nil, "unsafe packed peer identifier rejected before real constructor")
    check(parsed("remote", ["accountId": "-101", "peerId": "\(invalid)", "msg_id": "3"]) == nil, "unsafe packed peer payload rejected before real constructor")
    check(parsed("m\(invalid):0:3_legacy") == nil, "unsafe legacy packed peer rejected")
}
for valid: Int64 in [0, 7, 1 << 32, (3 << 32) | 0xffffffff, 1 << 35, 0x07ffffffffffffff] {
    let expected = PeerId(valid)
    check(expected.toInt64() == valid, "real Peer.swift packed roundtrip")
    check(parsed("a-101:m\(valid):0:3") == .messageId(mid(3, peer: valid), accountId: accountA), "valid packed peer passes real constructor")
    check(parsed("remote", ["accountId": "-101", "peerId": "\(valid)", "msg_id": "3"]) == .messageId(mid(3, peer: valid), accountId: accountA), "valid packed payload passes real constructor")
}
for invalid in ["a9223372036854775808:m7:0:3", "a-9223372036854775809:m7:0:3", "a1:m9223372036854775808:0:3", "a1:m7:2147483648:3", "a1:m7:0:-2147483649", "aX:m7:0:3", "a1:m7:0:3_suffix", "a1:m7:0:3junk", "a1:m7:0:3\n"] {
    check(parsed(invalid, ["accountId": "1", "peerId": "7", "msg_id": "3"]) == nil, "malformed scoped identifier does not fall back: \(invalid)")
}
check(parsed("m7:0:3_legacy") == .messageId(mid(3)), "legacy underscore suffix constructor preserved")
check(parsed("m7:0:3_legacy", ["accountId": "-101"]) == .messageId(mid(3), accountId: accountA), "legacy metadata supplies scope")
check(parsed("a-101:m7:0:3", ["accountId": "202"]) == nil, "account conflict fails closed")
check(parsed("a-101:m7:0:3", ["accountId": "overflow"]) == nil, "present invalid account fails closed")
check(parsed("a-101:m7:0:3", ["accountId": NSNumber(value: true)]) == nil, "boolean is not account identity")
check(parsed("a-101:m7:0:3", ["accountId": NSNumber(value: 1.5)]) == nil, "fraction is not account identity")
check(parsed("a-101:m7:0:3", ["peerId": "8"]) == nil, "peer metadata conflict")
check(parsed("a-101:m7:0:3", ["messageId.namespace": 1]) == nil, "namespace metadata conflict")
check(parsed("a-101:m7:0:3", ["msg_id": "4"]) == nil, "message metadata conflict")
check(parsed("a-101:m7:0:3", ["messageId.id": 4]) == nil, "local message metadata conflict")
check(parsed("abc-uuid", ["accountId": "-101", "peerId": "7", "msg_id": "3"]) == .messageId(mid(3), accountId: accountA), "opaque remote UUID may begin a")
check(parsed("remote", ["accountId": "-101", "peerId": "7", "msg_id": "3", "messageId.namespace": 4, "messageId.id": 3]) == .messageId(mid(3, namespace: 4), accountId: accountA), "metadata preserves local namespace")
check(parsed("remote", ["accountId": "-101", "from_id": "7", "msg_id": "3"]) == .messageId(mid(3), accountId: accountA), "remote peer metadata parity")
for key in ["from_id", "chat_id", "channel_id"] {
    for invalid: Int64 in [-1, 0, 1 << 56, Int64.max] {
        check(parsed("remote", ["accountId": "-101", key: "\(invalid)", "msg_id": "3"]) == nil, "unpacked peer scalar bounds: \(key)/\(invalid)")
    }
}
for invalid: Int64 in [-1, Int64.min, Int64.max, 1 << 59, 0x0000000700000000, 0x7fffffff00000000] {
    check(TapPayloadFixture.peerIdFromNotification(UNNotification(["peerId": "\(invalid)"])) == nil, "actual system tap packed peer guard")
}
for valid: Int64 in [0, 7, (3 << 32) | 0xffffffff, 0x07ffffffffffffff] {
    check(TapPayloadFixture.peerIdFromNotification(UNNotification(["peerId": "\(valid)"]))?.peerId.toInt64() == valid, "actual system tap canonical peer roundtrip")
}
for key in ["from_id", "chat_id", "channel_id"] {
    for invalid: Int64 in [-1, 0, 1 << 56, Int64.max] {
        check(SharedPayloadFixture.notificationPayloadPeerId([key: "\(invalid)"]) == nil, "actual decrypted peer scalar helper guards constructor")
        check(TapPayloadFixture.peerIdFromNotification(UNNotification([key: "\(invalid)"])) == nil, "actual tap scalar helper guards constructor")
    }
    for valid: Int64 in [1, 0x00ffffffffffffff] {
        check(SharedPayloadFixture.notificationPayloadPeerId([key: "\(valid)"])?.id._internalGetInt64Value() == valid, "actual decrypted positive scalar constructor")
        check(TapPayloadFixture.peerIdFromNotification(UNNotification([key: "\(valid)"]))?.peerId.id._internalGetInt64Value() == valid, "actual tap positive scalar constructor")
    }
}
for value in [Int32.min, -1, 1, Int32.max] {
    let secret = SharedPayloadFixture.secret(["encryption_id": "\(value)"])
    check(secret?.namespace == Namespaces.Peer.SecretChat && secret?.id._internalGetInt64Value() == Int64(value), "actual decrypted secret branch accepts nonzero signed Int32")
    let tapped = TapPayloadFixture.peerIdFromNotification(UNNotification(["encryption_id": "\(value)"]))?.peerId
    check(tapped == secret && tapped.map { PeerId($0.toInt64()) == $0 } == true, "actual tap negative secret id canonical roundtrip")
}
for value: Int64 in [0, Int64(Int32.min) - 1, Int64(Int32.max) + 1, 1 << 56, Int64.min, Int64.max] {
    check(SharedPayloadFixture.secret(["encryption_id": "\(value)"]) == nil, "decrypted secret id outside signed Int32 rejected")
    check(TapPayloadFixture.peerIdFromNotification(UNNotification(["encryption_id": "\(value)"])) == nil, "tap secret id outside signed Int32 rejected")
}
for invalid: Any in [NSNumber(value: true), NSNumber(value: false), NSNumber(value: 1.5), NSNumber(value: UInt64.max), "9223372036854775808"] {
    check(SharedPayloadFixture.notificationPayloadInt64(invalid) == nil && TapPayloadFixture.notificationPayloadInt64(invalid) == nil, "actual decrypted/tap numeric helpers reject lossy bridges")
    check(TapPayloadFixture.account(UNNotification(["accountId": invalid])).value == nil, "actual explicit account metadata does not route invalid number")
    check(TapPayloadFixture.peerIdFromNotification(UNNotification(["peerId": invalid])) == nil, "actual tap packed metadata rejects invalid number")
}
for value: Int64 in [Int64.min, -101, 202, Int64.max] {
    check(TapPayloadFixture.account(UNNotification(["accountId": NSNumber(value: value)])).value?.int64 == value, "actual account metadata accepts signed full-width integer")
}
check(tapAction([:], accountId: nil), "actual tap guard preserves absent legacy account routing")
check(tapAction(["accountId": "-101"], accountId: AccountRecordId(int64: accountA)), "actual tap guard preserves valid explicit account")
for invalid: Any in [NSNumber(value: true), NSNumber(value: 1.5), NSNumber(value: UInt64.max), "bad"] {
    let account = TapPayloadFixture.account(UNNotification(["accountId": invalid])).value
    check(!tapAction(["accountId": invalid], accountId: account), "actual tap guard blocks invalid-present account instead of current-account fallback")
}
for invalid: Int64 in [-1, 0, 1 << 56, Int64.max] {
    check(pushCallPeer(["from_id": "\(invalid)", "group_call_id": "1", "msg_id": "3", "from_title": "fixture"]) == nil, "actual PushKit group call scalar condition guards constructor")
}
check(pushCallPeer(["from_id": "7", "group_call_id": "1", "msg_id": "3", "from_title": "fixture"])?.id._internalGetInt64Value() == 7, "valid PushKit group call peer")

typealias Entry = (String, NotificationManagedNotificationRequestId)
final class Center {
    var delivered: [Entry] = []; var pending: [Entry] = []
    var deliveredCallbacks: [ClearNotificationIdsCompletion] = []; var pendingCallbacks: [ClearNotificationIdsCompletion] = []
    lazy var manager = ClearNotificationsManager(getNotificationIds: { [unowned self] in deliveredCallbacks.append($0) }, removeNotificationIds: { [unowned self] ids in delivered.removeAll { ids.contains($0.0) } }, getPendingNotificationIds: { [unowned self] in pendingCallbacks.append($0) }, removePendingNotificationIds: { [unowned self] ids in pending.removeAll { ids.contains($0.0) } })
    func finish(reverse: Bool = false) {
        let d = deliveredCallbacks; let p = pendingCallbacks; deliveredCallbacks = []; pendingCallbacks = []
        for callback in reverse ? d.reversed() : d { callback.f(delivered) }
        for callback in reverse ? p.reversed() : p { callback.f(pending) }
        Queue.flush()
    }
}
func entry(_ key: String, _ account: Int64?, _ id: Int32, namespace: Int32 = 0) -> Entry { (key, .messageId(mid(id, namespace: namespace), accountId: account)) }
let center = Center()
center.delivered = [entry("A-old", accountA, 2), entry("A-new", accountA, 5), entry("B-same", accountB, 5), entry("A-other-namespace", accountA, 1, namespace: -1), entry("unknown", nil, 1)]
center.pending = [entry("A-pending", accountA, 4), entry("B-pending", accountB, 4), entry("unknown-pending", nil, 1)]
center.manager.append(mid(4), accountId: accountA); center.manager.append(mid(2), accountId: accountA); center.manager.commitNow(); center.finish()
check(Set(center.delivered.map { $0.0 }) == ["A-new", "B-same", "A-other-namespace", "unknown"], "read isolates account, namespace and maximum")
check(Set(center.pending.map { $0.0 }) == ["B-pending", "unknown-pending"], "pending has same scoped read rules")
center.delivered.append(entry("A-older-still-valid", accountA, 3))
center.manager.removeExact(mid(5), accountId: accountA); center.manager.commitNow(); center.finish()
check(center.delivered.contains { $0.0 == "A-older-still-valid" } && !center.delivered.contains { $0.0 == "A-new" } && center.delivered.contains { $0.0 == "B-same" }, "delete newer removes exact target only")
center.delivered.append(entry("A-ns4", accountA, 9, namespace: 4)); center.pending.append(entry("A-ns4-pending", accountA, 9, namespace: 4))
center.manager.append(mid(5), accountId: accountB); center.manager.commitNow()
center.manager.removeExact(mid(9, namespace: 4), accountId: accountA); center.manager.commitNow()
center.finish(reverse: true)
check(Set(center.delivered.map { $0.0 }) == ["A-other-namespace", "unknown", "A-older-still-valid"], "overlapping read/delete snapshots stay independent")
check(Set(center.pending.map { $0.0 }) == ["unknown-pending"], "overlapping pending snapshots stay independent")
center.delivered += [("A-call", parsed("call", ["accountId": "-101"])!), ("B-story", parsed("story", ["accountId": "202"])!)]
center.pending += [("A-random", parsed("random", ["accountId": "-101", "random_id": "88"])!), ("opaque-unknown", .globallyUniqueId(99, nil))]
center.manager.clearAll(accountId: accountA); center.finish()
check(Set(center.delivered.map { $0.0 }) == ["unknown", "B-story"], "logout clears account-owned opaque and message notifications only")
check(Set(center.pending.map { $0.0 }) == ["unknown-pending", "opaque-unknown"], "logout keeps unknown pending identities")
let sameLegacyKey = Center()
sameLegacyKey.delivered = [entry("m7:0:5_legacy", accountA, 5)]
sameLegacyKey.pending = [entry("m7:0:5_legacy", accountB, 5)]
sameLegacyKey.manager.append(mid(5), accountId: accountA); sameLegacyKey.manager.commitNow(); sameLegacyKey.finish()
check(sameLegacyKey.delivered.isEmpty && sameLegacyKey.pending.count == 1, "same legacy key across delivered/pending pools retains other account")

func makeBindings(legacy: @escaping ([MessageId]) -> Void, scoped: ((AccountRecordId, [MessageId]) -> Void)? = nil) -> TelegramApplicationBindings {
    if scoped == nil {
        return TelegramApplicationBindings(isMainApp: false, appBundleId: "fixture", appBuildType: .internal, containerPath: "", appSpecificScheme: "", openUrl: { _ in }, openUniversalUrl: { _, _ in }, canOpenUrl: { _ in false }, getTopWindow: { nil }, displayNotification: { _ in }, applicationInForeground: .single(false), applicationIsActive: .single(false), clearMessageNotifications: legacy, pushIdleTimerExtension: { EmptyDisposable() }, openSettings: {}, openAppStorePage: {}, openSubscriptions: {}, registerForNotifications: { _ in }, requestSiriAuthorization: { _ in }, siriAuthorization: { .allowed }, getWindowHost: { nil }, presentNativeController: { _ in }, dismissNativeController: {}, getAvailableAlternateIcons: { [] }, getAlternateIconName: { nil }, requestSetAlternateIconName: { _, _ in }, forceOrientation: { _ in })
    }
    return TelegramApplicationBindings(isMainApp: false, appBundleId: "fixture", appBuildType: .internal, containerPath: "", appSpecificScheme: "", openUrl: { _ in }, openUniversalUrl: { _, _ in }, canOpenUrl: { _ in false }, getTopWindow: { nil }, displayNotification: { _ in }, applicationInForeground: .single(false), applicationIsActive: .single(false), clearMessageNotifications: legacy, pushIdleTimerExtension: { EmptyDisposable() }, openSettings: {}, openAppStorePage: {}, openSubscriptions: {}, registerForNotifications: { _ in }, requestSiriAuthorization: { _ in }, siriAuthorization: { .allowed }, getWindowHost: { nil }, presentNativeController: { _ in }, dismissNativeController: {}, getAvailableAlternateIcons: { [] }, getAlternateIconName: { nil }, requestSetAlternateIconName: { _, _ in }, forceOrientation: { _ in }, clearMessageNotificationsForAccount: scoped)
}
var legacyIds: [MessageId] = []
let legacy = makeBindings(legacy: { legacyIds = $0 })
legacy.clearMessageNotificationsForAccount(AccountRecordId(int64: accountA), [mid(1)])
check(legacyIds == [mid(1)], "old extension initializer preserves supplied legacy closure")
var capturedAccount: Int64?
let explicit = makeBindings(legacy: { _ in preconditionFailure("main scoped route must not fall back") }, scoped: { capturedAccount = $0.int64; legacyIds = $1 })
explicit.clearMessageNotificationsForAccount(AccountRecordId(int64: accountB), [mid(2)])
check(capturedAccount == accountB && legacyIds == [mid(2)], "explicit binding forwards caller account")
'''

# Compile actual scoped binding and decrypted-account call statements too.
expected = [
    (application, r"strongSelf\.context\.sharedContext\.applicationBindings\.clearMessageNotificationsForAccount\(strongSelf\.context\.account\.id, ids\)"),
    (delegate, r"self\.clearNotificationsManager\?\.append\(id, accountId: accountId\.int64\)"),
    (shared, r"self\.clearNotificationsManager\?\.append\(readMessageId, accountId: account\.id\.int64\)"),
    (shared, r"self\.clearNotificationsManager\?\.removeExact\(messageId, accountId: account\.id\.int64\)"),
    (shared, r"self\.clearNotificationsManager\?\.clearAll\(accountId: account\.id\.int64\)"),
]
for source, pattern in expected:
    assert re.search(pattern, source), f"Missing actual account-scoped caller: {pattern}"
assert delegate.count("NotificationManagedNotificationRequestId(string:") >= 4
for line in delegate.splitlines():
    if "NotificationManagedNotificationRequestId(string:" in line:
        assert "userInfo:" in line, "Delivered and pending collectors must resolve account metadata identically"
forced_logout = block(shared, "if isForcedLogOut {")
assert "continue" in forced_logout and "return" not in forced_logout

calls = [re.search(pattern, source).group(0) for source, pattern in expected]
swift += r'''
final class StandaloneFixture { func startStandalone() {} }
func logoutFromAccount(id: AccountRecordId, accountManager: Int, alreadyLoggedOutRemotely: Bool) -> StandaloneFixture { StandaloneFixture() }
final class RouteFixture {
    struct Account { let id: AccountRecordId }; struct Shared { let applicationBindings: TelegramApplicationBindings }; struct Context { let account: Account; let sharedContext: Shared }
    let context: Context; var clearNotificationsManager: ClearNotificationsManager?; var accountManager: Int? = 1; var processed: [Int64] = []
    init(_ accountId: Int64, _ manager: ClearNotificationsManager, _ binding: TelegramApplicationBindings) { clearNotificationsManager = manager; context = Context(account: Account(id: AccountRecordId(int64: accountId)), sharedContext: Shared(applicationBindings: binding)) }
    func incomingRead(_ ids: [MessageId]) { let strongSelf = self
'''
swift += calls[0] + "\n}\nfunc mainBinding(accountId: AccountRecordId, ids: [MessageId]) { for id in ids {\n" + calls[1] + "\n}\n}\n"
swift += "func remoteRead(account: Account, readMessageId: MessageId) {\n" + calls[2] + "\n}\nfunc remoteDelete(account: Account, messageId: MessageId) {\n" + calls[3] + "\n}\n"
swift += "func batch(_ items: [(Int64, Bool)]) { for (rawId, isForcedLogOut) in items { let account = Account(id: AccountRecordId(int64: rawId))\n" + forced_logout + "\nprocessed.append(account.id.int64)\n}\n}\n}\n"
swift += r'''
let routeCenter = Center()
routeCenter.delivered = [entry("route-A", accountA, 5), entry("route-B", accountB, 5)]
var forwardedAccount: Int64?
let routeBinding = makeBindings(legacy: { _ in preconditionFailure("account route missing") }, scoped: { forwardedAccount = $0.int64; for id in $1 { routeCenter.manager.append(id, accountId: $0.int64) } })
let route = RouteFixture(accountB, routeCenter.manager, routeBinding)
route.incomingRead([mid(5)]); routeCenter.manager.commitNow(); routeCenter.finish()
check(forwardedAccount == accountB && routeCenter.delivered.map { $0.0 } == ["route-A"], "actual appliedIncomingReadMessages forwards owning context instead of selected account")
route.mainBinding(accountId: AccountRecordId(int64: accountA), ids: [mid(4)])
route.remoteDelete(account: RouteFixture.Account(id: AccountRecordId(int64: accountB)), messageId: mid(5))
route.remoteRead(account: RouteFixture.Account(id: AccountRecordId(int64: accountB)), readMessageId: mid(4))
routeCenter.manager.commitNow(); routeCenter.finish()
check(routeCenter.delivered.map { $0.0 } == ["route-A"], "actual main/decrypted deletion routes preserve higher other-account message")
route.batch([(accountA, true), (accountB, false)]); routeCenter.finish()
check(route.processed == [accountB] && routeCenter.delivered.isEmpty, "actual forced-logout branch scopes cleanup and continues later account in batch")
'''

identifier_line = next(line.strip() for line in application.splitlines() if 'let identifier = "a' in line)
thread_line = next(line.strip() for line in application.splitlines() if 'content.threadIdentifier = "account-' in line)
swift += r'''
final class IdentityFixture {
    struct Account { let id: AccountRecordId }; struct Context { let account: Account }; struct Message { let id: MessageId }; final class Content { var threadIdentifier = "" }
    let context: Context
    init(_ account: Int64) { context = Context(account: Account(id: AccountRecordId(int64: account))) }
    func identity(_ message: MessageId) -> (String, String) {
        let firstMessage = Message(id: message); let content = Content()
'''
swift += identifier_line + "\n" + thread_line + "\nreturn (identifier, content.threadIdentifier)\n}\n}\n"
swift += r'''
let identityA = IdentityFixture(accountA).identity(mid(5))
let identityB = IdentityFixture(accountB).identity(mid(5))
check(identityA.0 != identityB.0 && identityA.1 != identityB.1, "same peer and message across accounts has distinct request and grouping identity")
check(parsed(identityA.0)?.accountId == accountA && parsed(identityB.0)?.accountId == accountB, "actual fallback identifiers round trip")
print("PASS: \(assertions) checks of actual Peer.swift constructors, notification parser, decrypted/tap/PushKit payload helpers, account/namespace read maxima, exact deletion, overlapping delivered/pending cleanup, scoped logout, binding compatibility and fallback grouping")
'''
with tempfile.TemporaryDirectory(prefix="supergram-notification-account-") as temporary:
    source = Path(temporary) / "main.swift"
    executable = Path(temporary) / "regression"
    source.write_text(swift.replace("public ", ""))
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", str(source), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
