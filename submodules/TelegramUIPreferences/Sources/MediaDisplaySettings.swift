import Foundation
import TelegramCore
import SwiftSignalKit

public struct MediaDisplaySettings: Codable, Equatable {
    public let showNextMediaOnTap: Bool
    public let playVideoInBackground: Bool
    public let performanceMode: Bool
    public let localVoiceTranscription: Bool
    public let showVoiceTranscriptionButton: Bool
    public let voiceTranscriptionOnDeviceOnly: Bool
    public let voiceTranscriptionLocale: String
    
    // SuperGram: "performance mode" turns off `loopEmoji` and `fullTranslucency` in the energy-usage settings.
    // Those are not invisible micro-optimisations: `loopEmoji` stops animated/premium emoji and reaction
    // animations from looping, and `fullTranslucency` disables spoiler (invisible-ink) animations, animated chat
    // backgrounds, reaction fly-to-panel effects, shimmering media placeholders and chat-list reveal animations —
    // including inside the InstantPage V2 renderer used for this fork's rich-text messages. Shipping that on by
    // default made a stock install look visibly degraded versus upstream, so it is opt-in now.
    public static var defaultSettings: MediaDisplaySettings {
        return MediaDisplaySettings(
            showNextMediaOnTap: true,
            playVideoInBackground: false,
            performanceMode: false,
            localVoiceTranscription: true,
            showVoiceTranscriptionButton: true,
            voiceTranscriptionOnDeviceOnly: true,
            voiceTranscriptionLocale: "auto"
        )
    }
    
    public init(
        showNextMediaOnTap: Bool,
        playVideoInBackground: Bool = false,
        performanceMode: Bool = false,
        localVoiceTranscription: Bool = true,
        showVoiceTranscriptionButton: Bool = true,
        voiceTranscriptionOnDeviceOnly: Bool = true,
        voiceTranscriptionLocale: String = "auto"
    ) {
        self.showNextMediaOnTap = showNextMediaOnTap
        self.playVideoInBackground = playVideoInBackground
        self.performanceMode = performanceMode
        self.localVoiceTranscription = localVoiceTranscription
        self.showVoiceTranscriptionButton = showVoiceTranscriptionButton
        self.voiceTranscriptionOnDeviceOnly = voiceTranscriptionOnDeviceOnly
        self.voiceTranscriptionLocale = voiceTranscriptionLocale
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.showNextMediaOnTap = (try container.decode(Int32.self, forKey: "showNextMediaOnTap")) != 0
        self.playVideoInBackground = (try container.decodeIfPresent(Int32.self, forKey: "playVideoInBackground") ?? 0) != 0
        // SuperGram: builds up to 10020 stored `performanceMode: 1` without the user ever choosing it (it was the
        // default). Version 2 resets that implicit value to off once, so everybody gets the upstream look back and
        // can opt in again from Settings -> SuperGram -> App.
        let performanceModeVersion = try container.decodeIfPresent(Int32.self, forKey: "performanceModeVersion") ?? 1
        if performanceModeVersion >= 2 {
            self.performanceMode = (try container.decodeIfPresent(Int32.self, forKey: "performanceMode") ?? 0) != 0
        } else {
            self.performanceMode = false
        }
        self.localVoiceTranscription = (try container.decodeIfPresent(Int32.self, forKey: "localVoiceTranscription") ?? 1) != 0
        self.showVoiceTranscriptionButton = (try container.decodeIfPresent(Int32.self, forKey: "showVoiceTranscriptionButton") ?? 1) != 0
        let voiceTranscriptionSettingsVersion = try container.decodeIfPresent(Int32.self, forKey: "voiceTranscriptionSettingsVersion") ?? 1
        // Earlier versions opted everybody into Apple's server recognition implicitly. Reset that
        // default once; subsequent explicit changes to the Offline Only switch are preserved.
        if voiceTranscriptionSettingsVersion >= 3 {
            self.voiceTranscriptionOnDeviceOnly = (try container.decodeIfPresent(Int32.self, forKey: "voiceTranscriptionOnDeviceOnly") ?? 1) != 0
        } else {
            self.voiceTranscriptionOnDeviceOnly = true
        }
        self.voiceTranscriptionLocale = try container.decodeIfPresent(String.self, forKey: "voiceTranscriptionLocale") ?? "auto"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode((self.showNextMediaOnTap ? 1 : 0) as Int32, forKey: "showNextMediaOnTap")
        try container.encode((self.playVideoInBackground ? 1 : 0) as Int32, forKey: "playVideoInBackground")
        try container.encode((self.performanceMode ? 1 : 0) as Int32, forKey: "performanceMode")
        try container.encode(2 as Int32, forKey: "performanceModeVersion")
        try container.encode((self.localVoiceTranscription ? 1 : 0) as Int32, forKey: "localVoiceTranscription")
        try container.encode((self.showVoiceTranscriptionButton ? 1 : 0) as Int32, forKey: "showVoiceTranscriptionButton")
        try container.encode((self.voiceTranscriptionOnDeviceOnly ? 1 : 0) as Int32, forKey: "voiceTranscriptionOnDeviceOnly")
        try container.encode(3 as Int32, forKey: "voiceTranscriptionSettingsVersion")
        try container.encode(self.voiceTranscriptionLocale, forKey: "voiceTranscriptionLocale")
    }
    
