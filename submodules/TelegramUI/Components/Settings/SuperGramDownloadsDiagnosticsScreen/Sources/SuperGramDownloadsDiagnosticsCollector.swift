// SuperGram (DOWNLOAD-DIAGNOSTICS): the sampler behind the diagnostics screen.
//
// It runs only while the screen is on screen (see `start()` / `stop()`, driven by the controller's
// didAppear/didDisappear) and takes one sample per second on its own queue.
//
// What it can see without any new fetch-layer API:
//   * `MediaBox.allFileContextResourceIds()` — every resource with a live MediaBox file context. This is the
//     set the stuck photos are in: a message showing a spinner has a context open for its resource.
//   * `MediaBox.fileSizeForId(_:)` — bytes on disk (partial or complete). Sampling it every second is what
//     gives "seconds since last progress" — the number that separates "slow" from "wedged".
//   * `MediaBox.resourceStatus(_:resourceSize:)` — exactly the status the message bubble renders its
//     progress/cancel affordance from. `Fetching(isActive:false)` with no byte growth is the signature of the
//     reported bug: the UI believes a download is running while nothing is in flight.
//   * `MediaDownloadPressure.shared.level` plus `ProcessInfo` thermal state / Low Power Mode.
//
// What needs the fetch layer (shown as "n/a" until a `SuperGramFetchDiagnosticsProvider` is registered):
// budget counters and waiters, per-fetch in-flight parts / lane / waiter flag, FetchManager category counts.
//
// Cost: one dataQueue hop plus two `stat()` per tracked resource per second, all off the main thread, capped
// at `maxTrackedResources`. Nothing is sampled while the screen is not visible.
import Foundation
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import FetchManagerImpl
import SGSimpleSettings

public final class SuperGramDownloadsDiagnosticsCollector {
    /// Resources tracked per tick. A chat that is scrolling fast can hold a lot of contexts; the list is
    /// sorted so that the interesting ones survive the cap, and the untruncated count is reported separately.
    private static let maxTrackedResources: Int = 64
    private static let refreshInterval: Double = 1.0

    private final class TrackedResource {
        let resourceId: MediaResourceId
        var receivedBytes: Int64
        var lastProgressTimestamp: Double
        let firstSeenTimestamp: Double
        var hasEverProgressed: Bool
        var status: MediaResourceStatus?
        var statusDisposable: Disposable?

        init(resourceId: MediaResourceId, receivedBytes: Int64, timestamp: Double) {
            self.resourceId = resourceId
            self.receivedBytes = receivedBytes
            self.lastProgressTimestamp = timestamp
            self.firstSeenTimestamp = timestamp
            self.hasEverProgressed = false
        }

        deinit {
            self.statusDisposable?.dispose()
        }
    }

    private let context: AccountContext
    private let queue = Queue(name: "SuperGramDownloadsDiagnostics")

    private let snapshotPromise: ValuePromise<SuperGramDownloadsDiagnosticsSnapshot>

    // Accessed only on self.queue
    private var tracked: [MediaResourceId: TrackedResource] = [:]
    /// Resources whose MediaBox status already reported `.Local`. Tracking one keeps a MediaBox file context
    /// alive (see `subscribeStatus`), so a finished resource is dropped from `tracked` and remembered here
    /// instead of being re-added on every following tick while MediaBox still reports the very context this
    /// screen is holding open. Entries are forgotten again once MediaBox stops reporting the resource.
    private var completedIds: Set<MediaResourceId> = []
    private var timer: SwiftSignalKit.Timer?
    private let idsDisposable = MetaDisposable()
    private var isRunning: Bool = false
    private var latestSnapshot: SuperGramDownloadsDiagnosticsSnapshot

    // Accessed only on the main queue
    private var fetchManagerDisposable: Disposable?
    private var foregroundDisposable: Disposable?
    private let fetchManagerEntryCount = Atomic<Int?>(value: nil)

    public var snapshot: Signal<SuperGramDownloadsDiagnosticsSnapshot, NoError> {
        return self.snapshotPromise.get()
    }

