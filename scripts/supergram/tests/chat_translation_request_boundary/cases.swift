let channel = EnginePeer.Id(value: 42)
let otherChannel = EnginePeer.Id(value: 43)
let one = EngineMessage.Id(peerId: channel, id: 1)
let two = EngineMessage.Id(peerId: channel, id: 2)
func watch(_ account: Int64 = 1, peer: EnginePeer.Id = channel, language: String = "de") -> ChatTranslationPanelNode {
    let panel = ChatTranslationPanelNode(accountId: account, peerId: peer)
    panel.currentInfo?.toLang = language; panel.subscribe(); return panel
}
func history(_ account: Int64 = 1, language: String? = "de", base: String = "de") -> (AccountContext, HistoryNode) {
    let context = AccountContext(account); let node = HistoryNode(context)
    node.applyRaw(raw(language), base: base); return (context, node)
}
func pinnedState(_ language: String = "de", enabled: Bool = true, message: PinnedMessageValue? = PinnedMessageValue(one)) -> PinnedInterfaceState {
    PinnedInterfaceState(translationState: ChatPresentationTranslationState(isEnabled: enabled, fromLang: "en", toLang: language), pinnedMessage: message.map { PinnedValue(message: $0) })
}
final class EventCount {
    var value = 0
    var onEvent: (() -> Void)?
    func subscribe(_ account: Int64 = 1, _ peer: EnginePeer.Id = channel) -> Disposable {
        #if SCOPED
        return sgChatTranslationFailures(accountId: account, peerId: peer).start(next: { [weak self] _ in self?.value += 1; self?.onEvent?() })
        #else
        return sgChatTranslationFailures(peerId: peer).start(next: { [weak self] _ in self?.value += 1; self?.onEvent?() })
        #endif
    }
}

// Account + normalized language guard executes through the real catch and pipe.
do {
    let a = watch(); let b = watch(2)
    let (context, node) = history(); node.process([one]); context.engine.requests[0].fail()
    check(a.toggleCount == 1, "current history failure reaches its own panel")
    check(b.toggleCount == 0 && b.viewController.presented == 0, "same public peer in another account remains unchanged")
    a.dispose(); b.dispose()
}
do {
    let panel = watch(-7, language: "de-AT"); let (context, node) = history(-7, language: "de-DE")
    node.process([one]); context.engine.requests[0].fail()
    check(panel.toggleCount == 1, "normalized current target preserves legitimate failure")
    panel.dispose()
}

