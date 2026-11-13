import Foundation
import SwiftSignalKit

// SuperGram: download speed mode ("sgDownloadSpeedMode"). Faster modes use larger parts and more parallel
// requests for user-initiated downloads; background preloads keep the conservative policy.
enum MediaDownloadSpeedMode: Int32 {
    case standard = 0
    case fast = 1
    case maximum = 2
}

// SuperGram: runtime switches of the download pipeline. They are read from UserDefaults.standard
// without depending on SGSimpleSettings (key names and defaults are shared with the SuperGram settings
// screen) and cached, because they are consulted on hot paths (every FetchV2 scheduling pass).
final class MediaDownloadRuntimeSettings {
    static let downloadLimiterKey = "sgDownloadLimiter"
    static let pauseDownloadsUnderPressureKey = "sgPauseDownloadsUnderPressure"
    static let networkLoggingKey = "sgNetworkLogging"
    static let downloadSpeedModeKey = "sgDownloadSpeedMode"

    private static let shared = MediaDownloadRuntimeSettings()

    private let lock = NSLock()
    private var downloadLimiter: Bool
    private var pauseDownloadsUnderPressure: Bool
    private var networkLogging: Bool
    private var downloadSpeedMode: MediaDownloadSpeedMode
    private var changeHandlers: [() -> Void] = []
    private var observer: NSObjectProtocol?

    static var isDownloadLimiterEnabled: Bool {
        let shared = MediaDownloadRuntimeSettings.shared
        shared.lock.lock()
        let value = shared.downloadLimiter
        shared.lock.unlock()
        return value
    }

    static var isPauseDownloadsUnderPressureEnabled: Bool {
        let shared = MediaDownloadRuntimeSettings.shared
        shared.lock.lock()
        let value = shared.pauseDownloadsUnderPressure
        shared.lock.unlock()
        return value
    }

    static var speedMode: MediaDownloadSpeedMode {
        let shared = MediaDownloadRuntimeSettings.shared
        shared.lock.lock()
        let value = shared.downloadSpeedMode
        shared.lock.unlock()
        return value
    }

    static var isNetworkLoggingEnabled: Bool {
        let shared = MediaDownloadRuntimeSettings.shared
        shared.lock.lock()
        let value = shared.networkLogging
        shared.lock.unlock()
        return value
    }

    // The handler is invoked on the thread that changed UserDefaults, only when one of the cached values changed.
    static func addChangeHandler(_ f: @escaping () -> Void) {
        let shared = MediaDownloadRuntimeSettings.shared
        shared.lock.lock()
        shared.changeHandlers.append(f)
        shared.lock.unlock()
    }

    private init() {
        let values = MediaDownloadRuntimeSettings.readValues()
        self.downloadLimiter = values.downloadLimiter
        self.pauseDownloadsUnderPressure = values.pauseDownloadsUnderPressure
        self.networkLogging = values.networkLogging
        self.downloadSpeedMode = values.downloadSpeedMode

        self.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil, using: { [weak self] _ in
            self?.reload()
        })
    }

    deinit {
        if let observer = self.observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private static func readValues() -> (downloadLimiter: Bool, pauseDownloadsUnderPressure: Bool, networkLogging: Bool, downloadSpeedMode: MediaDownloadSpeedMode) {
        let defaults = UserDefaults.standard
        let speedModeValue = (defaults.object(forKey: MediaDownloadRuntimeSettings.downloadSpeedModeKey) as? NSNumber)?.int32Value ?? MediaDownloadSpeedMode.fast.rawValue
        return (
            defaults.object(forKey: MediaDownloadRuntimeSettings.downloadLimiterKey) as? Bool ?? true,
            defaults.object(forKey: MediaDownloadRuntimeSettings.pauseDownloadsUnderPressureKey) as? Bool ?? true,
            defaults.object(forKey: MediaDownloadRuntimeSettings.networkLoggingKey) as? Bool ?? false,
            MediaDownloadSpeedMode(rawValue: speedModeValue) ?? .fast
        )
    }

    private func reload() {
        let values = MediaDownloadRuntimeSettings.readValues()

        var handlers: [() -> Void] = []
        self.lock.lock()
        if self.downloadLimiter != values.downloadLimiter || self.pauseDownloadsUnderPressure != values.pauseDownloadsUnderPressure || self.networkLogging != values.networkLogging || self.downloadSpeedMode != values.downloadSpeedMode {
            self.downloadLimiter = values.downloadLimiter
            self.pauseDownloadsUnderPressure = values.pauseDownloadsUnderPressure
            self.networkLogging = values.networkLogging
            self.downloadSpeedMode = values.downloadSpeedMode
            handlers = self.changeHandlers
        }
        self.lock.unlock()

        for handler in handlers {
            handler()
        }
    }
}

