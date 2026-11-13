// SuperGram: context menu and message selection settings (stream W2-CONTEXT).
// Swiftgram keys reused as-is: `contextShowSaveToCloud`, `contextShowHideForwardName`, `contextShowSelectFromUser`,
// `contextShowRestrict`, `contextShowReport`, `contextShowReply`, `contextShowPin`, `contextShowSaveMedia`,
// `contextShowMessageReplies` (all default true: ON = item in the main menu, OFF = item moves to the "SuperGram"
// submenu) and `contextShowJson` (default false: the JSON item is shown only when it is ON).
// Raw readers (TelegramUI) use the same key strings and defaults.
import Foundation

private let sgSelectionBarSaveToCloudStorage = UserDefault<Bool>(key: SGSimpleSettings.sgSelectionBarSaveToCloudKey, defaultValue: true)
private let sgSelectionBarForwardHideNamesStorage = UserDefault<Bool>(key: SGSimpleSettings.sgSelectionBarForwardHideNamesKey, defaultValue: true)

public extension SGSimpleSettings {
    static let sgSelectionBarSaveToCloudKey = "sgSelectionBarSaveToCloud"
    static let sgSelectionBarForwardHideNamesKey = "sgSelectionBarForwardHideNames"

    /// Registered with `SGSimpleSettings.registerDefaults()` so a raw `UserDefaults.standard` reader in a module
    /// without the SGSimpleSettings dependency sees the same values these properties return.
    static let contextDefaultValues: [String: Any] = [
        SGSimpleSettings.sgSelectionBarSaveToCloudKey: true,
        SGSimpleSettings.sgSelectionBarForwardHideNamesKey: true
    ]

    /// "Save to Cloud" (forward to Saved Messages) button in the message selection bar (Swiftgram chat-07).
    var sgSelectionBarSaveToCloud: Bool {
        get {
            return sgSelectionBarSaveToCloudStorage.wrappedValue
        }
        set {
            sgSelectionBarSaveToCloudStorage.wrappedValue = newValue
        }
    }

    /// "Forward without sender names" button in the message selection bar (Swiftgram chat-07).
    var sgSelectionBarForwardHideNames: Bool {
        get {
            return sgSelectionBarForwardHideNamesStorage.wrappedValue
        }
        set {
            sgSelectionBarForwardHideNamesStorage.wrappedValue = newValue
        }
    }
}
