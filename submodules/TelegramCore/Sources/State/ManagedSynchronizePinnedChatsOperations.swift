import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

enum SavedPinnedThreadsSynchronizationState {
    fileprivate struct Key: Hashable {
        let postbox: ObjectIdentifier
        let accountPeerId: PeerId
    }

    fileprivate final class State {
        weak var postbox: Postbox?
        var generation = UUID()
        var mutations = 0
        var readers = 0
        var waiters: [UUID: (UUID) -> Void] = [:]

        init(postbox: Postbox) {
            self.postbox = postbox
        }
    }

    fileprivate static let states = Atomic<[Key: State]>(value: [:])

    final class Scope {
        private let postbox: Postbox
        fileprivate let key: Key
        fileprivate let state: State
        private let release: Disposable
        private var isDisposed = false
        private var waiterIds = Set<UUID>()

        fileprivate init(postbox: Postbox, key: Key, state: State, release: Disposable) {
            self.postbox = postbox
            self.key = key
            self.state = state
            self.release = release
        }

        func dispose() {
            states.with { entries in
                self.isDisposed = true
                if entries[self.key] === self.state {
                    for waiterId in self.waiterIds {
                        self.state.waiters.removeValue(forKey: waiterId)
                    }
                }
                self.waiterIds.removeAll()
            }
            self.release.dispose()
        }

        var isActive: Bool {
            return states.with { _ in !self.isDisposed }
        }

        func matches(_ generation: UUID) -> Bool {
            return states.with { entries in
                return !self.isDisposed && entries[self.key] === self.state && self.state.postbox === self.postbox
                    && self.state.mutations == 0 && self.state.generation == generation
            }
        }

        func waitForIdle() -> Signal<UUID, NoError> {
            return Signal { subscriber in
                let waiterId = UUID()
                var isValid = false
                let generation = states.with { entries -> UUID? in
                    guard !self.isDisposed, entries[self.key] === self.state, self.state.postbox === self.postbox else {
                        return nil
                    }
                    isValid = true
                    if self.state.mutations == 0 {
                        return self.state.generation
                    }
                    self.waiterIds.insert(waiterId)
                    self.state.waiters[waiterId] = { generation in
                        subscriber.putNext(generation)
                        subscriber.putCompletion()
                    }
                    return nil
                }
                // Subscriber callouts can reenter this registry on the same queue.
                if let generation {
                    subscriber.putNext(generation)
                    subscriber.putCompletion()
                } else if !isValid {
                    subscriber.putCompletion()
                }
                return ActionDisposable {
                    states.with { entries in
                        self.waiterIds.remove(waiterId)
                        if entries[self.key] === self.state {
                            self.state.waiters.removeValue(forKey: waiterId)
                        }
                    }
                }
            }
        }
    }

    private static func begin(postbox: Postbox, accountPeerId: PeerId, isMutation: Bool) -> (Key, State, Disposable) {
        let key = Key(postbox: ObjectIdentifier(postbox), accountPeerId: accountPeerId)
        let state = states.modify { entries in
            var entries = entries
            let state: State
            if let current = entries[key], current.postbox === postbox {
                state = current
            } else {
                state = State(postbox: postbox)
                entries[key] = state
            }
            if isMutation {
                state.mutations += 1
                state.generation = UUID()
            } else {
                state.readers += 1
            }
            return entries
        }[key]!
        let release = ActionDisposable {
            var callbacks: [(UUID) -> Void] = []
            var generation: UUID?
            let _ = states.modify { entries in
                var entries = entries
                guard entries[key] === state, state.postbox === postbox else {
                    return entries
                }
                if isMutation {
                    state.mutations -= 1
                    state.generation = UUID()
                    if state.mutations == 0 {
                        generation = state.generation
                        callbacks = Array(state.waiters.values)
                        state.waiters.removeAll()
                    }
                } else {
                    state.readers -= 1
                }
                if state.mutations == 0 && state.readers == 0 {
                    entries.removeValue(forKey: key)
                }
                return entries
            }
            if let generation {
                for callback in callbacks {
                    callback(generation)
                }
            }
        }
        return (key, state, release)
    }

