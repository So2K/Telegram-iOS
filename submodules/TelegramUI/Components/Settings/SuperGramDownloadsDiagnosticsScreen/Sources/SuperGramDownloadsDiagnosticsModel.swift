// SuperGram (DOWNLOAD-DIAGNOSTICS): value model of one download-pipeline snapshot.
//
// Deliberately Foundation-only: the same structs are produced by the always-available MediaBox probe
// (SuperGramDownloadsDiagnosticsCollector) and by the not-yet-existing TelegramCore / FetchManagerImpl
// snapshot APIs consumed through SuperGramFetchDiagnosticsProvider. Nothing here may depend on which of
// the two filled it in, so that the screen renders the same rows either way and simply shows "n/a" for the
// parts that no source could supply.
import Foundation

/// Which FetchV2 budget lane a part was taken from. Mirrors `FetchImpl.BudgetClass`.
public enum SuperGramDownloadLane: String {
    /// Playhead parts of a video the user is watching; never limited by the global budget.
    case urgent
    /// The fetch has a user-initiated requester.
    case interactive
    /// Auto-downloads, prefetch, preloads.
    case background
}

/// Counters of the process-wide FetchV2 part budget. Only a TelegramCore snapshot API can produce this.
public struct SuperGramDownloadBudgetSnapshot: Equatable {
    public var interactiveParts: Int
    public var backgroundParts: Int
    public var interactiveLimit: Int
    public var backgroundLimit: Int
    public var interactiveBytes: Int64
    public var backgroundBytes: Int64
    public var maxInFlightBytes: Int64
    public var waiterCount: Int
    public var interactiveWaiterCount: Int
    /// How long the waiter that has been blocked longest has been waiting, in seconds.
    public var oldestWaiterAge: Double?
    /// Resource ids of the blocked waiters, longest-waiting first (may be truncated).
    public var waiterResourceIds: [String]

    public init(
        interactiveParts: Int,
        backgroundParts: Int,
        interactiveLimit: Int,
        backgroundLimit: Int,
        interactiveBytes: Int64,
        backgroundBytes: Int64,
        maxInFlightBytes: Int64,
        waiterCount: Int,
        interactiveWaiterCount: Int,
        oldestWaiterAge: Double?,
        waiterResourceIds: [String]
    ) {
        self.interactiveParts = interactiveParts
        self.backgroundParts = backgroundParts
        self.interactiveLimit = interactiveLimit
        self.backgroundLimit = backgroundLimit
        self.interactiveBytes = interactiveBytes
        self.backgroundBytes = backgroundBytes
        self.maxInFlightBytes = maxInFlightBytes
        self.waiterCount = waiterCount
        self.interactiveWaiterCount = interactiveWaiterCount
        self.oldestWaiterAge = oldestWaiterAge
        self.waiterResourceIds = waiterResourceIds
    }
}

/// One media resource that currently has a live MediaBox file context and/or a live FetchV2 fetch.
public struct SuperGramDownloadFetchSnapshot: Equatable {
    /// Full MediaBox resource id (`MediaResourceId.stringRepresentation`).
    public var resourceId: String
    /// Total size of the resource, when it is known. FetchV2 knows it; the MediaBox probe can only estimate it.
    public var totalSize: Int64?
    /// True when `totalSize` was estimated from received bytes / progress rather than read from the fetch.
    public var isTotalSizeEstimated: Bool
    /// Bytes on disk for this resource (partial file, or the complete file once it lands).
    public var receivedBytes: Int64
    /// Parts currently in flight for this fetch. Needs the FetchV2 snapshot API.
    public var inFlightParts: Int?
    /// Budget lane of this fetch. Needs the FetchV2 snapshot API.
    public var lane: SuperGramDownloadLane?
    /// Whether this fetch is currently parked in the budget's waiter list. Needs the FetchV2 snapshot API.
    public var isBudgetWaiter: Bool?
    /// Seconds since `receivedBytes` last grew, as observed by this screen (see `isProgressObservationTruncated`).
    public var secondsSinceProgress: Double
    /// Seconds since this screen first saw the resource.
    public var observedForSeconds: Double
    /// True while `secondsSinceProgress` is still equal to `observedForSeconds`, i.e. the resource has not
    /// moved once since the screen opened and the real stall may be much older.
    public var isProgressObservationTruncated: Bool
    /// `MediaResourceStatus` rendered for display ("Fetching(active, 12%)", "Remote", "Local", "Paused(3%)").
    public var statusDescription: String
    /// True when MediaBox reports `.Fetching`, i.e. the UI is showing a progress/cancel affordance.
    public var isFetching: Bool
    /// True when MediaBox reports `.Fetching(isActive: false, ...)`, i.e. nothing is actually in flight.
    public var isFetchingButInactive: Bool

