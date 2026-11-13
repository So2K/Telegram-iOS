import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit
import RangeSet
import TelegramApi

private let possiblePartLengths: [Int64] = [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072, 262144, 524288, 1048576]

// SuperGram: per-part and per-pass FetchV2 logs are produced only with network logging enabled (sgNetworkLogging).
// Errors, retries and state changes are still logged unconditionally.
private func fetchV2VerboseLog(_ what: @autoclosure () -> String) {
    if MediaDownloadRuntimeSettings.isNetworkLoggingEnabled {
        Logger.shared.log("FetchV2", what())
    }
}

// SuperGram: resources that currently have at least one live user-initiated requester. MediaBox creates a single
// fetch per resource with the parameters of the first requester, so the FetchV2 budget consults this registry to
// classify a fetch by the most interactive live requester.
final class MediaFetchInteractiveRegistry {
    static let shared = MediaFetchInteractiveRegistry()

    private let lock = NSLock()
    private var counters: [String: Int] = [:]

    private init() {
    }

    func add(resourceId: String) -> Disposable {
        self.lock.lock()
        let previousCount = self.counters[resourceId] ?? 0
        self.counters[resourceId] = previousCount + 1
        self.lock.unlock()

        if previousCount == 0 {
            FetchImpl.interactiveResourceAdded(resourceId: resourceId)
        }

        return ActionDisposable { [weak self] in
            guard let self else {
                return
            }
            self.lock.lock()
            if let count = self.counters[resourceId] {
                if count <= 1 {
                    self.counters.removeValue(forKey: resourceId)
                } else {
                    self.counters[resourceId] = count - 1
                }
            }
            self.lock.unlock()
        }
    }

    func contains(resourceId: String) -> Bool {
        self.lock.lock()
        let result = !self.counters.isEmpty && self.counters[resourceId] != nil
        self.lock.unlock()
        return result
    }
}

private func alignPartFetchRange(partRange: Range<Int64>, minPartSize: Int64, maxPartSize: Int64, alignment: Int64, boundaryLimit: Int64) -> (partRange: Range<Int64>, fetchRange: Range<Int64>) {
    var partRange = partRange
    
    let lowerPartitionIndex = partRange.lowerBound / boundaryLimit
    let upperPartitionIndex = (partRange.upperBound - 1) / boundaryLimit
    if lowerPartitionIndex != upperPartitionIndex {
        partRange = partRange.lowerBound ..< (upperPartitionIndex * boundaryLimit)
    }
    
    let absolutePartLowerBound = (partRange.lowerBound / boundaryLimit) * boundaryLimit
    let absolutePartUpperBound = absolutePartLowerBound + boundaryLimit
    let maxPartRange = absolutePartLowerBound ..< absolutePartUpperBound
    
    let alignedPartLowerBound = (partRange.lowerBound / alignment) * alignment
    let alignmentDifference = partRange.lowerBound - alignedPartLowerBound
    if (partRange.upperBound - alignmentDifference) > partRange.lowerBound {
        partRange = partRange.lowerBound ..< (partRange.upperBound - alignmentDifference)
    }
    
    var selectedPartLength: Int64?
    if minPartSize == maxPartSize {
        assert(possiblePartLengths.contains(minPartSize))
        selectedPartLength = minPartSize
    } else {
        for partLength in possiblePartLengths {
            if partLength >= minPartSize && partLength <= maxPartSize && partLength >= partRange.upperBound - alignedPartLowerBound {
                selectedPartLength = partLength
                break
            }
        }
    }
    
    guard let fetchPartLength = selectedPartLength else {
        preconditionFailure()
    }
    
    var fetchRange = alignedPartLowerBound ..< (alignedPartLowerBound + fetchPartLength)
    
    if fetchRange.upperBound > maxPartRange.upperBound {
        fetchRange = (maxPartRange.upperBound - fetchPartLength) ..< maxPartRange.upperBound
    }
    
    assert(fetchRange.lowerBound >= maxPartRange.lowerBound)
    assert(fetchRange.lowerBound % alignment == 0)
    assert(possiblePartLengths.contains(fetchRange.upperBound - fetchRange.lowerBound))
    assert(fetchRange.lowerBound <= partRange.lowerBound && fetchRange.upperBound >= partRange.upperBound)
    assert(fetchRange.lowerBound / boundaryLimit == (fetchRange.upperBound - 1) / boundaryLimit)
    
    return (partRange, fetchRange)
}

private final class FetchImpl {
    // SuperGram: budget class of a scheduled part.
    // urgent: taken from an .elevated/.maximum range (playhead), never limited globally;
    // interactive: fetch has a user-initiated requester; background: everything else (auto-downloads, preloads).
    fileprivate enum BudgetClass {
        case urgent
        case interactive
        case background
    }

    private static let maxConsecutiveFailures: Int = 6
    private static let maxFileReferenceRefreshes: Int = 3
    private static let urgentPartSize: Int64 = 128 * 1024
    // SuperGram: stall watchdog period, see Impl.scheduleWatchdogIfNeeded
    private static let watchdogInterval: Double = 12.0
    // SuperGram: hard ceiling on how long a single *issued* request may stay unanswered. MTProto retransmits a
    // request rather than failing it, so a part whose response never arrives (a worker whose session was reset,
    // a connection that died while the app was suspended, a queued request the transport dropped) keeps a live
    // disposable forever. checkWatchdog treated "has a disposable" as "is in flight" and stood down, so this was
    // precisely the hole the watchdog was supposed to close: no progress, no error, and the FetchManager entry
    // holding its per-category slot for the rest of the session.
    //
    // This is a *floor*, not the deadline: see inFlightRequestDeadline. A flat 60 s is only safe for small
    // requests. A part is delivered as one indivisible response, so the only thing this timer can observe is
    // "the response has not arrived yet" — on a weak link a legitimate 512 KB part needs more than 60 s to
    // come back, and cancelling it throws away every byte that was already on the wire and asks for exactly
    // the same bytes again. That does not converge: the retry is just as slow, so the fetch burns data and
    // battery re-downloading one part until maxConsecutiveFailures turns it into a hard error.
    private static let inFlightRequestTimeout: Double = 60.0
    // SuperGram: the slowest per-request throughput that is still considered a working transfer. Below this a
    // download is hopeless anyway (2 KB/s is ~16 kbit/s), and cancelling would not make it any faster.
    private static let minAssumedRequestThroughput: Double = 2.0 * 1024.0
    // SuperGram: upper bound, so a dead request is still reaped in a bounded time. Kept below the FetchManager
    // stall sweep (FetchManagerCategoryContext.activeStallTimeout) plus its sweep period, so the layer that
    // actually knows the part sizes is always the one that acts first.
    private static let maxInFlightRequestTimeout: Double = 240.0

    // SuperGram: how long a single issued request of `size` bytes may stay unanswered before it is treated as
    // dead. Scaled by the request size so that a big part on a slow-but-working link is not killed.
    private static func inFlightRequestDeadline(size: Int64) -> Double {
        if size <= 0 {
            return FetchImpl.inFlightRequestTimeout
        }
        let scaled = Double(size) / FetchImpl.minAssumedRequestThroughput
        return min(FetchImpl.maxInFlightRequestTimeout, max(FetchImpl.inFlightRequestTimeout, scaled))
    }

    private static let priorityOrder: [Int] = [2, 1, 0]
    private static let defaultFirstPriorityOrder: [Int] = [0, 2, 1]

