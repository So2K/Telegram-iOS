import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramUIPreferences
import AccountContext
import UniversalMediaPlayer
import RangeSet

public struct FetchManagerLocationEntryId: Hashable {
    public let location: FetchManagerLocation
    public let resourceId: MediaResourceId
    public let locationKey: FetchManagerLocationKey
    
    public static func ==(lhs: FetchManagerLocationEntryId, rhs: FetchManagerLocationEntryId) -> Bool {
        if lhs.location != rhs.location {
            return false
        }
        if lhs.resourceId != rhs.resourceId {
            return false
        }
        if lhs.locationKey != rhs.locationKey {
            return false
        }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.resourceId.hashValue)
        hasher.combine(self.locationKey)
    }
}

private final class FetchManagerLocationEntry {
    let id: FetchManagerLocationEntryId
    let episode: Int32
    let mediaReference: AnyMediaReference?
    let resourceReference: MediaResourceReference
    let statsCategory: MediaResourceStatsCategory
    
    var userInitiated: Bool = false
    var storeToDownloadsPeerId: EnginePeer.Id?
    let references = Bag<FetchManagerPriority>()
    let ranges = Bag<RangeSet<Int64>>()
    var elevatedPriorityReferenceCount: Int32 = 0
    var userInitiatedPriorityIndices: [Int32] = []
    var isPaused: Bool = false
    // SuperGram: priorityKey allocates; it is cached after every mutation made through withEntry
    var cachedPriorityKey: FetchManagerPriorityKey?
    var failureCount: Int = 0
    var retryTimestamp: Double?
    // SuperGram: consecutive failed attempts that produced no new bytes at all, and the byte count they were
    // measured against. `failureCount` cannot be used for this: it is deliberately reset whenever an attempt ran
    // for a while before failing, and a fetch that hangs for a minute and is then reaped by a watchdog always
    // qualifies — so a hopeless resource would retry every 60 s for the rest of the session while the UI kept
    // showing a cancel button for a download that is not happening.
    var zeroProgressFailureCount: Int = 0
    var lastKnownBytes: Int64 = -1
    // Set once a resource has failed repeatedly without ever transferring a byte. The entry stays (its
    // references are still held by live views) but it stops being activated and stops claiming to be
    // downloading, so the UI shows "tap to download" instead of a cancel button that does nothing.
    var isAbandoned: Bool = false

    var combinedRanges: RangeSet<Int64> {
        var result = RangeSet<Int64>()
        if self.userInitiated {
            result.insert(contentsOf: 0 ..< Int64.max)
        } else {
            for range in self.ranges.copyItems() {
                result.formUnion(range)
            }
        }
        return result
    }
    
    var priorityKey: FetchManagerPriorityKey? {
        if !self.references.isEmpty || self.userInitiated {
            return FetchManagerPriorityKey(locationKey: self.id.locationKey, hasElevatedPriority: self.elevatedPriorityReferenceCount > 0, userInitiatedPriority: userInitiatedPriorityIndices.last, topReference: self.references.copyItems().max())
        } else {
            return nil
        }
    }
    
    init(id: FetchManagerLocationEntryId, episode: Int32, mediaReference: AnyMediaReference?, resourceReference: MediaResourceReference, statsCategory: MediaResourceStatsCategory) {
        self.id = id
        self.episode = episode
        self.mediaReference = mediaReference
        self.resourceReference = resourceReference
        self.statsCategory = statsCategory
    }
}

private final class FetchManagerFetchAttempt {
}

private final class FetchManagerActiveContext {
    var userInitiated: Bool
    var ranges = RangeSet<Int64>()
    var disposable: Disposable?
    // Callback delivery can outlive disposal, so an entry id alone does not identify the current attempt.
    var attempt = FetchManagerFetchAttempt()
    // SuperGram: when the current fetch attempt was started, used to decide whether a failure is a fresh one
    var activationTimestamp: Double = CFAbsoluteTimeGetCurrent()
    // SuperGram: on-disk byte count of the resource the last time it changed, and when that was. An active entry
    // whose bytes have not moved for activeStallTimeout is treated as failed, because nothing else would ever
    // release its per-category slot: rebalanceActiveEntries only deactivates entries that became ineligible or
    // were outranked, so an entry with the best priority key and a fetch that never completes and never errors
    // used to hold its slot for the rest of the session.
    var lastProgressBytes: Int64 = -1
    var lastProgressTimestamp: Double = CFAbsoluteTimeGetCurrent()

    init(userInitiated: Bool) {
        self.userInitiated = userInitiated
    }
}

// SuperGram: how many entries of a category may fetch at the same time. Previously a new top entry was
// activated without deactivating the former one, so every visible auto-download ran in parallel (DL-03).
private func fetchManagerActiveEntryLimit(category: FetchManagerCategory, pressureLevel: MediaDownloadPressure.Level) -> Int {
    if pressureLevel == .critical {
        switch category {
        case .image:
            return 2
        case .file, .voice, .animation:
            return 1
        }
    } else if pressureLevel == .constrained {
        switch category {
        case .image:
            return 3
        case .file, .voice, .animation:
            return 2
        }
    } else if pressureLevel == .reduced {
        // SuperGram: `reduced` is Low Power Mode / a brief thermal spike, not a memory emergency. It trims
        // best-effort preloading (PrefetchManager, MediaPreloadGate) and leaves the entries a user is actually
        // waiting on alone — cutting these limits here is what made downloads crawl for every Low Power Mode
        // user, and the download itself is already bounded by the FetchV2 part budget.
        switch category {
        case .image:
            return 6
        case .file, .voice:
            return 3
        case .animation:
            return 4
        }
    } else {
        switch category {
        case .image:
            return 6
        case .file, .voice:
            return 3
        case .animation:
            return 4
        }
    }
}

private final class FetchManagerStatusContext {
    var disposable: Disposable?
    var originalStatus: MediaResourceStatus?
    var subscribers = Bag<(MediaResourceStatus) -> Void>()
    
    var hasEntry = false
    var isPaused = false
    // SuperGram: mirrors FetchManagerLocationEntry.isAbandoned, see below
    var isAbandoned = false

    var isEmpty: Bool {
        return !self.hasEntry && self.subscribers.isEmpty
    }

    var combinedStatus: MediaResourceStatus? {
        if let originalStatus = self.originalStatus {
            if case let .Remote(progress) = originalStatus, self.hasEntry {
                if self.isPaused {
                    return .Paused(progress: progress)
                } else if self.isAbandoned {
                    // SuperGram: the mere existence of an entry used to mean "downloading" here, so an entry that
                    // had given up still showed a spinner with a cancel button that could never finish. Nothing is
                    // running and nothing will restart it on its own, so report the truth: .Remote, which the UI
                    // draws as the "tap to download" affordance.
                    return originalStatus
                } else {
                    return .Fetching(isActive: false, progress: progress)
                }
            } else if self.hasEntry {
                return originalStatus
            } else if case .Local = originalStatus {
                return originalStatus
            } else {
                return .Remote(progress: 0.0)
            }
        } else {
            return nil
        }
    }
}