    public init(context: AccountContext) {
        self.context = context
        // The first frame is rendered (and can be copied as a report) before the first sample lands, so it is
        // built from the values that can be read synchronously rather than from placeholder constants.
        let initialSnapshot = SuperGramDownloadsDiagnosticsCollector.makeSnapshot(
            timestamp: CFAbsoluteTimeGetCurrent(),
            fetches: [],
            totalResourceContexts: 0,
            fetchManagerVisibleEntries: nil,
            provider: SuperGramFetchDiagnosticsRegistry.shared.provider
        )
        self.snapshotPromise = ValuePromise<SuperGramDownloadsDiagnosticsSnapshot>(initialSnapshot, ignoreRepeated: false)
        self.latestSnapshot = initialSnapshot
    }

    deinit {
        self.idsDisposable.dispose()
        self.fetchManagerDisposable?.dispose()
        self.foregroundDisposable?.dispose()
        self.timer?.invalidate()
    }

    // MARK: - Lifecycle

    /// Starts sampling. Main queue only (called from the controller's didAppear); safe to call repeatedly.
    public func start() {
        self.startFetchManagerObservation()
        self.resumeSampling()
        if self.foregroundDisposable == nil {
            // didDisappear does not fire when the app is backgrounded with this screen still on top, so without
            // this the 1 Hz timer would keep stat()ing every tracked resource — and keep every sampled MediaBox
            // file context alive — in the user's pocket. Sampling only ever resumes, never starts, from here:
            // `start()` above has already done the initial resume, so a binding that has not yet reported the
            // foreground state cannot leave the screen frozen.
            self.foregroundDisposable = (self.context.sharedContext.applicationBindings.applicationInForeground
            |> deliverOnMainQueue).start(next: { [weak self] inForeground in
                guard let self else {
                    return
                }
                if inForeground {
                    self.resumeSampling()
                } else {
                    self.suspendSampling()
                }
            })
        }
    }

    /// Stops sampling and releases every MediaBox status subscription. Main queue only; safe to call repeatedly.
    public func stop() {
        self.fetchManagerDisposable?.dispose()
        self.fetchManagerDisposable = nil
        self.foregroundDisposable?.dispose()
        self.foregroundDisposable = nil
        self.suspendSampling()
    }

    private func resumeSampling() {
        self.queue.async { [weak self] in
            guard let self, !self.isRunning else {
                return
            }
            self.isRunning = true
            self.sample()
            let timer = SwiftSignalKit.Timer(timeout: SuperGramDownloadsDiagnosticsCollector.refreshInterval, repeat: true, completion: { [weak self] in
                self?.sample()
            }, queue: self.queue)
            self.timer = timer
            timer.start()
        }
    }

    /// Stops the timer and drops every tracked resource, which releases the MediaBox file contexts this screen
    /// was holding open. The stall observation deliberately starts over on the next resume: bytes can very well
    /// have arrived while we were not looking (background downloads), and carrying the old timestamps across
    /// that gap would report a working download as stuck.
    private func suspendSampling() {
        self.queue.async { [weak self] in
            guard let self else {
                return
            }
            self.isRunning = false
            self.timer?.invalidate()
            self.timer = nil
            self.idsDisposable.set(nil)
            for (_, resource) in self.tracked {
                resource.statusDisposable?.dispose()
                resource.statusDisposable = nil
            }
            self.tracked.removeAll()
            self.completedIds.removeAll()
        }
    }

    /// Main queue only (called from the controller's didAppear).
    private func startFetchManagerObservation() {
        if self.fetchManagerDisposable != nil {
            return
        }
        guard let fetchManager = self.context.fetchManager as? FetchManagerImpl else {
            return
        }
        let counter = self.fetchManagerEntryCount
        self.fetchManagerDisposable = fetchManager.entriesSummary.start(next: { entries in
            let _ = counter.swap(entries.count)
        })
    }

    // MARK: - Sampling

    private func sample() {
        let mediaBox = self.context.account.postbox.mediaBox
        self.idsDisposable.set((mediaBox.allFileContextResourceIds()
        |> deliverOn(self.queue)).start(next: { [weak self] ids in
            self?.updateTracked(ids: ids)
        }))
    }