    // SuperGram: global FetchV2 part budget (DL-01). Accessed only on FetchImpl.sharedQueue.
    fileprivate final class Budget {
        static let shared = Budget()

        // SuperGram: a freed part slot is held for the waiters until the next drain, so the fetch that just
        // released it can't take it back in the same update() pass (see release/drain).
        private static let safetyDrainInterval: Double = 5.0
        // SuperGram: escape valve. If a waiter is still blocked after this long, it is granted one part even
        // though the limiter says there is no room. Bounded (one extra part per starved fetch per safety drain),
        // but it guarantees forward progress if the part accounting ever leaks a slot.
        private static let starvedWaiterTimeout: Double = 20.0

        private final class Waiter {
            weak var impl: Impl?
            let resourceId: String
            var isInteractive: Bool
            // SuperGram: the size of the part this fetch was refused, so drain() can test the byte budget with
            // the size that actually matters instead of a constant guess.
            var neededPartSize: Int64
            // SuperGram: the lane that refused it — .urgent has a byte ceiling of its own, so probing the shared
            // one would wake a playhead waiter that is about to be refused again.
            var neededBudgetClass: BudgetClass
            let seq: Int64
            let addedTimestamp: Double

            init(impl: Impl, resourceId: String, isInteractive: Bool, neededPartSize: Int64, neededBudgetClass: BudgetClass, seq: Int64, addedTimestamp: Double) {
                self.impl = impl
                self.resourceId = resourceId
                self.isInteractive = isInteractive
                self.neededPartSize = neededPartSize
                self.neededBudgetClass = neededBudgetClass
                self.seq = seq
                self.addedTimestamp = addedTimestamp
            }
        }

        private var interactiveParts: Int = 0
        private var backgroundParts: Int = 0
        // SuperGram: bytes of the parts currently in flight, see maxInFlightBytes. Taken and released with
        // exactly the same value (PendingPart carries it), so the accounting cannot drift.
        private var interactiveBytes: Int64 = 0
        private var backgroundBytes: Int64 = 0
        // SuperGram: the .urgent (playhead) share of interactiveBytes, so those parts can have a ceiling of
        // their own instead of no ceiling at all. Taken and released with the same stored PendingPart value.
        private var urgentBytes: Int64 = 0
        // SuperGram: capacity freed while waiters exist, held for them until drain() runs
        private var reservedInteractiveParts: Int = 0
        private var reservedBackgroundParts: Int = 0
        private var waiters: [ObjectIdentifier: Waiter] = [:]
        private var nextWaiterSeq: Int64 = 0
        private var isDrainScheduled: Bool = false
        fileprivate var isSafetyDrainScheduled: Bool = false
        fileprivate var safetyDrainTimer: DispatchSourceTimer?
        private var level: MediaDownloadPressure.Level
        private var levelDisposable: Disposable?

        private init() {
            self.level = MediaDownloadPressure.shared.level

            self.levelDisposable = (MediaDownloadPressure.shared.levelSignal
            |> deliverOn(FetchImpl.sharedQueue)).start(next: { [weak self] level in
                guard let self else {
                    return
                }
                if self.level != level {
                    self.level = level
                    self.scheduleDrain()
                }
            })
            MediaDownloadRuntimeSettings.addChangeHandler({
                FetchImpl.sharedQueue.async {
                    FetchImpl.Budget.shared.scheduleDrain()
                }
            })
        }

        private func limits() -> (interactive: Int, background: Int) {
            switch self.level {
            case .normal:
                // SuperGram: faster speed modes allow more parallel parts for user-visible downloads
                switch MediaDownloadRuntimeSettings.speedMode {
                case .standard:
                    return (32, 12)
                case .fast:
                    return (40, 12)
                case .maximum:
                    return (64, 16)
                }
            case .reduced:
                // Low Power Mode / a brief thermal spike. Trim, don't strangle: a user in Low Power Mode still
                // expects tapping a photo to load it, and the background lane still has to make real progress.
                return (24, 8)
            case .constrained:
                return (16, 4)
            case .critical:
                // SuperGram: never fewer than 2 background parts. At 1 the whole process shares a single
                // 128–256 KB request for every auto-download, which is indistinguishable from "it never loads"
                // and is the state a 12 s watchdog tick cannot rescue.
                return (8, 2)
            }
        }

        // SuperGram: hard ceiling on bytes held in download buffers at once, independent of the part count.
        // "maximum" speed mode takes 1 MB interactive parts, so its 64-part limit alone is ~64 MB of transient
        // buffers on top of the player and HLS buffers — a real jetsam contribution on a media-heavy chat.
        // Scaled by installed RAM, because the part limits are the same on every device.
        private static let maxInFlightBytes: Int64 = {
            let physicalMemory = ProcessInfo.processInfo.physicalMemory
            let scaled = Int64(min(physicalMemory / 128, UInt64(32 * 1024 * 1024)))
            return max(8 * 1024 * 1024, scaled)
        }()

        // SuperGram: playhead (.urgent) parts used to bypass the byte budget entirely — the user is watching
        // those bytes arrive, so refusing them is worse than the memory they hold. That was fine while urgent
        // parts were always 128 KB and rare, but it left the "hard ceiling" above with no upper bound at all:
        // several simultaneous streaming/story fetches (story urgent parts are 512 KB, see effectivePartSize)
        // could hold tens of megabytes of buffers and still be invisible to every other lane's admission test.
        // They now have a ceiling of their own instead of none. It is deliberately separate from (and on top of)
        // maxInFlightBytes so that the playhead still wins against every background and non-urgent interactive
        // part; what it can no longer do is grow without limit.
        private static let maxUrgentInFlightBytes: Int64 = max(2 * 1024 * 1024, Budget.maxInFlightBytes / 4)

        // SuperGram: bounded overdraft for a forced grant (the 20 s starved-waiter escape valve). The valve has
        // to be able to admit a part that the ceiling refuses — otherwise a byte-accounting drift would deadlock
        // the whole pipeline with no way back — but "force" used to mean "no byte test at all", so one drain
        // pass with dozens of starved waiters could admit dozens of extra parts (~25 MB with 512 KB parts) in
        // one go. The overdraft is cumulative and re-tested on every grant, so it bounds the whole pass, not
        // each grant: once the total is past ceiling + headroom no further forced grant succeeds.
        private static let forcedGrantHeadroomBytes: Int64 = 2 * 1024 * 1024

        // SuperGram: the smallest part any fetch can ask for (FetchingState.minPartSize). Used as the probe size
        // when a waiter's own needed size is not known.
        fileprivate static let minProbePartSize: Int64 = 4 * 1024

        // SuperGram: MediaDownloadActivity only cares whether *anything* is downloading (it keeps the app awake
        // in background). Reporting every take and release was ~80 cross-queue hops/s at speed on the hottest
        // path in the downloader, all of them discarded by the promise's ignoreRepeated. Report the edges only.
        private func reportInteractiveActivity(previousParts: Int) {
            if (previousParts == 0) != (self.interactiveParts == 0) {
                MediaDownloadActivity.shared.update(activeParts: self.interactiveParts)
            }
        }

        func tryTake(budgetClass: BudgetClass, fetchPendingParts: Int, partSize: Int64, force: Bool) -> Bool {
            let previousInteractiveParts = self.interactiveParts
            // SuperGram: the byte ceiling is the one rule nothing may skip. The part-count limits are a fairness
            // device and it is fine for the "every interactive fetch gets at least one part" and starved-waiter
            // rules to step over them; the byte ceiling is a memory bound, and stepping over it is precisely the
            // jetsam the limiter exists to prevent. hasByteCapacity keeps its own escape hatches (nothing in
            // flight at all, and a bounded overdraft for a forced grant) so nothing can deadlock on it.
            if !self.hasByteCapacity(budgetClass: budgetClass, partSize: partSize, force: force) {
                return false
            }
            switch budgetClass {
            case .urgent:
                // Playhead parts are never limited by the part counts: the user is watching these bytes arrive.
                self.interactiveParts += 1
                self.interactiveBytes += partSize
                self.urgentBytes += partSize
                self.reportInteractiveActivity(previousParts: previousInteractiveParts)
                return true
            case .interactive:
                // An interactive fetch always gets at least one part, so it can't starve
                let isUnconditional = force || fetchPendingParts == 0 || !MediaDownloadRuntimeSettings.isDownloadLimiterEnabled
                if isUnconditional || self.interactiveParts + self.reservedInteractiveParts < self.limits().interactive {
                    self.interactiveParts += 1
                    self.interactiveBytes += partSize
                    self.reportInteractiveActivity(previousParts: previousInteractiveParts)
                    return true
                } else {
                    return false
                }
            case .background:
                let isUnconditional = force || !MediaDownloadRuntimeSettings.isDownloadLimiterEnabled
                if isUnconditional || self.backgroundParts + self.reservedBackgroundParts < self.limits().background {
                    self.backgroundParts += 1
                    self.backgroundBytes += partSize
                    return true
                } else {
                    return false
                }
            }
        }

        // SuperGram: the memory bound of the whole downloader. Returns whether one more part of `partSize` may
        // be held in flight right now.
        //
        // Two deliberate escape hatches, both bounded:
        //  * nothing at all is in flight — one part always gets through, whatever its size and whatever the
        //    counters say. Without this a part larger than the remaining budget (or a byte-accounting drift that
        //    somehow survived PendingPart.deinit) would wedge the entire process with no way back.
        //  * a forced grant (the 20 s starved-waiter valve) may overdraw the ceiling by at most
        //    forcedGrantHeadroomBytes in total, not per grant.
        private func hasByteCapacity(budgetClass: BudgetClass, partSize: Int64, force: Bool) -> Bool {
            if !MediaDownloadRuntimeSettings.isDownloadLimiterEnabled {
                return true
            }
            if self.interactiveBytes + self.backgroundBytes <= 0 {
                return true
            }
            let total = self.interactiveBytes + self.backgroundBytes
            var ceiling: Int64
            let used: Int64
            switch budgetClass {
            case .urgent:
                ceiling = Budget.maxUrgentInFlightBytes
                used = self.urgentBytes
            case .interactive, .background:
                ceiling = Budget.maxInFlightBytes
                used = self.interactiveBytes + self.backgroundBytes
            }
            if force {
                ceiling += Budget.forcedGrantHeadroomBytes
            }
            if used + partSize > ceiling {
                return false
            }
            // SuperGram: urgentBytes is a share of interactiveBytes, so the playhead lane's own ceiling sits on
            // top of the shared one. Cap the sum as well, so there is a single number that the whole downloader
            // provably never exceeds instead of two that can be added together.
            var absoluteCeiling = Budget.maxInFlightBytes + Budget.maxUrgentInFlightBytes
            if force {
                absoluteCeiling += Budget.forcedGrantHeadroomBytes
            }
            return total + partSize <= absoluteCeiling
        }

        func release(budgetClass: BudgetClass, partSize: Int64) {
            switch budgetClass {
            case .urgent, .interactive:
                let previousInteractiveParts = self.interactiveParts
                self.interactiveParts = max(0, self.interactiveParts - 1)
                self.interactiveBytes = max(0, self.interactiveBytes - partSize)
                if case .urgent = budgetClass {
                    self.urgentBytes = max(0, self.urgentBytes - partSize)
                }
                self.reportInteractiveActivity(previousParts: previousInteractiveParts)
                // SuperGram: hold the freed slot for the waiters until drain() runs. Without this the fetch that
                // released the part re-takes it synchronously in the same update() pass (release() runs inline on
                // FetchImpl.sharedQueue from PendingPart.deinit, while drain() is dispatched), so a fetch waiting
                // for capacity could be starved indefinitely — "the download never starts".
                if !self.waiters.isEmpty && self.reservedInteractiveParts < self.waiters.count {
                    self.reservedInteractiveParts += 1
                }
            case .background:
                self.backgroundParts = max(0, self.backgroundParts - 1)
                self.backgroundBytes = max(0, self.backgroundBytes - partSize)
                if !self.waiters.isEmpty && self.reservedBackgroundParts < self.waiters.count {
                    self.reservedBackgroundParts += 1
                }
            }
            if !self.waiters.isEmpty {
                self.scheduleDrain()
            }
        }

        func addWaiter(impl: Impl, resourceId: String, isInteractive: Bool, neededPartSize: Int64, neededBudgetClass: BudgetClass) {
            let id = ObjectIdentifier(impl)
            if let current = self.waiters[id], current.impl === impl {
                current.isInteractive = isInteractive
                current.neededPartSize = neededPartSize
                current.neededBudgetClass = neededBudgetClass
            } else {
                // SuperGram: the wait clock and the FIFO position live on the Impl, not on the Waiter record.
                // drain() empties `waiters` and re-inserts only the ones it did not wake, so a fetch that *was*
                // woken and then failed tryTake (hasCapacity is checked with the smallest part size, tryTake with
                // the real one, so the two can disagree on the byte budget) used to land here and get a brand new
                // seq and a brand new timestamp. That reset its place in the queue and, worse, postponed the 20 s
                // starved-waiter escape valve on every single drain pass — the one backstop that guarantees a
                // blocked fetch eventually gets a part could therefore never fire.
                let seq: Int64
                if let existingSeq = impl.budgetWaitSeq {
                    seq = existingSeq
                } else {
                    self.nextWaiterSeq += 1
                    seq = self.nextWaiterSeq
                    impl.budgetWaitSeq = seq
                }
                let addedTimestamp = impl.budgetWaitSince ?? CFAbsoluteTimeGetCurrent()
                impl.budgetWaitSince = addedTimestamp
                self.waiters[id] = Waiter(impl: impl, resourceId: resourceId, isInteractive: isInteractive, neededPartSize: neededPartSize, neededBudgetClass: neededBudgetClass, seq: seq, addedTimestamp: addedTimestamp)
            }
            self.scheduleSafetyDrain()
        }

        func removeWaiter(impl: Impl) {
            self.waiters.removeValue(forKey: ObjectIdentifier(impl))
        }

        // SuperGram: identity-based removal for callers that must not keep the fetch alive (e.g. deinit
        // dispatching the removal to FetchImpl.sharedQueue).
        func removeWaiter(identity: ObjectIdentifier) {
            if let waiter = self.waiters[identity], waiter.impl != nil {
                // An ObjectIdentifier is just the address, and malloc reuses a freed block eagerly. A live impl
                // registered at this identity is a *new* fetch that happened to land on the dead one's address —
                // dropping its waiter would strand it forever.
                return
            }
            self.waiters.removeValue(forKey: identity)
        }

        func interactiveResourceAdded(resourceId: String) {
            // A waiting fetch that became interactive is re-evaluated right away: it is guaranteed at least one part
            var wokenImpls: [Impl] = []
            for (id, waiter) in self.waiters {
                if waiter.resourceId == resourceId {
                    self.waiters.removeValue(forKey: id)
                    if let impl = waiter.impl {
                        wokenImpls.append(impl)
                    }
                }
            }
            for impl in wokenImpls {
                impl.wakeFromBudget(forceGrant: false)
            }
        }

        private func hasCapacity(isInteractive: Bool, neededPartSize: Int64, neededBudgetClass: BudgetClass) -> Bool {
            if !MediaDownloadRuntimeSettings.isDownloadLimiterEnabled {
                return true
            }
            // SuperGram: probe with the size this waiter is actually blocked on, not with a constant.
            // This used to probe with urgentPartSize (128 KB) as "the smallest part there can be", which is
            // simply not true — a part can be as small as FetchingState.minPartSize (4 KB), and the tail part of
            // a file usually is. With under 128 KB of byte budget free no waiter was woken at all, even though
            // its 8 KB part would have fitted, so such a fetch only ever advanced through the 20 s starved-waiter
            // valve: one part every 20 seconds.
            if !self.hasByteCapacity(budgetClass: neededBudgetClass, partSize: max(Budget.minProbePartSize, neededPartSize), force: false) {
                return false
            }
            if case .urgent = neededBudgetClass {
                // The playhead lane has no part-count limit, only the byte ceiling tested above.
                return true
            }
            // SuperGram: count reservations exactly as tryTake does. drain() zeroes them first, so normally this
            // is the same test — but a release() can run inline (PendingPart.deinit) while drain is waking
            // waiters, and then a waiter woken on a "yes" here would fail tryTake, re-register with a fresh seq
            // and a fresh timestamp, and lose both its FIFO position and its progress toward the 20 s
            // starved-waiter escape valve. Declining to wake it instead keeps it in place, untouched.
            let limits = self.limits()
            if isInteractive {
                return self.interactiveParts + self.reservedInteractiveParts < limits.interactive
            } else {
                return self.backgroundParts + self.reservedBackgroundParts < limits.background
            }
        }

        private func scheduleDrain() {
            if self.isDrainScheduled {
                return
            }
            self.isDrainScheduled = true
            FetchImpl.sharedQueue.justDispatch {
                self.isDrainScheduled = false
                self.drain()
            }
        }

        // SuperGram: backstop for waiters that no release() would ever wake (a leaked slot, a level that never
        // changes again, a waiter added while nothing else is in flight). Runs only while waiters exist.
        private func scheduleSafetyDrain() {
            if self.isSafetyDrainScheduled || self.waiters.isEmpty {
                return
            }
            self.isSafetyDrainScheduled = true
            // Leeway so this backstop coalesces with other wake-ups rather than waking the CPU by itself every
            // 5 s for as long as anything is queued.
            let timer = DispatchSource.makeTimerSource(queue: FetchImpl.sharedQueue.queue)
            timer.schedule(deadline: DispatchTime.now() + Budget.safetyDrainInterval, leeway: .seconds(1))
            timer.setEventHandler(handler: {
                let budget = FetchImpl.Budget.shared
                budget.safetyDrainTimer?.cancel()
                budget.safetyDrainTimer = nil
                budget.isSafetyDrainScheduled = false
                budget.drain()
            })
            self.safetyDrainTimer?.cancel()
            self.safetyDrainTimer = timer
            timer.resume()
        }

        private func drain() {
            // Any capacity that was being held for the waiters is handed out in this pass
            self.reservedInteractiveParts = 0
            self.reservedBackgroundParts = 0

            if self.waiters.isEmpty {
                return
            }
            // SuperGram: oldest waiter first. Dictionary order gave no fairness at all, so under sustained load
            // the same fetch could be skipped pass after pass and never download anything.
            let waiters = self.waiters.values.sorted(by: { $0.seq < $1.seq })
            self.waiters.removeAll()

            let timestamp = CFAbsoluteTimeGetCurrent()

            // SuperGram: three passes, most latency-sensitive first — a blocked playhead part (the video the
            // user is watching right now), then the rest of the interactive lane (a file he tapped, media on
            // screen), then background (auto-download, preload). Within a pass the order stays FIFO by seq, so
            // nothing inside a pass can be starved. This used to be two passes with the playhead mixed into the
            // interactive one, which was harmless only because urgent parts could never be refused at all.
            for pass in 0 ..< 3 {
                for waiter in waiters {
                    let waiterPass: Int
                    if case .urgent = waiter.neededBudgetClass {
                        waiterPass = 0
                    } else if waiter.isInteractive {
                        waiterPass = 1
                    } else {
                        waiterPass = 2
                    }
                    if waiterPass != pass {
                        continue
                    }
                    guard let impl = waiter.impl else {
                        continue
                    }
                    let id = ObjectIdentifier(impl)
                    if self.hasCapacity(isInteractive: waiter.isInteractive, neededPartSize: waiter.neededPartSize, neededBudgetClass: waiter.neededBudgetClass) {
                        impl.wakeFromBudget(forceGrant: false)
                    } else if timestamp - waiter.addedTimestamp >= Budget.starvedWaiterTimeout {
                        fetchV2VerboseLog("Budget: waiter starved for \(timestamp - waiter.addedTimestamp) s, granting one part out of budget")
                        impl.wakeFromBudget(forceGrant: true)
                    } else if self.waiters[id] == nil {
                        self.waiters[id] = waiter
                    }
                }
            }

            self.scheduleSafetyDrain()
        }
    }