// SuperGram: process-wide media download pressure level (memory pressure, thermal state, Low Power Mode).
// Consumers scale or pause background downloads and preloads with it. Foundation/Dispatch only.
// levelSignal delivers on an internal serial queue; use deliverOn(...) in consumers.
public final class MediaDownloadPressure {
    // SuperGram: the levels are an ordered scale of how much the download pipeline should hold back.
    //
    // `reduced` exists because the inputs are not equivalent. A memory warning is an emergency: the OS is about
    // to jetsam us and the right answer is to cut everything, and it decays after 30 s. Low Power Mode is the
    // opposite — it is a standing user preference that often stays on for days, and treating it as an emergency
    // meant that for those users *every* background download in the process permanently shared four parts
    // (one at `critical`), which is indistinguishable from "media never loads". A brief thermal `serious` is
    // likewise routine (charging in a warm room, ten minutes of video).
    //
    // So: `reduced` trims best-effort work — preloads, prefetch, preload lanes — and leaves the lanes that a
    // user is actually looking at essentially intact. `constrained`/`critical` stay strict and are reserved for
    // real memory pressure, thermal `critical`, and a thermal `serious` that has *persisted*.
    public enum Level: Int32, Comparable {
        case normal = 0
        case reduced = 1
        case constrained = 2
        case critical = 3

        public static func <(lhs: Level, rhs: Level) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    public static let shared = MediaDownloadPressure()

    private static let memoryPressureDecayTimeout: Double = 30.0
    // SuperGram: while the level is elevated it is re-evaluated periodically. Everything that raises it except
    // memory pressure (thermal state, Low Power Mode) is only observed through notifications, and a missed or
    // coalesced notification would leave downloads throttled for the rest of the session with no way back.
    private static let elevatedLevelRecheckInterval: Double = 30.0
    // SuperGram: how long thermal `.serious` has to persist before it is escalated from `reduced` to
    // `constrained`. A transient spike must not park the download pipeline.
    private static let thermalSeriousEscalationTimeout: Double = 60.0

    private let queue: DispatchQueue
    private let lock = NSLock()
    private var currentLevel: Level = .normal
    private let levelValue = ValuePromise<Level>(.normal, ignoreRepeated: true)

    // Accessed only on queue
    private var memoryPressureSource: DispatchSourceMemoryPressure?
    private var memoryLevel: Level = .normal
    private var memoryDecayWorkItem: DispatchWorkItem?
    private var isRecheckScheduled: Bool = false
    private var recheckTimer: DispatchSourceTimer?
    // SuperGram: when thermal state first became `.serious` (nil while it is not), see thermalSeriousEscalationTimeout
    private var thermalSeriousSince: Double?
    private var observers: [NSObjectProtocol] = []

    public var level: Level {
        self.lock.lock()
        let level = self.currentLevel
        self.lock.unlock()
        return level
    }

    public var levelSignal: Signal<Level, NoError> {
        return self.levelValue.get()
    }

    private init() {
        self.queue = DispatchQueue(label: "MediaDownloadPressure", qos: .utility)

        let initialLevel = self.computeLevel()
        self.currentLevel = initialLevel
        self.levelValue.set(initialLevel)

        let queue = self.queue

        let memoryPressureSource = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)
        memoryPressureSource.setEventHandler(handler: { [weak self] in
            guard let self, let source = self.memoryPressureSource else {
                return
            }
            self.handleMemoryPressureEvent(source.data)
        })
        self.memoryPressureSource = memoryPressureSource
        memoryPressureSource.resume()

