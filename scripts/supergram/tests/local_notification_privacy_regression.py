#!/usr/bin/env python3
"""Test extracted local fallback and real notification-policy resolution on macOS.

Signals/postbox data and UserNotifications are doubles. No account, device,
permission, notification delivery, or network is touched.
"""
from pathlib import Path
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


application = (ROOT / "submodules/TelegramUI/Sources/ApplicationContext.swift").read_text()
state = (ROOT / "submodules/TelegramCore/Sources/State/AccountStateManager.swift").read_text()
cleanup = (ROOT / "submodules/TelegramUI/Sources/ClearNotificationsManager.swift").read_text()
swift = r'''
import Foundation
import CoreFoundation
enum NoError: Error {}
struct Signal<T, E: Error> {
    let values: [T]
    static func single(_ value: T) -> Signal { Signal(values: [value]) }
    static func complete() -> Signal { Signal(values: []) }
    func start(next: (T) -> Void) { values.forEach(next) }
}
infix operator |> : AdditionPrecedence
func |> <T, R>(value: T, transform: (T) -> R) -> R { transform(value) }
func map<T, R>(_ f: @escaping (T) -> R) -> (Signal<T, NoError>) -> Signal<R, NoError> { { Signal(values: $0.values.map(f)) } }
func mapToSignal<T, R>(_ f: @escaping (T) -> Signal<R, NoError>) -> (Signal<T, NoError>) -> Signal<R, NoError> { { Signal(values: $0.values.flatMap { f($0).values }) } }
func take<T>(_ count: Int) -> (Signal<T, NoError>) -> Signal<T, NoError> { { Signal(values: Array($0.values.prefix(count))) } }
func deliverOnMainQueue<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> { precondition(Thread.isMainThread); return signal }
final class Atomic<T> { var value: T; init(_ value: T) { self.value = value }; func with<R>(_ f: (T) -> R) -> R { f(value) } }
enum Namespaces { enum Peer { static let CloudUser = 0; static let CloudGroup = 1; static let CloudChannel = 2; static let SecretChat = 3 }; enum Message { static let Cloud: Int32 = 0 } }
struct PeerId: Hashable {
    struct Id { let value: Int64; static func _internalFromInt64Value(_ value: Int64) -> Id { Id(value: value) } }
    let namespace: Int
    let value: Int64
    init(namespace: Int, value: Int64) { self.namespace = namespace; self.value = value }
    init(namespace: Int, id: Id) { self.namespace = namespace; self.value = id.value }
    init(_ raw: Int64) { namespace = Int(raw / 100000); value = raw % 100000 }
    func toInt64() -> Int64 { Int64(namespace) * 100000 + value }
}
struct MessageId: Hashable, Comparable {
    let peerId: PeerId; let namespace: Int32; let id: Int32
    static func < (lhs: MessageId, rhs: MessageId) -> Bool { lhs.id < rhs.id }
}
class Peer { let id: PeerId; let title: String; var associatedPeerId: PeerId?; init(_ id: PeerId, _ title: String) { self.id = id; self.title = title } }
final class TelegramSecretChat: Peer {}
final class TelegramChannel: Peer {
    enum Info { case broadcast, group }; enum Participation { case member, kicked, left }
    var info = Info.group; var isMonoForum = false; var flags: MessageFlags = []; var participationStatus = Participation.member
}
struct MessageFlags: OptionSet { let rawValue: Int; static let muted = Self(rawValue: 1); static let isForum = Self(rawValue: 2); static let isImported = Self(rawValue: 4); static let WasScheduled = Self(rawValue: 8) }
final class NotificationInfoMessageAttribute { var flags: MessageFlags; init(_ flags: MessageFlags) { self.flags = flags } }
final class ReplyMessageAttribute { var threadMessageId: MessageId? }
struct ForwardInfo { var flags: MessageFlags = [] }
enum MediaAction { case messageAutoremoveTimeoutUpdated, conferenceCall, groupMigratedToChannel, channelMigratedFromGroup, other }
final class TelegramMediaAction { let action: MediaAction; init(_ action: MediaAction) { self.action = action } }
final class Message {
    let id: MessageId; var threadId: Int64?; let author: Peer?; let peers: [PeerId: Peer]; var text: String
    var attributes: [Any] = []; var media: [Any] = []; var forwardInfo: ForwardInfo?; var sourceReference: Int?; var groupingKey: Int64?; var personal = false
    var index: Int { Int(id.id) }; var flags: MessageFlags = []
    init(id: MessageId, peer: Peer, author: Peer?, text: String) { self.id = id; self.author = author; self.peers = [peer.id: peer]; self.text = text }
}
enum PeerMessageSound: Equatable { case none, `default`, bundledModern(id: Int32), bundledClassic(id: Int32), cloud(fileId: Int64) }
let defaultCloudPeerNotificationSound = PeerMessageSound.cloud(fileId: 10)
let defaultCloudPeerNotificationSoundFixture = defaultCloudPeerNotificationSound
enum Preview { case `default`, show, hide }
enum Mute { case `default`, unmuted, muted(deadline: Int32) }
struct TelegramPeerNotificationSettings { var messageSound = PeerMessageSound.default; var displayPreviews = Preview.default; var muteState = Mute.default }
struct MessageNotificationSettings { var sound = PeerMessageSound.default; var enabled = true; var displayPreviews = true }
struct GlobalNotificationSettings {
    var privateChats = MessageNotificationSettings(); var channels = MessageNotificationSettings(); var groupChats = MessageNotificationSettings()
    var effective: Self { self }; static var defaultSettings: Self { Self() }
}
struct MessageHistoryThreadData { var notificationSettings: TelegramPeerNotificationSettings }
struct DataBox { let value: Any; func get<T>(_ type: T.Type) -> T? { value as? T } }
struct ThreadInfo { let data: DataBox }
struct ReadState { let read: Bool; func isIncomingMessageIndexRead(_ index: Int) -> Bool { read } }
enum PreferencesKeys { static let globalNotifications = 0 }
final class Transaction {
    var message: Message?; var global = GlobalNotificationSettings(); var peerSettings: TelegramPeerNotificationSettings?; var topicSettings: TelegramPeerNotificationSettings?; var read = false
    func getMessage(_ id: MessageId) -> Message? { message?.id == id ? message : nil }
    func getPeer(_ id: PeerId) -> Peer? { message?.peers[id] }
    func getPeerNotificationSettings(id: PeerId) -> Any? { peerSettings }
    func getPreferencesEntry(key: Int) -> DataBox? { DataBox(value: global) }
    func getMessageHistoryThreadInfo(peerId: PeerId, threadId: Int64) -> ThreadInfo? { topicSettings.map { ThreadInfo(data: DataBox(value: MessageHistoryThreadData(notificationSettings: $0))) } }
    func getCombinedPeerReadState(_ id: PeerId) -> ReadState? { ReadState(read: read) }
    func getMessageForwardedGroup(_ id: MessageId) -> [Message]? { nil }
    func getMessageGroup(_ id: MessageId) -> [Message]? { nil }
}
final class Logger { static let shared = Logger(); func log(_ category: String, _ text: String) {} }
'''
swift += block(state, "func resolveNotificationSettings(list:")
swift += block(state, "public func messagesForNotification(transaction:")
swift += r'''
struct AccountId { let int64: Int64 }
final class Postbox { let data: Transaction; var lookups = 0; init(_ data: Transaction) { self.data = data }; func transaction<T>(_ f: (Transaction) -> T) -> Signal<T, NoError> { lookups += 1; return .single(f(data)) } }
final class Account { let id = AccountId(int64: 42); let peerId = PeerId(namespace: 0, value: 99); let postbox: Postbox; init(_ data: Transaction) { postbox = Postbox(data) } }
final class AppLockContextImpl { var isCurrentlyLocked = Signal<Bool, NoError>.single(false) }
struct PresentationFixture { let strings = 0; let nameDisplayOrder = 0; let dateTimeFormat = 0 }
final class SharedContext { var appLockContext: AnyObject? = AppLockContextImpl(); let currentPresentationData = Atomic(PresentationFixture()) }
final class AccountContext { let account: Account; let sharedContext = SharedContext(); let currentContentSettings = Atomic(0); init(_ data: Transaction) { account = Account(data) } }
struct InAppNotificationSettings { var displayPreviews = true; var playSounds = true; static var defaultSettings: Self { Self() } }
struct EngineMessage { typealias Id = MessageId; let message: Message; init(_ message: Message) { self.message = message } }
struct EnginePeer { typealias Id = PeerId; let peer: Peer; init(_ peer: Peer) { self.peer = peer }; var id: PeerId { peer.id }; var compactDisplayTitle: String { peer.title }; func displayTitle(strings: Int, displayOrder: Int) -> String { peer.title } }
func messageMainPeer(_ message: EngineMessage) -> EnginePeer? { message.message.peers[message.message.id.peerId].map(EnginePeer.init) }
func descriptionStringForMessage(contentSettings: Int, message: EngineMessage, strings: Int, nameDisplayOrder: Int, dateTimeFormat: Int, accountPeerId: PeerId) -> (NSAttributedString, Bool, Bool) { (NSAttributedString(string: message.message.text), false, true) }
final class UNNotificationSound { static let `default` = UNNotificationSound() }
final class UNMutableNotificationContent {
    enum Level { case active, timeSensitive }
    var title = ""; var body = ""; var sound: UNNotificationSound?; var categoryIdentifier = ""; var threadIdentifier = ""; var userInfo: [AnyHashable: Any] = [:]; var interruptionLevel = Level.active; var relevanceScore = 0.0
}
struct UNNotificationRequest { let identifier: String; let content: UNMutableNotificationContent; let trigger: Int? }
final class UNUserNotificationCenter {
    static let shared = UNUserNotificationCenter(); var requests: [UNNotificationRequest] = []
    static func current() -> UNUserNotificationCenter { shared }
    func add(_ request: UNNotificationRequest, withCompletionHandler: (Error?) -> Void) { requests.append(request); withCompletionHandler(nil) }
}
let telegramLocalNotificationFallbackEnabled = true
let telegramLocalNotificationFallbackKey = "sgLocalNotificationFallback"
func superGramNoteBackgroundNotificationActivity() {}
final class ApplicationFixture {
    let context: AccountContext
    var inAppNotificationSettings: InAppNotificationSettings? = .defaultSettings
    init(_ data: Transaction) { context = AccountContext(data) }
    func send(_ messages: [Message], notify: Bool = true) { scheduleBackgroundMessageNotification(messages: messages, notify: notify) }
'''
for marker in ["private func superGramGenericNotificationBody(", "private func scheduleBackgroundMessageNotification(", "private func enqueueBackgroundMessageNotification("]:
    swift += block(application, marker)
