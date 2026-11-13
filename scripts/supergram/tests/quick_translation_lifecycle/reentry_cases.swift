// Execute the actual renderer decision, not an invented spinner predicate.
do {
    let (registry, context, interaction, node) = fixture(20)
    check(!actualRenderer(item: ChatMessageItem(context: context, message: EngineMessage(id: 20), controllerInteraction: interaction)), "unselected original has no translation spinner")
    withExtendedLifetime(node) {}
    registry.forceCleanup()
}
do {
    resetSyntheticStore()
    let registry = EngineRegistry()
    let context = AccountContext(registry)
    let interaction = ControllerInteraction()
    let message = EngineMessage(id: 21)
    context.engine.data.values[21] = message
    var node: ChatMessageBubbleItemNode? = ChatMessageBubbleItemNode()
    node!.item = ChatMessageItem(context: context, message: message, controllerInteraction: interaction)
    node!.quickTranslateButtonPressed()
    check(actualRenderer(item: node!.item!), "pending translation displays spinner while request exists")
    node = nil
    check(registry.count == 0, "removed pending node has no active producer")
    check(sgQuickTranslationLanguage(messageId: 21) == nil, "pending cancellation clears own display selector")
    let reentered = ChatMessageItem(context: context, message: message, controllerInteraction: interaction)
    check(!actualRenderer(item: reentered), "reentered canceled message has no orphan translation spinner")
    registry.forceCleanup()
}
do {
    resetSyntheticStore()
    let registry = EngineRegistry()
    let context = AccountContext(registry)
    let interaction = ControllerInteraction()
    let cached = EngineMessage(id: 22, attributes: [TranslationMessageAttribute(toLang: "de", text: "cached")])
    context.engine.data.values[22] = cached
    var node: ChatMessageBubbleItemNode? = ChatMessageBubbleItemNode()
    node!.item = ChatMessageItem(context: context, message: cached, controllerInteraction: interaction)
    node!.quickTranslateButtonPressed()
    node = nil
    check(registry.count == 0 && registry.startedIds.isEmpty, "sync cached completion has no request")
    check(sgQuickTranslationLanguage(messageId: 22) == "de", "sync cached completion survives node deinit")
    check(!actualRenderer(item: ChatMessageItem(context: context, message: cached, controllerInteraction: interaction)), "cached selector renders translation without spinner")
}
do {
    resetSyntheticStore()
    let registry = EngineRegistry()
    let context = AccountContext(registry)
    let interaction = ControllerInteraction()
    context.engine.data.values[23] = EngineMessage(id: 23)
    var node: ChatMessageBubbleItemNode? = ChatMessageBubbleItemNode()
    node!.item = ChatMessageItem(context: context, message: EngineMessage(id: 23), controllerInteraction: interaction)
    node!.quickTranslateButtonPressed()
    let translated = EngineMessage(id: 23, attributes: [TranslationMessageAttribute(toLang: "de", text: "stored")])
    context.engine.data.values[23] = translated
    registry.complete()
    node = nil
    check(registry.count == 0 && registry.disposalCount == 1, "async completion cleans producer once")
    check(sgQuickTranslationLanguage(messageId: 23) == "de", "successful async completion retains selector after deinit")
    check(!actualRenderer(item: ChatMessageItem(context: context, message: translated, controllerInteraction: interaction)), "successful reentry renders stored translation without spinner")
}