    static func withLocalMutation<T, E>(postbox: Postbox, accountPeerId: PeerId, _ f: @escaping (Scope) -> Signal<T, E>) -> Signal<T, E> {
        return Signal { subscriber in
            let (key, state, release) = self.begin(postbox: postbox, accountPeerId: accountPeerId, isMutation: true)
            let scope = Scope(postbox: postbox, key: key, state: state, release: release)
            let disposable = f(scope).start(next: { subscriber.putNext($0) }, error: {
                scope.dispose()
                subscriber.putError($0)
            }, completed: {
                scope.dispose()
                subscriber.putCompletion()
            })
            return ActionDisposable {
                // Queued Postbox bodies can run during source disposal; revoke their admission first.
                scope.dispose()
                disposable.dispose()
            }
        }
    }

    static func withSynchronization<T, E>(postbox: Postbox, accountPeerId: PeerId, _ f: @escaping (Scope) -> Signal<T, E>) -> Signal<T, E> {
        return Signal { subscriber in
            let (key, state, release) = self.begin(postbox: postbox, accountPeerId: accountPeerId, isMutation: false)
            let scope = Scope(postbox: postbox, key: key, state: state, release: release)
            let disposable = f(scope).start(next: { subscriber.putNext($0) }, error: {
                scope.dispose()
                subscriber.putError($0)
            }, completed: {
                scope.dispose()
                subscriber.putCompletion()
            })
            return ActionDisposable {
                scope.dispose()
                disposable.dispose()
            }
        }
    }
}

private final class ManagedSynchronizePinnedChatsOperationsHelper {
    var operationDisposables: [Int32: Disposable] = [:]
    
    func update(_ entries: [PeerMergedOperationLogEntry]) -> (disposeOperations: [Disposable], beginOperations: [(PeerMergedOperationLogEntry, MetaDisposable)]) {
        var disposeOperations: [Disposable] = []
        var beginOperations: [(PeerMergedOperationLogEntry, MetaDisposable)] = []
        
        var hasRunningOperationForPeerId = Set<PeerId>()
        var validMergedIndices = Set<Int32>()
        for entry in entries {
            if !hasRunningOperationForPeerId.contains(entry.peerId) {
                hasRunningOperationForPeerId.insert(entry.peerId)
                validMergedIndices.insert(entry.mergedIndex)
                
                if self.operationDisposables[entry.mergedIndex] == nil {
                    let disposable = MetaDisposable()
                    beginOperations.append((entry, disposable))
                    self.operationDisposables[entry.mergedIndex] = disposable
                }
            }
        }
        
        var removeMergedIndices: [Int32] = []
        for (mergedIndex, disposable) in self.operationDisposables {
            if !validMergedIndices.contains(mergedIndex) {
                removeMergedIndices.append(mergedIndex)
                disposeOperations.append(disposable)
            }
        }
        
        for mergedIndex in removeMergedIndices {
            self.operationDisposables.removeValue(forKey: mergedIndex)
        }
        
        return (disposeOperations, beginOperations)
    }
    
    func reset() -> [Disposable] {
        let disposables = Array(self.operationDisposables.values)
        self.operationDisposables.removeAll()
        return disposables
    }
}

private func withTakenOperation(postbox: Postbox, tag: PeerOperationLogTag, peerId: PeerId, tagLocalIndex: Int32, _ f: @escaping (Transaction, PeerMergedOperationLogEntry?) -> Signal<Void, NoError>) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Signal<Void, NoError> in
        var result: PeerMergedOperationLogEntry?
        transaction.operationLogUpdateEntry(peerId: peerId, tag: tag, tagLocalIndex: tagLocalIndex, { entry in
            if let entry = entry, let _ = entry.mergedIndex, entry.contents is SynchronizePinnedChatsOperation  {
                result = entry.mergedEntry!
                return PeerOperationLogEntryUpdate(mergedIndex: .none, contents: .none)
            } else {
                return PeerOperationLogEntryUpdate(mergedIndex: .none, contents: .none)
            }
        })
        
        return f(transaction, result)
        } |> switchToLatest
}

