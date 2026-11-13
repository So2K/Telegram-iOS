import Foundation
import UIKit
import SwiftSignalKit
import TelegramCore

/// One chat the user opened, with the place they left off.
public struct SuperGramChatHistoryEntry: Codable, Equatable {
    public var peerId: Int64
    public var threadId: Int64?
    /// Last visible message when the chat was left; nil when the user was at the bottom of the chat.
    public var messageNamespace: Int32?
    public var messageId: Int32?
    public var timestamp: Int32
    /// Title at the time of the visit, used only when the peer can no longer be resolved.
    public var title: String

    public var enginePeerId: EnginePeer.Id {
        return EnginePeer.Id(self.peerId)
    }

    public var savedMessageId: EngineMessage.Id? {
        guard let messageNamespace = self.messageNamespace, let messageId = self.messageId else {
            return nil
        }
        return EngineMessage.Id(peerId: self.enginePeerId, namespace: messageNamespace, id: messageId)
    }

    func isSameChat(peerId: Int64, threadId: Int64?) -> Bool {
        return self.peerId == peerId && self.threadId == threadId
    }
}

// SuperGram: browser-like history of opened chats ("History" button at the top left of the chat list).
// It answers two everyday problems: a channel closed by accident while scrolling far back, and a chat the
// user left to answer someone else. Every opened chat is recorded with the last message that was on screen,
// so the history can reopen it exactly where the user stopped. Stored per account in UserDefaults; secret
// chats are never recorded.
public final class SuperGramChatHistory {
    public static let shared = SuperGramChatHistory()

    public static let enabledKey = "sgChatListHistoryButton"
    private static let maxEntries = 200

    private let queue = Queue(name: "SuperGramChatHistory")
    private var cachedEntries: [Int64: [SuperGramChatHistoryEntry]] = [:]
    private var pendingSaveAccounts = Set<Int64>()
    private var isSaveScheduled = false
    private let updatedPipe = ValuePipe<Int64>()

    // Accessed only on the main thread
    private var activePositionSavers: [ObjectIdentifier: () -> Void] = [:]
    private var applicationObservers: [NSObjectProtocol] = []

    private init() {
    }