// The actual history callback early insertion executes even when loaded processing returns.
for gate in ["loading", "fill-hole"] {
    for intent in ["off", "new-language", "nil-state"] {
        let panel = watch(); let (context, node) = history(); node.process([one])
        let state: ChatTranslationState? = intent == "nil-state" ? nil : raw(intent == "new-language" ? "fr" : "de", enabled: intent != "off")
        node.applyRaw(state, loading: gate == "loading", fillHole: gate == "fill-hole")
        node.process([two])
        check(context.engine.requests.count == 1, "\(gate)/\(intent): stale effective language cannot start a fresh request")
        context.engine.requests[0].fail()
        check(panel.toggleCount == 0 && panel.viewController.presented == 0, "\(gate)/\(intent): previous request is revoked before early return")
        panel.dispose()
    }
}
for mode in ["language-ABA", "off-on"] {
    let panel = watch(); let (context, node) = history(); node.process([one])
    node.applyRaw(mode == "language-ABA" ? raw("fr") : raw(enabled: false), loading: true)
    node.applyRaw(raw(), loading: true)
    panel.updateInfo(Info(peer: Peer(id: channel)))
    context.engine.requests[0].fail()
    check(panel.toggleCount == 0, "\(mode): retained old RPC cannot fail the new same-language episode")
    node.process([two]); check(context.engine.requests.count == 2, "\(mode): current same-language request remains eligible while loading")
    context.engine.requests[1].fail()
    check(panel.toggleCount == 1, "\(mode): newly-owned RPC retains failure feedback")
    panel.dispose()
}
do {
    let events = EventCount(); let sub = events.subscribe(); let (context, node) = history()
    node.process([one]); node.process([two]); node.applyRaw(raw(), loading: true)
    check(context.engine.requests.count == 2, "concurrent batches of same intent both start")
    context.engine.requests[0].fail(); context.engine.requests[1].fail()
    check(events.value == 2, "same-intent history callback does not retire a legitimate concurrent batch")
    sub.dispose()
}
do {
    let events = EventCount(); let sub = events.subscribe(); let (context, node) = history()
    node.process([one]); node.applyRaw(raw(from: "es"), loading: true); node.process([two])
    check(context.engine.requests.count == 1, "raw source-language change rejects stale manager invocation")
    context.engine.requests[0].fail(); check(events.value == 0, "source-language episode change revokes old failure")
    node.applyRaw(raw(from: "es")); node.process([two]); context.engine.requests[1].fail()
    check(events.value == 1, "loaded source-language replacement retains current error")
    sub.dispose()
}
do {
    let events = EventCount(); let sub = events.subscribe(); let (context, node) = history(language: nil, base: "de-raw")
    node.process([one]); node.applyRaw(raw(nil), loading: true, base: "fr-raw"); node.process([two])
    check(context.engine.requests.count == 1, "base-language fallback change revokes stale effective pair")
    context.engine.requests[0].fail(); check(events.value == 0, "base fallback episode rejects previous error")
    node.applyRaw(raw(nil), base: "fr-raw"); node.process([two]); context.engine.requests[1].fail()
    check(events.value == 1, "normalized raw-suffix fallback works when loaded")
    sub.dispose()
}
do {
    let events = EventCount(); let sub = events.subscribe(); let (context, node) = history()
    node.process([one]); node.applyRaw(raw(enabled: false), loading: true, source: .other)
    context.engine.requests[0].fail(); check(events.value == 1, "other history source does not revoke the default source's intent")
    sub.dispose()
}
do {
    let panel = watch(); let (context, node) = history(); node.process([one])
    let queued = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { context.engine.requests[0].fail(); queued.signal() }
    check(queued.wait(timeout: .now() + 2) == .success, "actual error callback was queued from background")
    node.applyRaw(raw("fr"), loading: true); node.applyRaw(raw(), loading: true)
    pump(); check(panel.toggleCount == 0, "main delivery evaluates latest caller episode after queued error")
    panel.dispose()
}
do {
    let events = EventCount(); let sub = events.subscribe(); let context = AccountContext(1)
    var node: HistoryNode? = HistoryNode(context); node?.applyRaw(raw()); node?.process([one])
    weak var weakNode = node; node = nil
    check(weakNode == nil, "retained standalone worker does not retain departed history owner")
    context.engine.requests[0].fail(); check(events.value == 0, "departed history owner cannot publish a new error")
    sub.dispose()
}

