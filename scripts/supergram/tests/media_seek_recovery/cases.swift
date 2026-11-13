let checks = Atomic<Int>(value: 0)
func check(_ value: Bool, _ note: String) { let _ = checks.modify { $0 + 1 }; if !value { print("FAIL: \(note)"); exit(42) } }
private final class Holder {
    let queue = Queue(name: "media-recovery-control")
    let probe: EngineProbe
    var context: MediaPlayerContext?
    init(completed: Bool = false, streaming: MediaPlayerStreaming = .earlierStart, temp: String? = nil, range: Range<Int64>? = nil, configure: (EngineProbe) -> Void = { _ in }) {
        self.probe = EngineProbe(completed: completed); configure(probe)
        queue.sync { context = MediaPlayerContext(queue: queue, probe: probe, streamable: streaming, tempFilePath: temp, limitedFileRange: range); context!.seek(timestamp: 3.0, action: .play) }
    }
    var events: [String] { probe.events.with { $0 } }
    var seeks: [String] { events.filter { $0.hasPrefix("seek:") } }
    func later(_ delay: Double, _ body: @escaping (MediaPlayerContext, EngineProbe) -> Void) { queue.after(delay) { [weak self] in guard let self, let context = self.context else { return }; body(context, self.probe) } }
    func finish() { queue.sync { context?.stop(); context = nil } }
}
private let corrupt = Holder(completed: true)
private let synchronous = Holder(completed: true, configure: { $0.synchronousComplete = true })
private let lateComplete = Holder(configure: { $0.successWhenComplete = true })
private func completeAfterTimedBudget() {
    lateComplete.queue.after(0.05) {
        if lateComplete.seeks.count < 5 { completeAfterTimedBudget() }
        else { lateComplete.probe.record("before-late-completion-count:\(lateComplete.seeks.count)"); lateComplete.probe.completeNow() }
    }
}
completeAfterTimedBudget()
private let fresh = Holder()
fresh.later(0.05) { context, _ in context.seek(timestamp: 9.0, action: .play) }
private let transient = Holder(configure: { $0.successAtAttempt = 2 })
private let nonstream = Holder(completed: true, streaming: .none)
private let temp = Holder(completed: true, temp: "/synthetic-local-input")
private let range = Holder(completed: true, range: 0 ..< 1024)
private let timedPause = Holder()
timedPause.later(0.05) { context, probe in context.pause(lostAudioSession: false); probe.record("after-pause-action:\(context.stateAction)") }
private let completionPause = Holder(configure: { $0.successWhenComplete = true })
completionPause.later(0.05) { context, probe in context.pause(lostAudioSession: false); probe.record("after-pause-action:\(context.stateAction)"); probe.completeNow() }
private let pausePlay = Holder(configure: { $0.successAtAttempt = 2 })
pausePlay.later(0.02) { context, _ in context.pause(lostAudioSession: false) }
pausePlay.later(0.05) { context, probe in context.seek(timestamp: 3.0, action: .play); probe.record("after-resume-action:\(context.stateAction)") }
private let superseded = Holder(configure: { $0.successWhenComplete = true })
superseded.later(0.05) { context, _ in context.seek(timestamp: 9.0, action: .pause) }
superseded.later(0.08) { _, probe in probe.completeNow() }
private let queuedError = Holder(configure: { $0.manualErrors = true })
queuedError.queue.sync {
    let posted = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { queuedError.probe.failAttempt(1); posted.signal() }
    check(posted.wait(timeout: .now() + 1.0) == .success, "old error queued while context queue held")
    queuedError.context!.seek(timestamp: 9.0, action: .pause)
}
private let queuedCompletion = Holder()
queuedCompletion.later(0.05) { context, probe in
    let posted = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { probe.completeNow(); posted.signal() }
    check(posted.wait(timeout: .now() + 1.0) == .success, "old complete observation queued while context queue held")
    context.seek(timestamp: 9.0, action: .pause)
}
private let retiredFresh = Holder()
retiredFresh.later(0.03) { context, probe in
    let episode = context.episode; let attempt = context.attempt
    context.seek(timestamp: 9.0, action: .pause)
    retiredFresh.later(0.03) { current, _ in
        current.replayRetiredTimer(timestamp: 3.0, seekRecoveryGeneration: episode, seekAttemptGeneration: attempt, action: .play)
        probe.record("retired-fresh-owned:\(current.hasRetryTimer)")
    }
}
private let retiredAutomatic = Holder()
retiredAutomatic.later(0.03) { context, probe in
    let episode = context.episode; let attempt = context.attempt
    probe.completeNow()
    retiredAutomatic.later(0.03) { current, _ in
        current.replayRetiredTimer(timestamp: 3.0, seekRecoveryGeneration: episode, seekAttemptGeneration: attempt, action: .play)
        probe.record("retired-automatic-owned:\(current.hasRetryTimer)")
    }
}
private let released = Holder()
private weak var releasedContext = released.context
released.later(0.05) { _, _ in }
released.queue.after(0.08) { released.context = nil }
private let releasedError = Holder(configure: { $0.manualErrors = true })
private weak var releasedErrorContext = releasedError.context
releasedError.queue.sync {
    let posted = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { releasedError.probe.failAttempt(1); posted.signal() }
    check(posted.wait(timeout: .now() + 1.0) == .success, "error queued before deinit")
    releasedError.context = nil
}
// Independent controls run concurrently with real one-, two-, three- and four-second retry timers.
Thread.sleep(forTimeInterval: 0.3)
check(corrupt.seeks.count <= 6, "cached permanent failure cannot retry unboundedly before timers")
check(corrupt.events.filter { $0 == "complete-observation" }.count == 1, "complete arm occurs once in episode")
check(synchronous.seeks.count <= 6 && synchronous.events.filter { $0 == "complete-observation" }.count == 1, "synchronous completion registration preserves one bounded arm")
check(queuedError.events.filter { $0 == "full-fetch" }.isEmpty, "queued old error cannot start replacement recovery")
check(queuedError.seeks == ["seek:3.0", "seek:9.0"], "queued old error cannot recreate old source")
check(queuedCompletion.seeks == ["seek:3.0", "seek:9.0", "seek:9.0"], "queued old completion cannot retry prior timestamp")
check(retiredFresh.events.contains("retired-fresh-owned:true"), "retired timer cannot clear fresh replacement timer")
check(retiredAutomatic.events.contains("retired-automatic-owned:true"), "retired timer cannot clear same-episode automatic replacement timer")
check(releasedContext == nil && releasedErrorContext == nil, "actual deinit releases contexts with pending recovery and queued error")
check(releasedError.events.filter { $0 == "full-fetch" }.isEmpty, "queued error after deinit does not recover")
for h in [nonstream, temp, range] {
    check(h.seeks.count == 1, "nonstream/temp/range policy retains single failed attempt")
    check(!h.events.contains("full-fetch") && !h.events.contains("complete-observation"), "nonstream/temp/range bypass recovery")
}
Thread.sleep(forTimeInterval: 1.05)
check(fresh.seeks.prefix(3).map { $0 } == ["seek:3.0", "seek:9.0", "seek:9.0"], "fresh different timestamp receives a fresh one-second retry budget")
check(transient.seeks.count == 2 && transient.events.contains("success-action:play"), "transient second attempt succeeds")
transient.queue.sync { check(transient.context!.retryBudget == 0, "successful seek clears retry budget"); check(!transient.context!.hasRetryTimer && !transient.context!.hasCompletionObserver, "successful seek cancels recovery timer and observer") }
check(timedPause.events.contains("after-pause-action:pause"), "actual pause updates pending action")
timedPause.queue.sync { check(timedPause.context!.stateAction == "pause", "timed retry preserves paused action") }
check(completionPause.events.contains("success-action:pause"), "completion retry preserves paused action through success")
check(pausePlay.events.contains("after-resume-action:play") && pausePlay.events.contains("success-action:play"), "pause-to-play update stays current during retry")
check(superseded.seeks == ["seek:3.0", "seek:9.0", "seek:9.0"], "fresh seek disposes old completion and retries current timestamp")
check(superseded.events.contains("success-action:pause"), "replacement completion preserves current action")
let deadline = Date().addingTimeInterval(15.0)
while !lateComplete.events.contains("success-action:play") && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
Thread.sleep(forTimeInterval: 0.3)
print("late completion: \(lateComplete.events)")
check(retiredFresh.seeks.prefix(3).map { $0 } == ["seek:3.0", "seek:9.0", "seek:9.0"], "fresh replacement retry still fires after retired callback")
check(retiredAutomatic.seeks.count >= 3 && retiredAutomatic.seeks.count <= 6, "automatic replacement retry still fires after retired callback")
check(corrupt.seeks.count <= 6, "cached permanent failure stays bounded beyond all retry timers")
check(synchronous.seeks.count <= 6, "synchronous cached failure remains bounded beyond timer budget")
check(corrupt.events.filter { $0 == "complete-observation" }.count == 1, "timed retries cannot re-arm completed resource")
check(lateComplete.events.contains("before-late-completion-count:5"), "incomplete failure exhausts all four timed retries")
check(lateComplete.seeks.count == 6 && lateComplete.events.contains("success-action:play"), "completion after four timed retries still receives one successful recovery")
check(transient.seeks.count == 2, "successful seek cannot be replaced by later recovery callbacks")
check(released.seeks.count == 1, "deinit cancels pending retry timer")
check(corrupt.events.filter { $0 == "full-fetch" }.count == 1, "one full fetch is reused within recovery")
for (name, holder) in [("retiredFresh",retiredFresh),("retiredAutomatic",retiredAutomatic),("corrupt",corrupt),("synchronous",synchronous),("lateComplete",lateComplete),("fresh",fresh),("transient",transient),("timedPause",timedPause),("completionPause",completionPause),("pausePlay",pausePlay),("superseded",superseded),("queuedError",queuedError),("queuedCompletion",queuedCompletion),("released",released),("releasedError",releasedError)] { print("\(name): \(holder.events)") }
for h in [retiredFresh,retiredAutomatic,corrupt,synchronous,lateComplete,fresh,transient,nonstream,temp,range,timedPause,completionPause,pausePlay,superseded,queuedError,queuedCompletion,released,releasedError] { h.finish() }
print("PASS: \(checks.with { $0 }) actual-source media recovery assertions with26 real SwiftSignalKit sources")