private final class FetchManagerCategoryContext {
    private let postbox: Postbox
    private let storeManager: DownloadedMediaStoreManager?
    private let category: FetchManagerCategory
    private let entryCompleted: (FetchManagerLocationEntryId, FetchManagerFetchAttempt) -> Void
    private let entryFailed: (FetchManagerLocationEntryId, FetchManagerFetchAttempt) -> Void
    // SuperGram: the fetch was torn down because another owner of the same resource cancelled it
    // (FetchResourceError.cancelled). Not a failure — restart without any backoff or give-up penalty.
    private let entryCancelledByAnotherOwner: (FetchManagerLocationEntryId, FetchManagerFetchAttempt) -> Void
    private let activeEntriesUpdated: () -> Void

    var pressureLevel: MediaDownloadPressure.Level

    private var entries: [FetchManagerLocationEntryId: FetchManagerLocationEntry] = [:]
    
    private var activeContexts: [FetchManagerLocationEntryId: FetchManagerActiveContext] = [:]
    private var statusContexts: [FetchManagerLocationEntryId: FetchManagerStatusContext] = [:]
    
    var hasActiveUserInitiatedEntries: Bool {
        for (_, context) in self.activeContexts {
            if context.userInitiated {
                return true
            }
        }
        return false
    }
    
    init(postbox: Postbox, storeManager: DownloadedMediaStoreManager?, category: FetchManagerCategory, pressureLevel: MediaDownloadPressure.Level, entryCompleted: @escaping (FetchManagerLocationEntryId, FetchManagerFetchAttempt) -> Void, entryFailed: @escaping (FetchManagerLocationEntryId, FetchManagerFetchAttempt) -> Void, entryCancelledByAnotherOwner: @escaping (FetchManagerLocationEntryId, FetchManagerFetchAttempt) -> Void, activeEntriesUpdated: @escaping () -> Void) {
        self.postbox = postbox
        self.storeManager = storeManager
        self.category = category
        self.pressureLevel = pressureLevel
        self.entryCompleted = entryCompleted
        self.entryFailed = entryFailed
        self.entryCancelledByAnotherOwner = entryCancelledByAnotherOwner
        self.activeEntriesUpdated = activeEntriesUpdated
    }
    
    func getActiveEntries() -> [FetchManagerLocationEntry] {
        return Array(self.entries.values)
    }
    
    func withEntry(id: FetchManagerLocationEntryId, takeNew: (() -> (AnyMediaReference?, MediaResourceReference, MediaResourceStatsCategory, Int32))?, _ f: (FetchManagerLocationEntry) -> Void) {
        let entry: FetchManagerLocationEntry
        let previousPriorityKey: FetchManagerPriorityKey?
        let isNewEntry: Bool

        if let current = self.entries[id] {
            entry = current
            previousPriorityKey = entry.priorityKey
            isNewEntry = false
        } else if let takeNew = takeNew {
            previousPriorityKey = nil
            isNewEntry = true
            let (mediaReference, resourceReference, statsCategory, episode) = takeNew()
            entry = FetchManagerLocationEntry(id: id, episode: episode, mediaReference: mediaReference, resourceReference: resourceReference, statsCategory: statsCategory)
            
            Logger.shared.log("FetchManager", "[\(entry.id.location)] Adding entry \(entry.resourceReference.resource.id.stringRepresentation) (\(self.entries.count) in queue)")
            
            self.entries[id] = entry
        } else {
            return
        }

        // SuperGram: rebalanceActiveEntries() walks every entry in the category, and withEntry runs on every
        // range update of every registering media node — so scrolling a media-heavy channel made it quadratic in
        // the size of the fetch queue. Nothing about which entries are *eligible* or how they are *ordered* can
        // change unless one of these does, so snapshot them and skip the scan when the call was a pure range
        // update. (Time-based eligibility — retryTimestamp expiring — is owned by the retry timer, which calls
        // retryFailedEntries() -> rebalanceActiveEntries().)
        let wasPaused = entry.isPaused
        let wasUserInitiated = entry.userInitiated
        let previousRetryTimestamp = entry.retryTimestamp

        f(entry)

        var removedEntries = false

        let updatedPriorityKey = entry.priorityKey
        entry.cachedPriorityKey = updatedPriorityKey
        if previousPriorityKey != updatedPriorityKey {
            if updatedPriorityKey == nil {
                if let entry = self.entries[id] {
                    Logger.shared.log("FetchManager", "Canceled fetching \(entry.resourceReference.resource.id.stringRepresentation)")
                }
                self.entries.removeValue(forKey: id)
                removedEntries = true
            }
        }

        if removedEntries {
            var removedIds: [FetchManagerLocationEntryId] = []
            for (entryId, activeContext) in self.activeContexts {
                if self.entries[entryId] == nil {
                    removedIds.append(entryId)
                    activeContext.disposable?.dispose()
                }
            }
            for entryId in removedIds {
                self.activeContexts.removeValue(forKey: entryId)
            }
        }

        // SuperGram: a user tap on an auto-download upgrades the running fetch (continueInBackground, interactive class)
        // and protects it from preemption
        var userInitiatedChanged = false
        if let entry = self.entries[id], let activeContext = self.activeContexts[id], activeContext.userInitiated != entry.userInitiated {
            activeContext.userInitiated = entry.userInitiated
            userInitiatedChanged = true
        }

        let needsRebalance = isNewEntry
            || removedEntries
            || userInitiatedChanged
            || previousPriorityKey != updatedPriorityKey
            || entry.isPaused != wasPaused
            || entry.userInitiated != wasUserInitiated
            || entry.retryTimestamp != previousRetryTimestamp
        if needsRebalance {
            self.rebalanceActiveEntries()
        }

        if let entry = self.entries[id], let activeContext = self.activeContexts[id] {
            let ranges = entry.combinedRanges
            if activeContext.disposable == nil || activeContext.ranges != ranges || userInitiatedChanged {
                self.startFetch(id: id, entry: entry, activeContext: activeContext, ranges: ranges)
                if activeContext.disposable == nil {
                    // Nothing left to fetch for this entry: release the active slot instead of holding it idle
                    self.activeContexts.removeValue(forKey: id)
                }
            }
        }

        self.updateStatusContextFlags(id: id)

        self.activeEntriesUpdated()
    }
    
    private func isEntryEligibleForActivation(_ entry: FetchManagerLocationEntry, key: FetchManagerPriorityKey, timestamp: Double) -> Bool {
        if entry.isPaused {
            return false
        }
        if entry.isAbandoned {
            return false
        }
        if let retryTimestamp = entry.retryTimestamp, retryTimestamp > timestamp {
            return false
        }
        if self.pressureLevel == .critical {
            // SuperGram: under critical pressure only explicit downloads and currently visible media keep fetching
            if !entry.userInitiated && key.topReference != FetchManagerPriority.userInitiated {
                return false
            }
        }
        return true
    }