    public init(
        resourceId: String,
        totalSize: Int64?,
        isTotalSizeEstimated: Bool,
        receivedBytes: Int64,
        inFlightParts: Int?,
        lane: SuperGramDownloadLane?,
        isBudgetWaiter: Bool?,
        secondsSinceProgress: Double,
        observedForSeconds: Double,
        isProgressObservationTruncated: Bool,
        statusDescription: String,
        isFetching: Bool,
        isFetchingButInactive: Bool
    ) {
        self.resourceId = resourceId
        self.totalSize = totalSize
        self.isTotalSizeEstimated = isTotalSizeEstimated
        self.receivedBytes = receivedBytes
        self.inFlightParts = inFlightParts
        self.lane = lane
        self.isBudgetWaiter = isBudgetWaiter
        self.secondsSinceProgress = secondsSinceProgress
        self.observedForSeconds = observedForSeconds
        self.isProgressObservationTruncated = isProgressObservationTruncated
        self.statusDescription = statusDescription
        self.isFetching = isFetching
        self.isFetchingButInactive = isFetchingButInactive
    }

    /// Short, screen-friendly form of the resource id.
    public var shortResourceId: String {
        if self.resourceId.count <= 22 {
            return self.resourceId
        }
        return String(self.resourceId.prefix(14)) + "…" + String(self.resourceId.suffix(6))
    }
}

/// Active / queued entries of one FetchManagerImpl category. Needs the FetchManagerImpl snapshot API.
public struct SuperGramDownloadCategorySnapshot: Equatable {
    public var name: String
    public var active: Int
    public var queued: Int
    public var limit: Int?

    public init(name: String, active: Int, queued: Int, limit: Int?) {
        self.name = name
        self.active = active
        self.queued = queued
        self.limit = limit
    }
}

/// Everything the diagnostics screen shows for one refresh tick.
public struct SuperGramDownloadsDiagnosticsSnapshot: Equatable {
    public var timestamp: Double

    // Pressure
    public var pressureLevelValue: Int32
    public var pressureLevelName: String
    public var thermalStateName: String
    public var isLowPowerModeEnabled: Bool
    public var isPauseUnderPressureEnabled: Bool
    /// True when the reported level is higher than thermal state + Low Power Mode alone can explain, i.e.
    /// the remaining contribution must be memory pressure. See `SuperGramDownloadsDiagnosticsCollector`.
    public var isMemoryPressureInferred: Bool
    /// False when TelegramCore does not expose which input raised the level and we had to infer it.
    public var isPressureReasonExact: Bool

    // Settings
    public var speedModeName: String
    public var speedModeValue: Int32
    public var isDownloadLimiterEnabled: Bool
    public var isBackgroundDownloadsEnabled: Bool

    // Fetch layer
    public var budget: SuperGramDownloadBudgetSnapshot?
    public var fetches: [SuperGramDownloadFetchSnapshot]
    /// Live MediaBox file contexts, including the ones not shown because the list is capped.
    public var totalResourceContexts: Int
    public var categories: [SuperGramDownloadCategorySnapshot]?
    /// User-initiated entries visible through `FetchManagerImpl.entriesSummary`, when that was readable.
    public var fetchManagerVisibleEntries: Int?

    /// True when a `SuperGramFetchDiagnosticsProvider` supplied budget / per-fetch / category detail.
    public var hasFetchLayerDetail: Bool

