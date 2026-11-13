import Foundation
import AppBundle

// SuperGram (W2-CONTEXT): Swiftgram message context menu settings and strings read inside TelegramUI.
//
// TelegramUI has no `//Swiftgram/SGSimpleSettings` / `//Swiftgram/SGStrings` dependency, so these read the same
// `UserDefaults.standard` keys (and defaults) that `SGSimpleSettings.Keys` declares, and the bundled
// `SGLocalizable.strings` table. Writes happen only through `SGSimpleSettings.shared` on the SuperGram settings
// screen, which stores the value in `UserDefaults.standard` immediately. All reads happen when a context menu is built.
enum SuperGramContextMenuSettings {
    private static func bool(_ key: String, _ defaultValue: Bool) -> Bool {
        return UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }

    /// `sgAllowSaveProtectedContent` (default true): Copy / Save / Save to Files for protected (noforwards) messages.
    /// Never applies to secret chats or secret (view-once / short TTL) media; forwarding stays server-restricted.
    static var allowSaveProtectedContent: Bool {
        return self.bool("sgAllowSaveProtectedContent", true)
    }

    /// Swiftgram `contextShow*` keys (default true): ON = item in the main menu, OFF = item in the "SuperGram" submenu.
    static var showSaveToCloud: Bool {
        return self.bool("contextShowSaveToCloud", true)
    }

    static var showHideForwardName: Bool {
        return self.bool("contextShowHideForwardName", true)
    }

    static var showSelectFromUser: Bool {
        return self.bool("contextShowSelectFromUser", true)
    }

    static var showRestrict: Bool {
        return self.bool("contextShowRestrict", true)
    }

    static var showReport: Bool {
        return self.bool("contextShowReport", true)
    }

    static var showReply: Bool {
        return self.bool("contextShowReply", true)
    }

    static var showPin: Bool {
        return self.bool("contextShowPin", true)
    }

    static var showSaveMedia: Bool {
        return self.bool("contextShowSaveMedia", true)
    }

    static var showMessageReplies: Bool {
        return self.bool("contextShowMessageReplies", true)
    }

    /// Swiftgram `contextShowJson` (default false). SuperGram shows the JSON item only when this is ON.
    static var showJson: Bool {
        return self.bool("contextShowJson", false)
    }
}

/// Localized string from the bundled `SGLocalizable.strings` (en/ru; `be` falls back to `ru`, everything else to `en`).
/// Mirrors `SGLocalizationManager.localizedString` for the few Swiftgram strings used by the message context menu.
func superGramContextMenuString(_ key: String, _ languageCode: String) -> String {
    return SuperGramContextMenuStrings.shared.string(key, languageCode)
}

private final class SuperGramContextMenuStrings {
    static let shared = SuperGramContextMenuStrings()

    private let lock = NSLock()
    private var tables: [String: [String: String]] = [:]

    func string(_ key: String, _ languageCode: String) -> String {
        var locale = languageCode.lowercased()
        if locale.hasSuffix("-raw") {
            locale = String(locale.dropLast("-raw".count))
        }
        var candidates: [String] = [locale]
        if locale == "be" {
            candidates.append("ru")
        }
        candidates.append("en")
        for candidate in candidates {
            if let value = self.table(candidate)[key], !value.isEmpty {
                return value
            }
        }
        return key
    }

    private func table(_ locale: String) -> [String: String] {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        if let current = self.tables[locale] {
            return current
        }
        var result: [String: String] = [:]
        if let path = getAppBundle().path(forResource: "SGLocalizable", ofType: "strings", inDirectory: nil, forLocalization: locale), let dictionary = NSDictionary(contentsOf: URL(fileURLWithPath: path)) as? [String: String] {
            result = dictionary
        }
        self.tables[locale] = result
        return result
    }
}