    // SuperGram: one coalescable tick for every live fetch's stall watchdog, instead of a self-rescheduling
    // `queue.after` per fetch. The timer exists only while at least one fetch is registered — i.e. only while
    // something is actually pending — and is cancelled the moment the last one deregisters, so an idle app
    // has no fetch timer running at all. Accessed only on FetchImpl.sharedQueue.
    fileprivate final class WatchdogSweeper {
        static let shared = WatchdogSweeper()

        private final class Entry {
            weak var impl: Impl?

            init(impl: Impl) {
                self.impl = impl
            }
        }

        private var entries: [ObjectIdentifier: Entry] = [:]
        private var timer: DispatchSourceTimer?

        func add(_ impl: Impl) {
            let identity = ObjectIdentifier(impl)
            if let existing = self.entries[identity], existing.impl === impl {
                return
            }
            self.entries[identity] = Entry(impl: impl)
            self.startTimerIfNeeded()
        }

        func remove(_ impl: Impl) {
            let identity = ObjectIdentifier(impl)
            guard let existing = self.entries[identity] else {
                return
            }
            // An ObjectIdentifier is just an address and malloc reuses freed blocks eagerly: never drop an
            // entry that belongs to a *different*, live fetch that landed on the same address.
            if let existingImpl = existing.impl, existingImpl !== impl {
                return
            }
            self.entries.removeValue(forKey: identity)
            self.stopTimerIfIdle()
        }

        func removeDead(identity: ObjectIdentifier) {
            if let existing = self.entries[identity], existing.impl == nil {
                self.entries.removeValue(forKey: identity)
                self.stopTimerIfIdle()
            }
        }

        private func startTimerIfNeeded() {
            if self.timer != nil || self.entries.isEmpty {
                return
            }
            let timer = DispatchSource.makeTimerSource(queue: FetchImpl.sharedQueue.queue)
            // Generous leeway: this is a stall backstop, not a deadline. It lets iOS fire it together with
            // other wake-ups rather than waking the CPU on its own.
            timer.schedule(deadline: DispatchTime.now() + FetchImpl.watchdogInterval, repeating: FetchImpl.watchdogInterval, leeway: .seconds(2))
            timer.setEventHandler(handler: {
                WatchdogSweeper.shared.sweep()
            })
            self.timer = timer
            timer.resume()
        }

        private func stopTimerIfIdle() {
            if self.entries.isEmpty {
                self.timer?.cancel()
                self.timer = nil
            }
        }

        private func sweep() {
            var impls: [Impl] = []
            var deadIdentities: [ObjectIdentifier] = []
            for (identity, entry) in self.entries {
                if let impl = entry.impl {
                    impls.append(impl)
                } else {
                    deadIdentities.append(identity)
                }
            }
            for identity in deadIdentities {
                self.entries.removeValue(forKey: identity)
            }

            let timestamp = CFAbsoluteTimeGetCurrent()
            for impl in impls {
                // checkWatchdog may re-enter add()/remove() through update(); entries is not being iterated here.
                if !impl.checkWatchdog(timestamp: timestamp) {
                    self.remove(impl)
                }
            }

            self.stopTimerIfIdle()
        }
    }

    fileprivate static func interactiveResourceAdded(resourceId: String) {
        FetchImpl.sharedQueue.justDispatch {
            FetchImpl.Budget.shared.interactiveResourceAdded(resourceId: resourceId)
        }
    }

    private final class PendingPart {
        let partRange: Range<Int64>
        let fetchRange: Range<Int64>
        let priorityIndex: Int
        let budgetClass: BudgetClass
        // SuperGram: the byte size this part was charged for when it was taken from the budget. Released with
        // exactly this value so the byte accounting cannot drift away from the part accounting.
        let budgetByteSize: Int64
        var disposable: Disposable?
        // SuperGram: when the network request behind this part was issued, see FetchImpl.inFlightRequestTimeout
        var requestStartTimestamp: Double?

        init(
            partRange: Range<Int64>,
            fetchRange: Range<Int64>,
            priorityIndex: Int,
            budgetClass: BudgetClass,
            budgetByteSize: Int64
        ) {
            self.partRange = partRange
            self.fetchRange = fetchRange
            self.priorityIndex = priorityIndex
            self.budgetClass = budgetClass
            self.budgetByteSize = budgetByteSize
        }

        deinit {
            self.disposable?.dispose()

            let budgetClass = self.budgetClass
            let budgetByteSize = self.budgetByteSize
            FetchImpl.sharedQueue.async {
                FetchImpl.Budget.shared.release(budgetClass: budgetClass, partSize: budgetByteSize)
            }
        }
    }
    
    private final class PendingReadyPart {
        let partRange: Range<Int64>
        let fetchRange: Range<Int64>
        let fetchedData: Data
        let cleanData: Data

        var verificationRange: Range<Int64> {
            // A final CDN response can be shorter than its aligned request. Hash only bytes
            // that were actually returned, without requiring nonexistent bytes beyond EOF.
            return self.fetchRange.lowerBound ..< (self.fetchRange.lowerBound + Int64(self.fetchedData.count))
        }
        
        init(
            partRange: Range<Int64>,
            fetchRange: Range<Int64>,
            fetchedData: Data,
            cleanData: Data
        ) {
            self.partRange = partRange
            self.fetchRange = fetchRange
            self.fetchedData = fetchedData
            self.cleanData = cleanData
        }
    }
    
    private final class PendingHashRange {
        let range: Range<Int64>
        var disposable: Disposable?
        // SuperGram: when the network request behind this hash range was issued, see FetchImpl.inFlightRequestTimeout
        var requestStartTimestamp: Double?

        init(range: Range<Int64>) {
            self.range = range
        }
        
        deinit {
            self.disposable?.dispose()
        }
    }
    
    private final class HashRangeData {
        let range: Range<Int64>
        let data: Data
        
        init(range: Range<Int64>, data: Data) {
            self.range = range
            self.data = data
        }
    }
    
    private final class CdnData {
        let id: Int
        let sourceDatacenterId: Int
        let fileToken: Data
        let encryptionKey: Data
        let encryptionIv: Data
        
        init(
            id: Int,
            sourceDatacenterId: Int,
            fileToken: Data,
            encryptionKey: Data,
            encryptionIv: Data
        ) {
            self.id = id
            self.sourceDatacenterId = sourceDatacenterId
            self.fileToken = fileToken
            self.encryptionKey = encryptionKey
            self.encryptionIv = encryptionIv
        }
    }
    
    private final class VerifyPartHashData {
        let fetchRange: Range<Int64>
        let fetchedData: Data
        
        init(fetchRange: Range<Int64>, fetchedData: Data) {
            self.fetchRange = fetchRange
            self.fetchedData = fetchedData
        }
    }
    
    private enum FetchLocation {
        case datacenter(Int)
        case cdn(CdnData)
    }
    
    private final class DecryptionState {
        let aesKey: Data
        var aesIv: Data
        let decryptedSize: Int64
        var offset: Int = 0
        
        init(aesKey: Data, aesIv: Data, decryptedSize: Int64) {
            self.aesKey = aesKey
            self.aesIv = aesIv
            self.decryptedSize = decryptedSize
        }

        func canDecrypt(data: Data, offset: Int64) -> Bool {
            // The native IGE implementation copies 32 IV bytes and expects complete AES blocks.
            return self.aesKey.count == 32 && self.aesIv.count == 32 && self.decryptedSize >= 0
                && offset >= 0 && offset <= self.decryptedSize
                && (data.isEmpty ? offset == self.decryptedSize : offset < self.decryptedSize)
                && offset <= Int64.max - Int64(data.count) && data.count % 16 == 0
        }
        
