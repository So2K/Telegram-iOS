import Foundation
import Postbox
import SwiftSignalKit

// SuperGram (STUCK-UI-LAYER): the escalation policy a view uses when a download it is showing has stopped
// making progress.
//
// Why a view cannot simply "re-issue its own fetch":
//
// A `FetchManager` entry is keyed by (category, chat, locationKey, resourceId) and is shared by *every* holder
// of that tuple — the visible message node, `PrefetchManagerImpl` (history preload), `InChatPrefetchManager`
// (the messages just off screen), the downloads list, and any other node showing the same message. Disposing
// one holder's registration only removes one reference from `FetchManagerLocationEntry.references`; the entry
// itself survives, and — crucially — its `combinedRanges` do not change, because every holder registers the
// same `0 ..< Int64.max`. `FetchManagerCategoryContext.withEntry` restarts a fetch only when
// `activeContext.ranges != entry.combinedRanges` (or the active context has no disposable), so re-issuing is
// then provably a no-op: nothing is torn down, nothing is started, and the spinner keeps spinning.
//
// Only cancelling the *entry* recreates the fetch: `cancelInteractiveFetches` removes the entry outright,
// disposes the active context's disposable, drops the accumulated retry backoff (`retryTimestamp`) and tells
// `MediaBox` to cancel the resource's full-range fetches. A fresh registration afterwards allocates a new
// episode, so the stale holders' disposables become inert instead of clobbering it.
public enum SuperGramMediaFetchSelfHeal {
    public enum Step {
        /// Drop and re-issue this view's own fetch registration. Cheap, and enough when the view is the only
        /// holder of the entry — useless otherwise (see above).
        case reissue
        /// Cancel every registration for the entry and start a fresh one.
        case cancelAndRestart
        /// `cancelAndRestart`, plus a request to drop whatever fetch state `MediaBox` cached for the resource.
        case hardReset
    }

    /// Picks the escalation step for a stall.
    ///
    /// - Parameters:
    ///   - attempt: zero-based index of this self-heal attempt for the current media.
    ///   - isFetchActive: the `isActive` flag of the last `.Fetching` status. `false` means the download is not
    ///     running in `MediaBox` at all (the status was synthesised by
    ///     `FetchManagerStatusContext.combinedStatus` from `.Remote` + "an entry exists"), i.e. the entry is
    ///     queued, preempted or in retry backoff. Re-issuing cannot help in that state, so it is skipped.
    public static func step(forAttempt attempt: Int, isFetchActive: Bool) -> Step {
        if attempt <= 0 && isFetchActive {
            return .reissue
        } else if attempt <= 1 {
            return .cancelAndRestart
        } else {
            return .hardReset
        }
    }

    /// Set once at startup by the fetch layer, to
    /// `{ mediaBox, resourceId in mediaBox.superGramResetResourceFetch(resourceId: resourceId) }`.
    ///
    /// Kept as a hook rather than a direct call so that the UI layer does not have to be edited in lockstep
    /// with `MediaBox`. Read and written on the main queue only.
    public static var hardResetResourceFetch: ((MediaBox, MediaResourceId) -> Void)?

    /// Best available "forget everything you know about this resource's download".
    ///
    /// VER-UI-SELFHEAL: nothing ever installed `hardResetResourceFetch`, so every caller took the fallback — and
    /// the fallback used to be `cancelInteractiveResourceFetch`, i.e. `cancelFullRangeFetches()`. That fails the
    /// other owners' full-range requests while leaving the materialized-range bookkeeping that wedged the fetch
    /// in the first place untouched, so step 3 of the escalation was strictly worse than step 2 rather than
    /// stronger than it. `MediaBox.superGramResetResourceFetch` is the operation this was always written
    /// against: it disposes the pending fetch, clears the materialized ranges so an identical retry is not
    /// deduplicated away, fails the outstanding range requests so their owners retry, and moves the live status
    /// subscribers to `.Remote`. Bytes already on disk and the file map are kept, so a reset costs at most a
    /// resumed download.
    ///
    /// The hook is still honoured when something does install one.
    public static func requestHardReset(mediaBox: MediaBox, resourceId: MediaResourceId) {
        if let hardResetResourceFetch = self.hardResetResourceFetch {
            hardResetResourceFetch(mediaBox, resourceId)
        } else {
            mediaBox.superGramResetResourceFetch(resourceId: resourceId)
        }
    }
}