    // SuperGram: replaces the single "top entry" activation (DL-03). Keeps at most `limit` active fetches per
    // category, preempting the lowest-priority non-user-initiated fetch when a better entry needs a slot.
    // User-initiated fetches are never preempted; a preempted entry stays queued (.Fetching(isActive: false)).
    func rebalanceActiveEntries() {
        let limit = fetchManagerActiveEntryLimit(category: self.category, pressureLevel: self.pressureLevel)
        let timestamp = CFAbsoluteTimeGetCurrent()

        var ineligibleActiveIds: [FetchManagerLocationEntryId] = []
        for (id, activeContext) in self.activeContexts {
            if activeContext.userInitiated {
                continue
            }
            guard let entry = self.entries[id], let key = entry.cachedPriorityKey else {
                continue
            }
            if !self.isEntryEligibleForActivation(entry, key: key, timestamp: timestamp) {
                ineligibleActiveIds.append(id)
            }
        }
        for id in ineligibleActiveIds {
            self.deactivateEntry(id)
        }

        var selected: [(FetchManagerLocationEntryId, FetchManagerPriorityKey)] = []
        for (id, entry) in self.entries {
            guard let key = entry.cachedPriorityKey else {
                continue
            }
            if !self.isEntryEligibleForActivation(entry, key: key, timestamp: timestamp) {
                continue
            }
            if selected.count < limit || key < selected[selected.count - 1].1 {
                var insertIndex = selected.count
                while insertIndex > 0 && key < selected[insertIndex - 1].1 {
                    insertIndex -= 1
                }
                selected.insert((id, key), at: insertIndex)
                if selected.count > limit {
                    selected.removeLast()
                }
            }
        }

        for (id, key) in selected {
            if self.activeContexts[id] != nil {
                continue
            }
            guard let entry = self.entries[id] else {
                continue
            }
            if self.activeContexts.count >= limit {
                guard let (worstId, worstKey) = self.worstPreemptibleActiveEntry(), key < worstKey else {
                    break
                }
                self.deactivateEntry(worstId)
            }

            let activeContext = FetchManagerActiveContext(userInitiated: entry.userInitiated)
            self.activeContexts[id] = activeContext
            self.startFetch(id: id, entry: entry, activeContext: activeContext, ranges: entry.combinedRanges)
            if activeContext.disposable == nil {
                // SuperGram: startFetch starts nothing when the entry has no ranges to fetch. Such an entry used
                // to keep an active slot for the rest of the session, so with a per-category limit it could block
                // every other download in that category forever.
                self.activeContexts.removeValue(forKey: id)
            }
        }

        // The limit may have shrunk (pressure): shed the lowest-priority preemptible fetches
        while self.activeContexts.count > limit {
            guard let (worstId, _) = self.worstPreemptibleActiveEntry() else {
                break
            }
            self.deactivateEntry(worstId)
        }
    }

    private func worstPreemptibleActiveEntry() -> (FetchManagerLocationEntryId, FetchManagerPriorityKey)? {
        var result: (FetchManagerLocationEntryId, FetchManagerPriorityKey)?
        for (id, activeContext) in self.activeContexts {
            if activeContext.userInitiated {
                continue
            }
            guard let key = self.entries[id]?.cachedPriorityKey else {
                continue
            }
            if let current = result {
                if current.1 < key {
                    result = (id, key)
                }
            } else {
                result = (id, key)
            }
        }
        return result
    }

    private func deactivateEntry(_ id: FetchManagerLocationEntryId) {
        if let activeContext = self.activeContexts.removeValue(forKey: id) {
            activeContext.disposable?.dispose()
            activeContext.disposable = nil
            if let entry = self.entries[id] {
                Logger.shared.log("FetchManager", "[\(entry.id.location)] Deactivated \(entry.resourceReference.resource.id.stringRepresentation)")
            }
        }
    }

    func isCurrentFetchAttempt(id: FetchManagerLocationEntryId, attempt: FetchManagerFetchAttempt) -> Bool {
        return self.activeContexts[id]?.attempt === attempt
    }

    func handleEntryFetchFailed(_ id: FetchManagerLocationEntryId) -> Double? {
        guard let entry = self.entries[id] else {
            return nil
        }
        // SuperGram: only the attempt that is still active can fail. Without this guard a late error from a
        // fetch that was already disposed — preempted by rebalanceActiveEntries, or reaped by the stall sweep
        // microseconds earlier — is charged to the entry a second time, doubling both the backoff and the
        // zero-progress count that leads to abandonment.
        guard let activeContext = self.activeContexts[id] else {
            return nil
        }
        let activationTimestamp = activeContext.activationTimestamp
        self.deactivateEntry(id)

        let attemptRuntime = CFAbsoluteTimeGetCurrent() - activationTimestamp

        // SuperGram: a fetch that ran for a while before failing was clearly making progress, so this is a fresh
        // problem and not a hopeless resource. Without the reset the backoff stayed pinned at 60 s for the rest
        // of the session after six early failures, which looks like "the download never resumes".
        if attemptRuntime >= FetchManagerCategoryContext.failureCountResetRuntime {
            entry.failureCount = 0
        }

        // SuperGram: track failures that transferred nothing at all, separately from `failureCount`. The runtime
        // reset above makes `failureCount` useless as a give-up signal for a resource that fails immediately and
        // repeatedly (a dead reference, a datacenter that will not route it). Bytes on disk do not lie.
        //
        // Only a *fast* failure counts. An attempt that ran for tens of seconds and still wrote nothing is
        // either a stall — which the sweep restarts, and restarting is the whole point — or a transfer so slow
        // that not one part has completed yet. On a weak link a large file legitimately looks exactly like the
        // latter (bytes only reach the disk when a whole part lands), and abandoning it would leave a perfectly
        // healthy download showing "tap to download" and never resuming on its own.
        let currentBytes = self.postbox.mediaBox.fileSizeForId(id.resourceId)
        if entry.lastKnownBytes < 0 || currentBytes > entry.lastKnownBytes {
            entry.lastKnownBytes = currentBytes
            entry.zeroProgressFailureCount = 0
        } else if attemptRuntime < FetchManagerCategoryContext.failureCountResetRuntime {
            entry.zeroProgressFailureCount += 1
        }

        // SuperGram: retry with backoff instead of keeping a dead fetch in an active slot forever
        entry.failureCount += 1
        let delay = min(60.0, pow(2.0, Double(min(entry.failureCount, 6))))
        entry.retryTimestamp = CFAbsoluteTimeGetCurrent() + delay

        if entry.zeroProgressFailureCount >= FetchManagerCategoryContext.maxZeroProgressFailures {
            // Nothing has ever arrived for this resource and repeated attempts changed nothing. Retrying forever
            // is indistinguishable from a hang: it keeps taking a slot of the category every minute and keeps the
            // UI on a cancel button that can never complete.
            entry.isAbandoned = true
            entry.retryTimestamp = nil
            Logger.shared.log("FetchManager", "[\(entry.id.location)] Giving up on \(entry.resourceReference.resource.id.stringRepresentation) after \(entry.zeroProgressFailureCount) attempts with no bytes received")
            self.updateStatusContextFlags(id: id)
            self.rebalanceActiveEntries()
            self.activeEntriesUpdated()
            return nil
        }

        Logger.shared.log("FetchManager", "[\(entry.id.location)] Fetch failed for \(entry.resourceReference.resource.id.stringRepresentation), retrying in \(delay) s")

        self.rebalanceActiveEntries()
        self.activeEntriesUpdated()

        return delay
    }

    // SuperGram: another owner of the same resource cancelled it, so this entry's fetch was torn down through
    // MediaBox.cancelInteractiveResourceFetch -> cancelFullRangeFetches (which is keyed by resource id and
    // therefore hits every live owner). This is not a failure of this entry: nothing is wrong with the resource,
    // the link or the request, and charging it as one gave a still-visible copy of the same media a 2–60 s
    // exponential backoff plus a step toward abandonment every time an off-screen sibling was recycled.
    //
    // Deactivate (the disposable is already dead) and come back after a short fixed delay. The delay exists only
    // so the restart lands after the cancelling burst has settled on the media data queue; it never grows, and
    // failureCount / zeroProgressFailureCount / lastKnownBytes are deliberately untouched.
    static let restartAfterForeignCancelDelay: Double = 0.5

