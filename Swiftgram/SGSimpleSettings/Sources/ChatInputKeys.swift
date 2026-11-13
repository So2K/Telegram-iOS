// SuperGram: chat input panel and keyboard settings (stream W2-CHATUI-INPUT).
//
// Swiftgram keys declared in `SGSimpleSettings.Keys` and reused as-is by this stream:
//   `hideRecordingButton` (false)     — no voice/round-video button, the send button is always visible
//   `sendWithReturnKey` (false)       — the keyboard return key sends the message
//   `disableSendAsButton` (false)     — no "send as" avatar in the input panel
//   `hideChannelBottomButton` (true)  — no Mute bottom panel in channels the user already follows
//   `forceEmojiTab` (false)           — the media keyboard always opens on the Emoji tab
//   `defaultEmojisFirst` (false)      — standard emoji group right after "recent", before premium packs
//   `inputToolbar` (false)            — formatting panel above the keyboard (Swiftgram gates it behind Pro)
//   `stickerSize` (Int32, 100)        — sticker display size, in percent
//   `stickerTimestamp` (true)         — time/status pill drawn on top of stickers
import Foundation

private let sgHideRecordingTooltipStorage = UserDefault<Bool>(key: SGSimpleSettings.sgHideRecordingTooltipKey, defaultValue: true)

public extension SGSimpleSettings {
    static let sgHideRecordingTooltipKey = "sgHideRecordingTooltip"

    /// Registered with `SGSimpleSettings.registerDefaults()` so a raw `UserDefaults.standard` reader in a module
    /// without the SGSimpleSettings dependency sees the same value this property returns.
    static let chatInputDefaultValues: [String: Any] = [
        SGSimpleSettings.sgHideRecordingTooltipKey: true
    ]

    /// Suppresses the "Hold to record audio / video" tooltip that stock Telegram shows when the media button is
    /// tapped instead of held, and after every switch between voice and round-video mode.
    ///
    /// Default ON (suppressed), which is Swiftgram's behaviour — Swiftgram returns from
    /// `displayMediaRecordingTooltip()` unconditionally and has no key for it. Turning this OFF restores the
    /// stock hint.
    var sgHideRecordingTooltip: Bool {
        get {
            return sgHideRecordingTooltipStorage.wrappedValue
        }
        set {
            sgHideRecordingTooltipStorage.wrappedValue = newValue
        }
    }
}