    /// Registers (or with nil removes) a callback that saves the reading position of a chat that is currently on
    /// screen. All registered callbacks run when the app leaves the foreground, and the history is then written to
    /// disk synchronously, so the position survives the app being suspended or closed from the app switcher.
    /// Main thread only.
    public func setActivePositionSaver(owner: AnyObject, saver: (() -> Void)?) {
        assert(Thread.isMainThread)
        let key = ObjectIdentifier(owner)
        if let saver {
            self.activePositionSavers[key] = saver
        } else {
            self.activePositionSavers.removeValue(forKey: key)
        }
        if self.applicationObservers.isEmpty {
            let handler: (Notification) -> Void = { [weak self] _ in
                self?.saveActivePositionsAndFlush()
            }
            self.applicationObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main, using: handler))
            self.applicationObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: handler))
            self.applicationObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main, using: handler))
        }
    }

    private func saveActivePositionsAndFlush() {
        for saver in self.activePositionSavers.values {
            saver()
        }
        // updatePosition() enqueues on the same serial queue, so this write includes the positions saved above
        self.queue.sync {
            self.flush()
        }
    }

    /// Whether the History button and the moved Edit button replace the stock chat list header buttons.
    public static var isEnabled: Bool {
        return UserDefaults.standard.object(forKey: SuperGramChatHistory.enabledKey) as? Bool ?? true
    }

    private static func storageKey(accountPeerId: Int64) -> String {
        return "sgChatHistory_\(accountPeerId)"
    }

    // Accessed only on queue
    private func loadedEntries(accountPeerId: Int64) -> [SuperGramChatHistoryEntry] {
        if let entries = self.cachedEntries[accountPeerId] {
            return entries
        }
        var entries: [SuperGramChatHistoryEntry] = []
        if let data = UserDefaults.standard.data(forKey: SuperGramChatHistory.storageKey(accountPeerId: accountPeerId)), let decoded = try? JSONDecoder().decode([SuperGramChatHistoryEntry].self, from: data) {
            entries = decoded
        }
        self.cachedEntries[accountPeerId] = entries
        return entries
    }

    // Accessed only on queue
    private func store(accountPeerId: Int64, entries: [SuperGramChatHistoryEntry]) {
        self.cachedEntries[accountPeerId] = entries
        self.pendingSaveAccounts.insert(accountPeerId)
        self.updatedPipe.putNext(accountPeerId)
        if !self.isSaveScheduled {
            self.isSaveScheduled = true
            // Coalesce bursts (open chat + leave chat + navigate) into one write
            self.queue.after(1.0, { [weak self] in
                self?.flush()
            })
        }
    }

    // Accessed only on queue
    private func flush() {
        self.isSaveScheduled = false
        let accounts = self.pendingSaveAccounts
        self.pendingSaveAccounts.removeAll()
        for accountPeerId in accounts {
            let entries = self.cachedEntries[accountPeerId] ?? []
            if let data = try? JSONEncoder().encode(entries) {
                UserDefaults.standard.set(data, forKey: SuperGramChatHistory.storageKey(accountPeerId: accountPeerId))
            }
        }
    }

    /// Records that a chat was opened; it moves to the top of the history. The saved position is kept.
    public func recordVisit(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id, threadId: Int64?, title: String) {
        if peerId.namespace == Namespaces.Peer.SecretChat {
            return
        }
        let accountKey = accountPeerId.toInt64()
        let peerKey = peerId.toInt64()
        let timestamp = Int32(Date().timeIntervalSince1970)
        self.queue.async {
            var entries = self.loadedEntries(accountPeerId: accountKey)
            var entry = SuperGramChatHistoryEntry(peerId: peerKey, threadId: threadId, messageNamespace: nil, messageId: nil, timestamp: timestamp, title: title)
            if let index = entries.firstIndex(where: { $0.isSameChat(peerId: peerKey, threadId: threadId) }) {
                entry.messageNamespace = entries[index].messageNamespace
                entry.messageId = entries[index].messageId
                if title.isEmpty {
                    entry.title = entries[index].title
                }
                entries.remove(at: index)
            }
            entries.insert(entry, at: 0)
            if entries.count > SuperGramChatHistory.maxEntries {
                entries.removeLast(entries.count - SuperGramChatHistory.maxEntries)
            }
            self.store(accountPeerId: accountKey, entries: entries)
        }
    }

    /// Saves where the user stopped in a chat. Pass nil when they were at the bottom (latest messages).
    public func updatePosition(accountPeerId: EnginePeer.Id, peerId: EnginePeer.Id, threadId: Int64?, messageId: EngineMessage.Id?) {
        if peerId.namespace == Namespaces.Peer.SecretChat {
            return
        }
        let accountKey = accountPeerId.toInt64()
        let peerKey = peerId.toInt64()
        let timestamp = Int32(Date().timeIntervalSince1970)
        self.queue.async {
            var entries = self.loadedEntries(accountPeerId: accountKey)
            guard let index = entries.firstIndex(where: { $0.isSameChat(peerId: peerKey, threadId: threadId) }) else {
                return
            }
            var entry = entries[index]
            if let messageId, messageId.peerId == peerId {
                entry.messageNamespace = messageId.namespace
                entry.messageId = messageId.id
            } else {
                entry.messageNamespace = nil
                entry.messageId = nil
            }
            entry.timestamp = timestamp
            if entry == entries[index] {
                return
            }
            entries[index] = entry
            self.store(accountPeerId: accountKey, entries: entries)
        }
    }

    public func remove(accountPeerId: EnginePeer.Id, peerId: Int64, threadId: Int64?) {
        let accountKey = accountPeerId.toInt64()
        self.queue.async {
            var entries = self.loadedEntries(accountPeerId: accountKey)
            entries.removeAll(where: { $0.isSameChat(peerId: peerId, threadId: threadId) })
            self.store(accountPeerId: accountKey, entries: entries)
        }
    }

    public func clear(accountPeerId: EnginePeer.Id) {
        let accountKey = accountPeerId.toInt64()
        self.queue.async {
            self.store(accountPeerId: accountKey, entries: [])
        }
    }

    /// Current history of an account, newest first; emits again on every change.
    public func entries(accountPeerId: EnginePeer.Id) -> Signal<[SuperGramChatHistoryEntry], NoError> {
        let accountKey = accountPeerId.toInt64()
        return Signal { subscriber in
            let disposable = self.updatedPipe.signal().start(next: { [weak self] updatedAccount in
                guard let self, updatedAccount == accountKey else {
                    return
                }
                self.queue.async {
                    subscriber.putNext(self.loadedEntries(accountPeerId: accountKey))
                }
            })
            self.queue.async {
                subscriber.putNext(self.loadedEntries(accountPeerId: accountKey))
            }
            return disposable
        }
    }
}
