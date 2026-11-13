// SuperGram: voice-to-text (hooks: W1-TRANSCRIBE). Storage stays in MediaDisplaySettings
// (moved here from DataAndStorageSettingsController, INFRA-10). Swiftgram's `transcriptionBackend`
// selector is intentionally not shown: local transcription is `localVoiceTranscription`.
import Foundation
import SwiftSignalKit
import TelegramUIPreferences
import AccountContext
import SGItemListUI
import SGStrings

enum SuperGramTranscriptionSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .transcription

    private static let localSetting = "transcription.local"
    private static let showButtonSetting = "transcription.showButton"
    private static let onDeviceOnlySetting = "transcription.onDeviceOnly"
    private static let languageSetting = "transcription.language"

    /// Recognition locales offered in the picker. "auto" lets the transcriber pick the language.
    static let locales: [String] = ["auto", "ru-RU", "en-US", "kk-KZ", "uk-UA", "de-DE", "es-ES"]

    static func localeTitle(_ locale: String, lang: String) -> String {
        if self.locales.contains(locale) {
            return i18n("SuperGram.Transcription.Language.\(locale)", lang)
        }
        return locale
    }

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        let section = SuperGramSettingsSection(self.group)
        let settings = state.mediaDisplaySettings
        var entries: [SuperGramSettingsEntry] = []
        entries.append(sgHeader(id, section, sgString("SuperGram.Transcription.Header", state)))
        entries.append(sgCustomToggle(id, section, self.localSetting, value: settings.localVoiceTranscription, text: sgString("SuperGram.Transcription.Local", state)))
        entries.append(sgCustomToggle(id, section, self.showButtonSetting, value: settings.showVoiceTranscriptionButton, text: sgString("SuperGram.Transcription.ShowButton", state)))
        if settings.localVoiceTranscription {
            entries.append(sgCustomToggle(id, section, self.onDeviceOnlySetting, value: settings.voiceTranscriptionOnDeviceOnly, text: sgString("SuperGram.Transcription.OnDeviceOnly", state)))
            entries.append(.oneFromManySelector(id: id.count, section: section, settingName: self.languageSetting, text: sgString("SuperGram.Transcription.Language", state), value: self.localeTitle(settings.voiceTranscriptionLocale, lang: state.lang), enabled: true))
        } else {
            id.increment(2)
        }
        entries.append(sgNotice(id, section, sgString("SuperGram.Transcription.Notice", state)))
        return entries
    }

    static func setBoolValue(_ setting: String, value: Bool, actions: SuperGramSettingsActions) -> Bool {
        let accountManager = actions.context.sharedContext.accountManager
        switch setting {
        case self.localSetting:
            let _ = updateMediaDisplaySettingsInteractively(accountManager: accountManager, {
                $0.withUpdatedLocalVoiceTranscription(value)
            }).start()
        case self.showButtonSetting:
            let _ = updateMediaDisplaySettingsInteractively(accountManager: accountManager, {
                $0.withUpdatedShowVoiceTranscriptionButton(value)
            }).start()
        case self.onDeviceOnlySetting:
            let _ = updateMediaDisplaySettingsInteractively(accountManager: accountManager, {
                $0.withUpdatedVoiceTranscriptionOnDeviceOnly(value)
            }).start()
        default:
            return false
        }
        return true
    }

    static func setOneFromManyValue(_ setting: String, actions: SuperGramSettingsActions) -> Bool {
        guard setting == self.languageSetting else {
            return false
        }
        let context = actions.context
        let lang = actions.presentationData.strings.baseLanguageCode
        let currentLocale = context.sharedContext.currentMediaDisplaySettings.with { $0 }.voiceTranscriptionLocale
        let options = self.locales.map { locale -> (title: String, isSelected: Bool, action: () -> Void) in
            return (title: self.localeTitle(locale, lang: lang), isSelected: locale == currentLocale, action: {
                let _ = updateMediaDisplaySettingsInteractively(accountManager: context.sharedContext.accountManager, {
                    $0.withUpdatedVoiceTranscriptionLocale(locale)
                }).start()
            })
        }
        actions.presentOptions(options)
        return true
    }
}
