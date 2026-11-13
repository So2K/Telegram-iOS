#!/usr/bin/env python3
"""Execute actual wakeup policy/state machine with controllable OS/audio/queue doubles.

Includes real Postbox transaction-gate callback and Network worker-keep expression.
No notifications are delivered, no audio plays, and no device/account is accessed.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
source = (ROOT / "submodules/TelegramUI/Sources/SharedWakeupManager.swift").read_text()
postbox_source = (ROOT / "submodules/Postbox/Sources/Postbox.swift").read_text()
network_source = (ROOT / "submodules/TelegramCore/Sources/Network/Network.swift").read_text()


def block(text, marker):
    start = text.index(marker)
    opening = text.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end] + "\n"


swift = r'''
import Foundation
import CoreFoundation
var clockNow = 0.0
struct Queue {
    final class Storage { var pending: [() -> Void] = []; var blocked = false }
    let storage: Storage
    static let main = Queue(storage: Storage())
    static let concurrent = Queue(storage: Storage())
    static func mainQueue() -> Queue { main }; static func concurrentDefaultQueue() -> Queue { concurrent }
    func isCurrent() -> Bool { true }
    func async(_ f: @escaping () -> Void) { storage.pending.append(f) }
    func flush() { while !storage.blocked && !storage.pending.isEmpty { storage.pending.removeFirst()() } }
}
enum SwiftSignalKit { final class Timer {
    let timeout: Double; let completion: () -> Void; let deadline: Double
    var started = false; var invalidated = false
    init(timeout: Double, repeat: Bool, completion: @escaping () -> Void, queue: Queue) { self.timeout = timeout; self.completion = completion; deadline = clockNow + timeout }
    func start() { started = true }; func invalidate() { invalidated = true }
    func fire() { guard started && !invalidated else { return }; invalidated = true; completion() }
} }
final class ProcessInfo {
    enum ThermalState { case nominal, fair, serious, critical }
    static let processInfo = ProcessInfo()
    static let thermalStateDidChangeNotification = Notification.Name("thermal")
    var thermalState = ThermalState.nominal; var isLowPowerModeEnabled = false
}
final class UIDevice {
    enum BatteryState { case unknown, unplugged, charging, full }
    static let current = UIDevice(); static let batteryStateDidChangeNotification = Notification.Name("battery")
    var batteryState = BatteryState.unplugged
}
final class UserDefaults {
    static let standard = UserDefaults(); var values: [String: Any] = [:]
    static let didChangeNotification = Notification.Name("defaults")
    func object(forKey: String) -> Any? { values[forKey] }
}
final class NotificationCenter {
    static let `default` = NotificationCenter()
    var observers: [(NSObject, Notification.Name, (Notification) -> Void)] = []
    func addObserver(forName: Notification.Name?, object: Any?, queue: OperationQueue?, using: @escaping (Notification) -> Void) -> NSObjectProtocol { precondition(queue === OperationQueue.main); let token = NSObject(); observers.append((token, forName!, using)); return token }
    func removeObserver(_ token: Any) { guard let token = token as? NSObject else { return }; observers.removeAll { $0.0 === token } }
    func post(_ name: Notification.Name) { for (_, expected, f) in observers where expected == name { Queue.mainQueue().async { f(Notification(name: name)) } }; Queue.mainQueue().flush() }
}
struct Signal<T> { let value: T; static func single(_ value: T) -> Self { Self(value: value) } }
final class Promise<T> { var value: T; init(_ value: T) { self.value = value }; func set(_ signal: Signal<T>) { value = signal.value } }
final class Atomic<T> {
    var value: T; init(value: T) { self.value = value }
    func swap(_ value: T) -> T { let old = self.value; self.value = value; return old }
    func with<R>(_ f: (T) -> R) -> R { f(value) }
}
protocol Disposable { func dispose() }
final class ActionDisposable: Disposable { let f: () -> Void; init(_ f: @escaping () -> Void) { self.f = f }; func dispose() { f() } }
struct AccountRecordId: Hashable { let int64: Int64 }
struct AccountRunningImportantTasks: OptionSet {
    let rawValue: Int; static let message = Self(rawValue: 1); static let story = Self(rawValue: 2)
    var pendingMessageCount: Int { rawValue & 1 }; var pendingStoryCount: Int { (rawValue & 2) >> 1 }
}
final class Postbox {
    let queue = Queue(storage: Queue.Storage()); let canBeginTransactionsValue = Atomic(value: true); let queuedInternalTransactions = Atomic<[() -> Void]>(value: [])
'''
swift += block(postbox_source, "public func setCanBeginTransactions(_ value: Bool, afterTransactionIfRunning:")
swift += r'''
    func setCanBeginTransactions(_ value: Bool) { setCanBeginTransactions(value, afterTransactionIfRunning: {}) }
}
enum ServiceTaskMaster { case always, never }
final class Account {
    let id: AccountRecordId; let postbox = Postbox()
    let shouldBeServiceTaskMaster = Promise(ServiceTaskMaster.never)
    let shouldExplicitelyKeepWorkerConnections = Promise(false); let shouldKeepBackgroundDownloadConnections = Promise(false); let shouldKeepOnlinePresence = Promise(false)
    init(_ id: Int64) { self.id = AccountRecordId(int64: id) }
    func workerKeep(continueInBackground: Bool) -> Bool {
        let shouldKeepConnection = shouldBeServiceTaskMaster.value == .always
        let shouldExplicitelyKeepWorkerConnections = self.shouldExplicitelyKeepWorkerConnections.value
        let shouldKeepBackgroundDownloadConnections = self.shouldKeepBackgroundDownloadConnections.value
'''
swift += next(line.strip() for line in network_source.splitlines() if "return shouldKeepConnection || shouldExplicitelyKeepWorkerConnections ||" in line) + "\n}\n}\n"
swift += r'''
typealias UIBackgroundTaskIdentifier = Int
final class Logger { static let shared = Logger(); func log(_ tag: String, _ text: String) {} }
final class AVAudioSession {
    enum Category { case playback }; enum Mode { case `default` }; enum Option { case mixWithOthers, notifyOthersOnDeactivation }
    static let shared = AVAudioSession(); static func sharedInstance() -> AVAudioSession { shared }
    var deactivations = 0
    func setCategory(_ category: Category, mode: Mode, options: [Option]) throws {}
    func setActive(_ value: Bool, options: [Option] = []) throws { if !value { deactivations += 1 } }
}
final class AudioControl { func activate() {} }
enum RendererSession { case custom((AudioControl) -> Disposable) }
func ValuePipe() -> Int { 0 }
final class MediaPlayerAudioRenderer {
    static var starts = 0; static var stops = 0; let factory: (AudioControl) -> Disposable; var disposal: Disposable?
    init(audioSession: RendererSession, forAudioVideoMessage: Bool, playAndRecord: Bool, useVoiceProcessingMode: Bool, soundMuted: Bool, ambient: Bool, mixWithOthers: Bool, forceAudioToSpeaker: Bool, baseRate: Double, audioLevelPipe: Int, updatedRate: @escaping () -> Void, audioPaused: @escaping () -> Void) { switch audioSession { case let .custom(f): factory = f } }
    func start() { Self.starts += 1; disposal = factory(AudioControl()) }
    func stop() { Self.stops += 1; disposal?.dispose(); disposal = nil }
}
let telegramLocalNotificationFallbackEnabled = true
'''
swift += block(source, "private func superGramBackgroundDownloadsEnabled(")
swift += block(source, "private struct AccountTasks").replace("private struct", "struct", 1)
swift += r'''
final class Harness {
    var inForeground = false; var hasActiveAudioSession = false; var silenceAudioInterrupted = false
    var accountsAndTasks: [(Account, Bool, AccountTasks)] = []
    var currentTask: (Int, Double, SwiftSignalKit.Timer)?; var isInBackgroundExtension = false; var backgroundExtensionBudgetExhausted = false
    var currentExternalCompletion: (() -> Void, SwiftSignalKit.Timer)?; var currentExternalCompletionValidationTimer: SwiftSignalKit.Timer?
    var activeExplicitExtensionTimer: SwiftSignalKit.Timer?; var allowBackgroundTimeExtensionDeadline: Double?; var allowBackgroundTimeExtensionDeadlineTimer: SwiftSignalKit.Timer?
    var keepIdleDisposable: Disposable?; func acquireIdleExtension() -> Disposable? { nil }
    var backgroundProcessingTaskId: String?; var backgroundStoryProcessingTaskId: String?
    var silenceAudioRenderer: MediaPlayerAudioRenderer?; var silenceAudioInterruptionTask: (Int, SwiftSignalKit.Timer)?
    var keepAliveLastActivityTimestamp = clockNow; var keepAliveIdleTimer: SwiftSignalKit.Timer?; var keepAliveIdleTimerDeadline: Double?
    var primaryAccountHasNetwork = true; var primaryAccountNoNetworkSince: Double?
    var isKeepAliveSuspendedForIdle = false; var isKeepAliveSuspendedForNetwork = false; var isKeepAliveSuspendedForThermal = false
    var backgroundStateObservers: [NSObjectProtocol] = []; var begun = 0; var ended: [Int] = []; var denied = false; var checks = 0; let episodeId = 1
    func beginBackgroundTask(_ name: String, _ expiration: @escaping () -> Void) -> Int? { guard !denied else { return nil }; begun += 1; return begun }
    func endBackgroundTask(_ id: Int) { ended.append(id) }; func backgroundTimeRemaining() -> Double { 40 }
    func markSilenceAudioUnavailable(reason: String) { silenceAudioInterrupted = true }
'''
for constant in ["keepAliveIdleTimeout", "keepAliveLowPowerIdleTimeout", "keepAliveNoNetworkGracePeriod"]:
    swift += next(line.strip() for line in source.splitlines() if f"private static let {constant}:" in line) + "\n"
for marker in ["private var superGramBackgroundKeepAliveEnabled:", "private func updateKeepAliveDutyCycle(", "private func armKeepAliveIdleTimer(", "private func beginBackgroundExtensionTaskIfNeeded(", "private func beginSilenceAudioReleaseTask(", "private func endSilenceAudioInterruptionTask(", "fileprivate func noteBackgroundNotificationActivity(", "func checkTasks()", "private func updateAccounts("]:
    extracted = block(source, marker).replace("CFAbsoluteTimeGetCurrent()", "clockNow")
    extracted = extracted.replace("SharedWakeupManager.", "Harness.")
    if marker == "func checkTasks()":
        extracted = extracted.replace("func checkTasks() {", "func checkTasks() { checks += 1", 1)
    swift += extracted
observer_start = source.index("_ = ProcessInfo.processInfo.thermalState")
observer_end = source.index("sharedWakeupManagerInstance = self", observer_start)
swift += "func observe() {\n" + source[observer_start:observer_end] + "}\n"
swift += "deinit {\n" + block(source, "for observer in self.backgroundStateObservers {") + "keepAliveIdleTimer?.invalidate()\n}\n"
swift += r'''
}
var assertions = 0
func check(_ value: @autoclosure () -> Bool, _ text: String) { assertions += 1; precondition(value(), text) }
func tasks(downloads: Bool = false, audio: Bool = false, call: Bool = false) -> AccountTasks { AccountTasks(stateSynchronization: false, importantTasks: [], backgroundLocation: false, backgroundDownloads: downloads, backgroundAudio: audio, activeCalls: call, watchTasks: false, userInterfaceInUse: false) }
func flush(_ accounts: [Account]) { for account in accounts { account.postbox.queue.flush() }; Queue.mainQueue().flush(); Queue.concurrentDefaultQueue().flush() }
func fixture() -> (Harness, Account) { let h = Harness(); let account = Account(1); h.accountsAndTasks = [(account, true, tasks())]; return (h, account) }
UserDefaults.standard.values = ["sgBackgroundKeepAlive": true, "sgBackgroundDownloads": true]
for charging in [UIDevice.BatteryState.charging, .full, .unplugged, .unknown] {
    clockNow = 0; ProcessInfo.processInfo.thermalState = .nominal; UIDevice.current.batteryState = charging
    let (h, account) = fixture(); h.checkTasks(); check(h.silenceAudioRenderer != nil, "starts eligible speculative notification keepalive")
    let originalTimer = h.keepAliveIdleTimer
    for time in stride(from: 60.0, to: 7200.0, by: 60.0) { clockNow = time; h.checkTasks() }
    check(h.keepAliveLastActivityTimestamp == 0 && h.keepAliveIdleTimer === originalTimer, "charger/check events never reset real idle anchor or churn timer")
    clockNow = 7200; h.keepAliveIdleTimer?.fire(); flush([account])
    check(h.silenceAudioRenderer == nil && h.isKeepAliveSuspendedForIdle && h.keepAliveIdleTimer == nil, "idle expires while charging too, no repeating timer")
    check(h.silenceAudioInterruptionTask?.1.timeout == 5.0, "existing bounded transaction release task retained")
}
clockNow = 0; ProcessInfo.processInfo.thermalState = .fair
let (warm, warmAccount) = fixture(); warm.observe(); warm.checkTasks(); flush([warmAccount])
check(warm.keepAliveIdleTimerDeadline == 7200, "fair thermal preserves nominal idle window")
clockNow = 100; ProcessInfo.processInfo.thermalState = .serious; NotificationCenter.default.post(ProcessInfo.thermalStateDidChangeNotification)
check(warm.keepAliveIdleTimerDeadline == 1200 && warm.keepAliveLastActivityTimestamp == 0, "serious event caps idle without counting as activity")
clockNow = 1199; warm.checkTasks(); check(warm.silenceAudioRenderer != nil, "serious retains recent notification path")
clockNow = 1200; warm.keepAliveIdleTimer?.fire(); flush([warmAccount]); check(warm.silenceAudioRenderer == nil, "serious idle expires at existing LowPower window")
ProcessInfo.processInfo.thermalState = .critical; NotificationCenter.default.post(ProcessInfo.thermalStateDidChangeNotification)
let criticalChecks = warm.checks; for _ in 0..<1000 { warm.checkTasks() }
check(warm.keepAliveIdleTimer == nil && warm.silenceAudioRenderer == nil && warm.checks == criticalChecks + 1000, "critical cannot create a timer or renderer loop")
ProcessInfo.processInfo.thermalState = .nominal; NotificationCenter.default.post(ProcessInfo.thermalStateDidChangeNotification); flush([warmAccount])
check(warm.silenceAudioRenderer != nil && warm.keepAliveLastActivityTimestamp == 0, "cooling event resumes eligible original idle budget")
clockNow = 8000; ProcessInfo.processInfo.thermalState = .critical; NotificationCenter.default.post(ProcessInfo.thermalStateDidChangeNotification)
ProcessInfo.processInfo.thermalState = .nominal; NotificationCenter.default.post(ProcessInfo.thermalStateDidChangeNotification); flush([warmAccount])
check(warm.silenceAudioRenderer == nil && warm.keepAliveIdleTimer == nil, "cooling cannot manufacture new activity after idle budget expired")
clockNow = 0; ProcessInfo.processInfo.thermalState = .critical
let (coldStart, coldAccount) = fixture(); coldStart.observe(); coldStart.checkTasks(); flush([coldAccount])
check(coldStart.silenceAudioRenderer == nil && coldStart.keepAliveIdleTimer == nil, "initial critical prevents speculative activation")
coldStart.accountsAndTasks = [(coldAccount, true, tasks(downloads: true))]; coldStart.checkTasks(); flush([coldAccount])
check(coldStart.silenceAudioRenderer != nil && coldAccount.shouldKeepBackgroundDownloadConnections.value && coldAccount.workerKeep(continueInBackground: false), "critical preserves real user download path and worker pins")
coldAccount.postbox.queue.storage.blocked = true
coldStart.accountsAndTasks = [(coldAccount, true, tasks())]; coldStart.checkTasks()
check(coldStart.silenceAudioRenderer == nil && !coldAccount.shouldExplicitelyKeepWorkerConnections.value && !coldAccount.workerKeep(continueInBackground: false), "last download releases stale explicit worker pin through actual idle branch")
check(coldStart.silenceAudioInterruptionTask != nil && coldAccount.postbox.canBeginTransactionsValue.value, "release assertion covers transaction queue still draining")
coldAccount.postbox.queue.storage.blocked = false; flush([coldAccount])
check(!coldAccount.postbox.canBeginTransactionsValue.value, "real Postbox callback disables new transactions after running queue drains")
coldStart.silenceAudioInterruptionTask?.1.fire(); check(coldStart.ended == [1], "release assertion expires once within original five seconds")
for _ in 0..<1000 { coldStart.checkTasks() }; check(coldStart.begun == 1, "critical idle does not reacquire exhausted release assertions")
coldStart.hasActiveAudioSession = true; coldStart.accountsAndTasks = [(coldAccount, true, tasks(audio: true, call: true))]; coldStart.checkTasks(); flush([coldAccount])
check(coldStart.silenceAudioRenderer == nil && coldAccount.postbox.canBeginTransactionsValue.value && coldAccount.shouldBeServiceTaskMaster.value == .always, "actual audio/call retains upstream service and transactions without silent renderer")
let (ringing, primaryIdle) = fixture(); let secondaryCall = Account(2)
ringing.accountsAndTasks = [(primaryIdle, true, tasks()), (secondaryCall, false, tasks(call: true))]
ringing.checkTasks(); flush([primaryIdle, secondaryCall])
check(ringing.silenceAudioRenderer == nil && !ringing.hasActiveAudioSession && secondaryCall.postbox.canBeginTransactionsValue.value, "ringing pre-audio call retains transaction access at critical heat")
check(primaryIdle.shouldBeServiceTaskMaster.value == .never && secondaryCall.shouldBeServiceTaskMaster.value == .always && secondaryCall.workerKeep(continueInBackground: false), "critical ringing call keeps only working secondary account service master")
ringing.accountsAndTasks = [(primaryIdle, true, tasks(call: true)), (secondaryCall, false, tasks())]
ringing.checkTasks(); flush([primaryIdle, secondaryCall])
check(primaryIdle.shouldBeServiceTaskMaster.value == .always && secondaryCall.shouldBeServiceTaskMaster.value == .never, "primary/secondary call service attribution follows task ownership")
ringing.accountsAndTasks = [(primaryIdle, true, tasks()), (secondaryCall, false, tasks())]
ringing.checkTasks(); flush([primaryIdle, secondaryCall])
check(!primaryIdle.postbox.canBeginTransactionsValue.value && !secondaryCall.postbox.canBeginTransactionsValue.value && !primaryIdle.workerKeep(continueInBackground: false) && !secondaryCall.workerKeep(continueInBackground: false), "ending call returns both accounts to idle gates and worker flags")
let (draining, drainingAccount) = fixture(); drainingAccount.postbox.queue.storage.blocked = true
let assertionTimer = SwiftSignalKit.Timer(timeout: 30, repeat: false, completion: {}, queue: .mainQueue()); assertionTimer.start()
draining.currentTask = (90, clockNow, assertionTimer); draining.isInBackgroundExtension = true
draining.checkTasks(); check(draining.ended.isEmpty && assertionTimer.invalidated && !draining.isInBackgroundExtension, "idle background assertion remains owned until transaction callback")
drainingAccount.postbox.queue.storage.blocked = false; flush([drainingAccount])
check(draining.ended == [90] && !drainingAccount.postbox.canBeginTransactionsValue.value, "actual postbox callback ends old assertion after drain exactly once")
let (deniedRelease, deniedAccount) = fixture(); ProcessInfo.processInfo.thermalState = .nominal; deniedRelease.checkTasks(); deniedRelease.denied = true
ProcessInfo.processInfo.thermalState = .critical; deniedRelease.checkTasks(); flush([deniedAccount])
for _ in 0..<1000 { deniedRelease.checkTasks() }
check(deniedRelease.silenceAudioRenderer == nil && deniedRelease.keepAliveIdleTimer == nil && deniedRelease.begun == 0 && !deniedAccount.postbox.canBeginTransactionsValue.value, "denied release budget still drains gates without a retry loop")
clockNow = 0; ProcessInfo.processInfo.thermalState = .nominal
let (offline, offlineAccount) = fixture(); offline.primaryAccountHasNetwork = false; offline.primaryAccountNoNetworkSince = 0; offline.checkTasks()
clockNow = 100; ProcessInfo.processInfo.thermalState = .critical; offline.checkTasks()
clockNow = 700; ProcessInfo.processInfo.thermalState = .nominal; offline.checkTasks(); flush([offlineAccount])
check(offline.silenceAudioRenderer == nil && offline.primaryAccountNoNetworkSince == 0 && offline.isKeepAliveSuspendedForNetwork, "cooling keeps original no-network budget expired")
offline.primaryAccountHasNetwork = true; offline.primaryAccountNoNetworkSince = nil; offline.checkTasks(); flush([offlineAccount])
check(offline.silenceAudioRenderer != nil, "network recovery restarts still-eligible notification keepalive")
ProcessInfo.processInfo.thermalState = .critical; offline.checkTasks(); clockNow = 900; offline.noteBackgroundNotificationActivity()
check(offline.silenceAudioRenderer == nil, "real notification cannot bypass critical pause")
ProcessInfo.processInfo.thermalState = .serious; offline.checkTasks(); check(offline.keepAliveIdleTimerDeadline == 2100, "real delivered notification still earns activity after cooling")
let beforeObservers = NotificationCenter.default.observers.count
var temporary: Harness? = Harness(); temporary?.observe()
check(NotificationCenter.default.observers.count == beforeObservers + 3, "thermal/power/battery observers registered together")
temporary = nil; check(NotificationCenter.default.observers.count == beforeObservers, "released manager removes thermal/power/battery observers")
var removedTimer: SwiftSignalKit.Timer?
do { var owner: Harness? = Harness(); owner?.observe(); owner?.checkTasks(); removedTimer = owner?.keepAliveIdleTimer; Queue.mainQueue().flush(); owner = nil }
check(NotificationCenter.default.observers.count == beforeObservers && removedTimer?.invalidated == true, "released manager invalidates its idle timer and removes observer tokens after queued callbacks finish")
print("PASS: \(assertions) actual-source wakeup thermal/charging/duty, renderer, worker, timer, queue and transaction-release assertions")
'''
with tempfile.TemporaryDirectory(prefix="supergram-wakeup-thermal-") as temporary:
    path = Path(temporary)
    (path / "main.swift").write_text(swift.replace("public ", ""))
    subprocess.run(["xcrun", "swiftc", "-warnings-as-errors", str(path / "main.swift"), "-o", str(path / "test")], check=True)
    subprocess.run([str(path / "test")], check=True)