        func tryDecrypt(data: Data, offset: Int, loggingIdentifier: String) -> Data? {
            guard offset == self.offset, self.canDecrypt(data: data, offset: Int64(offset)) else {
                return nil
            }
            if offset == self.offset {
                var decryptedData = data
                let decryptedDataCount = decryptedData.count
                // SuperGram: an empty part used to trap on the force unwrap of baseAddress (0 % 16 == 0 passes
                // the check above), and so did an empty IV. Nothing to decrypt in either case.
                if decryptedDataCount == 0 {
                    return decryptedData
                }
                decryptedData.withUnsafeMutableBytes { rawBytes -> Void in
                    guard let bytes = rawBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        return
                    }
                    self.aesIv.withUnsafeMutableBytes { rawIv -> Void in
                        guard let iv = rawIv.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                            return
                        }
                        MTAesDecryptBytesInplaceAndModifyIv(bytes, decryptedDataCount, self.aesKey, iv)
                    }
                }
                let remainingSize = self.decryptedSize - Int64(self.offset)
                decryptedData.count = Int(min(Int64(decryptedData.count), remainingSize))
                self.offset += decryptedData.count
                fetchV2VerboseLog("\(loggingIdentifier): decrypted part \(offset) ..< \(offset + data.count) (new offset is \(self.offset))")
                return decryptedData
            } else {
                return nil
            }
        }
    }
    
    private final class FetchingState {
        let fetchLocation: FetchLocation
        let partSize: Int64
        let minPartSize: Int64
        let maxPartSize: Int64
        let partAlignment: Int64
        let partDivision: Int64
        let maxPendingParts: Int
        
        var pendingParts: [PendingPart] = []
        var completedRanges = RangeSet<Int64>()
        
        var decryptionState: DecryptionState?
        var pendingReadyParts: [PendingReadyPart] = []
        var completedHashRanges = RangeSet<Int64>()
        var pendingHashRanges: [PendingHashRange] = []
        var hashRanges: [Int64: HashRangeData] = [:]

        init(
            fetchLocation: FetchLocation,
            partSize: Int64,
            minPartSize: Int64,
            maxPartSize: Int64,
            partAlignment: Int64,
            partDivision: Int64,
            maxPendingParts: Int,
            decryptionState: DecryptionState?
        ) {
            self.fetchLocation = fetchLocation
            self.partSize = partSize
            self.minPartSize = minPartSize
            self.maxPartSize = maxPartSize
            self.partAlignment = partAlignment
            self.partDivision = partDivision
            self.maxPendingParts = maxPendingParts
            self.decryptionState = decryptionState
        }
        
        deinit {
            for pendingPart in self.pendingParts {
                pendingPart.disposable?.dispose()
            }
            for pendingHashRange in self.pendingHashRanges {
                pendingHashRange.disposable?.dispose()
            }
        }
    }
    
    private final class ReuploadingToCdnState {
        let cdnData: CdnData
        let refreshToken: Data
        var disposable: Disposable?
        
        init(cdnData: CdnData, refreshToken: Data) {
            self.cdnData = cdnData
            self.refreshToken = refreshToken
        }
        
        deinit {
            self.disposable?.dispose()
        }
    }
    
    private final class RefreshingFileReferenceState {
        let fetchLocation: FetchLocation
        var disposable: Disposable?
        
        init(
            fetchLocation: FetchLocation
        ) {
            self.fetchLocation = fetchLocation
        }
        
        deinit {
            self.disposable?.dispose()
        }
    }
    
    private enum State {
        case fetching(FetchingState)
        case reuploadingToCdn(ReuploadingToCdnState)
        case refreshingFileReference(RefreshingFileReferenceState)
        case failed
    }
    
    private struct RequiredRange: Equatable {
        let value: Range<Int64>
        let priority: MediaBoxFetchPriority
        
        init(
            value: Range<Int64>,
            priority: MediaBoxFetchPriority
        ) {
            self.value = value
            self.priority = priority
        }
    }
    
    fileprivate final class Impl {
        private let queue: Queue
        
        private let accountPeerId: PeerId
        private let postbox: Postbox
        private let network: Network
        private let mediaReferenceRevalidationContext: MediaReferenceRevalidationContext?
        private var resource: TelegramMediaResource
        private let datacenterId: Int
        private let size: Int64?
        private let parameters: MediaResourceFetchParameters?
        private let encryptionKey: SecretFileEncryptionKey?
        private let decryptedSize: Int64?
        private let continueInBackground: Bool
        private let useMainConnection: Bool
        private let onNext: (MediaResourceDataFetchResult) -> Void
        private let onError: (MediaResourceDataFetchError) -> Void
        
        private let consumerId: Int64
        
        private var knownSize: Int64?
        private var didReportKnownSize: Bool = false
        private var updatedFileReference: Data?
        
        private var requiredRangesDisposable: Disposable?
        private var requiredRanges: [RequiredRange] = []
        
        private let defaultPartSize: Int64
        private let cdnPartSize: Int64
        private let maxPendingParts: Int
        private var state: State?

        // SuperGram: limiter and failure handling state
        private let resourceIdString: String
        private let isStory: Bool
        private let isInteractiveByParameters: Bool
        private var isBudgetWaiter: Bool = false
        // SuperGram: owned by Budget.addWaiter/drain. They survive a wake-up that failed to take a part, so the
        // starved-waiter escape valve and the FIFO order are measured from when this fetch *first* started
        // waiting, not from the last drain pass. Cleared as soon as the fetch actually gets capacity.
        fileprivate var budgetWaitSince: Double?
        fileprivate var budgetWaitSeq: Int64?
        private var budgetForceGrant: Bool = false
        private var consecutiveFailures: Int = 0
        private var retryNotBefore: Double?
        private var fileReferenceRefreshCount: Int = 0
        private var didReportError: Bool = false

        // SuperGram: stall watchdog. `progressCounter` is bumped by every part/hash response; if nothing
        // happened and nothing is in flight while ranges are still required, update() is re-run.
        private var progressCounter: Int = 0
        private var watchdogProgressCounter: Int = 0
        private var isWatchdogScheduled: Bool = false
        private var watchdogLastCheckTimestamp: Double = 0.0

        private let loggingIdentifier: String
        
        init(
            queue: Queue,
            accountPeerId: PeerId,
            postbox: Postbox,
            network: Network,
            mediaReferenceRevalidationContext: MediaReferenceRevalidationContext?,
            resource: TelegramMediaResource,
            datacenterId: Int,
            size: Int64?,
            intervals: Signal<[(Range<Int64>, MediaBoxFetchPriority)], NoError>,
            parameters: MediaResourceFetchParameters?,
            encryptionKey: SecretFileEncryptionKey?,
            decryptedSize: Int64?,
            continueInBackground: Bool,
            useMainConnection: Bool,
            onNext: @escaping (MediaResourceDataFetchResult) -> Void,
            onError: @escaping (MediaResourceDataFetchError) -> Void
        ) {
            self.queue = queue
            
            self.accountPeerId = accountPeerId
            self.postbox = postbox
            self.network = network
            self.mediaReferenceRevalidationContext = mediaReferenceRevalidationContext
            self.resource = resource
            self.datacenterId = datacenterId
            self.size = size
            self.parameters = parameters
            self.encryptionKey = encryptionKey
            self.decryptedSize = decryptedSize

            // SuperGram: honor continueInBackground of user-initiated fetches (FetchManager) (DL-11)
            let infoContinueInBackground = (parameters?.info as? TelegramCloudMediaResourceFetchInfo)?.continueInBackground ?? false
            self.continueInBackground = continueInBackground || infoContinueInBackground
            self.useMainConnection = useMainConnection

            self.onNext = onNext
            self.onError = onError

            self.consumerId = Int64.random(in: Int64.min ... Int64.max)

            self.knownSize = size

            /*#if DEBUG
            self.updatedFileReference = Data()
            #endif*/

            var isStory = false
            if let info = parameters?.info as? TelegramCloudMediaResourceFetchInfo {
                switch info.reference {
                case let .media(media, _):
                    if case .story = media {
                        isStory = true
                    }
                default:
                    break
                }
            }

            self.resourceIdString = resource.id.stringRepresentation
            self.isStory = isStory
            // Small resources (photos, stickers, emoji; one or two parts) are cheap and almost always on screen,
            // so only large media competes for the background budget
            var isSmallResource = false
            if let size, size > 0, size <= 512 * 1024 {
                isSmallResource = true
            }
            self.isInteractiveByParameters = (parameters?.isInteractive ?? false) || infoContinueInBackground || isSmallResource

            // SuperGram: part size policy (CRIT-07): 256K parts for .default ranges of large files (fewer part events),
            // parts taken from .elevated/.maximum ranges are capped at urgentPartSize in update(); 6 pending parts per fetch,
            // the global budget bounds the total.
            if isStory {
                self.defaultPartSize = 512 * 1024
                self.maxPendingParts = 6
            } else if (size ?? 0) > 2 * 1024 * 1024 {
                self.defaultPartSize = 256 * 1024
                // SuperGram: more parallel parts per large file in faster speed modes (the global budget bounds the total)
                switch MediaDownloadRuntimeSettings.speedMode {
                case .standard:
                    self.maxPendingParts = 6
                case .fast:
                    self.maxPendingParts = 8
                case .maximum:
                    self.maxPendingParts = 12
                }
            } else {
                self.defaultPartSize = 128 * 1024
                self.maxPendingParts = 6
            }
            self.cdnPartSize = 128 * 1024
            
            if let resource = resource as? TelegramCloudMediaResource {
                if let apiInputLocation = resource.apiInputLocation(fileReference: Data()) {
                    self.loggingIdentifier = "\(apiInputLocation)"
                } else {
                    self.loggingIdentifier = "unknown cloud"
                }
            } else {
                self.loggingIdentifier = "unknown"
            }
            
            self.update()
            
            self.requiredRangesDisposable = (intervals
            |> deliverOn(self.queue)).startStrict(next: { [weak self] intervals in
                guard let `self` = self else {
                    return
                }
                let requiredRanges = intervals.map { RequiredRange(value: $0.0, priority: $0.1) }
                if self.requiredRanges != requiredRanges {
                    self.requiredRanges = requiredRanges
                    self.update()
                }
            })
        }
        
        deinit {
            self.requiredRangesDisposable?.dispose()

            // SuperGram: the budget and the watchdog registry are documented as "accessed only on
            // FetchImpl.sharedQueue", but deinit can run on any thread (the last release may come from a signal
            // delivered elsewhere), so mutate the shared state on that queue. Mirrors PendingPart.deinit.
            let identity = ObjectIdentifier(self)
            let wasBudgetWaiter = self.isBudgetWaiter
            let wasWatchdogScheduled = self.isWatchdogScheduled
            if wasBudgetWaiter || wasWatchdogScheduled {
                FetchImpl.sharedQueue.async {
                    if wasBudgetWaiter {
                        FetchImpl.Budget.shared.removeWaiter(identity: identity)
                    }
                    if wasWatchdogScheduled {
                        FetchImpl.WatchdogSweeper.shared.removeDead(identity: identity)
                    }
                }
            }
        }

        func wakeFromBudget(forceGrant: Bool) {
            self.isBudgetWaiter = false
            if forceGrant {
                self.budgetForceGrant = true
            }
            self.update()
            self.budgetForceGrant = false
        }

        // SuperGram: re-run update() when a fetch has gone quiet with nothing in flight while it still needs
        // bytes. Any such state is a bug, but the user-visible symptom is a download that spins forever, so the
        // watchdog turns it into a (logged) retry instead.
        //
        // This used to be one self-rescheduling `queue.after` per live fetch. A media-heavy channel with a
        // saturated budget meant dozens of independent no-leeway timers firing several times a second forever,
        // including while the app was backgrounded. The work is now a single shared, coalescable tick
        // (WatchdogSweeper) that only exists while at least one fetch is actually waiting on something.
        private func scheduleWatchdogIfNeeded() {
            if self.didReportError {
                self.stopWatchdog()
                return
            }
            guard case .fetching = self.state else {
                self.stopWatchdog()
                return
            }
            if self.requiredRanges.isEmpty {
                self.stopWatchdog()
                return
            }
            // A registered budget waiter is legitimately idle and is owned by the budget's own safety drain —
            // but only while it has nothing outstanding. A waiter whose own dead requests are what hold the
            // budget slots would never be reaped otherwise: the drain wakes it, tryTake fails because its own
            // zombie parts occupy the lane, and it re-registers forever.
            if self.isBudgetWaiter && !self.hasInFlightRequests {
                self.stopWatchdog()
                return
            }
            if !self.isWatchdogScheduled {
                self.isWatchdogScheduled = true
                self.watchdogLastCheckTimestamp = CFAbsoluteTimeGetCurrent()
                WatchdogSweeper.shared.add(self)
            }
        }

        private func stopWatchdog() {
            if self.isWatchdogScheduled {
                self.isWatchdogScheduled = false
                WatchdogSweeper.shared.remove(self)
            }
        }

        // SuperGram: whether any network request issued by this fetch is still outstanding.
        private var hasInFlightRequests: Bool {
            guard case let .fetching(state) = self.state else {
                return false
            }
            if state.pendingParts.contains(where: { $0.disposable != nil }) {
                return true
            }
            if state.pendingHashRanges.contains(where: { $0.disposable != nil }) {
                return true
            }
            return false
        }

        // Returns whether this fetch should keep being watched. Called from the shared sweeper tick.
        fileprivate func checkWatchdog(timestamp: Double) -> Bool {
            if self.didReportError {
                self.isWatchdogScheduled = false
                return false
            }
            guard case let .fetching(state) = self.state else {
                self.isWatchdogScheduled = false
                return false
            }
            if self.requiredRanges.isEmpty {
                self.isWatchdogScheduled = false
                return false
            }
            if self.isBudgetWaiter && !self.hasInFlightRequests {
                // The budget's safety drain and starved-waiter escape valve own this case; re-running update()
                // here would reset the waiter's place in the FIFO on every tick. A waiter that still has
                // requests outstanding is *not* owned by the budget: only the timeout below can reap those.
                self.isWatchdogScheduled = false
                return false
            }
            // The shared tick is not aligned to when this fetch was registered, so only act once a full
            // interval has actually elapsed for *this* fetch.
            if timestamp - self.watchdogLastCheckTimestamp < FetchImpl.watchdogInterval {
                return true
            }
            self.watchdogLastCheckTimestamp = timestamp

            let madeProgress = self.progressCounter != self.watchdogProgressCounter
            self.watchdogProgressCounter = self.progressCounter

            var isBackingOffNow = false
            if let retryNotBefore = self.retryNotBefore, timestamp < retryNotBefore {
                isBackingOffNow = true
            }

            var hasInFlight = false
            // SuperGram: a request that was issued but is never answered used to make this method stand down
            // forever ("something is in flight, so this is not a stall"). MTProto keeps retransmitting instead of
            // reporting an error, so nothing below ever fired and the whole fetch hung. Treat a request that has
            // been outstanding for inFlightRequestTimeout with no progress anywhere in this fetch as dead:
            // cancel it, release its budget slot and go through the normal retry/backoff path, which re-schedules
            // the range and eventually reports a real error (MediaBox then resets and FetchManager retries).
            var timedOutParts: [PendingPart] = []
            var timedOutHashRanges: [PendingHashRange] = []
            for pendingPart in state.pendingParts where pendingPart.disposable != nil {
                hasInFlight = true
                // SuperGram: the deadline scales with the size of this particular request, so a large part that
                // is simply arriving slowly is left alone (see inFlightRequestDeadline).
                let requestSize = max(pendingPart.budgetByteSize, pendingPart.fetchRange.upperBound - pendingPart.fetchRange.lowerBound)
                if let requestStartTimestamp = pendingPart.requestStartTimestamp, timestamp - requestStartTimestamp >= FetchImpl.inFlightRequestDeadline(size: requestSize) {
                    timedOutParts.append(pendingPart)
                }
            }
            for pendingHashRange in state.pendingHashRanges where pendingHashRange.disposable != nil {
                hasInFlight = true
                // A hash request carries a handful of bytes, so the floor is the right deadline for it.
                if let requestStartTimestamp = pendingHashRange.requestStartTimestamp, timestamp - requestStartTimestamp >= FetchImpl.inFlightRequestTimeout {
                    timedOutHashRanges.append(pendingHashRange)
                }
            }

            if !madeProgress && !isBackingOffNow && (!timedOutParts.isEmpty || !timedOutHashRanges.isEmpty) {
                Logger.shared.log("FetchV2", "\(self.loggingIdentifier): \(timedOutParts.count + timedOutHashRanges.count) request(s) unanswered past their deadline with no progress, cancelling and retrying")

                for pendingPart in timedOutParts {
                    pendingPart.disposable?.dispose()
                    pendingPart.disposable = nil
                    if let index = state.pendingParts.firstIndex(where: { $0 === pendingPart }) {
                        state.pendingParts.remove(at: index)
                    }
                }
                for pendingHashRange in timedOutHashRanges {
                    pendingHashRange.disposable?.dispose()
                    pendingHashRange.disposable = nil
                    if let index = state.pendingHashRanges.firstIndex(where: { $0 === pendingHashRange }) {
                        state.pendingHashRanges.remove(at: index)
                    }
                }
                // Drop the last strong references here, so the budget slots are released (PendingPart.deinit runs
                // inline on this queue) before update() tries to take capacity for the replacement parts.
                timedOutParts.removeAll()
                timedOutHashRanges.removeAll()

                self.isWatchdogScheduled = false
                if !self.scheduleRetryAfterFailure() {
                    self.failWithError(reason: "requests timed out \(FetchImpl.maxConsecutiveFailures + 1) times")
                    return false
                }
                self.update()
                return self.isWatchdogScheduled
            }

            if !madeProgress && !hasInFlight && !isBackingOffNow {
                fetchV2VerboseLog("\(self.loggingIdentifier): watchdog: no progress and nothing in flight for \(FetchImpl.watchdogInterval) s, re-running update()")
                // update() ends by re-evaluating the registration, so an update that leaves .fetching or
                // registers as a budget waiter deregisters this fetch on its own.
                self.isWatchdogScheduled = false
                self.update()
                return self.isWatchdogScheduled
            }

            return true
        }

        private func failWithError(reason: String) {
            if self.didReportError {
                return
            }
            self.didReportError = true

            Logger.shared.log("FetchV2", "\(self.loggingIdentifier): fetch failed: \(reason)")

            self.state = .failed
            if self.isBudgetWaiter {
                self.isBudgetWaiter = false
                FetchImpl.Budget.shared.removeWaiter(impl: self)
            }
            self.budgetWaitSince = nil
            self.budgetWaitSeq = nil
            self.onError(.generic)
        }

        // Returns false when the retry limit is exhausted
        private func scheduleRetryAfterFailure() -> Bool {
            let timestamp = CFAbsoluteTimeGetCurrent()
            if let retryNotBefore = self.retryNotBefore, timestamp < retryNotBefore {
                // A request started before the current backoff window failed too; already accounted for
                return true
            }

            self.consecutiveFailures += 1
            if self.consecutiveFailures > FetchImpl.maxConsecutiveFailures {
                return false
            }

            let delay = min(8.0, 0.5 * pow(2.0, Double(self.consecutiveFailures - 1)))
            self.retryNotBefore = timestamp + delay
            Logger.shared.log("FetchV2", "\(self.loggingIdentifier): request failed (attempt \(self.consecutiveFailures)), retrying in \(delay) s")

            self.queue.after(delay, { [weak self] in
                guard let self else {
                    return
                }
                if let retryNotBefore = self.retryNotBefore, CFAbsoluteTimeGetCurrent() + 0.05 >= retryNotBefore {
                    self.retryNotBefore = nil
                }
                self.update()
            })

            return true
        }

        private func update() {
            if self.state == nil {
                fetchV2VerboseLog("\(self.loggingIdentifier): initializing to .datacenter(\(self.datacenterId))")
                
                var decryptionState: DecryptionState?
                if let encryptionKey = self.encryptionKey, let decryptedSize = self.decryptedSize {
                    decryptionState = DecryptionState(aesKey: encryptionKey.aesKey, aesIv: encryptionKey.aesIv, decryptedSize: decryptedSize)
                    self.onNext(.reset)
                }
                
                self.state = .fetching(FetchingState(
                    fetchLocation: .datacenter(self.datacenterId),
                    partSize: self.defaultPartSize,
                    minPartSize: 4 * 1024,
                    maxPartSize: 1 * 1024 * 1024,
                    partAlignment: 4 * 1024,
                    partDivision: 1 * 1024 * 1024,
                    maxPendingParts: self.maxPendingParts,
                    decryptionState: decryptionState
                ))
            }
            guard let state = self.state else {
                return
            }
            
            switch state {
            case let .fetching(state):
                if let knownSize = self.knownSize, !self.didReportKnownSize {
                    self.didReportKnownSize = true
                    self.onNext(.resourceSizeUpdated(knownSize))
                }
                
                do {
                    var removedPendingReadyPartIndices: [Int] = []
                    if let decryptionState = state.decryptionState {
                        while true {
                            var removedSomePendingReadyPart = false
                            for i in 0 ..< state.pendingReadyParts.count {
                                if removedPendingReadyPartIndices.contains(i) {
                                    continue
                                }
                                let pendingReadyPart = state.pendingReadyParts[i]
                                if let resultData = decryptionState.tryDecrypt(data: pendingReadyPart.cleanData, offset: Int(pendingReadyPart.fetchRange.lowerBound), loggingIdentifier: self.loggingIdentifier) {
                                    removedPendingReadyPartIndices.append(i)
                                    removedSomePendingReadyPart = true
                                    self.commitPendingReadyPart(state: state, partRange: pendingReadyPart.partRange, fetchRange: pendingReadyPart.fetchRange, data: resultData)
                                }
                            }
                            if !removedSomePendingReadyPart {
                                break
                            }
                        }
                    } else {
                        for i in 0 ..< state.pendingReadyParts.count {
                            let pendingReadyPart = state.pendingReadyParts[i]
                            if state.completedHashRanges.isSuperset(of: RangeSet<Int64>(pendingReadyPart.verificationRange)) {
                                removedPendingReadyPartIndices.append(i)
                                
                                var checkOffset: Int64 = 0
                                var checkFailed = false
                                while checkOffset < pendingReadyPart.fetchedData.count {
                                    if let hashRange = state.hashRanges[pendingReadyPart.fetchRange.lowerBound + checkOffset] {
                                        var clippedHashRange = hashRange.range
                                        // A master digest describes its entire declared range. Never accept a
                                        // digest of a shorter prefix as proof of bytes missing beyond EOF.
                                        guard clippedHashRange.upperBound <= pendingReadyPart.verificationRange.upperBound else {
                                            checkFailed = true
                                            break
                                        }
                                        
                                        if pendingReadyPart.fetchRange.lowerBound + Int64(pendingReadyPart.fetchedData.count) < clippedHashRange.lowerBound {
                                            Logger.shared.log("FetchV2", "\(self.loggingIdentifier): unable to check \(pendingReadyPart.fetchRange): data range \(clippedHashRange) out of bounds (0 ..< \(pendingReadyPart.fetchedData.count))")
                                            checkFailed = true
                                            break
                                        }
                                        clippedHashRange = clippedHashRange.lowerBound ..< min(clippedHashRange.upperBound, pendingReadyPart.fetchRange.lowerBound + Int64(pendingReadyPart.fetchedData.count))
                                        
                                        let partLocalHashRange = (clippedHashRange.lowerBound - pendingReadyPart.fetchRange.lowerBound) ..< (clippedHashRange.upperBound - pendingReadyPart.fetchRange.lowerBound)
                                        
                                        if partLocalHashRange.lowerBound < 0 || partLocalHashRange.upperBound > pendingReadyPart.fetchedData.count {
                                            Logger.shared.log("FetchV2", "\(self.loggingIdentifier): unable to check \(pendingReadyPart.fetchRange): data range \(partLocalHashRange) out of bounds (0 ..< \(pendingReadyPart.fetchedData.count))")
                                            checkFailed = true
                                            break
                                        }
                                        
                                        let dataToHash = pendingReadyPart.cleanData.subdata(in: Int(partLocalHashRange.lowerBound) ..< Int(partLocalHashRange.upperBound))
                                        let localHash = MTSha256(dataToHash)
                                        if localHash != hashRange.data {
                                            Logger.shared.log("FetchV2", "\(self.loggingIdentifier): failed to verify \(pendingReadyPart.fetchRange): hash mismatch")
                                            checkFailed = true
                                            break
                                        }
                                        
                                        checkOffset += partLocalHashRange.upperBound - partLocalHashRange.lowerBound
                                    } else {
                                        Logger.shared.log("FetchV2", "\(self.loggingIdentifier): unable to find \(pendingReadyPart.fetchRange) hash range despite it being marked as ready")
                                        checkFailed = true
                                        break
                                    }
                                }
                                if !checkFailed {
                                    if self.commitPendingReadyPart(state: state, partRange: pendingReadyPart.partRange, fetchRange: pendingReadyPart.fetchRange, data: pendingReadyPart.cleanData) {
                                        self.consecutiveFailures = 0
                                        self.fileReferenceRefreshCount = 0
                                    }
                                } else {
                                    Logger.shared.log("FetchV2", "\(self.loggingIdentifier): unable to find \(pendingReadyPart.fetchRange) hash check failed")
                                    if !self.scheduleRetryAfterFailure() {
                                        self.failWithError(reason: "CDN hash verification repeatedly failed")
                                        return
                                    }
                                }
                            }
                        }
                    }
                    for index in removedPendingReadyPartIndices.sorted(by: >) {
                        state.pendingReadyParts.remove(at: index)
                    }
                }
                
                var requiredHashRanges = RangeSet<Int64>()
                for pendingReadyPart in state.pendingReadyParts {
                    //TODO:check if already have hashes
                    if state.decryptionState == nil {
                        requiredHashRanges.formUnion(RangeSet<Int64>(pendingReadyPart.verificationRange))
                    }
                }
                requiredHashRanges.subtract(state.completedHashRanges)
                for pendingHashRange in state.pendingHashRanges {
                    requiredHashRanges.subtract(RangeSet<Int64>(pendingHashRange.range))
                }
                
                let expectedHashRangeLength: Int64 = 1 * 1024 * 1024
                while state.pendingHashRanges.count < state.maxPendingParts {
                    guard let requiredHashRange = requiredHashRanges.ranges.first else {
                        break
                    }
                    let hashRange: Range<Int64> = requiredHashRange.lowerBound ..< (requiredHashRange.lowerBound + expectedHashRangeLength)
                    requiredHashRanges.subtract(RangeSet<Int64>(hashRange))
                    
                    state.pendingHashRanges.append(FetchImpl.PendingHashRange(range: hashRange))
                }
                
                var filteredRequiredRanges: [RangeSet<Int64>] = []
                for _ in 0 ..< 3 {
                    filteredRequiredRanges.append(RangeSet<Int64>())
                }

                for range in self.requiredRanges {
                    filteredRequiredRanges[Int(range.priority.rawValue)].formUnion(RangeSet<Int64>(range.value))
                }
                if let knownSize = self.knownSize {
                    for i in 0 ..< filteredRequiredRanges.count {
                        filteredRequiredRanges[i].remove(contentsOf: knownSize ..< Int64.max)
                    }
                }
                var excludedInHigherPriorities = RangeSet<Int64>()
                for i in (0 ..< filteredRequiredRanges.count).reversed() {
                    filteredRequiredRanges[i].subtract(excludedInHigherPriorities)
                    filteredRequiredRanges[i].subtract(state.completedRanges)
                    for pendingPart in state.pendingParts {
                        filteredRequiredRanges[i].remove(contentsOf: pendingPart.partRange)
                    }
                    for pendingReadyPart in state.pendingReadyParts {
                        filteredRequiredRanges[i].remove(contentsOf: pendingReadyPart.partRange)
                    }

                    // SuperGram: a range requested at several priorities is scheduled only once, at the highest one (DL-06)
                    excludedInHigherPriorities.formUnion(filteredRequiredRanges[i])
                }

                // SuperGram: after a failed request, don't schedule new requests until the backoff interval passes (DL-04)
                var isBackingOff = false
                if let retryNotBefore = self.retryNotBefore {
                    if CFAbsoluteTimeGetCurrent() < retryNotBefore {
                        isBackingOff = true
                    } else {
                        self.retryNotBefore = nil
                    }
                }

                if !isBackingOff && state.pendingParts.count < state.maxPendingParts && state.pendingReadyParts.count < state.maxPendingParts {
                    if MediaDownloadRuntimeSettings.isNetworkLoggingEnabled {
                        var debugRangesString = ""
                        for priorityIndex in 0 ..< 3 {
                            if filteredRequiredRanges[priorityIndex].isEmpty {
                                continue
                            }

                            if !debugRangesString.isEmpty {
                                debugRangesString.append(", ")
                            }
                            debugRangesString.append("priority: \(priorityIndex): [")

                            var isFirst = true
                            for range in filteredRequiredRanges[priorityIndex].ranges {
                                if isFirst {
                                    isFirst = false
                                } else {
                                    debugRangesString.append(", ")
                                }
                                debugRangesString.append("\(range.lowerBound)..<\(range.upperBound)")
                            }
                            debugRangesString.append("]")
                        }

                        if !debugRangesString.isEmpty {
                            Logger.shared.log("FetchV2", "\(self.loggingIdentifier): will fetch \(debugRangesString)")
                        }
                    }

                    // SuperGram: the fetch is interactive if any requester asked for an .elevated/.maximum range,
                    // if it was started by a user-initiated API, or if a user-initiated requester joined it later
                    var isInteractiveFetch = self.isInteractiveByParameters
                    if !isInteractiveFetch {
                        for range in self.requiredRanges {
                            if range.priority != .default {
                                isInteractiveFetch = true
                                break
                            }
                        }
                    }
                    if !isInteractiveFetch && !filteredRequiredRanges[0].isEmpty {
                        isInteractiveFetch = MediaFetchInteractiveRegistry.shared.contains(resourceId: self.resourceIdString)
                    }

                    var isDefaultBlockedByBudget = false
                    // SuperGram: the smallest part size the budget refused in this pass. drain() probes the byte
                    // budget with it, so a fetch blocked on a small part is woken as soon as a small part fits
                    // (see Budget.hasCapacity). Starts at Int64.max so the first refusal wins.
                    var blockedPartSize: Int64 = Int64.max
                    // SuperGram: which lane refused that part, so drain() probes the same ceiling it will be
                    // tested against (the playhead lane has its own).
                    var blockedBudgetClass: BudgetClass = .background

                    while state.pendingParts.count < state.maxPendingParts && state.pendingReadyParts.count < state.maxPendingParts {
                        // SuperGram: strict priority (maximum, elevated, default) instead of round-robin, but the last
                        // free slot goes to .default when none is pending, so a full download still progresses (STREAM-3)
                        var hasPendingDefaultPart = false
                        for pendingPart in state.pendingParts {
                            if pendingPart.priorityIndex == 0 {
                                hasPendingDefaultPart = true
                                break
                            }
                        }
                        let priorityOrder: [Int]
                        if state.decryptionState != nil {
                            // SuperGram: a secret file is decrypted strictly sequentially (DecryptionState.offset
                            // must match the part offset exactly), so a part fetched out of order can never be
                            // decrypted: it sits in pendingReadyParts, pendingReadyParts fills up to maxPendingParts
                            // and the whole fetch deadlocks with no error. Always take the lowest required offset,
                            // whatever its priority.
                            priorityOrder = (0 ..< filteredRequiredRanges.count).sorted(by: { lhs, rhs in
                                let lhsValue = filteredRequiredRanges[lhs].ranges.first?.lowerBound ?? Int64.max
                                let rhsValue = filteredRequiredRanges[rhs].ranges.first?.lowerBound ?? Int64.max
                                if lhsValue != rhsValue {
                                    return lhsValue < rhsValue
                                }
                                return lhs > rhs
                            })
                        } else if !hasPendingDefaultPart && state.pendingParts.count >= state.maxPendingParts - 1 {
                            priorityOrder = FetchImpl.defaultFirstPriorityOrder
                        } else {
                            priorityOrder = FetchImpl.priorityOrder
                        }

                        var found = false
                        inner: for priorityIndex in priorityOrder {
                            if priorityIndex == 0 && isDefaultBlockedByBudget {
                                continue
                            }
                            guard let firstRange = filteredRequiredRanges[priorityIndex].ranges.first else {
                                continue
                            }

                            let budgetClass: BudgetClass
                            if priorityIndex > 0 {
                                budgetClass = .urgent
                            } else if isInteractiveFetch {
                                budgetClass = .interactive
                            } else {
                                budgetClass = .background
                            }
                            // SuperGram: small parts for the playhead: the first playable bytes arrive sooner (STREAM-4).
                            // Computed before taking the budget because the budget is also a byte budget and
                            // needs to know how much this part will hold in memory.
                            var effectivePartSize = state.partSize
                            if priorityIndex > 0 && !self.isStory {
                                effectivePartSize = min(effectivePartSize, FetchImpl.urgentPartSize)
                            } else if budgetClass == .interactive && state.partSize >= 256 * 1024 && state.decryptionState == nil && MediaDownloadPressure.shared.level <= .reduced {
                                // SuperGram: larger parts for user-initiated downloads of large files: fewer round trips per MB.
                                // Not for secret files: when the size changes mid-download (pressure level, background ->
                                // interactive), alignPartFetchRange shifts a part back to the 1 MB partition start, and the
                                // overlapping part never matches DecryptionState.offset, so the download stalls forever.
                                switch MediaDownloadRuntimeSettings.speedMode {
                                case .standard:
                                    break
                                case .fast:
                                    effectivePartSize = min(state.maxPartSize, 512 * 1024)
                                case .maximum:
                                    effectivePartSize = min(state.maxPartSize, 1024 * 1024)
                                }
                            }

                            // SuperGram: a forced grant now applies to .urgent too. It used to be skipped for the
                            // playhead because urgent parts could never be refused; they can be now (they have a
                            // byte ceiling of their own), so the starved-waiter valve has to be able to rescue
                            // them as well.
                            let forceTake = self.budgetForceGrant
                            if !FetchImpl.Budget.shared.tryTake(budgetClass: budgetClass, fetchPendingParts: state.pendingParts.count, partSize: effectivePartSize, force: forceTake) {
                                // SuperGram: an .urgent refusal (the playhead ceiling) lands here too. Registering
                                // as a budget waiter is the right response in both cases; the only side effect is
                                // that priority 0 is skipped for the rest of this pass, and the waiter is woken
                                // again as soon as capacity frees up.
                                isDefaultBlockedByBudget = true
                                if effectivePartSize < blockedPartSize {
                                    blockedPartSize = effectivePartSize
                                    blockedBudgetClass = budgetClass
                                }
                                continue
                            }
                            if forceTake {
                                // An out-of-budget grant covers exactly one part
                                self.budgetForceGrant = false
                            }
                            // Capacity was granted: this fetch is making progress, so the next time it has to
                            // wait its starvation clock starts from scratch.
                            self.budgetWaitSince = nil
                            self.budgetWaitSeq = nil

                            let (partRange, alignedRange) = alignPartFetchRange(
                                partRange: firstRange.lowerBound ..< min(firstRange.upperBound, firstRange.lowerBound + effectivePartSize),
                                minPartSize: state.minPartSize,
                                maxPartSize: state.maxPartSize,
                                alignment: state.partAlignment,
                                boundaryLimit: state.partDivision
                            )

                            let storePartRange = alignedRange
                            fetchV2VerboseLog("\(self.loggingIdentifier): take part \(partRange) (store aligned as \(storePartRange), priority \(priorityIndex))")

                            let pendingPart = PendingPart(
                                partRange: storePartRange,
                                fetchRange: alignedRange,
                                priorityIndex: priorityIndex,
                                budgetClass: budgetClass,
                                budgetByteSize: effectivePartSize
                            )
                            state.pendingParts.append(pendingPart)
                            // SuperGram: the aligned part may cover bytes of other priorities too (STREAM-3)
                            for i in 0 ..< filteredRequiredRanges.count {
                                filteredRequiredRanges[i].remove(contentsOf: storePartRange)
                            }

                            found = true
                            break inner
                        }
                        if !found {
                            break
                        }
                    }

                    if isDefaultBlockedByBudget {
                        FetchImpl.Budget.shared.addWaiter(impl: self, resourceId: self.resourceIdString, isInteractive: isInteractiveFetch, neededPartSize: blockedPartSize == Int64.max ? state.minPartSize : blockedPartSize, neededBudgetClass: blockedBudgetClass)
                        self.isBudgetWaiter = true
                    } else if self.isBudgetWaiter {
                        self.isBudgetWaiter = false
                        self.budgetWaitSince = nil
                        self.budgetWaitSeq = nil
                        FetchImpl.Budget.shared.removeWaiter(impl: self)
                    }
                }

                for pendingPart in state.pendingParts {
                    if pendingPart.disposable == nil {
                        self.fetchPart(state: state, part: pendingPart)
                        if self.didReportError {
                            return
                        }
                    }
                }
                if !isBackingOff {
                    for pendingHashRange in state.pendingHashRanges {
                        if pendingHashRange.disposable == nil {
                            self.fetchHashRange(state: state, hashRange: pendingHashRange)
                        }
                    }
                }

                self.scheduleWatchdogIfNeeded()
            case let .reuploadingToCdn(state):
                if state.disposable == nil {
                    Logger.shared.log("FetchV2", "\(self.loggingIdentifier): refreshing CDN")
                    
                    let reuploadSignal = self.network.multiplexedRequestManager.request(
                        to: .main(state.cdnData.sourceDatacenterId),
                        consumerId: self.consumerId,
                        resourceId: self.resource.id.stringRepresentation,
                        data: Api.functions.upload.reuploadCdnFile(
                            fileToken: Buffer(data: state.cdnData.fileToken),
                            requestToken: Buffer(data: state.refreshToken)
                        ),
                        tag: nil,
                        continueInBackground: self.continueInBackground,
                        expectedResponseSize: nil
                    )
                    
                    let cdnData = state.cdnData
                    
                    state.disposable = (reuploadSignal
                    |> deliverOn(self.queue)).startStrict(next: { [weak self] result in
                        guard let `self` = self else {
                            return
                        }
                        self.state = .fetching(FetchImpl.FetchingState(
                            fetchLocation: .cdn(cdnData),
                            partSize: self.cdnPartSize,
                            minPartSize: self.cdnPartSize,
                            maxPartSize: self.cdnPartSize * 2,
                            partAlignment: self.cdnPartSize,
                            partDivision: 1 * 1024 * 1024,
                            maxPendingParts: self.maxPendingParts,
                            decryptionState: nil
                        ))
                        self.update()
                    }, error: { [weak self] error in
                        guard let `self` = self else {
                            return
                        }
                        // SuperGram: report the error instead of stalling silently (DL-04)
                        self.failWithError(reason: "CDN reupload failed (\(error.errorCode))")
                    })
                }
            case let .refreshingFileReference(state):
                if state.disposable == nil {
                    Logger.shared.log("FetchV2", "\(self.loggingIdentifier): refreshing file reference")

                    guard let info = self.parameters?.info as? TelegramCloudMediaResourceFetchInfo, let mediaReferenceRevalidationContext = self.mediaReferenceRevalidationContext else {
                        // SuperGram: nothing can revalidate the reference; previously this stalled forever (DL-04)
                        self.failWithError(reason: "file reference expired and can't be revalidated")
                        return
                    }
                    do {
                        let fetchLocation = state.fetchLocation
                        
                        state.disposable = (revalidateMediaResourceReference(
                            accountPeerId: self.accountPeerId,
                            postbox: self.postbox,
                            network: self.network,
                            revalidationContext: mediaReferenceRevalidationContext,
                            info: info,
                            resource: self.resource
                        )
                        |> deliverOn(self.queue)).startStrict(next: { [weak self] validationResult in
                            guard let `self` = self else {
                                return
                            }
                            
                            if let validatedResource = validationResult.updatedResource as? TelegramCloudMediaResourceWithFileReference, let reference = validatedResource.fileReference {
                                self.updatedFileReference = reference
                            }
                            self.resource = validationResult.updatedResource
                            
                            /*if let reference = validationResult.updatedReference {
                             strongSelf.resourceReference = .reference(reference)
                             } else {
                             strongSelf.resourceReference = .empty
                             }*/
                            
                            self.state = .fetching(FetchingState(
                                fetchLocation: fetchLocation,
                                partSize: self.defaultPartSize,
                                minPartSize: 4 * 1024,
                                maxPartSize: self.defaultPartSize,
                                partAlignment: 4 * 1024,
                                partDivision: 1 * 1024 * 1024,
                                maxPendingParts: self.maxPendingParts,
                                decryptionState: nil
                            ))
                            
                            self.update()
                        }, error: { [weak self] _ in
                            guard let `self` = self else {
                                return
                            }
                            // SuperGram: report the error instead of stalling silently (DL-04)
                            self.failWithError(reason: "file reference revalidation failed")
                        })
                    }
                }
            case .failed:
                break
            }
        }
        
        private func fetchPart(state: FetchingState, part: PendingPart) {
            if part.disposable != nil {
                return
            }
            
            enum FilePartResult {
                case data(data: Data, verifyPartHashData: VerifyPartHashData?)
                case cdnRedirect(CdnData)
                case cdnRefresh(cdnData: CdnData, refreshToken: Data)
                case fileReferenceExpired
                case failure
            }
            
            let partRange = part.partRange
            let fetchRange = part.fetchRange
            let requestedLength = part.fetchRange.upperBound - part.fetchRange.lowerBound

            // SuperGram: request lane in MultiplexedRequestManager (DL-05): background parts yield to everything else,
            // parts of .elevated/.maximum ranges go first
            let requestPriority: Int
            switch part.budgetClass {
            case .background:
                requestPriority = -1
            case .interactive, .urgent:
                requestPriority = part.priorityIndex
            }

            var filePartRequest: Signal<FilePartResult, NoError>?
            switch state.fetchLocation {
            case let .cdn(cdnData):
                let requestedOffset = part.fetchRange.lowerBound
                // SuperGram: the map closure below is retained by the in-flight request; capturing `self` there kept
                // a cancelled Impl alive, so its next update() scheduled new CDN parts and the download never stopped
                let loggingIdentifier = self.loggingIdentifier

                filePartRequest = self.network.multiplexedRequestManager.request(
                    to: .cdn(cdnData.id),
                    consumerId: self.consumerId,
                    resourceId: self.resourceIdString,
                    data: Api.functions.upload.getCdnFile(
                        fileToken: Buffer(data: cdnData.fileToken),
                        offset: requestedOffset,
                        limit: Int32(requestedLength)
                    ),
                    tag: self.parameters?.tag,
                    continueInBackground: self.continueInBackground,
                    expectedResponseSize: Int32(requestedLength),
                    priority: requestPriority
                )
                |> map { result -> FilePartResult in
                    switch result {
                    case let .cdnFile(cdnFileData):
                        let bytes = cdnFileData.bytes
                        if bytes.size == 0 {
                            return .data(data: Data(), verifyPartHashData: nil)
                        } else {
                            var partIv = cdnData.encryptionIv
                            let partIvCount = partIv.count
                            // SuperGram: a malformed CDN response with an empty/short IV used to trap here
                            // (baseAddress!, `advanced(by: partIvCount - 4)` and the force-unwrapped
                            // MTAesCtrDecrypt result). Fail the part instead so the fetch retries.
                            guard partIvCount == 16, cdnData.encryptionKey.count == 32,
                                  requestedOffset >= 0, requestedOffset % 16 == 0,
                                  requestedOffset / 16 <= Int64(UInt32.max) else {
                                Logger.shared.log("FetchV2", "\(loggingIdentifier): invalid CDN cipher parameters")
                                return .failure
                            }
                            partIv.withUnsafeMutableBytes { rawBytes -> Void in
                                guard let bytes = rawBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                                    return
                                }
                                var ivOffset: UInt32 = UInt32(requestedOffset / 16).bigEndian
                                memcpy(bytes.advanced(by: partIvCount - 4), &ivOffset, 4)
                            }
                            
                            let fetchedData = bytes.makeData()
                            guard let decryptedData = MTAesCtrDecrypt(fetchedData, cdnData.encryptionKey, partIv) else {
                                Logger.shared.log("FetchV2", "\(loggingIdentifier): CDN part decryption failed")
                                return .failure
                            }
                            return .data(
                                data: decryptedData,
                                verifyPartHashData: VerifyPartHashData(fetchRange: fetchRange, fetchedData: fetchedData)
                            )
                        }
                    case let .cdnFileReuploadNeeded(cdnFileReuploadNeededData):
                        let requestToken = cdnFileReuploadNeededData.requestToken
                        return .cdnRefresh(cdnData: cdnData, refreshToken: requestToken.makeData())
                    }
                }
                |> `catch` { _ -> Signal<FilePartResult, NoError> in
                    return .single(.failure)
                }
            case let .datacenter(sourceDatacenterId):
                if let cloudResource = self.resource as? TelegramCloudMediaResource {
                    var fileReference: Data?
                    if let updatedFileReference = self.updatedFileReference {
                        fileReference = updatedFileReference
                    } else if let info = self.parameters?.info as? TelegramCloudMediaResourceFetchInfo {
                        fileReference = info.reference.apiFileReference
                    }
                    if let inputLocation = cloudResource.apiInputLocation(fileReference: fileReference) {
                        let queue = self.queue
                        filePartRequest = self.network.multiplexedRequestManager.request(
                            to: .main(sourceDatacenterId),
                            consumerId: self.consumerId,
                            resourceId: self.resourceIdString,
                            data: Api.functions.upload.getFile(
                                flags: 0,
                                location: inputLocation,
                                offset: part.fetchRange.lowerBound,
                                limit: Int32(requestedLength)),
                            tag: self.parameters?.tag,
                            continueInBackground: self.continueInBackground,
                            onFloodWaitError: { [weak self] error in
                                queue.async {
                                    guard let self else {
                                        return
                                    }
                                    self.processFloodWaitError(error: error)
                                }
                            }, expectedResponseSize: Int32(requestedLength),
                            priority: requestPriority
                        )
                        |> map { result -> FilePartResult in
                            switch result {
                            case let .file(fileData):
                                let bytes = fileData.bytes
                                return .data(data: bytes.makeData(), verifyPartHashData: nil)
                            case let .fileCdnRedirect(fileCdnRedirectData):
                                let (dcId, fileToken, encryptionKey, encryptionIv, fileHashes) = (fileCdnRedirectData.dcId, fileCdnRedirectData.fileToken, fileCdnRedirectData.encryptionKey, fileCdnRedirectData.encryptionIv, fileCdnRedirectData.fileHashes)
                                let _ = fileHashes
                                return .cdnRedirect(CdnData(
                                    id: Int(dcId),
                                    sourceDatacenterId: sourceDatacenterId,
                                    fileToken: fileToken.makeData(),
                                    encryptionKey: encryptionKey.makeData(),
                                    encryptionIv: encryptionIv.makeData()
                                ))
                            }
                        }
                        |> `catch` { error -> Signal<FilePartResult, NoError> in
                            if error.errorDescription.hasPrefix("FILEREF_INVALID") || error.errorDescription.hasPrefix("FILE_REFERENCE_")  {
                                return .single(.fileReferenceExpired)
                            } else {
                                return .single(.failure)
                            }
                        }
                    }
                }
            }
                
            if let filePartRequest {
                part.requestStartTimestamp = CFAbsoluteTimeGetCurrent()
                part.disposable = (filePartRequest
                |> deliverOn(self.queue)).startStrict(next: { [weak self, weak state, weak part] result in
                    guard let self, let state, let part, case let .fetching(fetchingState) = self.state, fetchingState === state,
                          let partIndex = state.pendingParts.firstIndex(where: { $0 === part }) else {
                        return
                    }

                    // SuperGram: only a response that actually advanced the fetch counts as progress. This used
                    // to be bumped here, before the response was classified, so a steady stream of *failing*
                    // responses read as "this fetch is making progress" and switched off the watchdog's
                    // in-flight-timeout branch for as long as it lasted — exactly the case where one dead request
                    // sits next to other traffic and would otherwise never be reaped. A state change
                    // (CDN redirect/refresh, file-reference revalidation) is genuine progress; `.failure` is not,
                    // and neither is a `.data` response the commit step rejects as malformed (see below).
                    switch result {
                    case .failure:
                        break
                    case .data, .cdnRedirect, .cdnRefresh, .fileReferenceExpired:
                        self.progressCounter += 1
                    }

                    state.pendingParts.remove(at: partIndex)

                    switch result {
                    case let .data(data, verifyPartHashData):
                        // Do not reset the failure count before validating the first part. Repeated empty
                        // responses used to reset it to zero, then fail commitPendingReadyPart and schedule
                        // attempt 1 again forever. Reject this before the encrypted/verified staging paths too.
                        let invalidEncryptedPart = state.decryptionState.map { decryptionState in
                            guard decryptionState.canDecrypt(data: data, offset: fetchRange.lowerBound) else { return true }
                            // A short ciphertext response cannot declare EOF before the authenticated
                            // plaintext size. The final padded block may extend beyond that size.
                            return Int64(data.count) < requestedLength && Int64(data.count) < decryptionState.decryptedSize - fetchRange.lowerBound
                        } ?? false
                        let invalidCdnEnd: Bool
                        if case .cdn = state.fetchLocation, let knownSize = self.knownSize, Int64(data.count) < requestedLength {
                            invalidCdnEnd = fetchRange.lowerBound + Int64(data.count) < knownSize
                        } else {
                            invalidCdnEnd = false
                        }
                        if (data.isEmpty && fetchRange.lowerBound == 0 && requestedLength > 0) || data.count > requestedLength || invalidEncryptedPart || invalidCdnEnd {
                            self.progressCounter -= 1
                            if !self.scheduleRetryAfterFailure() {
                                self.failWithError(reason: "part returned invalid data \(FetchImpl.maxConsecutiveFailures + 1) times")
                                return
                            }
                            self.update()
                            return
                        }
                        if verifyPartHashData == nil {
                            self.consecutiveFailures = 0
                            self.fileReferenceRefreshCount = 0
                        }

                        if let verifyPartHashData {
                            fetchV2VerboseLog("\(self.loggingIdentifier): stashing data part \(partRange) (aligned as \(fetchRange)) for hash verification")
                            
                            state.pendingReadyParts.append(FetchImpl.PendingReadyPart(
                                partRange: partRange,
                                fetchRange: fetchRange,
                                fetchedData: verifyPartHashData.fetchedData,
                                cleanData: data
                            ))
                        } else if state.decryptionState != nil {
                            fetchV2VerboseLog("\(self.loggingIdentifier): stashing data part \(partRange) (aligned as \(fetchRange)) for decryption")
                            
                            state.pendingReadyParts.append(FetchImpl.PendingReadyPart(
                                partRange: partRange,
                                fetchRange: fetchRange,
                                fetchedData: data,
                                cleanData: data
                            ))
                        } else {
                            if !self.commitPendingReadyPart(
                                state: state,
                                partRange: partRange,
                                fetchRange: fetchRange,
                                data: data
                            ) {
                                // The part was rejected as malformed (see commitPendingReadyPart). The range is
                                // still required and no longer pending, so the retry below re-schedules it.
                                // Nothing was stored, so this response was not progress after all — take the
                                // bump back, or a stream of rejected parts would keep the watchdog's in-flight
                                // reaper switched off.
                                self.progressCounter -= 1
                                if !self.scheduleRetryAfterFailure() {
                                    self.failWithError(reason: "part \(fetchRange) returned no data \(FetchImpl.maxConsecutiveFailures + 1) times")
                                    return
                                }
                            }
                        }
                    case let .cdnRedirect(cdnData):
                        self.state = .fetching(FetchImpl.FetchingState(
                            fetchLocation: .cdn(cdnData),
                            partSize: self.cdnPartSize,
                            minPartSize: self.cdnPartSize,
                            maxPartSize: self.cdnPartSize * 2,
                            partAlignment: self.cdnPartSize,
                            partDivision: 1 * 1024 * 1024,
                            maxPendingParts: self.maxPendingParts,
                            decryptionState: nil
                        ))
                    case let .cdnRefresh(cdnData, refreshToken):
                        self.state = .reuploadingToCdn(ReuploadingToCdnState(
                            cdnData: cdnData,
                            refreshToken: refreshToken
                        ))
                    case .fileReferenceExpired:
                        // SuperGram: bound repeated revalidations of the same fetch
                        self.fileReferenceRefreshCount += 1
                        if self.fileReferenceRefreshCount > FetchImpl.maxFileReferenceRefreshes {
                            self.failWithError(reason: "file reference expired after \(FetchImpl.maxFileReferenceRefreshes) revalidations")
                            return
                        }
                        self.state = .refreshingFileReference(RefreshingFileReferenceState(fetchLocation: fetchingState.fetchLocation))
                    case .failure:
                        // SuperGram: retry the part with backoff instead of stalling silently; the range stays required
                        // and not pending, so the next update() schedules it again. Give up with onError (DL-04).
                        if !self.scheduleRetryAfterFailure() {
                            self.failWithError(reason: "part \(fetchRange) failed \(FetchImpl.maxConsecutiveFailures + 1) times")
                            return
                        }
                    }

                    self.update()
                })
            } else {
                // SuperGram: no input location can be built for this resource; report instead of retrying forever
                self.failWithError(reason: "no input location")
            }
        }
        
        private func fetchHashRange(state: FetchingState, hashRange: PendingHashRange) {
            let fetchRequest: Signal<[Api.FileHash]?, NoError>
            
            switch state.fetchLocation {
            case let .cdn(cdnData):
                fetchV2VerboseLog("\(self.loggingIdentifier): will fetch hashes for \(hashRange.range)")

                // SuperGram: hashes gate delivery of already downloaded CDN parts; never put them in the background lane
                var hashRequestPriority = 0
                for range in self.requiredRanges {
                    if range.priority != .default {
                        hashRequestPriority = 1
                        break
                    }
                }

                fetchRequest = self.network.multiplexedRequestManager.request(
                    to: .main(cdnData.sourceDatacenterId),
                    consumerId: self.consumerId,
                    resourceId: self.resourceIdString,
                    data: Api.functions.upload.getCdnFileHashes(fileToken: Buffer(data: cdnData.fileToken), offset: hashRange.range.lowerBound),
                    tag: self.parameters?.tag,
                    continueInBackground: self.continueInBackground,
                    expectedResponseSize: nil,
                    priority: hashRequestPriority
                )
                |> map(Optional.init)
                |> `catch` { _ -> Signal<[Api.FileHash]?, NoError> in
                    return .single(nil)
                }
            case .datacenter:
                fetchRequest = .single(nil)
            }
            
            let queue = self.queue
            hashRange.disposable?.dispose()
            hashRange.requestStartTimestamp = CFAbsoluteTimeGetCurrent()
            hashRange.disposable = (fetchRequest
            |> deliverOn(self.queue)).startStrict(next: { [weak self, weak state, weak hashRange] result in
                queue.async {
                    guard let self, let state, let hashRange, case let .fetching(fetchingState) = self.state, fetchingState === state,
                          let hashIndex = state.pendingHashRanges.firstIndex(where: { $0 === hashRange }) else {
                        return
                    }

                    state.pendingHashRanges.remove(at: hashIndex)

                    if let hashRanges = self.validatedHashRanges(result, requiredOffset: hashRange.range.lowerBound) {
                        // SuperGram: only a hash response that actually delivered hashes is progress. Bumping the
                        // counter unconditionally (as this used to) meant a stream of empty/failed hash responses
                        // suppressed the watchdog's in-flight-timeout branch for the whole fetch.
                        self.progressCounter += 1

                        var filledRange = RangeSet<Int64>()
                        for hashRange in hashRanges {
                            filledRange.formUnion(RangeSet<Int64>(hashRange.range))
                            state.hashRanges[hashRange.range.lowerBound] = hashRange
                            state.completedHashRanges.formUnion(RangeSet<Int64>(hashRange.range))
                        }
                        fetchV2VerboseLog("\(self.loggingIdentifier): received hashes for \(filledRange)")
                    } else {
                        // SuperGram: an empty hash list covers nothing, so re-requesting the same offset right away
                        // is an infinite no-progress loop while the CDN parts waiting for verification keep
                        // pendingReadyParts full. Treat it like a failed request (retry with backoff, then error).
                        // SuperGram: a failed hash request was never retried, so CDN parts waiting for verification
                        // filled pendingReadyParts and the fetch stalled forever (DL-07). Drop it and retry with backoff.
                        //
                        // SuperGram: this used to be guarded by `case .cdn = fetchingState.fetchLocation`, so an
                        // empty response on any other fetch location left the PendingHashRange in
                        // pendingHashRanges forever: its disposable is non-nil, so update() never re-issues it,
                        // requiredHashRanges keeps subtracting its range, and the stashed parts waiting on it are
                        // never verified. Today only a .cdn state can own a hash range (the .datacenter branch of
                        // fetchHashRange returns .single(nil) and no hash range is ever created for it), so this
                        // is unreachable rather than broken — but the recovery must not depend on that, because
                        // the cost of being wrong is a permanently stalled download with no error.
                        if !self.scheduleRetryAfterFailure() {
                            self.failWithError(reason: "hash request failed \(FetchImpl.maxConsecutiveFailures + 1) times")
                            return
                        }
                    }

                    self.update()
                }
            })
        }

        private func validatedHashRanges(_ result: [Api.FileHash]?, requiredOffset: Int64) -> [HashRangeData]? {
            guard let result, !result.isEmpty else { return nil }
            var ranges: [HashRangeData] = []
            var coverage = RangeSet<Int64>()
            for item in result {
                switch item {
                case let .fileHash(data):
                    let (upperBound, overflow) = data.offset.addingReportingOverflow(Int64(data.limit))
                    guard data.offset >= 0, data.limit > 0, !overflow, data.hash.size == 32 else { return nil }
                    let range = data.offset ..< upperBound
                    guard coverage.intersection(RangeSet<Int64>(range)).isEmpty else { return nil }
                    ranges.append(HashRangeData(range: range, data: data.hash.makeData()))
                    coverage.formUnion(RangeSet<Int64>(range))
                }
            }
            // A nonempty list outside the requested gap is still no progress. Accepting it used
            // to reset failure counters and immediately request the same missing hashes forever.
            return coverage.contains(requiredOffset) ? ranges : nil
        }
        
        @discardableResult
        private func commitPendingReadyPart(state: FetchingState, partRange: Range<Int64>, fetchRange: Range<Int64>, data: Data) -> Bool {
            let requestedLength = fetchRange.upperBound - fetchRange.lowerBound
            let actualLength = Int64(data.count)

            // SuperGram: an empty response for the very first bytes of a resource would otherwise be taken at
            // face value — resourceSizeUpdated(0) makes MediaBox truncate the file map to zero, which matches
            // fileMap.sum, so the (empty) partial file is linked into place as the finished resource and cached
            // that way for good. The media then renders as a blank placeholder forever, with no spinner to hint
            // that anything went wrong and no retry, because as far as every layer is concerned it is complete.
            // Telegram never serves a zero-length file, so this is a transport failure: treat it as one.
            if actualLength == 0 && fetchRange.lowerBound == 0 && requestedLength > 0 {
                Logger.shared.log("FetchV2", "\(self.loggingIdentifier): empty response for the first \(requestedLength) bytes, treating as a failed part")
                return false
            }

            if actualLength < requestedLength {
                let resultingSize = fetchRange.lowerBound + actualLength
                if let currentKnownSize = self.knownSize {
                    Logger.shared.log("FetchV2", "\(self.loggingIdentifier): setting known size to min(\(currentKnownSize), \(resultingSize)) = \(min(currentKnownSize, resultingSize))")
                    self.knownSize = min(currentKnownSize, resultingSize)
                } else {
                    Logger.shared.log("FetchV2", "\(self.loggingIdentifier): setting known size to \(resultingSize)")
                    self.knownSize = resultingSize
                }
                Logger.shared.log("FetchV2", "\(self.loggingIdentifier): reporting resource size \(resultingSize)")
                self.onNext(.resourceSizeUpdated(resultingSize))
            }
            
            state.completedRanges.formUnion(RangeSet<Int64>(partRange))
            
            var actualData = data
            if partRange != fetchRange {
                precondition(partRange.lowerBound >= fetchRange.lowerBound)
                precondition(partRange.upperBound <= fetchRange.upperBound)
                let innerOffset = partRange.lowerBound - fetchRange.lowerBound
                var innerLength = partRange.upperBound - partRange.lowerBound
                innerLength = min(innerLength, Int64(actualData.count - Int(innerOffset)))
                if innerLength > 0 {
                    actualData = actualData.subdata(in: Int(innerOffset) ..< Int(innerOffset + innerLength))
                } else {
                    actualData = Data()
                }
                
                fetchV2VerboseLog("\(self.loggingIdentifier): extracting aligned part \(partRange) (\(fetchRange)): \(actualData.count)")
            }
            
            if !actualData.isEmpty {
                fetchV2VerboseLog("\(self.loggingIdentifier): emitting data part \(partRange) (aligned as \(fetchRange)): \(actualData.count)")
                
                self.onNext(.dataPart(
                    resourceOffset: partRange.lowerBound,
                    data: actualData,
                    range: 0 ..< Int64(actualData.count),
                    complete: false
                ))
            } else {
                fetchV2VerboseLog("\(self.loggingIdentifier): not emitting data part \(partRange) (aligned as \(fetchRange))")
            }

            return true
        }
        
        private func processFloodWaitError(error: String) {
            var networkSpeedLimitSubject: NetworkSpeedLimitedEvent.DownloadSubject?
            if let location = self.parameters?.location {
                if let messageId = location.messageId {
                    networkSpeedLimitSubject = .message(messageId)
                }
            }
            if let subject = networkSpeedLimitSubject {
                if error.hasPrefix("FLOOD_PREMIUM_WAIT") {
                    self.network.addNetworkSpeedLimitedEvent(event: .download(subject))
                }
            }
        }
    }
    
    private static let sharedQueue = Queue(name: "FetchImpl")
    
    private let queue: Queue
    private let impl: QueueLocalObject<Impl>
    
    
    
    init(
        accountPeerId: PeerId,
        postbox: Postbox,
        network: Network,
        mediaReferenceRevalidationContext: MediaReferenceRevalidationContext?,
        resource: TelegramMediaResource,
        datacenterId: Int,
        size: Int64?,
        intervals: Signal<[(Range<Int64>, MediaBoxFetchPriority)], NoError>,
        parameters: MediaResourceFetchParameters?,
        encryptionKey: SecretFileEncryptionKey?,
        decryptedSize: Int64?,
        continueInBackground: Bool,
        useMainConnection: Bool,
        onNext: @escaping (MediaResourceDataFetchResult) -> Void,
        onError: @escaping (MediaResourceDataFetchError) -> Void
    ) {
        let queue = FetchImpl.sharedQueue
        self.queue = queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return Impl(
                queue: queue,
                accountPeerId: accountPeerId,
                postbox: postbox,
                network: network,
                mediaReferenceRevalidationContext: mediaReferenceRevalidationContext,
                resource: resource,
                datacenterId: datacenterId,
                size: size,
                intervals: intervals,
                parameters: parameters,
                encryptionKey: encryptionKey,
                decryptedSize: decryptedSize,
                continueInBackground: continueInBackground,
                useMainConnection: useMainConnection,
                onNext: onNext,
                onError: onError
            )
        })
    }
}

