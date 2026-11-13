// SuperGram: translation settings (stream W2-TRANSLATE).
// Swiftgram keys reused as-is: `quickTranslateButton` (default false), `outgoingLanguageTranslation`
// (per-chat target language) and `translationBackend` ("default" = Telegram server, "system" = on-device
// Apple Translation; the Swiftgram "gtranslate" value is never offered and is treated as "default").
import Foundation

private let sgTranslateChatsWithoutPremiumStorage = UserDefault<Bool>(key: SGSimpleSettings.sgTranslateChatsWithoutPremiumKey, defaultValue: true)
private let sgOutgoingTranslationStorage = UserDefault<Bool>(key: SGSimpleSettings.sgOutgoingTranslationKey, defaultValue: false)

public extension SGSimpleSettings {
    static let sgTranslateChatsWithoutPremiumKey = "sgTranslateChatsWithoutPremium"
    static let sgOutgoingTranslationKey = "sgOutgoingTranslation"

    /// Registered with `SGSimpleSettings.registerDefaults()` so a raw `UserDefaults.standard` reader in a module
    /// without the SGSimpleSettings dependency sees the same values these properties return.
    static let translateDefaultValues: [String: Any] = [
        SGSimpleSettings.sgTranslateChatsWithoutPremiumKey: true,
        SGSimpleSettings.sgOutgoingTranslationKey: false
    ]

    /// "Translate Entire Chats" without Telegram Premium (removes the client-side Premium gate; the server may still refuse).
    var sgTranslateChatsWithoutPremium: Bool {
        get {
            return sgTranslateChatsWithoutPremiumStorage.wrappedValue
        }
        set {
            sgTranslateChatsWithoutPremiumStorage.wrappedValue = newValue
        }
    }

    /// "Translate to …" / "Change Language" items in the long-press Send menu (Swiftgram outgoing translation).
    var sgOutgoingTranslation: Bool {
        get {
            return sgOutgoingTranslationStorage.wrappedValue
        }
        set {
            sgOutgoingTranslationStorage.wrappedValue = newValue
        }
    }

    /// True when chat translation should run on-device (Apple Translation, iOS 18+) instead of the Telegram server.
    var sgPrefersOnDeviceTranslation: Bool {
        return self.translationBackendEnum == .system
    }
}