func managedSynchronizePinnedChatsOperations(postbox: Postbox, network: Network, accountPeerId: PeerId, stateManager: AccountStateManager, tag: PeerOperationLogTag) -> Signal<Void, NoError> {
    return Signal { _ in
        let helper = Atomic<ManagedSynchronizePinnedChatsOperationsHelper>(value: ManagedSynchronizePinnedChatsOperationsHelper())
        
        let disposable = postbox.mergedOperationLogView(tag: tag, limit: 10).start(next: { view in
            let (disposeOperations, beginOperations) = helper.with { helper -> (disposeOperations: [Disposable], beginOperations: [(PeerMergedOperationLogEntry, MetaDisposable)]) in
                return helper.update(view.entries)
            }
            
            for disposable in disposeOperations {
                disposable.dispose()
            }
            
            for (entry, disposable) in beginOperations {
                let signal = withTakenOperation(postbox: postbox, tag: tag, peerId: entry.peerId, tagLocalIndex: entry.tagLocalIndex, { transaction, entry -> Signal<Void, NoError> in
                    if let entry = entry {
                        if let operation = entry.contents as? SynchronizePinnedChatsOperation {
                            if tag == OperationLogTags.SynchronizePinnedChats {
                                return synchronizePinnedChats(transaction: transaction, postbox: postbox, network: network, accountPeerId: accountPeerId, stateManager: stateManager, groupId: PeerGroupId(rawValue: Int32(entry.peerId.id._internalGetInt64Value())), operation: operation)
                            } else if tag == OperationLogTags.SynchronizePinnedSavedChats {
                                return synchronizePinnedSavedChats(postbox: postbox, network: network, accountPeerId: accountPeerId, entry: entry)
                            }
                        } else {
                            assertionFailure()
                        }
                    }
                    return .complete()
                })
                |> then(postbox.transaction { transaction -> Void in
                    // Saved reconciliation retires its own exact operation atomically with admission.
                    if tag != OperationLogTags.SynchronizePinnedSavedChats {
                        let _ = transaction.operationLogRemoveEntry(peerId: entry.peerId, tag: tag, tagLocalIndex: entry.tagLocalIndex)
                    }
                })
                
                disposable.set((signal |> delay(2.0, queue: Queue.concurrentDefaultQueue())).start())
            }
        })
        
        return ActionDisposable {
            let disposables = helper.with { helper -> [Disposable] in
                return helper.reset()
            }
            for disposable in disposables {
                disposable.dispose()
            }
            disposable.dispose()
        }
    }
}

