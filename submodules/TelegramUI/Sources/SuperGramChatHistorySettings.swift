import Foundation

// SuperGram (W2-CHATUI-HISTORY): Swiftgram chat-history toggles read inside TelegramUI.
//
// TelegramUI has no `//Swiftgram/SGSimpleSettings` dependency, so these read the same
// `UserDefaults.standard` keys (and defaults) that `SGSimpleSettings.Keys` declares. Writes happen only
// through `SGSimpleSettings.shared` on the SuperGram settings screen, which stores the value in
// `UserDefaults.standard` immediately, so these reads always see the current value.
// None of the call sites is a per-frame path (controller setup and chat data updates only).
enum SuperGramChatHistorySettings {
    private static func bool(_ key: String, _ defaultValue: Bool) -> Bool {
        return UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    /// `SGSimpleSettings.Keys.disableScrollToNextChannel` (default false): no "pull up to the next unread channel".
    static var disableScrollToNextChannel: Bool {
        return self.bool("disableScrollToNextChannel", false)
    }

    /// `SGSimpleSettings.Keys.disableScrollToNextTopic` (default false): no "pull up to the next unread topic".
    static var disableScrollToNextTopic: Bool {
        return self.bool("disableScrollToNextTopic", false)
    }

    /// `SGSimpleSettings.Keys.disableSnapDeletionEffect` (default false): no "dust" animation when messages are deleted.
    static var disableSnapDeletionEffect: Bool {
        return self.bool("disableSnapDeletionEffect", false)
    }
}