func multipartFetchV2(
    accountPeerId: PeerId,
    postbox: Postbox,
    network: Network,
    mediaReferenceRevalidationContext: MediaReferenceRevalidationContext?,
    resource: TelegramMediaResource,
    datacenterId: Int,
    size: Int64?,
    intervals: Signal<[(Range<Int64>, MediaBoxFetchPriority)], NoError>,
    parameters: MediaResourceFetchParameters?,
    encryptionKey: SecretFileEncryptionKey?,
    decryptedSize: Int64?,
    continueInBackground: Bool,
    useMainConnection: Bool
) -> Signal<MediaResourceDataFetchResult, MediaResourceDataFetchError> {
    return Signal { subscriber in
        let impl = FetchImpl(
            accountPeerId: accountPeerId,
            postbox: postbox,
            network: network,
            mediaReferenceRevalidationContext: mediaReferenceRevalidationContext,
            resource: resource,
            datacenterId: datacenterId,
            size: size,
            intervals: intervals,
            parameters: parameters,
            encryptionKey: encryptionKey,
            decryptedSize: decryptedSize,
            continueInBackground: continueInBackground,
            useMainConnection: useMainConnection,
            onNext: subscriber.putNext,
            onError: subscriber.putError
        )
        
        return ActionDisposable {
            withExtendedLifetime(impl, {
            })
        }
    }
}