private func synchronizePinnedChats(transaction: Transaction, postbox: Postbox, network: Network, accountPeerId: PeerId, stateManager: AccountStateManager, groupId: PeerGroupId, operation: SynchronizePinnedChatsOperation) -> Signal<Void, NoError> {
    let initialRemoteItemIds = operation.previousItemIds
    let initialRemoteItemIdsWithoutSecretChats = initialRemoteItemIds.filter { item in
        switch item {
            case let .peer(peerId):
                return peerId.namespace != Namespaces.Peer.SecretChat
        }
    }
    let localItemIds = transaction.getPinnedItemIds(groupId: groupId)
    let localItemIdsWithoutSecretChats = localItemIds.filter { item in
        switch item {
            case let .peer(peerId):
                return peerId.namespace != Namespaces.Peer.SecretChat
        }
    }
    
    return network.request(Api.functions.messages.getPinnedDialogs(folderId: groupId.rawValue))
    |> retryRequestIfNotFrozen
    |> mapToSignal { dialogs -> Signal<Void, NoError> in
        guard let dialogs else {
            return .complete()
        }
        return postbox.transaction { transaction -> Signal<Void, NoError> in
            var storeMessages: [StoreMessage] = []
            var readStates: [PeerId: [MessageId.Namespace: PeerReadState]] = [:]
            var channelStates: [PeerId: Int32] = [:]
            var notificationSettings: [PeerId: PeerNotificationSettings] = [:]
            var ttlPeriods: [PeerId: CachedPeerAutoremoveTimeout] = [:]
            
            var remoteItemIds: [PinnedItemId] = []
            
            let parsedPeers: AccumulatedPeers
            
            switch dialogs {
            case let .peerDialogs(peerDialogsData):
                let (dialogs, messages, chats, users) = (peerDialogsData.dialogs, peerDialogsData.messages, peerDialogsData.chats, peerDialogsData.users)
                parsedPeers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                
            loop: for dialog in dialogs {
                let apiPeer: Api.Peer
                let apiReadInboxMaxId: Int32
                let apiReadOutboxMaxId: Int32
                let apiTopMessage: Int32
                let apiUnreadCount: Int32
                let apiMarkedUnread: Bool
                var apiChannelPts: Int32?
                let apiTtlPeriod: Int32?
                let apiNotificationSettings: Api.PeerNotifySettings
                switch dialog {
                case let .dialog(dialogData):
                    let (flags, peer, topMessage, readInboxMaxId, readOutboxMaxId, unreadCount, peerNotificationSettings, pts, ttlPeriod) = (dialogData.flags, dialogData.peer, dialogData.topMessage, dialogData.readInboxMaxId, dialogData.readOutboxMaxId, dialogData.unreadCount, dialogData.notifySettings, dialogData.pts, dialogData.ttlPeriod)
                    apiPeer = peer
                    apiTopMessage = topMessage
                    apiReadInboxMaxId = readInboxMaxId
                    apiReadOutboxMaxId = readOutboxMaxId
                    apiUnreadCount = unreadCount
                    apiMarkedUnread = (flags & (1 << 3)) != 0
                    apiNotificationSettings = peerNotificationSettings
                    apiChannelPts = pts
                    apiTtlPeriod = ttlPeriod
                case .dialogFolder:
                    //assertionFailure()
                    continue loop
                }
                
                let peerId: PeerId = apiPeer.peerId
                
                remoteItemIds.append(.peer(peerId))
                
                if readStates[peerId] == nil {
                    readStates[peerId] = [:]
                }
                readStates[peerId]![Namespaces.Message.Cloud] = .idBased(maxIncomingReadId: apiReadInboxMaxId, maxOutgoingReadId: apiReadOutboxMaxId, maxKnownId: apiTopMessage, count: apiUnreadCount, markedUnread: apiMarkedUnread)
                
                if let apiChannelPts = apiChannelPts {
                    channelStates[peerId] = apiChannelPts
                }
                
                notificationSettings[peerId] = TelegramPeerNotificationSettings(apiSettings: apiNotificationSettings)
                
                ttlPeriods[peerId] = .known(apiTtlPeriod.flatMap(CachedPeerAutoremoveTimeout.Value.init(peerValue:)))
            }
                
                for message in messages {
                    var peerIsForum = false
                    if let peerId = message.peerId, let peer = parsedPeers.get(peerId), peer.isForumOrMonoForum {
                        peerIsForum = true
                    }
                    if let storeMessage = StoreMessage(apiMessage: message, accountPeerId: accountPeerId, peerIsForum: peerIsForum) {
                        storeMessages.append(storeMessage)
                    }
                }
            }
            
            var resultingItemIds: [PinnedItemId]
            if initialRemoteItemIds == localItemIds {
                resultingItemIds = remoteItemIds
            } else {
                let locallyRemovedFromRemoteItemIds = Set(initialRemoteItemIdsWithoutSecretChats).subtracting(Set(localItemIdsWithoutSecretChats))
                let remotelyRemovedItemIds = Set(initialRemoteItemIdsWithoutSecretChats).subtracting(Set(remoteItemIds))
                
                resultingItemIds = localItemIds.filter { !remotelyRemovedItemIds.contains($0) }
                resultingItemIds.append(contentsOf: remoteItemIds.filter { !locallyRemovedFromRemoteItemIds.contains($0) && !resultingItemIds.contains($0) })
            }
            
            return postbox.transaction { transaction -> Signal<Void, NoError> in
                updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                
                transaction.setPinnedItemIds(groupId: groupId, itemIds: resultingItemIds)
                
                transaction.updateCurrentPeerNotificationSettings(notificationSettings)
                
                for (peerId, autoremoveValue) in ttlPeriods {
                    transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, current in
                        if peerId.namespace == Namespaces.Peer.CloudUser {
                            let current = (current as? CachedUserData) ?? CachedUserData()
                            return current.withUpdatedAutoremoveTimeout(autoremoveValue)
                        } else if peerId.namespace == Namespaces.Peer.CloudChannel {
                            let current = (current as? CachedChannelData) ?? CachedChannelData()
                            return current.withUpdatedAutoremoveTimeout(autoremoveValue)
                        } else if peerId.namespace == Namespaces.Peer.CloudGroup {
                            let current = (current as? CachedGroupData) ?? CachedGroupData()
                            return current.withUpdatedAutoremoveTimeout(autoremoveValue)
                        } else {
                            return current
                        }
                    })
                }
                
                var allPeersWithMessages = Set<PeerId>()
                for message in storeMessages {
                    if !allPeersWithMessages.contains(message.id.peerId) {
                        allPeersWithMessages.insert(message.id.peerId)
                    }
                }
                let _ = transaction.addMessages(storeMessages, location: .UpperHistoryBlock)
                
                transaction.resetIncomingReadStates(readStates)
                
                for (peerId, pts) in channelStates {
                    if let _ = transaction.getPeerChatState(peerId) as? ChannelState {
                        // skip changing state
                    } else {
                        transaction.setPeerChatState(peerId, state: ChannelState(pts: pts, invalidatedPts: nil, synchronizedUntilMessageId: nil))
                    }
                }
                
                if remoteItemIds == resultingItemIds {
                    return .complete()
                } else {
                    var inputDialogPeers: [Api.InputDialogPeer] = []
                    for itemId in resultingItemIds {
                        switch itemId {
                            case let .peer(peerId):
                                if let peer = transaction.getPeer(peerId), let inputPeer = apiInputPeer(peer) {
                                    inputDialogPeers.append(Api.InputDialogPeer.inputDialogPeer(.init(peer: inputPeer)))
                                }
                        }
                    }
                    
                    return network.request(Api.functions.messages.reorderPinnedDialogs(flags: 1 << 0, folderId: groupId.rawValue, order: inputDialogPeers))
                    |> `catch` { _ -> Signal<Api.Bool, NoError> in
                        return .single(Api.Bool.boolFalse)
                    }
                    |> mapToSignal { result -> Signal<Void, NoError> in
                        return postbox.transaction { transaction -> Void in
                        }
                    }
                }
            }
            |> switchToLatest
        }
        |> switchToLatest
    }
}