// Same message/language ABA: cancel/error of the old owner cannot clear the new token.
do {
    let (registry, context, interaction, node) = fixture(24)
    node.quickTranslateButtonPressed()
    let oldOwner = sgToggleQuickTranslation(context: context, messageId: 24, text: "same", updated: {}, failed: { _ in })
    // This toggle removes the old selection, but is intentionally kept alive.
    check(sgQuickTranslationLanguage(messageId: 24) == nil, "second owner toggle shows original")
    let newOwner = sgToggleQuickTranslation(context: context, messageId: 24, text: "same", updated: {}, failed: { _ in })
    check(sgQuickTranslationLanguage(messageId: 24) == "de", "new same-language owner is selected")
    // Dispose the original Bubble-owned pending request, then both stale handles.
    node.item = nil
    node.quickTranslateDisposableForTestDispose()
    oldOwner.dispose()
    check(sgQuickTranslationLanguage(messageId: 24) == "de", "old cancellation cannot clear newer same-language selector")
    check(registry.count == 1, "only new same-ID request remains")
    newOwner.dispose()
    check(sgQuickTranslationLanguage(messageId: 24) == nil && registry.count == 0, "current owner cancellation clears selector and producer")
    withExtendedLifetime(interaction) {}
}
do {
    let (registry, context, interaction, node) = fixture(25)
    node.quickTranslateButtonPressed()
    let queued = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { registry.fail(); queued.signal() }
    check(queued.wait(timeout: .now() + 2) == .success, "old error queued before same-language replacement")
    let undo = sgToggleQuickTranslation(context: context, messageId: 25, text: "same", updated: {}, failed: { _ in })
    let newOwner = sgToggleQuickTranslation(context: context, messageId: 25, text: "same", updated: {}, failed: { _ in })
    drainMainQueue()
    check(sgQuickTranslationLanguage(messageId: 25) == "de", "queued old failure cannot clear newer token")
    check(interaction.failures == 0, "queued old failure does not report after supersession")
    check(registry.count == 1, "queued stale failure leaves newer producer active")
    undo.dispose(); newOwner.dispose()
}

// Cleanup can synchronously reenter the store/helper; no callout runs under its NSLock.
do {
    let (registry, context, interaction, node) = fixture(26)
    node.quickTranslateButtonPressed()
    var childObservedLanguage: String??
    registry.onDispose = { childObservedLanguage = sgQuickTranslationLanguage(messageId: 26) }
    node.quickTranslateDisposableForTestDispose()
    check(childObservedLanguage != nil && childObservedLanguage! == nil, "selector revoked before reentrant producer cleanup")
    check(registry.count == 0 && interaction.failures == 0, "reentrant cleanup completes without UI failure")
    withExtendedLifetime(context) {}
}
do {
    let (registry, context, interaction, node) = fixture(27)
    node.quickTranslateButtonPressed()
    var reenteredOwner: Disposable?
    interaction.onUpdate = { _ in
        if reenteredOwner == nil {
            reenteredOwner = sgToggleQuickTranslation(context: context, messageId: 27, text: "same", updated: {}, failed: { _ in })
        }
    }
    registry.fail()
    check(reenteredOwner != nil && registry.count == 1, "failure update can start new request outside store lock")
    check(sgQuickTranslationLanguage(messageId: 27) == "de", "old completion cannot clear reentrant newer request")
    reenteredOwner?.dispose()
}

// The helper's initial queued notification must not survive a pending owner's disposal.
do {
    resetSyntheticStore()
    let registry = EngineRegistry()
    let context = AccountContext(registry)
    context.engine.data.values[28] = EngineMessage(id: 28)
    let notificationCount = Atomic<Int>(value: 0)
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        let owner = sgToggleQuickTranslation(context: context, messageId: 28, text: "same", updated: { _ = notificationCount.modify { $0 + 1 } }, failed: { _ in })
        owner.dispose()
        done.signal()
    }
    check(done.wait(timeout: .now() + 2) == .success, "background helper canceled before main queue drains")
    drainMainQueue()
    check(notificationCount.with { $0 } == 0, "pending cancellation suppresses queued initial update")
    check(sgQuickTranslationLanguage(messageId: 28) == nil && registry.count == 0, "queued initial update cannot resurrect selector")
}

