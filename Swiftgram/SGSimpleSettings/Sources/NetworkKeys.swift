// SuperGram: media quality, browser, network and storage settings (stream W2-NET).
//
// Keys declared in `SGSimpleSettings.Keys` and reused as-is by this stream:
//   `outgoingPhotoQuality` (Int32, 70)      — outgoing JPEG quality, see `outgoingPhotoQualityFactor` below
//   `sendLargePhotos` (false)               — start the media editor in "HD photo" mode
//   `localDNSForProxyHost` (false)          — resolve proxy / MTProto hostnames with the system resolver
//   `disableGalleryCamera` (false)          — no live camera tile in the attachment picker
//   `disableGalleryCameraPreview` (false)   — keep the tile, never start the capture session
//
// `localDNSForProxyHost` also has a raw reader in `MTTcpConnection.m` (MtProtoKit cannot depend on this
// module); it uses the same key string and the same default.
import Foundation

private let sgOpenLinksInAppSafariStorage = UserDefault<Bool>(key: SGSimpleSettings.sgOpenLinksInAppSafariKey, defaultValue: false)
private let sgMusicPlaybackRateButtonStorage = UserDefault<Bool>(key: SGSimpleSettings.sgMusicPlaybackRateButtonKey, defaultValue: true)
private let sgExtraMutePresetsStorage = UserDefault<Bool>(key: SGSimpleSettings.sgExtraMutePresetsKey, defaultValue: true)
private let sgShowSessionIPStorage = UserDefault<Bool>(key: SGSimpleSettings.sgShowSessionIPKey, defaultValue: true)
private let sgAggressiveCachePresetsStorage = UserDefault<Bool>(key: SGSimpleSettings.sgAggressiveCachePresetsKey, defaultValue: true)

public extension SGSimpleSettings {
    static let sgOpenLinksInAppSafariKey = "sgOpenLinksInAppSafari"
    static let sgMusicPlaybackRateButtonKey = "sgMusicPlaybackRateButton"
    static let sgExtraMutePresetsKey = "sgExtraMutePresets"
    static let sgShowSessionIPKey = "sgShowSessionIP"
    static let sgAggressiveCachePresetsKey = "sgAggressiveCachePresets"

    /// Registered by `SGSimpleSettings.registerDefaults()` so a raw `UserDefaults.standard` reader in a module
    /// without the SGSimpleSettings dependency sees the same value these properties return.
    static let networkDefaultValues: [String: Any] = [
        SGSimpleSettings.sgOpenLinksInAppSafariKey: false,
        SGSimpleSettings.sgMusicPlaybackRateButtonKey: true,
        SGSimpleSettings.sgExtraMutePresetsKey: true,
        SGSimpleSettings.sgShowSessionIPKey: true,
        SGSimpleSettings.sgAggressiveCachePresetsKey: true
    ]

    /// SGM-F4. Open a link that would go to an external browser in an in-app `SFSafariViewController` instead.
    /// OFF by default, matching stock Telegram (Swiftgram exposes the same behaviour as an extra "In-App Safari"
    /// row of the standard "Open Links In" screen; here it is a single SuperGram switch so there is one source
    /// of truth and the stock screen is left untouched).
    var sgOpenLinksInAppSafari: Bool {
        get {
            return sgOpenLinksInAppSafariStorage.wrappedValue
        }
        set {
            sgOpenLinksInAppSafariStorage.wrappedValue = newValue
        }
    }

    /// SGP-10. Show the playback-rate button in the music mini-player for every track, not only for tracks
    /// longer than 20 minutes. ON by default (Swiftgram does it unconditionally).
    var sgMusicPlaybackRateButton: Bool {
        get {
            return sgMusicPlaybackRateButtonStorage.wrappedValue
        }
        set {
            sgMusicPlaybackRateButtonStorage.wrappedValue = newValue
        }
    }

    /// SGP-10. Add 4 hours / 8 hours / 1 day to the "Mute for…" presets. ON by default (Swiftgram does it
    /// unconditionally).
    var sgExtraMutePresets: Bool {
        get {
            return sgExtraMutePresetsStorage.wrappedValue
        }
        set {
            sgExtraMutePresetsStorage.wrappedValue = newValue
        }
    }

    /// SGP-10. Show the IP address of an active session in the session sheet (Telegram hides it for sessions
    /// of the current app family and shows only the country). ON by default (Swiftgram does it unconditionally).
    var sgShowSessionIP: Bool {
        get {
            return sgShowSessionIPStorage.wrappedValue
        }
        set {
            sgShowSessionIPStorage.wrappedValue = newValue
        }
    }

    /// SGM-F15 / SGP-04. Offer the aggressive 1 GB cache cap and 1-hour keep-media presets in Storage Usage.
    /// ON by default, but this only *offers* the options — nothing changes until the user picks one. Per CRIT-13
    /// they must never become the defaults: a 1-hour retention deletes partially downloaded videos, so playback
    /// restarts from zero.
    var sgAggressiveCachePresets: Bool {
        get {
            return sgAggressiveCachePresetsStorage.wrappedValue
        }
        set {
            sgAggressiveCachePresetsStorage.wrappedValue = newValue
        }
    }

    /// SGM-F5. `outgoingPhotoQuality` as a 0…1 JPEG compression factor.
    ///
    /// Clamped to 30…100 before dividing: the stored value comes from a slider, and a value near zero would make
    /// every outgoing photo and thumbnail unusable. Stock Telegram used the constant 0.6/0.7 at these call sites,
    /// so the default of 70 keeps thumbnails byte-comparable with upstream.
    var outgoingPhotoQualityFactor: Float {
        return Float(max(30, min(100, self.outgoingPhotoQuality))) / 100.0
    }
}
