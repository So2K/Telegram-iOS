import Foundation
import UIKit
import SwiftSignalKit
import TelegramUIPreferences

// SuperGram: shared state for inline chat media.
// - application activity, maintained on the main thread (nodes may be created off-main inside async layout,
//   so they must never read UIApplication themselves),
// - the "sgInlineAutoplayVideos" key (inline video/GIF autoplay in the chat feed, default on),
// - a global budget of simultaneously attached inline players.

private let superGramInlineAutoplayVideosKey = "sgInlineAutoplayVideos"
// SuperGram (GOAL-STREAMING): must be the same value as `SGSimpleSettings.superGramDefaultValues[sgInlineAutoplayVideos]`
// (true), which is what `SGSimpleSettings.registerDefaults()` registers in `UserDefaults.standard` and therefore what
// this reader actually sees once registration has run. It was `false` here, so during the window before registration
// (and in any process that never touches `SGSimpleSettings.shared`) inline video/GIF autoplay was silently off while
// the settings toggle showed it on.
private let superGramInlineAutoplayVideosDefault = true

final class SuperGramInlineMediaEnvironment {
    enum Event {
        case applicationActivityChanged
        case inlineAutoplayVideosChanged
        case energyUsageSettingsChanged(ObjectIdentifier)
    }

    static let shared = SuperGramInlineMediaEnvironment()

    // Main thread only
    private(set) var isApplicationActive: Bool = true
    private let listeners = Bag<(Event) -> Void>()

    // Any thread
    private let inlineAutoplayVideosValue: Atomic<Bool>
    var inlineAutoplayVideos: Bool {
        return self.inlineAutoplayVideosValue.with { $0 }
    }

    private var observers: [NSObjectProtocol] = []
    private var pendingEnergyUsageSettingsContexts = Set<ObjectIdentifier>()

    private init() {
        self.inlineAutoplayVideosValue = Atomic(value: SuperGramInlineMediaEnvironment.readInlineAutoplayVideos())

        let notificationCenter = NotificationCenter.default
        self.observers.append(notificationCenter.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateApplicationActive(false)
        }))
        self.observers.append(notificationCenter.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateApplicationActive(true)
        }))
        self.observers.append(notificationCenter.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateApplicationActive(true)
        }))
        self.observers.append(notificationCenter.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil, using: { [weak self] _ in
            self?.updateInlineAutoplayVideos()
        }))
        self.observers.append(notificationCenter.addObserver(forName: .superGramEnergyUsageSettingsDidChange, object: nil, queue: .main, using: { [weak self] notification in
            guard let self, let sharedContext = notification.object as AnyObject? else {
                return
            }
            self.scheduleEnergyUsageSettingsChanged(ObjectIdentifier(sharedContext))
        }))

        if Thread.isMainThread {
            self.isApplicationActive = UIApplication.shared.applicationState != .background
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.updateApplicationActive(UIApplication.shared.applicationState != .background)
            }
        }
    }

    private static func readInlineAutoplayVideos() -> Bool {
        return UserDefaults.standard.object(forKey: superGramInlineAutoplayVideosKey) as? Bool ?? superGramInlineAutoplayVideosDefault
    }

    func addListener(_ f: @escaping (Event) -> Void) -> Int {
        assert(Thread.isMainThread)
        return self.listeners.add(f)
    }

    func removeListener(_ index: Int) {
        assert(Thread.isMainThread)
        self.listeners.remove(index)
    }

    private func updateApplicationActive(_ value: Bool) {
        assert(Thread.isMainThread)
        if self.isApplicationActive != value {
            self.isApplicationActive = value
            for listener in self.listeners.copyItems() {
                listener(.applicationActivityChanged)
            }
        }
    }

    private func updateInlineAutoplayVideos() {
        let value = SuperGramInlineMediaEnvironment.readInlineAutoplayVideos()
        let previous = self.inlineAutoplayVideosValue.swap(value)
        if previous != value {
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                for listener in self.listeners.copyItems() {
                    listener(.inlineAutoplayVideosChanged)
                }
            }
        }
    }

    private func scheduleEnergyUsageSettingsChanged(_ sharedContextId: ObjectIdentifier) {
        assert(Thread.isMainThread)
        guard self.pendingEnergyUsageSettingsContexts.insert(sharedContextId).inserted else {
            return
        }
        // An inline update lays out its whole bubble synchronously. Finish the thermal callback first and
        // combine repeated updates to the same context into one refresh of the latest effective policy.
        Queue.mainQueue().justDispatch { [weak self] in
            guard let self else {
                return
            }
            self.pendingEnergyUsageSettingsContexts.remove(sharedContextId)
            for listener in self.listeners.copyItems() {
                listener(.energyUsageSettingsChanged(sharedContextId))
            }
        }
    }
}