    public init(
        timestamp: Double,
        pressureLevelValue: Int32,
        pressureLevelName: String,
        thermalStateName: String,
        isLowPowerModeEnabled: Bool,
        isPauseUnderPressureEnabled: Bool,
        isMemoryPressureInferred: Bool,
        isPressureReasonExact: Bool,
        speedModeName: String,
        speedModeValue: Int32,
        isDownloadLimiterEnabled: Bool,
        isBackgroundDownloadsEnabled: Bool,
        budget: SuperGramDownloadBudgetSnapshot?,
        fetches: [SuperGramDownloadFetchSnapshot],
        totalResourceContexts: Int,
        categories: [SuperGramDownloadCategorySnapshot]?,
        fetchManagerVisibleEntries: Int?,
        hasFetchLayerDetail: Bool
    ) {
        self.timestamp = timestamp
        self.pressureLevelValue = pressureLevelValue
        self.pressureLevelName = pressureLevelName
        self.thermalStateName = thermalStateName
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.isPauseUnderPressureEnabled = isPauseUnderPressureEnabled
        self.isMemoryPressureInferred = isMemoryPressureInferred
        self.isPressureReasonExact = isPressureReasonExact
        self.speedModeName = speedModeName
        self.speedModeValue = speedModeValue
        self.isDownloadLimiterEnabled = isDownloadLimiterEnabled
        self.isBackgroundDownloadsEnabled = isBackgroundDownloadsEnabled
        self.budget = budget
        self.fetches = fetches
        self.totalResourceContexts = totalResourceContexts
        self.categories = categories
        self.fetchManagerVisibleEntries = fetchManagerVisibleEntries
        self.hasFetchLayerDetail = hasFetchLayerDetail
    }

    /// Fetches with no observed progress for at least `SuperGramDownloadsDiagnosticsCollector.stallThreshold`.
    public var stalledFetches: [SuperGramDownloadFetchSnapshot] {
        return self.fetches.filter { $0.isFetching && $0.secondsSinceProgress >= superGramDownloadStallThreshold }
    }

    public static func empty() -> SuperGramDownloadsDiagnosticsSnapshot {
        return SuperGramDownloadsDiagnosticsSnapshot(
            timestamp: CFAbsoluteTimeGetCurrent(),
            pressureLevelValue: 0,
            pressureLevelName: "normal",
            thermalStateName: "nominal",
            isLowPowerModeEnabled: false,
            isPauseUnderPressureEnabled: true,
            isMemoryPressureInferred: false,
            isPressureReasonExact: false,
            speedModeName: "fast",
            speedModeValue: 1,
            isDownloadLimiterEnabled: true,
            isBackgroundDownloadsEnabled: true,
            budget: nil,
            fetches: [],
            totalResourceContexts: 0,
            categories: nil,
            fetchManagerVisibleEntries: nil,
            hasFetchLayerDetail: false
        )
    }
}

/// A fetch with no progress for this long is treated as stuck by the reset button and highlighted in the list.
///
/// Progress is observed as growth of the resource's partial file, and MediaBox only writes a part once it has
/// arrived in full — so on a slow link a perfectly healthy large download stands still for as long as one part
/// takes. At the sizes the "fast"/"maximum" speed modes request, 30 s of stillness was well inside what a weak
/// mobile connection produces, which put a "STUCK" label (and the reset button's crosshairs) on downloads that
/// were working. A minute of not a single byte is the point where that stops being a plausible slow transfer.
/// Keep `SuperGram.Downloads.Diagnostics.Reset.Notice` (en + ru) in sync with this value.
public let superGramDownloadStallThreshold: Double = 60.0

// MARK: - Formatting

public func superGramDownloadsFormatBytes(_ value: Int64) -> String {
    if value < 1024 {
        return "\(value) B"
    } else if value < 1024 * 1024 {
        return String(format: "%.1f KB", Double(value) / 1024.0)
    } else if value < 1024 * 1024 * 1024 {
        return String(format: "%.2f MB", Double(value) / (1024.0 * 1024.0))
    } else {
        return String(format: "%.2f GB", Double(value) / (1024.0 * 1024.0 * 1024.0))
    }
}

public func superGramDownloadsFormatSeconds(_ value: Double) -> String {
    if value < 0.0 {
        return "0s"
    }
    if value < 60.0 {
        return String(format: "%.0fs", value)
    }
    let minutes = Int(value / 60.0)
    let seconds = Int(value) % 60
    return "\(minutes)m \(seconds)s"
}
