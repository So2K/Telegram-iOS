// SuperGram: privacy / profile settings (stream W2-GHOST).
// Keys declared elsewhere and reused as-is: `sgSkipReadReceipts`, `sgStoryGhostMode` (registry, default false),
// Swiftgram `hidePhoneInSettings` (false), `showProfileId` (true), `showDC` (false), `showCreationDate` (true),
// `showRegDate` (false), `confirmCalls` (false), `warnOnStoriesOpen` (false), `showRepostToStoryV2` (true, app group).
// Raw readers (TelegramCore `SuperGramGhostSettings`) use the same key strings and defaults.
import Foundation

private let sgShowJoinedDateStorage = UserDefault<Bool>(key: SGSimpleSettings.sgShowJoinedDateKey, defaultValue: false)

public extension SGSimpleSettings {
    static let sgShowJoinedDateKey = "sgShowJoinedDate"

    /// Registered with `SGSimpleSettings.registerDefaults()` so a raw `UserDefaults.standard` reader in a module
    /// without the SGSimpleSettings dependency sees the same value this property returns.
    static let ghostDefaultValues: [String: Any] = [
        SGSimpleSettings.sgShowJoinedDateKey: false
    ]

    /// Profile row "Joined <chat>" with the date the user joined the group the profile was opened from
    /// (Swiftgram shows it unconditionally; one `channels.getParticipant` request per profile open).
    ///
    /// SuperGram: OFF by default. The lookup is uncached, so every open of the same person's profile from a
    /// channel costs another `channels.getParticipant` — an opt-in cost, not one to pay for a row stock
    /// Telegram does not have (PERF-P2-7).
    var sgShowJoinedDate: Bool {
        get {
            return sgShowJoinedDateStorage.wrappedValue
        }
        set {
            sgShowJoinedDateStorage.wrappedValue = newValue
        }
    }
}