swift += "}\n"
swift += cleanup[cleanup.index("private let messageNotificationKeyExpr"):cleanup.index("public final class ClearNotificationIdsCompletion")]
swift += r'''
func check(_ condition: @autoclosure () -> Bool, _ label: String) { precondition(condition(), label) }
func fixture(namespace: Int = 0, title: String = "Alice") -> (ApplicationFixture, Transaction, Message) {
    let data = Transaction()
    let id = PeerId(namespace: namespace, value: 7)
    let peer: Peer
    if namespace == Namespaces.Peer.SecretChat { peer = TelegramSecretChat(id, title) }
    else if namespace == Namespaces.Peer.CloudChannel { peer = TelegramChannel(id, title) }
    else { peer = Peer(id, title) }
    let author = namespace == Namespaces.Peer.CloudGroup || namespace == Namespaces.Peer.CloudChannel ? Peer(PeerId(namespace: 0, value: 8), "Bob") : peer
    let message = Message(id: MessageId(peerId: id, namespace: 0, id: 11), peer: peer, author: author, text: "private message")
    data.message = message
    return (ApplicationFixture(data), data, message)
}
func content(_ app: ApplicationFixture, _ message: Message) -> UNMutableNotificationContent {
    UNUserNotificationCenter.shared.requests.removeAll(); app.send([message]); check(UNUserNotificationCenter.shared.requests.count == 1, "one source notification decision"); return UNUserNotificationCenter.shared.requests[0].content
}
func generic(_ value: UNMutableNotificationContent, _ label: String) { check(value.title.isEmpty && value.body == "You have a new message", label) }
let (normalApp, normalData, normalMessage) = fixture()
let normal = content(normalApp, normalMessage)
check(normal.title == "Alice" && normal.body == "private message", "authorized private preview retained")
normalData.global.privateChats.displayPreviews = false
generic(content(normalApp, normalMessage), "global preview disabled even when in-app preview enabled")
normalData.global.privateChats.displayPreviews = true
normalData.peerSettings = TelegramPeerNotificationSettings(displayPreviews: .hide)
generic(content(normalApp, normalMessage), "chat override hides sender and body")
normalData.peerSettings = nil
normalApp.inAppNotificationSettings?.displayPreviews = false
generic(content(normalApp, normalMessage), "in-app conservative preview gate preserved")
normalApp.inAppNotificationSettings?.displayPreviews = true
(normalApp.context.sharedContext.appLockContext as! AppLockContextImpl).isCurrentlyLocked = .single(true)
generic(content(normalApp, normalMessage), "locked app hides sender and body")
(normalApp.context.sharedContext.appLockContext as! AppLockContextImpl).isCurrentlyLocked = .single(false)
let (groupApp, groupData, groupMessage) = fixture(namespace: Namespaces.Peer.CloudChannel, title: "Team")
(groupMessage.peers[groupMessage.id.peerId] as! TelegramChannel).flags.insert(.isForum)
groupMessage.threadId = 99
groupData.peerSettings = TelegramPeerNotificationSettings(displayPreviews: .show)
groupData.topicSettings = TelegramPeerNotificationSettings(displayPreviews: .hide)
generic(content(groupApp, groupMessage), "topic hide takes precedence over chat show")
groupData.topicSettings = TelegramPeerNotificationSettings(displayPreviews: .show)
groupData.global.groupChats.displayPreviews = false
let topicAllowed = content(groupApp, groupMessage)
check(topicAllowed.title == "Team" && topicAllowed.body == "Bob: private message", "topic show overrides default and preserves group sender")
check(topicAllowed.userInfo["threadId"] as? Int64 == 99 && topicAllowed.userInfo["accountId"] as? String == "42" && topicAllowed.categoryIdentifier == "gr", "account/forum routing unchanged")
let request = UNUserNotificationCenter.shared.requests[0]
check(NotificationManagedNotificationRequestId(string: request.identifier, userInfo: request.content.userInfo) == .messageId(groupMessage.id, accountId: 42), "fallback account-scoped id stays readable by cleanup parser")
let (secretApp, _, secretMessage) = fixture(namespace: Namespaces.Peer.SecretChat)
generic(content(secretApp, secretMessage), "secret chat never reveals peer or content")
normalData.peerSettings = TelegramPeerNotificationSettings(messageSound: .none)
check(content(normalApp, normalMessage).sound == nil, "resolved Sound None silences fallback")
normalData.peerSettings = nil
normalMessage.attributes = [NotificationInfoMessageAttribute(.muted)]
check(content(normalApp, normalMessage).sound == nil, "muted message remains silent")
normalMessage.attributes = []
normalApp.inAppNotificationSettings?.playSounds = false
check(content(normalApp, normalMessage).sound == nil, "play sounds off remains silent")
normalApp.inAppNotificationSettings?.playSounds = true
check(content(normalApp, normalMessage).sound != nil, "non-silent existing default sound retained")
normalData.read = true
normalMessage.flags = [.WasScheduled]
check(!messagesForNotification(transaction: normalData, id: normalMessage.id, alwaysReturnMessage: true).notify, "scheduled fixture differs from ordinary unread decision")
check(content(normalApp, normalMessage).body == "private message", "scheduled source notify=true preserved while policy is resolved")
normalData.message = nil
generic(content(normalApp, normalMessage), "missing policy lookup fails closed to generic")
let previousLookups = normalApp.context.account.postbox.lookups
UNUserNotificationCenter.shared.requests.removeAll(); normalApp.send([normalMessage], notify: false)
check(UNUserNotificationCenter.shared.requests.isEmpty && normalApp.context.account.postbox.lookups == previousLookups, "source notify=false never queues or performs lookup")
print("PASS: extracted local fallback privacy, global/chat/topic policy, lock/secret, group sender, silent sound, scheduled decision, missing lookup, and cleanup identifier regressions")
'''
with tempfile.TemporaryDirectory(prefix="supergram-notification-privacy-") as temporary:
    source = Path(temporary) / "main.swift"
    executable = Path(temporary) / "regression"
    # Fixture types are internal; visibility is the only production declaration adjustment.
    source.write_text(swift.replace("public ", ""))
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", str(source), "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