// Pinned ownership revocation, cached result and identity replacement.
for boundary in ["off", "no-pin", "cache", "replacement", "language-ABA"] {
    let panel = watch(); let context = AccountContext(1); let node = PinnedNode(context)
    node.update(pinnedState()); check(context.engine.requests.count == 1, "pin \(boundary): request starts")
    switch boundary {
    case "off": node.update(pinnedState(enabled: false))
    case "no-pin": node.update(pinnedState(message: nil))
    case "cache": node.update(pinnedState(message: PinnedMessageValue(one, cached: "de")))
    case "replacement": node.update(pinnedState(message: PinnedMessageValue(two)))
    default: node.update(pinnedState("fr")); node.update(pinnedState())
    }
    check(context.engine.requests[0].disposals == 1, "pin \(boundary): old worker disposal is owned exactly once")
    context.engine.requests[0].fail(); pump()
    check(panel.toggleCount == 0, "pin \(boundary): old request cannot mutate panel")
    if boundary == "replacement" || boundary == "language-ABA" {
        let last = context.engine.requests.last!; check(last.disposals == 0, "pin \(boundary): latest worker remains subscribed")
        last.fail(); check(panel.toggleCount == 1, "pin \(boundary): latest failure remains eligible")
    }
    panel.dispose()
}
do {
    let events = EventCount(); let sub = events.subscribe(); let context = AccountContext(1); let node = PinnedNode(context)
    node.update(pinnedState()); node.update(pinnedState(), messageUpdated: false)
    check(context.engine.requests.count == 1 && context.engine.requests[0].disposals == 0, "unchanged pin layout preserves pending request")
    node.update(pinnedState())
    check(context.engine.requests.count == 2 && context.engine.requests[0].disposals == 1, "same-language producer replacement retires only earlier request")
    context.engine.requests[1].fail(); check(events.value == 1, "same-language replacement keeps current callback")
    sub.dispose()
}
do {
    let events = EventCount(); let sub = events.subscribe(); let context = AccountContext(1); let node = PinnedNode(context)
    context.engine.synchronousError = .generic; node.update(pinnedState())
    check(events.value == 1, "pin installs identity before a synchronous failure")
    sub.dispose()
}
do {
    let panel = watch(); let context = AccountContext(1); let node = PinnedNode(context)
    let events = EventCount(); let sub = events.subscribe()
    panel.onToggle = { panel.onToggle = nil; panel.updateInfo(Info(toLang: "fr", peer: Peer(id: channel))); node.update(pinnedState("fr")) }
    context.engine.synchronousError = .generic; node.update(pinnedState())
    check(context.engine.requests.count == 2, "synchronous failure can start a nested replacement")
    check(context.engine.requests[1].disposals == 0, "outer registration cannot dispose nested pin replacement")
    context.engine.requests[1].fail(); check(events.value == 2, "nested pin replacement can publish current failure before the unchanged UI cooldown")
    sub.dispose(); panel.dispose()
}
do {
    let events = EventCount(); let sub = events.subscribe(); let context = AccountContext(1)
    var node: PinnedNode? = PinnedNode(context); node?.update(pinnedState())
    weak var weakNode = node; node = nil
    check(weakNode == nil && context.engine.requests[0].disposals == 1, "pin teardown releases owner and disposes pending worker")
    context.engine.requests[0].fail(); check(events.value == 0, "disposed pin cannot publish late failure")
    sub.dispose()
}

// Actual complete handler action, not a rewritten Undo decision.
for change in ["unchanged-off", "already-on", "other-peer", "other-language", "dismiss"] {
    prefersOnDevice = false
    let panel = watch(); let (context, node) = history(); node.process([one]); context.engine.requests[0].fail()
    check(panel.toggleCount == 1 && panel.currentInfo?.isActive == false, "Undo \(change): failure disabled current translation")
    let overlay = panel.viewController.overlay!
    switch change {
    case "already-on": panel.updateInfo(Info(peer: Peer(id: channel)))
    case "other-peer": panel.updateInfo(Info(isActive: false, peer: Peer(id: otherChannel)))
    case "other-language": panel.updateInfo(Info(isActive: false, toLang: "fr", peer: Peer(id: channel)))
    default: break
    }
    let backendBefore = backendChoices
    _ = overlay.action(change == "dismiss" ? .dismiss : .undo)
    check(panel.toggleCount == (change == "unchanged-off" ? 2 : 1), "Undo \(change): toggles only original matching inactive selection")
    check(backendChoices == backendBefore + (change == "dismiss" ? 0 : 1), "Undo \(change): explicit action alone selects global on-device backend")
    panel.dispose()
}
do {
    prefersOnDevice = false
    let (context, node) = history(); var panel: ChatTranslationPanelNode? = watch()
    node.process([one]); context.engine.requests[0].fail(); let overlay = panel!.viewController.overlay!
    weak var weakPanel = panel; panel = nil
    check(weakPanel == nil, "Undo overlay does not retain the departed panel")
    let count = backendChoices; _ = overlay.action(.undo)
    check(backendChoices == count + 1, "explicit Undo after departure still chooses global backend without toggling any chat")
}

