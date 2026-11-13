// SuperGram: translation (hooks: W2-TRANSLATE, TranslateUI / TranslateHeaderPanelComponent / send menu).
// Translation goes through Telegram's messages.translateText or on-device Apple Translation (iOS 18+).
// Swiftgram's Google Translate backend ("gtranslate") and its silent fallback are intentionally not offered (SGM-F18).
import Foundation
import SGItemListUI
import SGSimpleSettings
import SGStrings

enum SuperGramTranslateSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .translate

    private static let serviceSetting = "translate.service"

    private static var isOnDeviceAvailable: Bool {
        if #available(iOS 18.0, *) {
            return true
        } else {
            return false
        }
    }

    private static func serviceTitle(onDevice: Bool, state: SuperGramSettingsState) -> String {
        return onDevice ? sgString("SuperGram.Translate.Service.OnDevice", state) : sgString("SuperGram.Translate.Service.Telegram", state)
    }

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        let chatSection = SuperGramSettingsSection(self.group)
        let messagesSection = SuperGramSettingsSection(self.group, block: 1)
        var entries: [SuperGramSettingsEntry] = []

        entries.append(sgHeader(id, chatSection, sgString("SuperGram.Translate.Header", state)))
        entries.append(sgToggle(id, chatSection, \.sgTranslateChatsWithoutPremium, text: sgString("SuperGram.Translate.ChatsWithoutPremium", state)))
        if self.isOnDeviceAvailable {
            let onDevice = SGSimpleSettings.shared.sgPrefersOnDeviceTranslation
            entries.append(.oneFromManySelector(id: id.count, section: chatSection, settingName: self.serviceSetting, text: sgString("SuperGram.Translate.Service", state), value: self.serviceTitle(onDevice: onDevice, state: state), enabled: true))
            entries.append(sgNotice(id, chatSection, sgString("SuperGram.Translate.Notice.OnDevice", state)))
        } else {
            id.increment(1)
            entries.append(sgNotice(id, chatSection, sgString("SuperGram.Translate.Notice", state)))
        }

        entries.append(sgToggle(id, messagesSection, \.quickTranslateButton, text: sgString("SuperGram.Translate.QuickTranslateButton", state)))
        entries.append(sgToggle(id, messagesSection, \.sgOutgoingTranslation, text: sgString("SuperGram.Translate.OutgoingTranslation", state)))
        entries.append(sgNotice(id, messagesSection, sgString("SuperGram.Translate.Messages.Notice", state)))
        return entries
    }

    static func setOneFromManyValue(_ setting: String, actions: SuperGramSettingsActions) -> Bool {
        guard setting == self.serviceSetting else {
            return false
        }
        let lang = actions.presentationData.strings.baseLanguageCode
        let onDevice = SGSimpleSettings.shared.sgPrefersOnDeviceTranslation
        actions.presentOptions([
            (title: i18n("SuperGram.Translate.Service.Telegram", lang), isSelected: !onDevice, action: {
                SGSimpleSettings.shared.translationBackend = SGSimpleSettings.TranslationBackend.default.rawValue
                actions.reload()
            }),
            (title: i18n("SuperGram.Translate.Service.OnDevice", lang), isSelected: onDevice, action: {
                SGSimpleSettings.shared.translationBackend = SGSimpleSettings.TranslationBackend.system.rawValue
                actions.reload()
            })
        ])
        return true
    }
}
