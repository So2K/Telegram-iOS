// SuperGram (DOWNLOAD-DIAGNOSTICS): seam between this screen and the fetch layer.
//
// The numbers that only FetchV2 / FetchManagerImpl know (budget counters, waiter ages, per-fetch in-flight
// parts and lane, per-category active/queued counts, hard reset) live behind types that neither this module
// nor TelegramCore owns today:
//
//   * `FetchImpl.Budget` is `fileprivate` inside a `private final class FetchImpl`
//     (submodules/TelegramCore/Sources/Network/FetchV2.swift),
//   * `FetchManagerCategoryContext.entries` / `.activeContexts` are internal
//     (submodules/FetchManagerImpl/Sources/FetchManagerImpl.swift),
//   * there is no cancel-and-restart ("hard reset") entry point at all.
//
// Those files are outside this agent's ownership, so this module declares what it needs as a protocol and
// renders "n/a" until something registers an implementation. See the cross-zone requests in
// output/ultra/impl/DOWNLOAD-DIAGNOSTICS.md for the exact API shapes requested from the fetch-layer agent;
// once they land, the only change needed is a ~40-line type in this module that conforms to
// `SuperGramFetchDiagnosticsProvider` by forwarding to them and registers itself below.
import Foundation

public protocol SuperGramFetchDiagnosticsProvider: AnyObject {
    /// Current FetchV2 global part budget, or nil when the fetch layer cannot report it.
    /// Called about once per second while the diagnostics screen is visible; must be cheap and non-blocking.
    func budgetSnapshot() -> SuperGramDownloadBudgetSnapshot?

    /// Per-fetch detail keyed by `MediaResourceId.stringRepresentation`. Merged into the rows that the
    /// MediaBox probe already produced, so a fetch missing here still shows its received bytes and stall time.
    func fetchDetail() -> [String: SuperGramDownloadFetchDetail]

    /// Active / queued entries per FetchManagerImpl category, or nil when not reportable.
    func categorySnapshot() -> [SuperGramDownloadCategorySnapshot]?

    /// Hard-reset every fetch that has made no progress for at least `minimumStallDuration` seconds:
    /// tear the fetch context down (including any poisoned MediaBox state) and restart it from the ranges
    /// that are still missing. `completion` is called on the main queue with the number of fetches reset.
    func resetStalledFetches(minimumStallDuration: Double, completion: @escaping (Int) -> Void)
}

/// The subset of `SuperGramDownloadFetchSnapshot` that only the fetch layer can fill in.
public struct SuperGramDownloadFetchDetail: Equatable {
    public var totalSize: Int64?
    public var inFlightParts: Int?
    public var lane: SuperGramDownloadLane?
    public var isBudgetWaiter: Bool?
    /// Seconds since the fetch last received bytes, as measured by the fetch layer itself. Unlike the value
    /// this screen observes, it is not truncated by when the screen was opened.
    public var secondsSinceProgress: Double?

    public init(totalSize: Int64? = nil, inFlightParts: Int? = nil, lane: SuperGramDownloadLane? = nil, isBudgetWaiter: Bool? = nil, secondsSinceProgress: Double? = nil) {
        self.totalSize = totalSize
        self.inFlightParts = inFlightParts
        self.lane = lane
        self.isBudgetWaiter = isBudgetWaiter
        self.secondsSinceProgress = secondsSinceProgress
    }
}

/// Process-wide registration point. Whoever can see both this module and the fetch layer (today: the adapter
/// in this module, once the TelegramCore APIs exist) installs the provider here.
public final class SuperGramFetchDiagnosticsRegistry {
    public static let shared = SuperGramFetchDiagnosticsRegistry()

    private let lock = NSLock()
    private var providerValue: SuperGramFetchDiagnosticsProvider?

    private init() {
    }

    public var provider: SuperGramFetchDiagnosticsProvider? {
        self.lock.lock()
        let value = self.providerValue
        self.lock.unlock()
        return value
    }

    public func register(provider: SuperGramFetchDiagnosticsProvider) {
        self.lock.lock()
        self.providerValue = provider
        self.lock.unlock()
    }
}