// Main thread only. Visible inline media nodes ask for a slot; the ones closest to the middle of the screen
// keep their player attached, the rest show their thumbnail until a slot frees up.
final class SuperGramInlineVideoPlaybackBudget {
    enum Kind {
        case video
        case animation
    }

    static let shared = SuperGramInlineVideoPlaybackBudget()

    private final class Entry {
        weak var node: ChatMessageInteractiveMediaNode?
        var kind: Kind
        var isGranted: Bool = false

        init(node: ChatMessageInteractiveMediaNode, kind: Kind) {
            self.node = node
            self.kind = kind
        }
    }

    private static let minRecomputeInterval: Double = 0.25
    private static let grantedDistanceBonus: CGFloat = 80.0

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var pinnedId: ObjectIdentifier?
    private var isRecomputeScheduled: Bool = false
    private var lastRecomputeTimestamp: Double = 0.0
    private var thermalStateObserver: NSObjectProtocol?

    private init() {
        self.thermalStateObserver = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            // The slot limits can change even if the effective policy is equal (e.g. GIF autoplay is off).
            self?.scheduleRecompute(immediate: true)
        })
    }

    deinit {
        if let thermalStateObserver = self.thermalStateObserver {
            NotificationCenter.default.removeObserver(thermalStateObserver)
        }
    }

    private func maxActive(kind: Kind) -> Int {
        let isThermallyConstrained = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
        switch kind {
        case .video:
            return isThermallyConstrained ? 1 : 2
        case .animation:
            return isThermallyConstrained ? 2 : 3
        }
    }

    /// Returns whether the node may keep its inline player attached right now.
    func requestPlayback(node: ChatMessageInteractiveMediaNode, kind: Kind) -> Bool {
        assert(Thread.isMainThread)
        let id = ObjectIdentifier(node)
        if let entry = self.entries[id], entry.node === node {
            if entry.kind != kind {
                entry.kind = kind
                self.scheduleRecompute(immediate: true)
            } else if self.entryCount(kind: kind) > self.maxActive(kind: kind) {
                // Someone is waiting for a slot: re-rank while the list scrolls, throttled
                self.scheduleRecompute(immediate: false)
            }
            return entry.isGranted
        }

        self.pruneReleasedEntries()
        let entry = Entry(node: node, kind: kind)
        self.entries[id] = entry
        if self.grantedCount(kind: kind) < self.maxActive(kind: kind) {
            entry.isGranted = true
        } else {
            self.scheduleRecompute(immediate: true)
        }
        return entry.isGranted
    }

    func releasePlayback(node: ChatMessageInteractiveMediaNode) {
        assert(Thread.isMainThread)
        let id = ObjectIdentifier(node)
        guard let entry = self.entries[id], entry.node === node else {
            return
        }
        self.entries.removeValue(forKey: id)
        if self.pinnedId == id {
            self.pinnedId = nil
        }
        if entry.isGranted {
            self.scheduleRecompute(immediate: true)
        }
    }

    /// The user explicitly started this player (e.g. playback with sound): it wins over position until it leaves.
    func pinPlayback(node: ChatMessageInteractiveMediaNode) {
        assert(Thread.isMainThread)
        let id = ObjectIdentifier(node)
        guard let entry = self.entries[id], entry.node === node else {
            return
        }
        self.pinnedId = id
        if !entry.isGranted {
            self.recompute()
        }
    }

    func nodeDeallocated() {
        assert(Thread.isMainThread)
        let previousCount = self.entries.count
        self.pruneReleasedEntries()
        if self.entries.count != previousCount {
            self.scheduleRecompute(immediate: true)
        }
    }

    private func entryCount(kind: Kind) -> Int {
        var count = 0
        for (_, entry) in self.entries {
            if entry.kind == kind && entry.node != nil {
                count += 1
            }
        }
        return count
    }

    private func grantedCount(kind: Kind) -> Int {
        var count = 0
        for (_, entry) in self.entries {
            if entry.kind == kind && entry.isGranted && entry.node != nil {
                count += 1
            }
        }
        return count
    }

    private func pruneReleasedEntries() {
        var removeIds: [ObjectIdentifier] = []
        for (id, entry) in self.entries {
            if entry.node == nil {
                removeIds.append(id)
            }
        }
        for id in removeIds {
            self.entries.removeValue(forKey: id)
            if self.pinnedId == id {
                self.pinnedId = nil
            }
        }
    }

    private func scheduleRecompute(immediate: Bool) {
        if self.isRecomputeScheduled {
            return
        }
        self.isRecomputeScheduled = true

        var delay: Double = 0.0
        if !immediate {
            let elapsed = CACurrentMediaTime() - self.lastRecomputeTimestamp
            delay = max(0.0, SuperGramInlineVideoPlaybackBudget.minRecomputeInterval - elapsed)
        }
        let perform: () -> Void = { [weak self] in
            guard let self else {
                return
            }
            self.isRecomputeScheduled = false
            self.recompute()
        }
        if delay > 0.0 {
            Queue.mainQueue().after(delay, perform)
        } else {
            // Never re-rank synchronously: callers may be inside a video content manager update
            Queue.mainQueue().justDispatch(perform)
        }
    }

    private func recompute() {
        self.lastRecomputeTimestamp = CACurrentMediaTime()
        self.pruneReleasedEntries()

        var releaseNodes: [ChatMessageInteractiveMediaNode] = []
        var grantNodes: [ChatMessageInteractiveMediaNode] = []

        for kind in [Kind.video, Kind.animation] {
            let maxActive = self.maxActive(kind: kind)
            var candidates: [(entry: Entry, score: CGFloat)] = []
            for (id, entry) in self.entries {
                guard entry.kind == kind, let node = entry.node else {
                    continue
                }
                var score: CGFloat
                if id == self.pinnedId {
                    score = -CGFloat.greatestFiniteMagnitude
                } else if let distance = node.superGramInlinePlaybackDistanceToWindowCenter() {
                    score = distance
                    if entry.isGranted {
                        score -= SuperGramInlineVideoPlaybackBudget.grantedDistanceBonus
                    }
                } else {
                    // Not in a window (e.g. a chat covered by another screen)
                    score = entry.isGranted ? 1000000.0 : 2000000.0
                }
                candidates.append((entry: entry, score: score))
            }
            candidates.sort(by: { $0.score < $1.score })

            for i in 0 ..< candidates.count {
                let entry = candidates[i].entry
                let isGranted = i < maxActive
                if entry.isGranted != isGranted {
                    entry.isGranted = isGranted
                    if let node = entry.node {
                        if isGranted {
                            grantNodes.append(node)
                        } else {
                            releaseNodes.append(node)
                        }
                    }
                }
            }
        }

        // Release first so the number of live players never exceeds the budget
        for node in releaseNodes {
            node.superGramApplyInlineVideoPlaybackGrant(false)
        }
        for node in grantNodes {
            node.superGramApplyInlineVideoPlaybackGrant(true)
        }
    }
}