    private func updateTracked(ids: Set<MediaResourceId>) {
        guard self.isRunning else {
            return
        }
        let mediaBox = self.context.account.postbox.mediaBox
        let timestamp = CFAbsoluteTimeGetCurrent()

        for (id, resource) in self.tracked where !ids.contains(id) {
            resource.statusDisposable?.dispose()
            resource.statusDisposable = nil
            self.tracked.removeValue(forKey: id)
        }
        self.completedIds.formIntersection(ids)

        // A resource that finished is dropped: its status subscription is the only thing still holding its
        // MediaBox file context open, so keeping it would make `totalResourceContexts` grow for as long as the
        // screen is up and would fill `maxTrackedResources` with rows that can never move again — crowding out
        // exactly the stuck fetch the user opened this screen to find.
        for (id, resource) in self.tracked {
            if case .some(.Local) = resource.status {
                resource.statusDisposable?.dispose()
                resource.statusDisposable = nil
                self.tracked.removeValue(forKey: id)
                self.completedIds.insert(id)
            }
        }

        // Newly seen contexts are added in a stable order so that the cap below does not flap between ticks.
        let sortedIds = ids.sorted(by: { $0.stringRepresentation < $1.stringRepresentation })
        for id in sortedIds {
            if self.completedIds.contains(id) {
                continue
            }
            let receivedBytes = mediaBox.fileSizeForId(id)
            if let resource = self.tracked[id] {
                if receivedBytes != resource.receivedBytes {
                    resource.receivedBytes = receivedBytes
                    resource.lastProgressTimestamp = timestamp
                    resource.hasEverProgressed = true
                }
            } else {
                if self.tracked.count >= SuperGramDownloadsDiagnosticsCollector.maxTrackedResources {
                    continue
                }
                let resource = TrackedResource(resourceId: id, receivedBytes: receivedBytes, timestamp: timestamp)
                self.tracked[id] = resource
                self.subscribeStatus(resource)
            }
        }

        self.publish(totalResourceContexts: ids.count, timestamp: timestamp)
    }

    private func subscribeStatus(_ resource: TrackedResource) {
        // The id already has a live file context (it came out of allFileContextResourceIds), so this reuses it
        // instead of creating one. It does hold a reference for as long as the screen is open, which is the
        // same thing every visible message bubble does for its own media.
        let mediaBox = self.context.account.postbox.mediaBox
        let resourceId = resource.resourceId
        resource.statusDisposable = (mediaBox.resourceStatus(resourceId, resourceSize: nil)
        |> deliverOn(self.queue)).start(next: { [weak self, weak resource] status in
            guard let self, let resource, self.tracked[resourceId] === resource else {
                return
            }
            resource.status = status
        })
    }

    // MARK: - Snapshot assembly