private enum SavedPinnedChatsAttemptStart {
    case request([Int64])
    case retryWhenIdle
    case finished
}

private enum SavedPinnedChatsAttemptResult {
    case retryWhenIdle
    case retryRequest
    case finished
}

private func ownsSavedPinnedChatsOperation(transaction: Transaction, entry: PeerMergedOperationLogEntry) -> Bool {
    var isOwned = false
    transaction.operationLogUpdateEntry(peerId: entry.peerId, tag: OperationLogTags.SynchronizePinnedSavedChats, tagLocalIndex: entry.tagLocalIndex, { current in
        if let current, current.mergedIndex == entry.mergedIndex, current.contents is SynchronizePinnedChatsOperation {
            isOwned = true
        }
        return PeerOperationLogEntryUpdate(mergedIndex: .none, contents: .none)
    })
    return isOwned
}

private func synchronizePinnedSavedChats(postbox: Postbox, network: Network, accountPeerId: PeerId, entry: PeerMergedOperationLogEntry) -> Signal<Void, NoError> {
    return SavedPinnedThreadsSynchronizationState.withSynchronization(postbox: postbox, accountPeerId: accountPeerId, { scope in
        func retireWhenIdle() -> Signal<Void, NoError> {
            return scope.waitForIdle()
            |> mapToSignal { generation -> Signal<Void, NoError> in
                return postbox.transaction { transaction -> Bool in
                    guard scope.isActive, ownsSavedPinnedChatsOperation(transaction: transaction, entry: entry) else {
                        return true
                    }
                    guard scope.matches(generation) else {
                        return false
                    }
                    let _ = transaction.operationLogRemoveEntry(peerId: entry.peerId, tag: OperationLogTags.SynchronizePinnedSavedChats, tagLocalIndex: entry.tagLocalIndex)
                    return true
                }
                |> mapToSignal { finished -> Signal<Void, NoError> in
                    return finished ? .complete() : retireWhenIdle()
                }
            }
        }

        func attempt(retriesLeft: Int) -> Signal<Void, NoError> {
            return scope.waitForIdle()
            |> mapToSignal { generation -> Signal<Void, NoError> in
                return postbox.transaction { transaction -> SavedPinnedChatsAttemptStart in
                    guard scope.isActive, ownsSavedPinnedChatsOperation(transaction: transaction, entry: entry) else {
                        return .finished
                    }
                    guard scope.matches(generation) else {
                        return .retryWhenIdle
                    }
                    return .request(transaction.getPeerPinnedThreads(peerId: accountPeerId))
                }
                |> mapToSignal { start -> Signal<Void, NoError> in
                    switch start {
                    case .finished:
                        return .complete()
                    case .retryWhenIdle:
                        return attempt(retriesLeft: retriesLeft)
                    case let .request(initialThreadIds):
                        guard scope.isActive else {
                            return .complete()
                        }
                        return network.request(Api.functions.messages.getPinnedSavedDialogs())
                        |> map(Optional.init)
                        |> `catch` { _ -> Signal<Api.messages.SavedDialogs?, NoError> in
                            return .single(nil)
                        }
                        |> mapToSignal { dialogs -> Signal<Void, NoError> in
                            return postbox.transaction { transaction -> SavedPinnedChatsAttemptResult in
                                guard scope.isActive, ownsSavedPinnedChatsOperation(transaction: transaction, entry: entry) else {
                                    return .finished
                                }
                                guard scope.matches(generation), transaction.getPeerPinnedThreads(peerId: accountPeerId) == initialThreadIds else {
                                    return .retryWhenIdle
                                }

                                func failedAttempt() -> SavedPinnedChatsAttemptResult {
                                    if retriesLeft > 0 {
                                        return .retryRequest
                                    }
                                    // Do not erase pins/messages on failure or retire a superseding operation.
                                    let _ = transaction.operationLogRemoveEntry(peerId: entry.peerId, tag: OperationLogTags.SynchronizePinnedSavedChats, tagLocalIndex: entry.tagLocalIndex)
                                    return .finished
                                }

                                // This method has no hash parameter. A slice/notModified cannot supply the full pin order.
                                guard let dialogs, case let .savedDialogs(data) = dialogs else {
                                    return failedAttempt()
                                }
                                let parsedPeers = AccumulatedPeers(transaction: transaction, chats: data.chats, users: data.users)
                                let storeMessages = data.messages.compactMap { StoreMessage(apiMessage: $0, accountPeerId: accountPeerId, peerIsForum: false) }
                                var storeMessagesById: [MessageId: StoreMessage] = [:]
                                for message in storeMessages {
                                    if case let .Id(id) = message.id {
                                        // A duplicate could overwrite the top message after validating its thread.
                                        guard storeMessagesById[id] == nil else {
                                            return failedAttempt()
                                        }
                                        storeMessagesById[id] = message
                                    }
                                }
                                var threadIds: [Int64] = []
                                var missingThreadInfos: [(Int64, StoredMessageHistoryThreadInfo)] = []
                                var seenThreadIds = Set<Int64>()
                                for dialog in data.dialogs {
                                    guard case let .savedDialog(savedDialog) = dialog else {
                                        return failedAttempt()
                                    }
                                    let peerId = savedDialog.peer.peerId
                                    let threadId = peerId.toInt64()
                                    guard seenThreadIds.insert(threadId).inserted, savedDialog.topMessage > 0, (parsedPeers.get(peerId) ?? transaction.getPeer(peerId)) != nil else {
                                        return failedAttempt()
                                    }
                                    let topMessageId = MessageId(peerId: accountPeerId, namespace: Namespaces.Message.Cloud, id: savedDialog.topMessage)
                                    if let returnedTopMessage = storeMessagesById[topMessageId] {
                                        guard returnedTopMessage.threadId == threadId else {
                                            return failedAttempt()
                                        }
                                    } else if transaction.getMessage(topMessageId)?.threadId != threadId {
                                        return failedAttempt()
                                    }
                                    if transaction.getMessageHistoryThreadInfo(peerId: accountPeerId, threadId: threadId) == nil {
                                        guard let info = telegramPostboxSeedConfiguration.automaticThreadIndexInfo(accountPeerId, threadId) else {
                                            return failedAttempt()
                                        }
                                        missingThreadInfos.append((threadId, info))
                                    }
                                    threadIds.append(threadId)
                                }

                                updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                                let _ = transaction.addMessages(storeMessages, location: .UpperHistoryBlock)
                                for (threadId, info) in missingThreadInfos {
                                    transaction.setMessageHistoryThreadInfo(peerId: accountPeerId, threadId: threadId, info: info)
                                }
                                // Pins-only results must not mark the entire Saved Messages list as loaded.
                                transaction.setPeerPinnedThreads(peerId: accountPeerId, threadIds: threadIds)
                                let _ = transaction.operationLogRemoveEntry(peerId: entry.peerId, tag: OperationLogTags.SynchronizePinnedSavedChats, tagLocalIndex: entry.tagLocalIndex)
                                return .finished
                            }
                            |> mapToSignal { result -> Signal<Void, NoError> in
                                switch result {
                                case .finished:
                                    return .complete()
                                case .retryWhenIdle:
                                    // Discarded stale responses also consume one of the three actual RPC slots.
                                    return retriesLeft > 0 ? attempt(retriesLeft: retriesLeft - 1) : retireWhenIdle()
                                case .retryRequest:
                                    return attempt(retriesLeft: retriesLeft - 1)
                                }
                            }
                        }
                    }
                }
            }
        }
        // Three actual RPC attempts total, including stale responses; later events/first-page loads can reconcile again.
        return attempt(retriesLeft: 2)
    })
}
