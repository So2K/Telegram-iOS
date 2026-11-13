// SuperGram: download pipeline (hooks: W1-FETCH).
import Foundation
import SGItemListUI
import SGSimpleSettings
import SGStrings
import SuperGramDownloadsDiagnosticsScreen

enum SuperGramDownloadsSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .downloads

    private static let speedModeSetting = "downloads.speedMode"
    private static let diagnosticsLink = "downloads.diagnostics"

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        let section = SuperGramSettingsSection(self.group)
        var entries: [SuperGramSettingsEntry] = []
        entries.append(sgHeader(id, section, sgString("SuperGram.Downloads.Header", state)))
        entries.append(.oneFromManySelector(id: id.count, section: section, settingName: self.speedModeSetting, text: sgString("SuperGram.Downloads.Speed", state), value: self.speedModeTitle(SGSimpleSettings.shared.sgDownloadSpeedMode, lang: state.lang), enabled: true))
        entries.append(sgToggle(id, section, \.sgBackgroundDownloads, text: sgString("SuperGram.Downloads.Background", state)))
        entries.append(sgNotice(id, section, sgString("SuperGram.Downloads.Speed.Notice", state)))

        let limiterSection = SuperGramSettingsSection(self.group, block: 1)
        entries.append(sgToggle(id, limiterSection, \.sgDownloadLimiter, text: sgString("SuperGram.Downloads.Limiter", state)))
        entries.append(sgNotice(id, limiterSection, sgString("SuperGram.Downloads.Limiter.Notice", state)))

        let pressureSection = SuperGramSettingsSection(self.group, block: 2)
        entries.append(sgToggle(id, pressureSection, \.sgPauseDownloadsUnderPressure, text: sgString("SuperGram.Downloads.PauseUnderPressure", state)))
        entries.append(sgNotice(id, pressureSection, sgString("SuperGram.Downloads.PauseUnderPressure.Notice", state)))

        // Live view of the download pipeline for a user who has no logs (DOWNLOAD-DIAGNOSTICS).
        let diagnosticsSection = SuperGramSettingsSection(self.group, block: 3)
        entries.append(.disclosure(id: id.count, section: diagnosticsSection, link: self.diagnosticsLink, text: sgString("SuperGram.Downloads.Diagnostics", state)))
        entries.append(sgNotice(id, diagnosticsSection, sgString("SuperGram.Downloads.Diagnostics.RowNotice", state)))
        return entries
    }

    static func openDisclosureLink(_ link: String, actions: SuperGramSettingsActions) -> Bool {
        guard link == self.diagnosticsLink else {
            return false
        }
        actions.push(superGramDownloadsDiagnosticsController(context: actions.context))
        return true
    }

    static func setOneFromManyValue(_ setting: String, actions: SuperGramSettingsActions) -> Bool {
        guard setting == self.speedModeSetting else {
            return false
        }
        let lang = actions.presentationData.strings.baseLanguageCode
        let currentMode = SGSimpleSettings.shared.sgDownloadSpeedMode
        let options = ([0, 1, 2] as [Int32]).map { mode -> (title: String, isSelected: Bool, action: () -> Void) in
            return (title: self.speedModeTitle(mode, lang: lang), isSelected: mode == currentMode, action: { [weak actions] in
                SGSimpleSettings.shared.sgDownloadSpeedMode = mode
                actions?.reload()
            })
        }
        actions.presentOptions(options)
        return true
    }

    private static func speedModeTitle(_ mode: Int32, lang: String) -> String {
        switch mode {
        case 0:
            return i18n("SuperGram.Downloads.Speed.Standard", lang)
        case 2:
            return i18n("SuperGram.Downloads.Speed.Maximum", lang)
        default:
            return i18n("SuperGram.Downloads.Speed.Fast", lang)
        }
    }
}
