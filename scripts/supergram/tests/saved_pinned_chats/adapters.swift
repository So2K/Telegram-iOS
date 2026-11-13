import Foundation
import SwiftSignalKit

struct PeerId: Hashable {
    let raw: Int64
    init(_ raw: Int64) { self.raw = raw }
    var id: PeerId { self }
    func _internalGetInt64Value() -> Int64 { raw }
    func toInt64() -> Int64 { raw }
}
struct MessageId: Hashable {
    let peerId: PeerId
    let namespace: Int32
    let id: Int32
}
enum StoreMessageId { case Id(MessageId), Partial(PeerId, Int32) }
struct Message { let threadId: Int64? }
struct ApiMessage { let id: MessageId; let threadId: Int64? }
struct StoreMessage {
    let id: StoreMessageId
    let threadId: Int64?
    init?(apiMessage: ApiMessage, accountPeerId: PeerId, peerIsForum: Bool) {
        precondition(!peerIsForum)
        self.id = .Id(apiMessage.id); self.threadId = apiMessage.threadId
    }
}
struct Peer { let id: PeerId }
struct StoredMessageHistoryThreadInfo { let value: Int }
struct MessageIndex { let id: MessageId }
struct Namespaces { struct Message { static let Cloud: Int32 = 0 } }
struct TelegramSeed { let automaticThreadIndexInfo: (PeerId, Int64) -> StoredMessageHistoryThreadInfo? }
let telegramPostboxSeedConfiguration = TelegramSeed(automaticThreadIndexInfo: { _, _ in StoredMessageHistoryThreadInfo(value: 1) })
struct AccumulatedPeers {
    let values: [PeerId: Peer]
    init(transaction: Transaction, chats: [Peer], users: [Peer]) {
        self.values = Dictionary((chats + users).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    }
    func get(_ id: PeerId) -> Peer? { values[id] }
}
func updatePeers(transaction: Transaction, accountPeerId: PeerId, peers: AccumulatedPeers) { transaction.peers = transaction.peers.merging(peers.values, uniquingKeysWith: { _, new in new }); transaction.peerWrites += 1 }
struct PeerOperationLogTag: Equatable { let value: Int }
struct OperationLogTags {
    static let SynchronizePinnedChats = PeerOperationLogTag(value: 25)
    static let SynchronizePinnedSavedChats = PeerOperationLogTag(value: 26)
}
struct PeerGroupId { let rawValue: Int32 }
class SynchronizePinnedChatsOperation {}
struct PeerMergedOperationLogEntry { let peerId: PeerId; let tagLocalIndex: Int32; let mergedIndex: Int32; let contents: Any }
struct OperationEntry {
    var mergedIndex: Int32?
    var contents: Any
    let peerId: PeerId
    let localIndex: Int32
    var mergedEntry: PeerMergedOperationLogEntry? { mergedIndex.map { PeerMergedOperationLogEntry(peerId: peerId, tagLocalIndex: localIndex, mergedIndex: $0, contents: contents) } }
}
enum EntryMergedUpdate { case none }
enum EntryContentsUpdate { case none }
struct PeerOperationLogEntryUpdate { let mergedIndex: EntryMergedUpdate; let contents: EntryContentsUpdate }
struct MergedView { let entries: [PeerMergedOperationLogEntry] }
enum MessageLocation { case UpperHistoryBlock }
final class Transaction {
    var pins: [Int64] = []
    var peers: [PeerId: Peer] = [:]
    var messages: [MessageId: Message] = [:]
    var infos: [Int64: StoredMessageHistoryThreadInfo] = [:]
    var log: [Int32: OperationEntry] = [:]
    var removed: [Int32] = []
    var pinWrites = 0
    var peerWrites = 0
    var messageWrites = 0
    var combinedState = "unchanged-full-list-boundary"
    func operationLogUpdateEntry(peerId: PeerId, tag: PeerOperationLogTag, tagLocalIndex: Int32, _ f: (OperationEntry?) -> PeerOperationLogEntryUpdate) { _ = f(log[tagLocalIndex]) }
    func operationLogRemoveEntry(peerId: PeerId, tag: PeerOperationLogTag, tagLocalIndex: Int32) -> Bool { removed.append(tagLocalIndex); return log.removeValue(forKey: tagLocalIndex) != nil }
    func getPeerPinnedThreads(peerId: PeerId) -> [Int64] { pins }
    func setPeerPinnedThreads(peerId: PeerId, threadIds: [Int64]) { pins = threadIds; pinWrites += 1 }
    func getPeer(_ id: PeerId) -> Peer? { peers[id] }
    func getMessage(_ id: MessageId) -> Message? { messages[id] }
    func getMessageHistoryThreadInfo(peerId: PeerId, threadId: Int64) -> StoredMessageHistoryThreadInfo? { infos[threadId] }
    func setMessageHistoryThreadInfo(peerId: PeerId, threadId: Int64, info: StoredMessageHistoryThreadInfo?) { infos[threadId] = info }
    func addMessages(_ input: [StoreMessage], location: MessageLocation) -> Int {
        messageWrites += 1
        for message in input { if case let .Id(id) = message.id { messages[id] = Message(threadId: message.threadId) } }
        return input.count
    }
    func isRenderable(_ threadId: Int64) -> Bool {
        // Thread index replay requires both topIndex and info; no combined-state shortcut.
        infos[threadId] != nil && messages.contains { $0.key.peerId == PeerId(100) && $0.value.threadId == threadId }
    }
}
final class Postbox {
    let tx = Transaction()
    var holdNextTransaction = false
    var queued: [() -> Void] = []
    var transactionCount = 0
    let view = Promise(MergedView(entries: []))
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        return Signal { subscriber in
            self.transactionCount += 1
            let work = { subscriber.putNext(f(self.tx)); subscriber.putCompletion() }
            if self.holdNextTransaction { self.holdNextTransaction = false; self.queued.append(work) } else { work() }
            return EmptyDisposable
        }
    }
    func drain() { let list = queued; queued = []; list.forEach { $0() } }
    func mergedOperationLogView(tag: PeerOperationLogTag, limit: Int) -> Signal<MergedView, NoError> { view.get() }
}
struct Api {
    struct Peer { let peerId: PeerId }
    struct SavedDialogData { let flags: Int32; let peer: Peer; let topMessage: Int32 }
    enum SavedDialog { case savedDialog(SavedDialogData), monoForumDialog }
    struct SavedDialogsData { let dialogs: [SavedDialog]; let messages: [ApiMessage]; let chats: [SwiftPeer]; let users: [SwiftPeer] }
    enum InputDialogPeer { case inputDialogPeer(InputDialogPeerData) }
    struct InputDialogPeerData { let peer: InputPeer }
    struct InputPeer { let peer: PeerId }
    struct messages { enum SavedDialogs { case savedDialogs(SavedDialogsData), savedDialogsNotModified, savedDialogsSlice(SavedDialogsData) } }
    struct functions { struct messages {
        static func getPinnedSavedDialogs() -> GetPins { GetPins() }
        static func reorderPinnedSavedDialogs(flags: Int32, order: [InputDialogPeer]) -> SetPins { SetPins() }
    } }
}
typealias SwiftPeer = Peer
func apiInputPeer(_ peer: Peer) -> Api.InputPeer? { Api.InputPeer(peer: peer.id) }
struct GetPins {}
struct SetPins {}
enum TestError: Error { case failed }
final class Network {
    enum Reply { case data(Api.messages.SavedDialogs), error, deferred }
    var replies: [Reply] = []
    private let fetchCount = Atomic<Int>(value: 0)
    var fetches: Int { fetchCount.with { $0 } }
    var setters = 0
    var getterDisposals = 0
    var setterDisposals = 0
    var pending: [Subscriber<Api.messages.SavedDialogs, TestError>] = []
    var pendingSetters: [Subscriber<Bool, TestError>] = []
    var onFetch: ((Int) -> Void)?
    var onRegistration: (() -> Void)?
    func request(_ request: GetPins) -> Signal<Api.messages.SavedDialogs, TestError> {
        return Signal { subscriber in
            let _ = self.fetchCount.modify { $0 + 1 }
            self.onFetch?(self.fetches)
            let reply = self.replies.isEmpty ? .deferred : self.replies.removeFirst()
            switch reply {
            case let .data(data): subscriber.putNext(data); subscriber.putCompletion()
            case .error: subscriber.putError(.failed)
            case .deferred: self.pending.append(subscriber)
            }
            self.onRegistration?()
            return ActionDisposable { self.getterDisposals += 1 }
        }
    }
    func request(_ request: SetPins) -> Signal<Bool, TestError> {
        return Signal { subscriber in
            self.setters += 1; self.pendingSetters.append(subscriber)
            return ActionDisposable { self.setterDisposals += 1 }
        }
    }
    func emit(_ data: Api.messages.SavedDialogs) { let subscriber = pending.removeFirst(); subscriber.putNext(data); subscriber.putCompletion() }
    func finishSetter(error: Bool = false) { let subscriber = pendingSetters.removeFirst(); if error { subscriber.putError(.failed) } else { subscriber.putNext(true); subscriber.putCompletion() } }
}
final class AccountStateManager {}
struct Account { let peerId: PeerId; let postbox: Postbox; let network: Network }
struct EnginePeer { typealias Id = PeerId }
enum SetForumChannelTopicPinnedError { case generic; case limitReached(Int) }
