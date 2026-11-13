// MARK: Swiftgram
// SuperGram (W2A-20, W1AUD-10): cached snapshot of the SuperGram chat-list density settings.
//
// `ChatListItemNode.setupItem` and `ChatListItemNode.asyncLayout` both need `compactChatList`,
// `SGCompactMessagePreviewLayout.isEnabled()` and the avatar scale divisor derived from them. Both run on hot
// paths — `setupItem` once per node set-up, `asyncLayout` once per layout closure, i.e. once per visible row per
// list update — and each read went all the way through `SGSimpleSettings` (property-wrapper lock + generation
// lock) and re-parsed the `chatListLines` raw string into its enum.
//
// The values only change when something writes to UserDefaults, so they are computed once and reused until a
// `UserDefaults.didChangeNotification` arrives. That also means the two call sites see the same snapshot object
// rather than two independently sampled values: a mismatch would let a row lay out with one avatar divisor while
// the avatar image is rendered for another.
//
// The notification handler deliberately does nothing but drop the cache. `UserDefaults` posts this notification
// synchronously from `set` / `register(defaults:)`, so reading a setting here could re-enter
// `SGSimpleSettings.shared` while it is still being initialised (see the comments in `SimpleSettings.swift` and
// `UserDefaultsWrapper.swift`).

import Foundation
import CoreGraphics
import SGSimpleSettings

struct SuperGramChatListLayoutSettings {
    let compactChatList: Bool
    let compactMessagePreview: Bool
    let avatarScaleDivisor: CGFloat

    private static let lock = NSLock()
    private static var cachedValue: SuperGramChatListLayoutSettings?
    private static var cachedGeneration: Int = -1
    private static var generation: Int = 0
    private static var observer: NSObjectProtocol?

    /// The current settings, recomputed only after something writes to UserDefaults.
    ///
    /// The value read outside the lock is tagged with the generation that was current *before* the read, so a write
    /// that lands while `SGSimpleSettings` is being consulted invalidates the result instead of being cached over.
    static var current: SuperGramChatListLayoutSettings {
        SuperGramChatListLayoutSettings.lock.lock()
        if SuperGramChatListLayoutSettings.observer == nil {
            SuperGramChatListLayoutSettings.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil, using: { _ in
                SuperGramChatListLayoutSettings.lock.lock()
                SuperGramChatListLayoutSettings.generation &+= 1
                SuperGramChatListLayoutSettings.lock.unlock()
            })
        }
        let generation = SuperGramChatListLayoutSettings.generation
        if let cachedValue = SuperGramChatListLayoutSettings.cachedValue, SuperGramChatListLayoutSettings.cachedGeneration == generation {
            SuperGramChatListLayoutSettings.lock.unlock()
            return cachedValue
        }
        SuperGramChatListLayoutSettings.lock.unlock()

        // Read outside of the lock: these go through SGSimpleSettings, which takes locks of its own, and
        // `UserDefaults` can post `didChangeNotification` synchronously to observers that read settings.
        let compactChatList = SGSimpleSettings.shared.compactChatList
        let compactMessagePreview = SGCompactMessagePreviewLayout.isEnabled()
        let value = SuperGramChatListLayoutSettings(
            compactChatList: compactChatList,
            compactMessagePreview: compactMessagePreview,
            avatarScaleDivisor: SGCompactMessagePreviewLayout.avatarScaleDivisor(compactChatList: compactChatList, compactMessagePreview: compactMessagePreview)
        )

        SuperGramChatListLayoutSettings.lock.lock()
        SuperGramChatListLayoutSettings.cachedValue = value
        SuperGramChatListLayoutSettings.cachedGeneration = generation
        SuperGramChatListLayoutSettings.lock.unlock()

        return value
    }
}