// Completed selections in the bounded cache must not retain their former context.
do {
    resetSyntheticStore()
    let registry = EngineRegistry()
    let interaction = ControllerInteraction()
    var context: AccountContext? = AccountContext(registry)
    weak var weakContext = context
    var node: ChatMessageBubbleItemNode? = ChatMessageBubbleItemNode()
    let translated = EngineMessage(id: 29, attributes: [TranslationMessageAttribute(toLang: "de", text: "cached")])
    context!.engine.data.values[29] = translated
    node!.item = ChatMessageItem(context: context!, message: translated, controllerInteraction: interaction)
    node!.quickTranslateButtonPressed()
    context = nil; node = nil
    check(weakContext == nil, "bounded cache completed token does not retain cached request context")
    check(sgQuickTranslationLanguage(messageId: 29) == "de", "cached completed token remains selected without context")
}
do {
    resetSyntheticStore()
    let registry = EngineRegistry()
    let interaction = ControllerInteraction()
    var context: AccountContext? = AccountContext(registry)
    weak var weakContext = context
    var node: ChatMessageBubbleItemNode? = ChatMessageBubbleItemNode()
    context!.engine.data.values[30] = EngineMessage(id: 30)
    node!.item = ChatMessageItem(context: context!, message: EngineMessage(id: 30), controllerInteraction: interaction)
    node!.quickTranslateButtonPressed()
    context!.engine.data.values[30] = EngineMessage(id: 30, attributes: [TranslationMessageAttribute(toLang: "de", text: "done")])
    registry.complete()
    context = nil; node = nil
    check(weakContext == nil, "bounded cache completed token does not retain async request context")
    check(sgQuickTranslationLanguage(messageId: 30) == "de" && registry.count == 0, "async completed token survives with no live producer")
}

// Defensive completion-without-result control: the real EngineData get normally emits once.
do {
    let (registry, context, interaction, node) = fixture(31)
    context.engine.data.emitsValue = false
    node.quickTranslateButtonPressed()
    check(registry.startedIds.isEmpty, "empty current-message stream invokes no translation RPC")
    check(interaction.failures == 1 && interaction.updates == [31, 31], "empty-result completion fails exactly once")
    check(sgQuickTranslationLanguage(messageId: 31) == nil, "empty-result completion clears pending selector")
}

do {
    resetSyntheticStore()
    let registry = EngineRegistry()
    let context = AccountContext(registry)
    context.engine.data.values[32] = EngineMessage(id: 32)
    let oldUpdates = Atomic<Int>(value: 0)
    let ready = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        let old = sgToggleQuickTranslation(context: context, messageId: 32, text: "same", updated: { _ = oldUpdates.modify { $0 + 1 } }, failed: { _ in })
        old.dispose()
        ready.signal()
    }
    check(ready.wait(timeout: .now() + 2) == .success, "old initial update queued and canceled")
    var newUpdates = 0
    let current = sgToggleQuickTranslation(context: context, messageId: 32, text: "same", updated: { newUpdates += 1 }, failed: { _ in })
    drainMainQueue()
    check(oldUpdates.with { $0 } == 0 && newUpdates == 1, "queued old initial update suppressed after same-language reselect")
    check(registry.count == 1 && sgQuickTranslationLanguage(messageId: 32) == "de", "reselected pending request stays active and selected")
    current.dispose()
}

// Deliberately reentrant producer cleanup may attempt an error before the child finishes disposing.
do {
    let (registry, _, interaction, node) = fixture(33)
    node.quickTranslateButtonPressed()
    let stale = registry.heldSubscribers()
    registry.onDispose = { stale.forEach { $0.putError(.generic) } }
    node.quickTranslateDisposableForTestDispose()
    check(interaction.failures == 0 && interaction.updates == [33], "revoked token blocks reentrant child-disposal error")
    check(registry.count == 0 && sgQuickTranslationLanguage(messageId: 33) == nil, "reentrant cancellation clears producer and own selector")
}

// Synthetic update reentry verifies admission safety; real Bubble currently requests layout here.
do {
    let (registry, context, interaction, node) = fixture(34)
    var nested: Disposable?
    interaction.onUpdate = { _ in
        if nested == nil {
            nested = EmptyDisposable
            nested = sgToggleQuickTranslation(context: context, messageId: 34, text: "same", updated: {}, failed: { _ in })
        }
    }
    node.quickTranslateButtonPressed()
    check(registry.startedIds.isEmpty, "initial update reentry revokes request before engine start")
    check(sgQuickTranslationLanguage(messageId: 34) == nil, "initial update reentry keeps original selection")
    nested?.dispose()
}
