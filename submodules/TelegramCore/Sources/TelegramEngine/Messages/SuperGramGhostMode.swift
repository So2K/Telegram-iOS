import Foundation
import Postbox
import SwiftSignalKit

// SuperGram: ghost mode switches (W2-GHOST).
// The keys are read without SGSimpleSettings (TelegramCore must not depend on UI settings modules). Values are cached
// and refreshed on UserDefaults changes, so reading them on list/scroll paths is cheap.
// - "sgSkipReadReceipts" (default false): don't send read receipts, reaction "seen" marks and voice/round "listened"
//   marks from the automatic chat paths. Explicit user actions ("Mark as Read") still work.
// - "sgStoryGhostMode" (default false): viewing someone's story updates only the local seen state; neither
//   `stories.readStories` nor `stories.incrementStoryViews` is sent.
public enum SuperGramGhostSettings {
    fileprivate struct Values {
        var skipReadReceipts: Bool
        var storyGhostMode: Bool
    }

    fileprivate final class Storage {
        let values: Atomic<Values>
        private var observer: NSObjectProtocol?

        init() {
            let values = Atomic<Values>(value: Storage.read())
            self.values = values
            self.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil, using: { _ in
                let _ = values.swap(Storage.read())
            })
        }

        deinit {
            if let observer = self.observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        static func read() -> Values {
            let defaults = UserDefaults.standard
            return Values(
                skipReadReceipts: defaults.object(forKey: "sgSkipReadReceipts") as? Bool ?? false,
                storyGhostMode: defaults.object(forKey: "sgStoryGhostMode") as? Bool ?? false
            )
        }
    }

    fileprivate static let storage = Storage()

    /// "Don't send read receipts": chat history reads, reaction seen marks, voice/round listened marks.
    public static var skipReadReceipts: Bool {
        return self.storage.values.with { $0.skipReadReceipts }
    }

    /// `skipReadReceipts` for a chat. Never true for secret chats: reading starts their self-destruct timers.
    public static func shouldSkipReadReceipts(peerId: EnginePeer.Id?) -> Bool {
        if let peerId, peerId.namespace == Namespaces.Peer.SecretChat {
            return false
        }
        return self.skipReadReceipts
    }

    /// "Ghost story viewing": stories are marked as seen locally only.
    public static var storyGhostMode: Bool {
        return self.storage.values.with { $0.storyGhostMode }
    }
}

// SuperGram: the local half of `_internal_markStoryAsSeen`. It raises the peer's local maxReadId and injects the
// read update so rings and lists turn "seen", but it neither enqueues the SynchronizeViewStories operation
// (`stories.readStories`) nor calls `stories.incrementStoryViews` (pinned/archive stories have no local state).
// Caveat: `stories.readStories(maxId)` marks every story up to maxId as read, so a later normal (non-ghost) view of a
// newer story of the same peer also reports the earlier ghost-viewed ones. A later server refresh of the peer's
// story state can show the ghost-viewed stories as unseen again.
func _internal_superGramMarkStoryAsSeenLocally(account: Account, peerId: PeerId, id: Int32, asPinned: Bool) -> Signal<Never, NoError> {
    if asPinned {
        return .complete()
    }
    return account.postbox.transaction { transaction -> Void in
        if let peerStoryState = transaction.getPeerStoryState(peerId: peerId)?.entry.get(Stories.PeerState.self) {
            transaction.setPeerStoryState(peerId: peerId, state: Stories.PeerState(
                maxReadId: max(peerStoryState.maxReadId, id)
            ).postboxRepresentation)
        }
    }
    |> mapToSignal { _ -> Signal<Never, NoError> in
        account.stateManager.injectStoryUpdates(updates: [.read(peerId: peerId, maxId: id)])
        return .complete()
    }
}