    func handleEntryCancelledByAnotherOwner(_ id: FetchManagerLocationEntryId) -> Double? {
        guard let entry = self.entries[id] else {
            return nil
        }
        // Same guard as handleEntryFetchFailed: only the attempt that is still active can be the one that was
        // cancelled. A late error from an already-disposed attempt must not reschedule anything.
        guard self.activeContexts[id] != nil else {
            return nil
        }
        self.deactivateEntry(id)

        let delay = FetchManagerCategoryContext.restartAfterForeignCancelDelay
        entry.retryTimestamp = CFAbsoluteTimeGetCurrent() + delay

        Logger.shared.log("FetchManager", "[\(entry.id.location)] \(entry.resourceReference.resource.id.stringRepresentation) was cancelled by another owner of the resource, restarting in \(delay) s")

        self.rebalanceActiveEntries()
        self.activeEntriesUpdated()

        return delay
    }

    func retryFailedEntries() {
        self.rebalanceActiveEntries()
        self.activeEntriesUpdated()
    }

    // SuperGram: last-resort self-heal, see FetchManagerImpl.resetStuckFetches. Tears down every active fetch of
    // this category (or of one resource), forgets the backoff and the abandonment, and leaves the entries ready
    // to be activated again. It does NOT rebalance: the caller restarts the entries only after MediaBox has had
    // its own state reset, so a restarted fetch does not join the poisoned context it was stuck on.
    // Returns the resource ids it touched.
    func prepareFetchStateReset(resourceIdString: String?) -> [MediaResourceId] {
        var result: [MediaResourceId] = []
        // Snapshot the ids first: updateStatusContextFlags fans out to status subscribers synchronously on this
        // queue, and a subscriber is free to register or cancel a fetch in response, which would mutate
        // self.entries mid-iteration.
        var targetIds: [FetchManagerLocationEntryId] = []
        for (id, _) in self.entries {
            if let resourceIdString, id.resourceId.stringRepresentation != resourceIdString {
                continue
            }
            targetIds.append(id)
        }
        for id in targetIds {
            guard let entry = self.entries[id] else {
                continue
            }
            entry.failureCount = 0
            entry.zeroProgressFailureCount = 0
            entry.lastKnownBytes = -1
            entry.retryTimestamp = nil
            entry.isAbandoned = false
            result.append(id.resourceId)

            if let activeContext = self.activeContexts[id] {
                activeContext.disposable?.dispose()
                activeContext.disposable = nil
                self.activeContexts.removeValue(forKey: id)
            }
            self.updateStatusContextFlags(id: id)
        }
        return result
    }

    func finishFetchStateReset() {
        self.rebalanceActiveEntries()
        self.activeEntriesUpdated()
    }

    // SuperGram: push the entry's current isPaused/isAbandoned state to its status subscribers.
    private func updateStatusContextFlags(id: FetchManagerLocationEntryId) {
        guard let statusContext = self.statusContexts[id] else {
            return
        }
        let previousStatus = statusContext.combinedStatus
        if let entry = self.entries[id] {
            statusContext.hasEntry = true
            statusContext.isPaused = entry.isPaused
            statusContext.isAbandoned = entry.isAbandoned
        } else {
            statusContext.hasEntry = false
            statusContext.isPaused = false
            statusContext.isAbandoned = false
        }
        if let combinedStatus = statusContext.combinedStatus, combinedStatus != previousStatus {
            for f in statusContext.subscribers.copyItems() {
                f(combinedStatus)
            }
        }
    }

    // SuperGram: an active entry whose resource has not grown on disk for this long is treated as failed. See
    // FetchManagerActiveContext.lastProgressBytes for why nothing else would ever release its slot.
    //
    // On-disk bytes are a very coarse progress signal: they only move when a whole part lands, and a part can
    // be up to 1 MB. On a weak link a perfectly healthy large download therefore shows no growth for minutes,
    // and restarting it throws away every part that was in flight and asks for the same bytes again — the
    // slower the link, the more certain it is that the restart is also killed, so it never converges. This is
    // a backstop for a fetch whose signal is wedged, not a throughput policy: FetchV2's own watchdog knows the
    // part sizes and reaps a genuinely dead request first (FetchImpl.inFlightRequestDeadline, at most 240 s
    // plus one 12 s sweep), so this has to sit above that.
    static let activeStallTimeout: Double = 300.0
    // SuperGram: consecutive failed attempts with zero bytes received before an entry is abandoned
    static let maxZeroProgressFailures: Int = 5

    // Returns the ids of active entries that have stopped making progress. The caller runs them through the same
    // path a reported fetch error takes (deactivate + backoff + retry), so there is exactly one failure policy.
    func takeStalledActiveEntryIds() -> [FetchManagerLocationEntryId] {
        if self.activeContexts.isEmpty {
            return []
        }
        let timestamp = CFAbsoluteTimeGetCurrent()
        var result: [FetchManagerLocationEntryId] = []
        for (id, activeContext) in self.activeContexts {
            if activeContext.disposable == nil {
                continue
            }
            let currentBytes = self.postbox.mediaBox.fileSizeForId(id.resourceId)
            if activeContext.lastProgressBytes < 0 || currentBytes != activeContext.lastProgressBytes {
                activeContext.lastProgressBytes = currentBytes
                activeContext.lastProgressTimestamp = timestamp
                continue
            }
            if timestamp - activeContext.lastProgressTimestamp >= FetchManagerCategoryContext.activeStallTimeout {
                if let entry = self.entries[id] {
                    Logger.shared.log("FetchManager", "[\(entry.id.location)] \(entry.resourceReference.resource.id.stringRepresentation) made no progress for \(FetchManagerCategoryContext.activeStallTimeout) s, restarting it")
                }
                result.append(id)
            }
        }
        return result
    }

    var hasActiveEntries: Bool {
        return !self.activeContexts.isEmpty
    }

    // SuperGram: a fetch that ran at least this long before failing resets the retry backoff
    static let failureCountResetRuntime: Double = 30.0

