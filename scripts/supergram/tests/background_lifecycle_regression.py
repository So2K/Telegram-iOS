#!/usr/bin/env python3
"""Run production background-task code against deterministic UIKit/timer doubles.

This checks task reuse, delayed/duplicate expiration callbacks, denied assertions,
and setting changes while a retained download task emits no new signal.
"""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "submodules/TelegramUI/Sources/SharedWakeupManager.swift"
ADAPTER = ROOT / "submodules/TelegramUI/Sources/AppDelegate.swift"


def extract_block(source: str, marker: str) -> str:
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    offset = opening + 1
    while depth:
        if source[offset] == "{":
            depth += 1
        elif source[offset] == "}":
            depth -= 1
        offset += 1
    return source[start:offset]


source = SOURCE.read_text()
tasks = extract_block(source, "private struct AccountTasks")
begin = extract_block(source, "private func beginBackgroundExtensionTaskIfNeeded")
transaction_gate = source.split("var enableBeginTransactions = false", 1)[1].split('Logger.shared.log("Wakeup"', 1)[0]
adapter = ADAPTER.read_text().split("SharedWakeupManager(beginBackgroundTask: { name, expiration in", 1)[1].split("}, endBackgroundTask:", 1)[0]
swift = r'''
import Foundation
import CoreFoundation

typealias UIBackgroundTaskIdentifier = Int
extension Int { static let invalid = -1 }
final class Logger {
    static let shared = Logger()
    func log(_ tag: String, _ text: String) {}
}
final class Application {
    var identifier = UIBackgroundTaskIdentifier.invalid
    func beginBackgroundTask(withName: String, expirationHandler: @escaping () -> Void) -> Int { self.identifier }
}
struct Queue { static func mainQueue() -> Queue { Queue() } }
enum SwiftSignalKit {
    final class Timer {
        let timeout: Double
        let completion: () -> Void
        var started = false
        var invalidated = false
        init(timeout: Double, repeat: Bool, completion: @escaping () -> Void, queue: Queue) {
            self.timeout = timeout
            self.completion = completion
        }
        func start() { self.started = true }
        func invalidate() { self.invalidated = true }
    }
}
struct AccountRunningImportantTasks: OptionSet {
    let rawValue: Int
    static let upload = AccountRunningImportantTasks(rawValue: 1)
}
var downloadsEnabled = true
func superGramBackgroundDownloadsEnabled() -> Bool { downloadsEnabled }
'''
swift += tasks + r'''
final class Harness {
    var currentTask: (UIBackgroundTaskIdentifier, Double, SwiftSignalKit.Timer)?
    var isInBackgroundExtension = false
    var backgroundExtensionBudgetExhausted = false
    var allowBackgroundTimeExtensionDeadlineTimer: SwiftSignalKit.Timer?
    let episodeId = 1
    var begun = 0
    var ended: [Int] = []
    var expirations: [() -> Void] = []
    var checks = 0
    var deny = false
    var timeRemaining = 40.0
    var grantedTime: Double?
    func beginBackgroundTask(_ name: String, _ expiration: @escaping () -> Void) -> Int? {
        if self.deny { return nil }
        self.begun += 1
        if let grantedTime = self.grantedTime { self.timeRemaining = grantedTime }
        self.expirations.append(expiration)
        return self.begun
    }
    func endBackgroundTask(_ id: Int) { self.ended.append(id) }
    func backgroundTimeRemaining() -> Double { self.timeRemaining }
    func checkTasks() { self.checks += 1 }
'''
swift += begin.replace("private func", "func", 1) + r'''
    func transactionGate() -> Bool {
        var enableBeginTransactions = false
''' + transaction_gate + r'''
        return enableBeginTransactions
    }
    func adapter(application: Application) -> Int? {
        let name = "regression"
        let expiration: () -> Void = {}
''' + adapter + r'''
    }
}

let harness = Harness()
harness.beginBackgroundExtensionTaskIfNeeded()
let firstTimer = harness.currentTask!.2
for _ in 0..<10_000 { harness.beginBackgroundExtensionTaskIfNeeded() }
precondition(harness.begun == 1 && harness.ended.isEmpty)
precondition(harness.currentTask!.2 === firstTimer && !firstTimer.invalidated)
precondition(firstTimer.started && firstTimer.timeout == 30.0)
let oldExpiration = harness.expirations[0]
oldExpiration()
oldExpiration()
precondition(harness.ended == [1] && harness.checks == 1)
precondition(firstTimer.invalidated && !harness.isInBackgroundExtension)

harness.timeRemaining = 12.0
harness.beginBackgroundExtensionTaskIfNeeded()
let nextTimer = harness.currentTask!.2
oldExpiration()
precondition(harness.isInBackgroundExtension && !nextTimer.invalidated)
precondition(harness.ended == [1] && nextTimer.timeout == 7.0)
nextTimer.completion()
harness.expirations[1]()
precondition(harness.ended == [1, 2] && harness.checks == 2)

harness.deny = true
harness.beginBackgroundExtensionTaskIfNeeded()
precondition(harness.currentTask == nil && !harness.isInBackgroundExtension && harness.backgroundExtensionBudgetExhausted)
harness.deny = false
harness.backgroundExtensionBudgetExhausted = false
harness.beginBackgroundExtensionTaskIfNeeded()
precondition(harness.begun == 3 && harness.isInBackgroundExtension)
harness.expirations[2]()
for remaining in [-1.0, 0.0, 4.0, 5.0] {
    let exhausted = Harness()
    exhausted.timeRemaining = remaining
    exhausted.beginBackgroundExtensionTaskIfNeeded()
    precondition(exhausted.begun == 1)
    exhausted.currentTask!.2.completion()
    for _ in 0..<1_000 { exhausted.beginBackgroundExtensionTaskIfNeeded() }
    precondition(exhausted.begun == 1 && exhausted.currentTask == nil)
    // A new foreground/wakeup budget may recover the same manager.
    exhausted.backgroundExtensionBudgetExhausted = false
    exhausted.grantedTime = 20.0
    exhausted.beginBackgroundExtensionTaskIfNeeded()
    precondition(exhausted.begun == 2 && exhausted.currentTask!.2.timeout == 15.0)
}
harness.timeRemaining = 5.1
harness.beginBackgroundExtensionTaskIfNeeded()
precondition(harness.begun == 4 && harness.currentTask!.2.timeout > 0.0)
let initial = Harness()
initial.timeRemaining = 0.0
initial.grantedTime = 40.0
initial.beginBackgroundExtensionTaskIfNeeded()
precondition(initial.begun == 1 && initial.currentTask!.2.timeout == 30.0)
initial.allowBackgroundTimeExtensionDeadlineTimer = firstTimer
precondition(initial.transactionGate())
initial.backgroundExtensionBudgetExhausted = true
precondition(!initial.transactionGate())
initial.backgroundExtensionBudgetExhausted = false
initial.allowBackgroundTimeExtensionDeadlineTimer = nil
precondition(!initial.transactionGate())
let application = Application()
precondition(initial.adapter(application: application) == nil)
application.identifier = 42
precondition(initial.adapter(application: application) == 42)

private let download = AccountTasks(stateSynchronization: false, importantTasks: [],
    backgroundLocation: false, backgroundDownloads: true, backgroundAudio: false,
    activeCalls: false, watchTasks: false, userInterfaceInUse: false)
precondition(!download.isEmpty && download.hasBackgroundDownloads)
downloadsEnabled = false
precondition(download.isEmpty && !download.hasBackgroundDownloads)
downloadsEnabled = true
precondition(!download.isEmpty && download.hasBackgroundDownloads)
downloadsEnabled = false
private let call = AccountTasks(stateSynchronization: false, importantTasks: [],
    backgroundLocation: false, backgroundDownloads: true, backgroundAudio: true,
    activeCalls: true, watchTasks: false, userInterfaceInUse: false)
precondition(!call.isEmpty)
print("PASS: task reuse, stale/duplicate expiry, UIKit refusal, timer bounds, live toggles, exhausted budgets, transaction gate")
'''

with tempfile.TemporaryDirectory(prefix="supergram-background-test-") as directory:
    path = Path(directory)
    (path / "main.swift").write_text(swift)
    subprocess.run(["xcrun", "swiftc", str(path / "main.swift"), "-o", str(path / "test")], check=True)
    subprocess.run([str(path / "test")], check=True)