    private func publish(totalResourceContexts: Int, timestamp: Double) {
        let provider = SuperGramFetchDiagnosticsRegistry.shared.provider
        let detail = provider?.fetchDetail() ?? [:]

        var fetches: [SuperGramDownloadFetchSnapshot] = []
        for (_, resource) in self.tracked {
            let status = resource.status
            var isFetching = false
            var isFetchingButInactive = false
            var progress: Float?
            if let status {
                switch status {
                case let .Fetching(isActive, value):
                    isFetching = true
                    isFetchingButInactive = !isActive
                    progress = value
                case let .Paused(value):
                    progress = value
                case let .Remote(value):
                    progress = value
                case .Local:
                    break
                }
            }

            let resourceDetail = detail[resource.resourceId.stringRepresentation]

            var totalSize = resourceDetail?.totalSize
            var isTotalSizeEstimated = false
            if totalSize == nil, let progress, progress > 0.01, resource.receivedBytes > 0 {
                totalSize = Int64(Double(resource.receivedBytes) / Double(progress))
                isTotalSizeEstimated = true
            }

            let observedForSeconds = timestamp - resource.firstSeenTimestamp
            var secondsSinceProgress = timestamp - resource.lastProgressTimestamp
            var isProgressObservationTruncated = !resource.hasEverProgressed
            if let providerSeconds = resourceDetail?.secondsSinceProgress {
                secondsSinceProgress = providerSeconds
                isProgressObservationTruncated = false
            }

            fetches.append(SuperGramDownloadFetchSnapshot(
                resourceId: resource.resourceId.stringRepresentation,
                totalSize: totalSize,
                isTotalSizeEstimated: isTotalSizeEstimated,
                receivedBytes: resource.receivedBytes,
                inFlightParts: resourceDetail?.inFlightParts,
                lane: resourceDetail?.lane,
                isBudgetWaiter: resourceDetail?.isBudgetWaiter,
                secondsSinceProgress: secondsSinceProgress,
                observedForSeconds: observedForSeconds,
                isProgressObservationTruncated: isProgressObservationTruncated,
                statusDescription: SuperGramDownloadsDiagnosticsCollector.describe(status: status),
                isFetching: isFetching,
                isFetchingButInactive: isFetchingButInactive
            ))
        }

        // Most interesting first: fetching before idle, then longest stalled, then largest.
        fetches.sort(by: { lhs, rhs in
            if lhs.isFetching != rhs.isFetching {
                return lhs.isFetching
            }
            if lhs.secondsSinceProgress != rhs.secondsSinceProgress {
                return lhs.secondsSinceProgress > rhs.secondsSinceProgress
            }
            return lhs.resourceId < rhs.resourceId
        })

        let snapshot = SuperGramDownloadsDiagnosticsCollector.makeSnapshot(
            timestamp: timestamp,
            fetches: fetches,
            totalResourceContexts: totalResourceContexts,
            fetchManagerVisibleEntries: self.fetchManagerEntryCount.with { $0 },
            provider: provider
        )

        self.latestSnapshot = snapshot
        self.snapshotPromise.set(snapshot)
    }

    /// Everything the screen shows, with the sampled parts passed in. Split out so that the first frame — which
    /// exists before any sample has been taken, and which "Copy report" would otherwise dump verbatim — reports
    /// the real pressure level and the real SuperGram download settings instead of placeholder constants.
    private static func makeSnapshot(
        timestamp: Double,
        fetches: [SuperGramDownloadFetchSnapshot],
        totalResourceContexts: Int,
        fetchManagerVisibleEntries: Int?,
        provider: SuperGramFetchDiagnosticsProvider?
    ) -> SuperGramDownloadsDiagnosticsSnapshot {
        let pressure = SuperGramDownloadsDiagnosticsCollector.readPressure()
        let speedMode = SGSimpleSettings.shared.sgDownloadSpeedMode

        return SuperGramDownloadsDiagnosticsSnapshot(
            timestamp: timestamp,
            pressureLevelValue: pressure.level.rawValue,
            pressureLevelName: SuperGramDownloadsDiagnosticsCollector.describe(level: pressure.level),
            thermalStateName: pressure.thermalStateName,
            isLowPowerModeEnabled: pressure.isLowPowerModeEnabled,
            isPauseUnderPressureEnabled: SGSimpleSettings.shared.sgPauseDownloadsUnderPressure,
            isMemoryPressureInferred: pressure.isMemoryPressureInferred,
            isPressureReasonExact: false,
            speedModeName: SuperGramDownloadsDiagnosticsCollector.describe(speedMode: speedMode),
            speedModeValue: speedMode,
            isDownloadLimiterEnabled: SGSimpleSettings.shared.sgDownloadLimiter,
            isBackgroundDownloadsEnabled: SGSimpleSettings.shared.sgBackgroundDownloads,
            budget: provider?.budgetSnapshot(),
            fetches: fetches,
            totalResourceContexts: totalResourceContexts,
            categories: provider?.categorySnapshot(),
            fetchManagerVisibleEntries: fetchManagerVisibleEntries,
            hasFetchLayerDetail: provider != nil
        )
    }

    // MARK: - Actions

