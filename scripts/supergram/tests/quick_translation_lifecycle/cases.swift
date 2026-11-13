var checks = 0
var failures: [String] = []
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if !condition() { failures.append(name) }
}
func drainMainQueue() { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.015)) }
func fixture(_ id: Int64 = 1) -> (EngineRegistry, AccountContext, ControllerInteraction, ChatMessageBubbleItemNode) {
    resetSyntheticStore()
    let registry = EngineRegistry()
    let context = AccountContext(registry)
    let interaction = ControllerInteraction()
    let message = EngineMessage(id: id)
    context.engine.data.values[id] = message
    let node = ChatMessageBubbleItemNode()
    node.item = ChatMessageItem(context: context, message: message, controllerInteraction: interaction)
    return (registry, context, interaction, node)
}

// Suspended producer outlives its UI; actual .start disposal is required, releasing
// MetaDisposable/SubscriberDisposable alone is insufficient. No cycle captures the node.
do {
    resetSyntheticStore()
    let registry = EngineRegistry()
    let interaction = ControllerInteraction()
    var context: AccountContext? = AccountContext(registry)
    weak var weakContext = context
    var node: ChatMessageBubbleItemNode? = ChatMessageBubbleItemNode()
    weak var weakNode = node
    let message = EngineMessage(id: 1)
    context!.engine.data.values[1] = message
    node!.item = ChatMessageItem(context: context!, message: message, controllerInteraction: interaction)
    node!.quickTranslateButtonPressed()
    check(registry.count == 1, "pending engine subscriber starts")
    check(interaction.updates == [1], "initial update is the captured message")
    let lateSubscribers = registry.heldSubscribers()
    context = nil
    node = nil
    check(weakNode == nil, "node deinitializes: no direct self capture cycle")
    check(registry.count == 0, "node deinit cancels active engine subscriber")
    check(registry.disposalCount == 1, "node deinit runs producer cleanup exactly once")
    check(weakContext == nil, "canceled request releases captured context")
    lateSubscribers.forEach { $0.putError(.generic) }
    drainMainQueue()
    check(interaction.failures == 0, "retained stale producer cannot present failure after node deinit")
    check(interaction.updates == [1], "retained stale producer cannot request a late layout")
    registry.forceCleanup()
}

// A worker can have already queued an error to main before the node disappears.
do {
    var (registry, context, interaction, node): (EngineRegistry, AccountContext, ControllerInteraction, ChatMessageBubbleItemNode?) = {
        let f = fixture(2); return (f.0, f.1, f.2, f.3)
    }()
    node!.quickTranslateButtonPressed()
    let fired = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { registry.fail(); fired.signal() }
    check(fired.wait(timeout: .now() + 2) == .success, "background error reaches delivery queue")
    node = nil
    drainMainQueue()
    check(interaction.failures == 0, "queued error delivery suppressed by deinit disposal")
    check(interaction.updates == [2], "queued error cannot request stale layout")
    check(registry.count == 0 && registry.disposalCount == 1, "error plus disposal has one producer cleanup")
    withExtendedLifetime(context) {}
}

// Alive requests keep their previous behavior; no blanket callback suppression.
do {
    let (registry, _, interaction, node) = fixture(3)
    node.quickTranslateButtonPressed()
    registry.fail()
    check(interaction.failures == 1, "live error reports exactly once")
    check(interaction.updates == [3, 3], "live error updates original message")
    check(registry.count == 0 && registry.disposalCount == 1, "live failure disposes producer")
    registry.fail()
    check(interaction.failures == 1, "repeated producer failure cannot report twice")
}
do {
    let (registry, context, interaction, node) = fixture(4)
    node.quickTranslateButtonPressed()
    context.engine.data.values[4] = EngineMessage(id: 4, attributes: [TranslationMessageAttribute(toLang: "de", text: "translated")])
    registry.complete()
    check(registry.count == 0, "successful request completes")
    check(interaction.failures == 0, "success has no error banner")
    check(sgQuickTranslationStore.language(messageId: 4) == "de", "success retains translate display state")
    node.quickTranslateButtonPressed()
    check(sgQuickTranslationStore.language(messageId: 4) == nil, "second press returns original display")
    check(registry.startedIds == [[4]], "return-to-original starts no second engine request")
}

// The captured IDs/interaction intentionally belong to the request's original item,
// never to a later replacement. This tests routing, not a claim of live node reuse on phone.
do {
    let (registry, context, oldInteraction, node) = fixture(5)
    node.quickTranslateButtonPressed()
    let newInteraction = ControllerInteraction()
    node.item = ChatMessageItem(context: context, message: EngineMessage(id: 6), controllerInteraction: newInteraction)
    registry.fail()
    check(oldInteraction.updates == [5, 5] && oldInteraction.failures == 1, "request callback targets captured old item")
    check(newInteraction.updates.isEmpty && newInteraction.failures == 0, "replacement item is not mutated or notified")
    check(registry.startedIds == [[5]], "engine request remains bound to original message ID")
}

// A new click replaces the previous active subscription through real MetaDisposable.set.
do {
    let (registry, context, interaction, node) = fixture(7)
    node.quickTranslateButtonPressed()
    let stale = registry.heldSubscribers()
    resetSyntheticStore()
    context.engine.data.values[8] = EngineMessage(id: 8)
    node.item = ChatMessageItem(context: context, message: EngineMessage(id: 8), controllerInteraction: interaction)
    node.quickTranslateButtonPressed()
    check(registry.count == 1 && registry.startedIds == [[7], [8]], "replacement leaves one active request")
    check(registry.disposalCount == 1, "replacement cancels previous producer")
    stale.forEach { $0.putError(.generic) }
    check(interaction.failures == 0, "replaced producer cannot report a late failure")
    registry.fail()
    check(interaction.failures == 1 && interaction.updates.last == 8, "current replacement still reports correctly")
}

// Already-translated data and on-device failure exercise the real helper's other paths.
do {
    let (registry, context, interaction, node) = fixture(9)
    context.engine.data.values[9] = EngineMessage(id: 9, attributes: [TranslationMessageAttribute(toLang: "de", text: "present")])
    node.quickTranslateButtonPressed()
    check(registry.count == 0 && registry.startedIds.isEmpty, "cached translation avoids engine request")
    check(interaction.failures == 0, "cached translation succeeds")
}
do {
    onDevice = true
    let (registry, _, interaction, node) = fixture(10)
    node.quickTranslateButtonPressed()
    registry.fail()
    check(interaction.failures == 1, "on-device error still reports while node is alive")
    onDevice = false
}