    private func startFetch(id: FetchManagerLocationEntryId, entry: FetchManagerLocationEntry, activeContext: FetchManagerActiveContext, ranges: RangeSet<Int64>) {
        let attempt = FetchManagerFetchAttempt()
        activeContext.attempt = attempt
        activeContext.ranges = ranges
        activeContext.activationTimestamp = CFAbsoluteTimeGetCurrent()
        // SuperGram: restart the stall clock for this attempt; the first sweep samples the actual byte count.
        activeContext.lastProgressBytes = -1
        activeContext.lastProgressTimestamp = activeContext.activationTimestamp

        let parsedRanges: [(Range<Int64>, MediaBoxFetchPriority)]?

        var count = 0
        var isCompleteRange = false
        var isVideoPreload = false
        for range in ranges.ranges {
            count += 1
            if range.lowerBound == 0 && range.upperBound == Int64.max {
                isCompleteRange = true
            }
        }

        if count == 2, let range = ranges.ranges.first, range.lowerBound == 0 && range.upperBound == 2 * 1024 * 1024 {
            isVideoPreload = true
        }

        if count == 1 && isCompleteRange && !"".isEmpty {
            parsedRanges = nil
        } else {
            var resultRanges: [(Range<Int64>, MediaBoxFetchPriority)] = []
            for range in ranges.ranges {
                resultRanges.append((range, .default))
            }
            parsedRanges = resultRanges
        }

        var userLocation: MediaResourceUserLocation = .other
        switch entry.id.location {
        case let .chat(peerId):
            userLocation = .peer(peerId)
        }
        var userContentType: MediaResourceUserContentType = .other
        switch entry.statsCategory {
        case .image:
            userContentType = .image
        case .video:
            userContentType = .video
        case .audio:
            userContentType = .audio
        case .file:
            userContentType = .file
        default:
            userContentType = .other
        }

        let entryCompleted = self.entryCompleted
        let entryFailed = self.entryFailed
        let entryCancelledByAnotherOwner = self.entryCancelledByAnotherOwner
        let storeManager = self.storeManager
        activeContext.disposable?.dispose()
        activeContext.disposable = nil
        if isVideoPreload {
            activeContext.disposable = (preloadVideoResource(postbox: self.postbox, userLocation: userLocation, userContentType: userContentType, resourceReference: entry.resourceReference, duration: 4.0)
            |> castError(FetchResourceError.self)
            |> map { _ -> FetchResourceSourceType in }
            |> then(.single(.local))
            |> deliverOnMainQueue).start(next: { _ in
                entryCompleted(id, attempt)
            })
        } else if ranges.isEmpty {
        } else {
            let postbox = self.postbox
            Logger.shared.log("FetchManager", "[\(entry.id.location)] Begin fetching \(entry.resourceReference.resource.id.stringRepresentation) ranges: \(String(describing: parsedRanges))")

            activeContext.disposable = (fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: userLocation, userContentType: userContentType, reference: entry.resourceReference, ranges: parsedRanges, statsCategory: entry.statsCategory, reportResultStatus: true, continueInBackground: entry.userInitiated)
            |> mapToSignal { type -> Signal<FetchResourceSourceType, FetchResourceError> in
                if filterDownloadStatsEntry(entry: entry), case let .message(message, _) = entry.mediaReference, let messageId = message.id, case .remote = type {
                    let _ = addRecentDownloadItem(postbox: postbox, item: RecentDownloadItem(messageId: messageId, resourceId: entry.resourceReference.resource.id.stringRepresentation, timestamp: Int32(Date().timeIntervalSince1970), isSeen: false)).start()
                }

                if let storeManager = storeManager, let mediaReference = entry.mediaReference, case .remote = type, let peerId = entry.storeToDownloadsPeerId {
                    return storeDownloadedMedia(storeManager: storeManager, media: mediaReference, peerId: peerId)
                    |> castError(FetchResourceError.self)
                    |> mapToSignal { _ -> Signal<FetchResourceSourceType, FetchResourceError> in
                    }
                    |> then(.single(type))
                }
                return .single(type)
            }
            |> deliverOnMainQueue).start(next: { _ in
                Logger.shared.log("FetchManager", "Completed fetching \(entry.resourceReference.resource.id.stringRepresentation)")
                entryCompleted(id, attempt)
            }, error: { error in
                // SuperGram: `.cancelled` means another owner of this resource id cancelled it, not that this
                // download failed. Restart it without a backoff penalty (see handleEntryCancelledByAnotherOwner).
                switch error {
                case .cancelled:
                    entryCancelledByAnotherOwner(id, attempt)
                case .generic:
                    entryFailed(id, attempt)
                }
            })
        }
    }
    
    func getEntryId(resourceId: String) -> FetchManagerLocationEntryId? {
        for (id, _) in self.entries {
            if id.resourceId.stringRepresentation == resourceId {
                return id
            }
        }
        return nil
    }
    
    func cancelEntry(_ entryId: FetchManagerLocationEntryId, isCompleted: Bool) {
        var id: FetchManagerLocationEntryId = entryId
        if self.entries[id] == nil {
            for (key, _) in self.entries {
                if key.resourceId == entryId.resourceId {
                    id = key
                    break
                }
            }
        }
        
        var entriesRemoved = false
        let _ = entriesRemoved
        
        if let entry = self.entries[id] {
            Logger.shared.log("FetchManager", "Cancel fetching \(entry.resourceReference.resource.id.stringRepresentation)")
            self.entries.removeValue(forKey: id)
            entriesRemoved = true
            
            if let statusContext = self.statusContexts[id] {
                if statusContext.hasEntry {
                    // SuperGram: previousStatus has to be sampled *before* originalStatus is overwritten.
                    // Reading it afterwards made it equal to the new value on the completion path, so the
                    // `combinedStatus != previousStatus` guard below swallowed the .Local transition and this
                    // path never told its subscribers that the download had finished. It happened to work only
                    // because the MediaBox status subscription delivers .Local independently.
                    let previousStatus = statusContext.combinedStatus
                    if isCompleted {
                        statusContext.originalStatus = .Local
                    }
                    statusContext.hasEntry = false
                    statusContext.isPaused = false
                    statusContext.isAbandoned = false
                    if let combinedStatus = statusContext.combinedStatus, combinedStatus != previousStatus {
                        for f in statusContext.subscribers.copyItems() {
                            f(combinedStatus)
                        }
                    }
                }
            }
        }
        
        if let activeContext = self.activeContexts[id] {
            activeContext.disposable?.dispose()
            activeContext.disposable = nil
            self.activeContexts.removeValue(forKey: id)
        }

        self.rebalanceActiveEntries()

        self.activeEntriesUpdated()
    }
    
    func toggleEntryPaused(_ entryId: FetchManagerLocationEntryId, isPaused: Bool) -> Bool {
        var id: FetchManagerLocationEntryId = entryId
        if self.entries[id] == nil {
            for (key, _) in self.entries {
                if key.resourceId == entryId.resourceId {
                    id = key
                    break
                }
            }
        }
        
        if let entry = self.entries[id] {
            // SuperGram: an abandoned entry is surfaced to the downloads list as paused, so "resume" has to take
            // it back even though its isPaused flag was never set.
            let shouldResumeAbandoned = !isPaused && entry.isAbandoned
            if entry.isPaused == isPaused && !shouldResumeAbandoned {
                return entry.isPaused
            }
            if entry.isPaused != isPaused {
                entry.isPaused = isPaused
            }

            if entry.isPaused {
                if let activeContext = self.activeContexts[id] {
                    activeContext.disposable?.dispose()
                    activeContext.disposable = nil
                    self.activeContexts.removeValue(forKey: id)
                }
            }
            
            if !entry.isPaused {
                // SuperGram: an explicit resume retries immediately, and takes an abandoned entry back
                entry.retryTimestamp = nil
                entry.failureCount = 0
                entry.zeroProgressFailureCount = 0
                entry.isAbandoned = false
            }

            self.updateStatusContextFlags(id: id)
            self.rebalanceActiveEntries()
            self.activeEntriesUpdated()

            return entry.isPaused
        } else {
            return false
        }
    }
    
    func raiseEntryPriority(_ entryId: FetchManagerLocationEntryId) {
        var id: FetchManagerLocationEntryId = entryId
        if self.entries[id] == nil {
            for (key, _) in self.entries {
                if key.resourceId == entryId.resourceId {
                    id = key
                    break
                }
            }
        }
        
        if self.entries[id] == nil {
            return
        }
        
        var topUserInitiatedPriority: Int32 = 0
        for (_, entry) in self.entries {
            for index in entry.userInitiatedPriorityIndices {
                topUserInitiatedPriority = min(topUserInitiatedPriority, index)
            }
        }
        
        self.withEntry(id: id, takeNew: nil, { entry in
            if entry.userInitiatedPriorityIndices.last == topUserInitiatedPriority {
                return
            }
            
            entry.userInitiatedPriorityIndices.removeAll()
            entry.userInitiatedPriorityIndices.append(topUserInitiatedPriority - 1)
        })
    }
    
    func withFetchStatusContext(_ id: FetchManagerLocationEntryId, _ f: (FetchManagerStatusContext) -> Void) {
        let statusContext: FetchManagerStatusContext
        if let current = self.statusContexts[id] {
            statusContext = current
        } else {
            statusContext = FetchManagerStatusContext()
            self.statusContexts[id] = statusContext
            if let entry = self.entries[id] {
                statusContext.hasEntry = true
                statusContext.isPaused = entry.isPaused
            }
        }
        
        f(statusContext)
        
        if statusContext.isEmpty {
            statusContext.disposable?.dispose()
            self.statusContexts.removeValue(forKey: id)
        }
    }
    
    var isEmpty: Bool {
        return self.entries.isEmpty && self.activeContexts.isEmpty && self.statusContexts.isEmpty
    }
}

