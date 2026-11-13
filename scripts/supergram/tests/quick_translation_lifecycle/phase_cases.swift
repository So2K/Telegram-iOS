// These run only when the real typed Request store is present; the before/V1 code
// lacks this API. General/helper/renderer controls are shared by every version.
do {
    let store = SGQuickTranslationStore()
    guard case let .translation(old) = store.toggle(messageId: 40, language: "de") else { fatalError() }
    guard case .original = store.toggle(messageId: 40, language: "de") else { fatalError() }
    guard case let .translation(new) = store.toggle(messageId: 40, language: "de") else { fatalError() }
    check(!store.complete(old, messageId: 40), "stale success cannot complete replacement token")
    check(!store.fail(old, messageId: 40), "stale failure cannot clear replacement token")
    store.cancel(old, messageId: 40)
    check(store.isSelected(new, messageId: 40), "stale cancel leaves same-language replacement selected")
    check(store.complete(new, messageId: 40), "replacement success completes current token")
    store.cancel(new, messageId: 40)
    check(store.language(messageId: 40) == "de", "completed token cancellation retains display selector")
}
do {
    let store = SGQuickTranslationStore()
    guard case let .translation(old) = store.toggle(messageId: 50, language: "de") else { fatalError() }
    for id in 51...562 { _ = store.toggle(messageId: Int64(id), language: "de") }
    check(store.language(messageId: 50) == nil, "512-entry bounded cache evicts oldest selection")
    guard case let .translation(new) = store.toggle(messageId: 50, language: "de") else { fatalError() }
    check(!store.complete(old, messageId: 50) && !store.fail(old, messageId: 50), "evicted old token cannot complete or fail reselected same ID")
    store.cancel(old, messageId: 50)
    check(store.isSelected(new, messageId: 50), "evicted old cancellation cannot clear reselected token")
    let selectedCount = (50...562).filter { store.language(messageId: Int64($0)) != nil }.count
    check(selectedCount <= 512, "language cache remains bounded after reselect")
}
do {
    // Cache eviction removes display selection but deliberately does not cancel the
    // node-owned producer. Normal completion or owner disposal tears it down.
    let (registry, _, interaction, node) = fixture(60)
    node.quickTranslateButtonPressed()
    for id in 61...572 { _ = sgQuickTranslationStore.toggle(messageId: Int64(id), language: "de") }
    check(sgQuickTranslationLanguage(messageId: 60) == nil && registry.count == 1, "eviction preserves node-owned request until cleanup")
    registry.fail()
    check(registry.count == 0 && interaction.failures == 0, "evicted request completion cleans producer without stale failure UI")
}
for iteration in 0..<40 {
    let store = SGQuickTranslationStore()
    let id = Int64(700 + iteration)
    guard case let .translation(request) = store.toggle(messageId: id, language: "de") else { fatalError() }
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global().async { store.complete(request, messageId: id); group.leave() }
    group.enter()
    DispatchQueue.global().async { store.cancel(request, messageId: id); group.leave() }
    check(group.wait(timeout: .now() + 2) == .success, "concurrent complete/cancel settles without deadlock \(iteration)")
    // Either success retained the selector, or cancellation removed it. No pending
    // token remains; a second cancel cannot turn completed back into pending.
    store.cancel(request, messageId: id)
    check(store.language(messageId: id) == nil || store.isSelected(request, messageId: id), "concurrent terminal policy preserves valid selected state \(iteration)")
}