    /// Resets every fetch that has made no observed progress for `superGramDownloadStallThreshold`.
    /// Uses the fetch layer's hard reset when one is registered, and otherwise goes through MediaBox's own
    /// `resetResourceFetchState`, which disposes the wedged fetch and fails the outstanding range requests so
    /// their owners retry — while keeping the bytes already on disk and the FetchManager entry. A resource
    /// whose MediaBox context had nothing in flight is wedged above MediaBox, and only there is the entry
    /// cancelled outright. Calls back on the main queue with the number of resources acted on.
    ///
    /// Deliberately not `cancelInteractiveFetches` + `cancelInteractiveResourceFetch` for every resource: the
    /// former already calls the latter, so doing both fails the range requests of *every* owner of the resource
    /// twice, and cancelling a healthy-but-slow download that was misread as stuck would throw its queue entry
    /// away for good.
    public func resetStalledFetches(completion: @escaping (Int) -> Void) {
        if let provider = SuperGramFetchDiagnosticsRegistry.shared.provider {
            provider.resetStalledFetches(minimumStallDuration: superGramDownloadStallThreshold, completion: completion)
            return
        }

        self.queue.async { [weak self] in
            guard let self else {
                Queue.mainQueue().async {
                    completion(0)
                }
                return
            }
            let stalled = self.latestSnapshot.stalledFetches.map { $0.resourceId }
            let context = self.context
            Queue.mainQueue().async {
                if stalled.isEmpty {
                    completion(0)
                    return
                }
                let mediaBox = context.account.postbox.mediaBox
                for resourceId in stalled {
                    mediaBox.resetResourceFetchState(MediaResourceId(resourceId), completion: { didReset in
                        // Runs on MediaBox's data queue; the FetchManager call must not.
                        if didReset {
                            return
                        }
                        Queue.mainQueue().async {
                            context.fetchManager.cancelInteractiveFetches(resourceId: resourceId)
                        }
                    })
                }
                // Reported straight away rather than after every reset has landed: MediaBox's data queue is one
                // of the places a download can be wedged, and a button that silently does nothing in exactly the
                // case it exists for is worse than one that reports what it asked for.
                completion(stalled.count)
            }
        }
    }

    // MARK: - Environment

    private static func readPressure() -> (level: MediaDownloadPressure.Level, thermalStateName: String, isLowPowerModeEnabled: Bool, isMemoryPressureInferred: Bool) {
        let level = MediaDownloadPressure.shared.level
        let processInfo = ProcessInfo.processInfo
        let thermalState = processInfo.thermalState
        let isLowPowerModeEnabled = processInfo.isLowPowerModeEnabled

        let thermalStateName: String
        // Highest level the *observable* inputs can account for on their own. MediaDownloadPressure keeps the
        // memory-pressure axis private, so anything above this must have come from a memory warning — that is
        // the only input left, and it is exactly the one the user cannot otherwise see.
        var explainable: MediaDownloadPressure.Level = .normal
        switch thermalState {
        case .critical:
            thermalStateName = "critical"
            explainable = .critical
        case .serious:
            thermalStateName = "serious"
            // `.serious` is `reduced` for the first 60 s and `constrained` after that, so both are explainable.
            explainable = .constrained
        case .fair:
            thermalStateName = "fair"
        case .nominal:
            thermalStateName = "nominal"
        @unknown default:
            thermalStateName = "unknown"
        }
        if isLowPowerModeEnabled && explainable < .reduced {
            explainable = .reduced
        }

        return (level, thermalStateName, isLowPowerModeEnabled, level > explainable)
    }

    private static func describe(level: MediaDownloadPressure.Level) -> String {
        switch level {
        case .normal:
            return "normal"
        case .reduced:
            return "reduced"
        case .constrained:
            return "constrained"
        case .critical:
            return "critical"
        }
    }

    private static func describe(speedMode: Int32) -> String {
        switch speedMode {
        case 0:
            return "standard"
        case 2:
            return "maximum"
        default:
            return "fast"
        }
    }

    private static func describe(status optionalStatus: MediaResourceStatus?) -> String {
        guard let status = optionalStatus else {
            return "unknown"
        }
        switch status {
        case .Local:
            return "Local"
        case let .Remote(progress):
            return String(format: "Remote %.0f%%", progress * 100.0)
        case let .Paused(progress):
            return String(format: "Paused %.0f%%", progress * 100.0)
        case let .Fetching(isActive, progress):
            return String(format: "Fetching%@ %.0f%%", isActive ? "" : "(idle)", progress * 100.0)
        }
    }
}