public struct FetchManagerEntrySummary: Equatable {
    public let id: FetchManagerLocationEntryId
    public let mediaReference: AnyMediaReference?
    public let resourceReference: MediaResourceReference
    public let priority: FetchManagerPriorityKey
    public let isPaused: Bool
}

private extension FetchManagerEntrySummary {
    init?(entry: FetchManagerLocationEntry) {
        guard let priority = entry.priorityKey else {
            return nil
        }
        self.id = entry.id
        self.mediaReference = entry.mediaReference
        self.resourceReference = entry.resourceReference
        self.priority = priority
        // SuperGram: an entry that gave up is shown in the downloads list as paused, which is the one state the
        // list already knows how to offer a "resume" for. Reporting it as running would be a lie.
        self.isPaused = entry.isPaused || entry.isAbandoned
    }
}

private func filterDownloadStatsEntry(entry: FetchManagerLocationEntry) -> Bool {
    guard let mediaReference = entry.mediaReference else {
        return false
    }
    if !entry.userInitiated {
        return false
    }
    switch mediaReference {
    case let .message(_, media):
        switch media {
        case let file as TelegramMediaFile:
            if file.isVideo {
                if file.isAnimated {
                    return false
                }
            }
            if file.isInstantVideo {
                return false
            }
            if file.isSticker {
                return false
            }
            if file.isVoice {
                return false
            }
            return true
        default:
            return false
        }
    default:
        return false
    }
}

public final class FetchManagerImpl: FetchManager {
    public let queue = Queue.mainQueue()
    private let postbox: Postbox
    private let storeManager: DownloadedMediaStoreManager?
    private var nextEpisodeId: Int32 = 0
    private var nextUserInitiatedIndex: Int32 = 0
    
    private var categoryContexts: [FetchManagerCategory: FetchManagerCategoryContext] = [:]
    
    private let hasUserInitiatedEntriesValue = ValuePromise<Bool>(false, ignoreRepeated: true)
    public var hasUserInitiatedEntries: Signal<Bool, NoError> {
        return self.hasUserInitiatedEntriesValue.get()
    }
    
    private let entriesSummaryValue = ValuePromise<[FetchManagerEntrySummary]>([], ignoreRepeated: true)
    public var entriesSummary: Signal<[FetchManagerEntrySummary], NoError> {
        return self.entriesSummaryValue.get()
    }
    
    private var pressureLevel: MediaDownloadPressure.Level = .normal
    private var pressureDisposable: Disposable?
    private var isActiveEntriesSummaryUpdateScheduled: Bool = false

    // SuperGram: how often active entries are checked for having stopped making progress. Armed only while
    // something is actually active, so an idle app has no timer.
    private static let stallSweepInterval: Double = 20.0
    private var isStallSweepScheduled: Bool = false
    private var selfHealDisposable: Disposable?

    public init(postbox: Postbox, storeManager: DownloadedMediaStoreManager?) {
        self.postbox = postbox
        self.storeManager = storeManager

        // SuperGram: fewer parallel fetches under memory/thermal/power pressure
        self.pressureDisposable = (MediaDownloadPressure.shared.levelSignal
        |> distinctUntilChanged
        |> deliverOn(self.queue)).start(next: { [weak self] level in
            guard let self else {
                return
            }
            self.updatePressureLevel(level)
        })

        // SuperGram: expose "reset stuck downloads" without making every FetchManager conformer implement it.
        self.selfHealDisposable = MediaDownloadSelfHeal.shared.registerHandler({ [weak self] resourceIdString, completion in
            guard let self else {
                completion(0)
                return
            }
            self.resetStuckFetches(resourceIdString: resourceIdString, completion: completion)
        })
    }

    deinit {
        self.pressureDisposable?.dispose()
        self.selfHealDisposable?.dispose()
    }

    // SuperGram: hard reset of the fetch state of one resource (or of everything). The order matters:
    //  1. tear down the FetchManager side first, so nothing is holding a disposable into MediaBox;
    //  2. reset MediaBox, which disposes the pending fetch, clears the materialized-range bookkeeping (an
    //     identical retry is otherwise deduplicated into a no-op) and moves status subscribers off .Fetching;
    //  3. only then restart the entries, so the new fetch does not join the state it was stuck on.
    // `completion` receives the number of distinct resources that were actually reset.
    public func resetStuckFetches(resourceIdString: String? = nil, completion: ((Int) -> Void)? = nil) {
        let queue = self.queue
        queue.async { [weak self] in
            guard let self else {
                completion?(0)
                return
            }

            var touchedResourceIds: [MediaResourceId] = []
            var touchedStrings = Set<String>()
            for (_, context) in self.categoryContexts {
                for resourceId in context.prepareFetchStateReset(resourceIdString: resourceIdString) {
                    if touchedStrings.insert(resourceId.stringRepresentation).inserted {
                        touchedResourceIds.append(resourceId)
                    }
                }
            }

            let restart: () -> Void = { [weak self] in
                queue.async {
                    guard let self else {
                        return
                    }
                    for key in Array(self.categoryContexts.keys) {
                        self.withCategoryContext(key, { context in
                            context.finishFetchStateReset()
                        })
                    }
                }
            }

            if let resourceIdString {
                let resourceId = touchedResourceIds.first ?? MediaResourceId(resourceIdString)
                self.postbox.mediaBox.resetResourceFetchState(resourceId, completion: { didReset in
                    restart()
                    queue.async {
                        completion?((didReset || !touchedStrings.isEmpty) ? 1 : 0)
                    }
                })
            } else {
                self.postbox.mediaBox.resetAllResourceFetchStates(completion: { resetIds in
                    for resourceId in resetIds {
                        touchedStrings.insert(resourceId.stringRepresentation)
                    }
                    restart()
                    queue.async {
                        completion?(touchedStrings.count)
                    }
                })
            }
        }
    }