// Existing error-category policy and typed event checks are retained.
do {
    let panel = watch(); let (context, node) = history(); node.process([one]); context.engine.requests[0].fail(.invalidMessageId)
    check(panel.toggleCount == 0 && panel.viewController.presented == 0, "single-message invalid ID does not disable whole chat")
    panel.dispose()
}
#if SCOPED
do {
    let panel = watch(); panel.sgHandleTranslationFailure(SGChatTranslationFailureEvent(accountId: 2, peerId: channel, toLang: "de", reason: .serverRejected))
    check(panel.toggleCount == 0 && panel.sgLastFailureTimestamp == 0, "handler independently rejects mismatched account before cooldown")
    panel.currentInfo?.isActive = false
    panel.sgHandleTranslationFailure(SGChatTranslationFailureEvent(accountId: 1, peerId: channel, toLang: "de", reason: .serverRejected))
    check(panel.toggleCount == 0 && panel.sgLastFailureTimestamp == 0, "inactive intent cannot consume cooldown")
    panel.dispose()
}
#endif

// An event published before the intent change is already queued at the UI boundary.
func publishFailure(_ account: Int64 = 1, peer: EnginePeer.Id = channel, language: String = "de") {
    #if SCOPED
    sgReportChatTranslationFailure(accountId: account, peerIds: [peer], toLang: language, error: .generic, onDevice: false)
    #else
    sgReportChatTranslationFailure(peerIds: [peer], error: .generic, onDevice: false)
    #endif
}
for mode in ["published-language-ABA", "published-off-on"] {
    let panel = watch(); let queued = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { publishFailure(); queued.signal() }
    check(queued.wait(timeout: .now() + 2) == .success, "\(mode): actual ValuePipe publication finished before state change")
    panel.updateInfo(mode == "published-language-ABA" ? Info(toLang: "fr", peer: Peer(id: channel)) : Info(isActive: false, peer: Peer(id: channel)))
    panel.updateInfo(Info(peer: Peer(id: channel))); pump()
    check(panel.toggleCount == 0 && panel.viewController.presented == 0, "\(mode): queued old subscription cannot mutate replacement")
    panel.dispose()
}
do {
    let context = AccountContext(1); let events = EventCount(); let sub = events.subscribe()
    let calledOnMain = Atomic(value: false)
    let handle = translateMessageIds(context: context, messageIds: [one], fromLang: "en", toLang: "de", isCurrent: {
        _ = calledOnMain.swap(Thread.isMainThread); return true
    }).start()
    let queued = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { context.engine.requests[0].fail(); queued.signal() }
    check(queued.wait(timeout: .now() + 2) == .success, "background engine error was emitted")
    pump()
    check(calledOnMain.with { $0 }, "caller intent predicate is evaluated on main, never on Postbox/RPC queue")
    check(events.value == 1, "main-delivered live caller still publishes its failure")
    handle.dispose(); sub.dispose()
}
do {
    let panel = watch(); let context = AccountContext(1); let node = PinnedNode(context)
    node.update(pinnedState()); let queued = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { context.engine.requests[0].fail(); queued.signal() }
    check(queued.wait(timeout: .now() + 2) == .success, "pin error queued before off-on")
    node.update(pinnedState(enabled: false), messageUpdated: false)
    node.update(pinnedState()); pump()
    check(panel.toggleCount == 0, "queued pinned error does not affect off-on replacement")
    check(context.engine.requests.last!.disposals == 0, "queued pinned error leaves new subscription owned")
    context.engine.requests.last!.fail(); check(panel.toggleCount == 1, "new pinned failure remains eligible after off-on")
    panel.dispose()
}
do {
    let context = AccountContext(1); let node = PinnedNode(context)
    node.update(pinnedState()); node.update(pinnedState(message: nil), messageUpdated: false)
    check(context.engine.requests[0].disposals == 1, "no-pin intent disposes even without messageUpdated")
    node.update(pinnedState(enabled: false), messageUpdated: false)
    check(context.engine.requests.count == 1, "disabled pin does not start worker with stale message")
}
do {
    let context = AccountContext(1); let node = PinnedNode(context)
    var message: PinnedMessageValue? = PinnedMessageValue(one)
    weak var weakMessage = message
    node.update(pinnedState(message: message)); message = nil
    check(weakMessage == nil, "pending pin identity callback stores ID rather than whole message/media")
}

print("RESULT \(checks) assertions; \(failures.count) desired failures")
exit(failures.isEmpty ? 0 : 42)