    public static func ==(lhs: MediaDisplaySettings, rhs: MediaDisplaySettings) -> Bool {
        return lhs.showNextMediaOnTap == rhs.showNextMediaOnTap
            && lhs.playVideoInBackground == rhs.playVideoInBackground
            && lhs.performanceMode == rhs.performanceMode
            && lhs.localVoiceTranscription == rhs.localVoiceTranscription
            && lhs.showVoiceTranscriptionButton == rhs.showVoiceTranscriptionButton
            && lhs.voiceTranscriptionOnDeviceOnly == rhs.voiceTranscriptionOnDeviceOnly
            && lhs.voiceTranscriptionLocale == rhs.voiceTranscriptionLocale
    }
    
    public func withUpdatedShowNextMediaOnTap(_ showNextMediaOnTap: Bool) -> MediaDisplaySettings {
        return MediaDisplaySettings(showNextMediaOnTap: showNextMediaOnTap, playVideoInBackground: self.playVideoInBackground, performanceMode: self.performanceMode, localVoiceTranscription: self.localVoiceTranscription, showVoiceTranscriptionButton: self.showVoiceTranscriptionButton, voiceTranscriptionOnDeviceOnly: self.voiceTranscriptionOnDeviceOnly, voiceTranscriptionLocale: self.voiceTranscriptionLocale)
    }

    public func withUpdatedPlayVideoInBackground(_ playVideoInBackground: Bool) -> MediaDisplaySettings {
        return MediaDisplaySettings(showNextMediaOnTap: self.showNextMediaOnTap, playVideoInBackground: playVideoInBackground, performanceMode: self.performanceMode, localVoiceTranscription: self.localVoiceTranscription, showVoiceTranscriptionButton: self.showVoiceTranscriptionButton, voiceTranscriptionOnDeviceOnly: self.voiceTranscriptionOnDeviceOnly, voiceTranscriptionLocale: self.voiceTranscriptionLocale)
    }

    public func withUpdatedPerformanceMode(_ performanceMode: Bool) -> MediaDisplaySettings {
        return MediaDisplaySettings(showNextMediaOnTap: self.showNextMediaOnTap, playVideoInBackground: self.playVideoInBackground, performanceMode: performanceMode, localVoiceTranscription: self.localVoiceTranscription, showVoiceTranscriptionButton: self.showVoiceTranscriptionButton, voiceTranscriptionOnDeviceOnly: self.voiceTranscriptionOnDeviceOnly, voiceTranscriptionLocale: self.voiceTranscriptionLocale)
    }

    public func withUpdatedLocalVoiceTranscription(_ localVoiceTranscription: Bool) -> MediaDisplaySettings {
        return MediaDisplaySettings(showNextMediaOnTap: self.showNextMediaOnTap, playVideoInBackground: self.playVideoInBackground, performanceMode: self.performanceMode, localVoiceTranscription: localVoiceTranscription, showVoiceTranscriptionButton: self.showVoiceTranscriptionButton, voiceTranscriptionOnDeviceOnly: self.voiceTranscriptionOnDeviceOnly, voiceTranscriptionLocale: self.voiceTranscriptionLocale)
    }

    public func withUpdatedShowVoiceTranscriptionButton(_ showVoiceTranscriptionButton: Bool) -> MediaDisplaySettings {
        return MediaDisplaySettings(showNextMediaOnTap: self.showNextMediaOnTap, playVideoInBackground: self.playVideoInBackground, performanceMode: self.performanceMode, localVoiceTranscription: self.localVoiceTranscription, showVoiceTranscriptionButton: showVoiceTranscriptionButton, voiceTranscriptionOnDeviceOnly: self.voiceTranscriptionOnDeviceOnly, voiceTranscriptionLocale: self.voiceTranscriptionLocale)
    }

    public func withUpdatedVoiceTranscriptionOnDeviceOnly(_ voiceTranscriptionOnDeviceOnly: Bool) -> MediaDisplaySettings {
        return MediaDisplaySettings(showNextMediaOnTap: self.showNextMediaOnTap, playVideoInBackground: self.playVideoInBackground, performanceMode: self.performanceMode, localVoiceTranscription: self.localVoiceTranscription, showVoiceTranscriptionButton: self.showVoiceTranscriptionButton, voiceTranscriptionOnDeviceOnly: voiceTranscriptionOnDeviceOnly, voiceTranscriptionLocale: self.voiceTranscriptionLocale)
    }

    public func withUpdatedVoiceTranscriptionLocale(_ voiceTranscriptionLocale: String) -> MediaDisplaySettings {
        return MediaDisplaySettings(showNextMediaOnTap: self.showNextMediaOnTap, playVideoInBackground: self.playVideoInBackground, performanceMode: self.performanceMode, localVoiceTranscription: self.localVoiceTranscription, showVoiceTranscriptionButton: self.showVoiceTranscriptionButton, voiceTranscriptionOnDeviceOnly: self.voiceTranscriptionOnDeviceOnly, voiceTranscriptionLocale: voiceTranscriptionLocale)
    }
}

public func updateMediaDisplaySettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (MediaDisplaySettings) -> MediaDisplaySettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.mediaDisplaySettings, { entry in
            let currentSettings: MediaDisplaySettings
            if let entry = entry?.get(MediaDisplaySettings.self) {
                currentSettings = entry
            } else {
                currentSettings = MediaDisplaySettings.defaultSettings
            }
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}