    private func scheduleStallSweepIfNeeded() {
        if self.isStallSweepScheduled {
            return
        }
        var hasActiveEntries = false
        for (_, context) in self.categoryContexts {
            if context.hasActiveEntries {
                hasActiveEntries = true
                break
            }
        }
        if !hasActiveEntries {
            return
        }
        self.isStallSweepScheduled = true
        self.queue.after(FetchManagerImpl.stallSweepInterval, { [weak self] in
            guard let self else {
                return
            }
            self.isStallSweepScheduled = false
            self.sweepStalledEntries()
            self.scheduleStallSweepIfNeeded()
        })
    }

    // SuperGram: single failure policy for both a fetch that reported an error and a fetch that simply stopped
    // making progress (see FetchManagerCategoryContext.takeStalledActiveEntryIds).
    private func entryFetchFailed(category: FetchManagerCategory, id: FetchManagerLocationEntryId, attempt: FetchManagerFetchAttempt? = nil) {
        assert(self.queue.isCurrent())
        let queue = self.queue
        var retryDelay: Double?
        self.withCategoryContext(category, { context in
            if let attempt, !context.isCurrentFetchAttempt(id: id, attempt: attempt) {
                return
            }
            retryDelay = context.handleEntryFetchFailed(id)
        })
        if let retryDelay {
            queue.after(retryDelay + 0.05, { [weak self] in
                guard let self else {
                    return
                }
                if self.categoryContexts[category] != nil {
                    self.withCategoryContext(category, { context in
                        context.retryFailedEntries()
                    })
                }
            })
        }
    }

    // SuperGram: an entry whose fetch was torn down because another owner of the same resource cancelled it.
    // Same restart plumbing as entryFetchFailed, but the category context applies no failure policy to it.
    private func entryFetchCancelledByAnotherOwner(category: FetchManagerCategory, id: FetchManagerLocationEntryId, attempt: FetchManagerFetchAttempt) {
        assert(self.queue.isCurrent())
        let queue = self.queue
        var retryDelay: Double?
        self.withCategoryContext(category, { context in
            guard context.isCurrentFetchAttempt(id: id, attempt: attempt) else {
                return
            }
            retryDelay = context.handleEntryCancelledByAnotherOwner(id)
        })
        if let retryDelay {
            queue.after(retryDelay + 0.05, { [weak self] in
                guard let self else {
                    return
                }
                if self.categoryContexts[category] != nil {
                    self.withCategoryContext(category, { context in
                        context.retryFailedEntries()
                    })
                }
            })
        }
    }

    private func sweepStalledEntries() {
        for key in Array(self.categoryContexts.keys) {
            guard let context = self.categoryContexts[key] else {
                continue
            }
            let stalledIds = context.takeStalledActiveEntryIds()
            for id in stalledIds {
                // Same path a reported fetch error takes: one failure policy, one retry policy.
                self.entryFetchFailed(category: key, id: id)
            }
        }
    }

    private func updatePressureLevel(_ level: MediaDownloadPressure.Level) {
        if self.pressureLevel == level {
            return
        }
        self.pressureLevel = level
        for (_, context) in self.categoryContexts {
            context.pressureLevel = level
            context.rebalanceActiveEntries()
        }
        self.scheduleActiveEntriesSummaryUpdate()
    }

    private func scheduleActiveEntriesSummaryUpdate() {
        if self.isActiveEntriesSummaryUpdateScheduled {
            return
        }
        self.isActiveEntriesSummaryUpdateScheduled = true
        self.queue.after(0.1, { [weak self] in
            guard let self else {
                return
            }
            self.isActiveEntriesSummaryUpdateScheduled = false
            self.updateActiveEntriesSummary()
        })
    }

    private func updateActiveEntriesSummary() {
        // SuperGram: this is the one place that already runs (coalesced) whenever the set of active entries can
        // have changed, so it is where the stall sweep is armed.
        self.scheduleStallSweepIfNeeded()

        var hasActiveUserInitiatedEntries = false
        var activeEntries: [FetchManagerEntrySummary] = []
        for (_, context) in self.categoryContexts {
            if context.hasActiveUserInitiatedEntries {
                hasActiveUserInitiatedEntries = true
            }
            activeEntries.append(contentsOf: context.getActiveEntries().filter { entry in
                return filterDownloadStatsEntry(entry: entry)
            }.compactMap { entry -> FetchManagerEntrySummary? in
                return FetchManagerEntrySummary(entry: entry)
            })
        }
        self.hasUserInitiatedEntriesValue.set(hasActiveUserInitiatedEntries)

        let sortedEntries = activeEntries.sorted(by: { $0.priority < $1.priority })

        self.entriesSummaryValue.set(sortedEntries)
    }
    
    private func takeNextEpisodeId() -> Int32 {
        let value = self.nextEpisodeId
        self.nextEpisodeId += 1
        return value
    }
    
    private func takeNextUserInitiatedIndex() -> Int32 {
        let value = self.nextUserInitiatedIndex
        self.nextUserInitiatedIndex += 1
        return value
    }
    
    private func withCategoryContext(_ key: FetchManagerCategory, _ f: (FetchManagerCategoryContext) -> Void) {
        assert(self.queue.isCurrent())
        let context: FetchManagerCategoryContext
        if let current = self.categoryContexts[key] {
            context = current
        } else {
            let queue = self.queue
            context = FetchManagerCategoryContext(postbox: self.postbox, storeManager: self.storeManager, category: key, pressureLevel: self.pressureLevel, entryCompleted: { [weak self] id, attempt in
                queue.async {
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.withCategoryContext(key, { context in
                        guard context.isCurrentFetchAttempt(id: id, attempt: attempt) else {
                            return
                        }
                        context.cancelEntry(id, isCompleted: true)
                    })
                }
            }, entryFailed: { [weak self] id, attempt in
                queue.async {
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.entryFetchFailed(category: key, id: id, attempt: attempt)
                }
            }, entryCancelledByAnotherOwner: { [weak self] id, attempt in
                queue.async {
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.entryFetchCancelledByAnotherOwner(category: key, id: id, attempt: attempt)
                }
            }, activeEntriesUpdated: { [weak self] in
                // SuperGram: coalesce summary rebuilds (they iterate and sort every entry on the main queue)
                queue.async {
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.scheduleActiveEntriesSummaryUpdate()
                }
            })
            self.categoryContexts[key] = context
        }
        
        f(context)
        
        if context.isEmpty {
            self.categoryContexts.removeValue(forKey: key)
        }
    }
    