        let center = NotificationCenter.default
        self.observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil, using: { [weak self] _ in
            queue.async {
                self?.updateLevel()
            }
        }))
        if #available(macOS 12.0, *) {
            self.observers.append(center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: nil, using: { [weak self] _ in
                queue.async {
                    self?.updateLevel()
                }
            }))
        }
        // SuperGram: nothing here may import UIKit (TelegramCore is shared with the macOS codebase), but the
        // level must never be able to stick across a background stretch where notifications were coalesced or
        // dropped. The raw notification name is Foundation-only and simply never fires on platforms that do not
        // post it; the periodic recheck below remains the guarantee, this is the fast path.
        self.observers.append(center.addObserver(forName: Notification.Name("UIApplicationDidBecomeActiveNotification"), object: nil, queue: nil, using: { [weak self] _ in
            queue.async {
                self?.updateLevel()
            }
        }))
        MediaDownloadRuntimeSettings.addChangeHandler({ [weak self] in
            queue.async {
                self?.updateLevel()
            }
        })

        queue.async { [weak self] in
            self?.scheduleRecheckIfNeeded()
        }
    }

    // SuperGram: re-evaluate the level now. Call this from the app layer on activation / whenever a stale level
    // would be user-visible; it is cheap and always safe.
    public func refresh() {
        self.queue.async { [weak self] in
            self?.updateLevel()
        }
    }

    deinit {
        self.memoryPressureSource?.cancel()
        self.memoryDecayWorkItem?.cancel()
        self.recheckTimer?.cancel()
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleMemoryPressureEvent(_ event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) {
            self.memoryLevel = .critical
        } else if event.contains(.warning) {
            if self.memoryLevel != .critical {
                self.memoryLevel = .constrained
            }
        } else {
            return
        }

        self.memoryDecayWorkItem?.cancel()
        let workItem = DispatchWorkItem(block: { [weak self] in
            guard let self else {
                return
            }
            self.memoryDecayWorkItem = nil
            self.memoryLevel = .normal
            self.updateLevel()
        })
        self.memoryDecayWorkItem = workItem
        self.queue.asyncAfter(deadline: DispatchTime.now() + MediaDownloadPressure.memoryPressureDecayTimeout, execute: workItem)

        self.updateLevel()
    }

    // Only on self.queue (mutates thermalSeriousSince), except for the single call from init.
    private func computeLevel() -> Level {
        if !MediaDownloadRuntimeSettings.isPauseDownloadsUnderPressureEnabled {
            self.thermalSeriousSince = nil
            return .normal
        }

        let timestamp = CFAbsoluteTimeGetCurrent()

        // Memory pressure is the strict axis: it means the OS is about to kill us. It decays after 30 s.
        var level = self.memoryLevel

        switch ProcessInfo.processInfo.thermalState {
        case .critical:
            self.thermalSeriousSince = nil
            level = max(level, .critical)
        case .serious:
            let since: Double
            if let thermalSeriousSince = self.thermalSeriousSince {
                since = thermalSeriousSince
            } else {
                since = timestamp
                self.thermalSeriousSince = timestamp
            }
            // A thermal spike is routine and transient; only a sustained one is worth parking downloads for.
            if timestamp - since >= MediaDownloadPressure.thermalSeriousEscalationTimeout {
                level = max(level, .constrained)
            } else {
                level = max(level, .reduced)
            }
        default:
            self.thermalSeriousSince = nil
        }

        if #available(macOS 12.0, *) {
            if ProcessInfo.processInfo.isLowPowerModeEnabled {
                // Low Power Mode is a standing user preference, not an emergency: trim best-effort work only.
                // It must never on its own reach a level that starves what the user is looking at.
                level = max(level, .reduced)
            }
        }

        return level
    }

    // Only on self.queue
    private func scheduleRecheckIfNeeded() {
        if self.isRecheckScheduled {
            return
        }
        self.lock.lock()
        let level = self.currentLevel
        self.lock.unlock()
        if level == .normal {
            return
        }
        self.isRecheckScheduled = true
        // SuperGram: Low Power Mode can hold the level at `reduced` indefinitely, so this timer can end up
        // running for the whole session. Generous leeway lets iOS coalesce it with other wake-ups instead of
        // waking the CPU on its own every 30 s.
        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        timer.schedule(deadline: DispatchTime.now() + MediaDownloadPressure.elevatedLevelRecheckInterval, leeway: .seconds(5))
        timer.setEventHandler(handler: { [weak self] in
            guard let self else {
                return
            }
            self.recheckTimer?.cancel()
            self.recheckTimer = nil
            self.isRecheckScheduled = false
            self.updateLevel()
        })
        self.recheckTimer?.cancel()
        self.recheckTimer = timer
        timer.resume()
    }

    private func updateLevel() {
        let level = self.computeLevel()

        self.lock.lock()
        let previousLevel = self.currentLevel
        self.currentLevel = level
        self.lock.unlock()

        if previousLevel != level {
            Logger.shared.log("MediaDownloadPressure", "level \(previousLevel) -> \(level)")
            self.levelValue.set(level)
        }

        self.scheduleRecheckIfNeeded()
    }
}

// SuperGram: whether user-visible downloads (user-initiated files, playback, on-screen media) are in progress.
// Driven by the FetchV2 part budget; goes false only after a quiet period, so short gaps between parts or
// between queued files don't flap. Used to keep the app awake in background while downloads are running.
public final class MediaDownloadActivity {
    public static let shared = MediaDownloadActivity()

    private static let idleTimeout: Double = 15.0

    private let queue = Queue(name: "MediaDownloadActivity")
    private let value = ValuePromise<Bool>(false, ignoreRepeated: true)
    // Accessed only on queue
    private var activeParts: Int = 0
    private var idleTimer: SwiftSignalKit.Timer?

    public var hasActiveDownloads: Signal<Bool, NoError> {
        return self.value.get()
    }

    private init() {
    }

    func update(activeParts: Int) {
        self.queue.async {
            self.activeParts = activeParts
            if activeParts > 0 {
                self.idleTimer?.invalidate()
                self.idleTimer = nil
                self.value.set(true)
            } else if self.idleTimer == nil {
                let timer = SwiftSignalKit.Timer(timeout: MediaDownloadActivity.idleTimeout, repeat: false, completion: { [weak self] in
                    guard let self else {
                        return
                    }
                    self.idleTimer = nil
                    if self.activeParts == 0 {
                        self.value.set(false)
                    }
                }, queue: self.queue)
                self.idleTimer = timer
                timer.start()
            }
        }
    }
}