    public func interactivelyFetched(category: FetchManagerCategory, location: FetchManagerLocation, locationKey: FetchManagerLocationKey, mediaReference: AnyMediaReference?, resourceReference: MediaResourceReference, ranges: RangeSet<Int64>, statsCategory: MediaResourceStatsCategory, elevatedPriority: Bool, userInitiated: Bool, priority: FetchManagerPriority = .userInitiated, storeToDownloadsPeerId: EnginePeer.Id?) -> Signal<Void, NoError> {
        let queue = self.queue
        return Signal { [weak self] subscriber in
            if let strongSelf = self {
                var assignedEpisode: Int32?
                var assignedUserInitiatedIndex: Int32?
                let _ = assignedUserInitiatedIndex
                
                var assignedReferenceIndex: Int?
                var assignedRangeIndex: Int?
                
                strongSelf.withCategoryContext(category, { context in
                    context.withEntry(id: FetchManagerLocationEntryId(location: location, resourceId: resourceReference.resource.id, locationKey: locationKey), takeNew: { return (mediaReference, resourceReference, statsCategory, strongSelf.takeNextEpisodeId()) }, { entry in
                        assignedEpisode = entry.episode
                        if userInitiated {
                            entry.userInitiated = true
                            // SuperGram: an explicit request retries a failed entry right away, and takes back an
                            // entry that had given up — the user asking for it again is the clearest possible
                            // signal that the resource is still wanted.
                            entry.retryTimestamp = nil
                            entry.failureCount = 0
                            entry.zeroProgressFailureCount = 0
                            entry.isAbandoned = false
                        }
                        let wasPaused = entry.isPaused
                        entry.isPaused = false
                        if let peerId = storeToDownloadsPeerId {
                            entry.storeToDownloadsPeerId = peerId
                        }
                        assignedReferenceIndex = entry.references.add(priority)
                        if elevatedPriority {
                            entry.elevatedPriorityReferenceCount += 1
                        }
                        assignedRangeIndex = entry.ranges.add(ranges)
                        if userInitiated && !wasPaused {
                            let userInitiatedIndex = strongSelf.takeNextUserInitiatedIndex()
                            assignedUserInitiatedIndex = userInitiatedIndex
                            entry.userInitiatedPriorityIndices.removeAll()
                            entry.userInitiatedPriorityIndices.append(userInitiatedIndex)
                            entry.userInitiatedPriorityIndices.sort()
                        }
                    })
                })
                
                assert(assignedReferenceIndex != nil)
                assert(assignedRangeIndex != nil)
                
                return ActionDisposable {
                    queue.async {
                        if let strongSelf = self {
                            strongSelf.withCategoryContext(category, { context in
                                context.withEntry(id: FetchManagerLocationEntryId(location: location, resourceId: resourceReference.resource.id, locationKey: locationKey), takeNew: nil, { entry in
                                    if entry.episode == assignedEpisode {
                                        if let assignedReferenceIndex = assignedReferenceIndex {
                                            let previousCount = entry.references.copyItems().count
                                            entry.references.remove(assignedReferenceIndex)
                                            assert(entry.references.copyItems().count < previousCount)
                                        }
                                        if let assignedRangeIndex = assignedRangeIndex {
                                            let previousCount = entry.ranges.copyItems().count
                                            entry.ranges.remove(assignedRangeIndex)
                                            assert(entry.ranges.copyItems().count < previousCount)
                                        }
                                        if elevatedPriority {
                                            entry.elevatedPriorityReferenceCount -= 1
                                            assert(entry.elevatedPriorityReferenceCount >= 0)
                                        }
                                        /*if let userInitiatedIndex = assignedUserInitiatedIndex {
                                            if let index = entry.userInitiatedPriorityIndices.firstIndex(of: userInitiatedIndex) {
                                                entry.userInitiatedPriorityIndices.remove(at: index)
                                            } else {
                                                assertionFailure()
                                            }
                                        }*/
                                    }
                                })
                            })
                        }
                    }
                }
            } else {
                return EmptyDisposable
            }
        } |> runOn(self.queue)
    }
    
    public func cancelInteractiveFetches(category: FetchManagerCategory, location: FetchManagerLocation, locationKey: FetchManagerLocationKey, resource: MediaResource) {
        self.queue.async {
            self.withCategoryContext(category, { context in
                context.cancelEntry(FetchManagerLocationEntryId(location: location, resourceId: resource.id, locationKey: locationKey), isCompleted: false)
            })
            
            self.postbox.mediaBox.cancelInteractiveResourceFetch(resource)
        }
    }
    
    public func cancelInteractiveFetches(resourceId: String) {
        self.queue.async {
            var removeCategories: [FetchManagerCategory] = []
            for (category, categoryContext) in self.categoryContexts {
                if let id = categoryContext.getEntryId(resourceId: resourceId) {
                    categoryContext.cancelEntry(id, isCompleted: false)
                    if categoryContext.isEmpty {
                        removeCategories.append(category)
                    }
                }
            }
            
            for category in removeCategories {
                self.categoryContexts.removeValue(forKey: category)
            }
            
            self.postbox.mediaBox.cancelInteractiveResourceFetch(resourceId: MediaResourceId(resourceId))
        }
    }
    
    public func toggleInteractiveFetchPaused(resourceId: String, isPaused: Bool) {
        self.queue.async {
            for (_, categoryContext) in self.categoryContexts {
                if let id = categoryContext.getEntryId(resourceId: resourceId) {
                    if categoryContext.toggleEntryPaused(id, isPaused: isPaused) {
                        self.postbox.mediaBox.cancelInteractiveResourceFetch(resourceId: MediaResourceId(resourceId))
                    }
                }
            }
        }
    }
    
    public func raisePriority(resourceId: String) {
        self.queue.async {
            for (_, categoryContext) in self.categoryContexts {
                if let id = categoryContext.getEntryId(resourceId: resourceId) {
                    categoryContext.raiseEntryPriority(id)
                }
            }
        }
    }
    
    public func fetchStatus(category: FetchManagerCategory, location: FetchManagerLocation, locationKey: FetchManagerLocationKey, resource: MediaResource) -> Signal<MediaResourceStatus, NoError> {
        let queue = self.queue
        return Signal { [weak self] subscriber in
            if let strongSelf = self {
                var assignedIndex: Int?
                
                let entryId = FetchManagerLocationEntryId(location: location, resourceId: resource.id, locationKey: locationKey)
                strongSelf.withCategoryContext(category, { context in
                    context.withFetchStatusContext(entryId, { statusContext in
                        assignedIndex = statusContext.subscribers.add({ status in
                            subscriber.putNext(status)
                            if case .Local = status {
                                subscriber.putCompletion()
                            }
                        })
                        if let status = statusContext.combinedStatus {
                            subscriber.putNext(status)
                            if case .Local = status {
                                subscriber.putCompletion()
                            }
                        }
                        if statusContext.disposable == nil {
                            statusContext.disposable = strongSelf.postbox.mediaBox.resourceStatus(resource).start(next: { status in
                                queue.async {
                                    if let strongSelf = self {
                                        strongSelf.withCategoryContext(category, { context in
                                            context.withFetchStatusContext(entryId, { statusContext in
                                                let previousStatus = statusContext.combinedStatus
                                                statusContext.originalStatus = status
                                                // SuperGram: skip the subscriber fan-out when the combined status did not change
                                                if let combinedStatus = statusContext.combinedStatus, combinedStatus != previousStatus {
                                                    for f in statusContext.subscribers.copyItems() {
                                                        f(combinedStatus)
                                                    }
                                                }
                                            })
                                        })
                                    }
                                }
                            })
                        }
                    })
                })
                
                return ActionDisposable {
                    queue.async {
                        if let strongSelf = self {
                            strongSelf.withCategoryContext(category, { context in
                                context.withFetchStatusContext(entryId, { statusContext in
                                    if let assignedIndex = assignedIndex {
                                        statusContext.subscribers.remove(assignedIndex)
                                    }
                                })
                            })
                        }
                    }
                }
            } else {
                return EmptyDisposable
            }
        } |> runOn(self.queue)
    }
}
