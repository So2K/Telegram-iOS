// SuperGram: app behaviour, background work, telemetry and diagnostics (hooks: W1-APP, W1-ADS, W1-CHATMEDIA).
// performanceMode / playVideoInBackground stay stored in MediaDisplaySettings (moved here from
// DataAndStorageSettingsController, INFRA-10).
import Foundation
import SwiftSignalKit
import TelegramUIPreferences
import AccountContext
import SGItemListUI
import SGSimpleSettings

enum SuperGramAppSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .app

    private static let performanceModeSetting = "app.performanceMode"
    private static let playVideoInBackgroundSetting = "app.playVideoInBackground"

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        var entries: [SuperGramSettingsEntry] = []

        let section = SuperGramSettingsSection(self.group)
        entries.append(sgHeader(id, section, sgString("SuperGram.App.Header", state)))
        entries.append(sgToggle(id, section, \.sgBackgroundKeepAlive, text: sgString("SuperGram.App.BackgroundKeepAlive", state)))
        entries.append(sgNotice(id, section, sgString("SuperGram.App.BackgroundKeepAlive.Notice", state)))

        let performanceSection = SuperGramSettingsSection(self.group, block: 1)
        entries.append(sgCustomToggle(id, performanceSection, self.performanceModeSetting, value: state.mediaDisplaySettings.performanceMode, text: sgString("SuperGram.App.PerformanceMode", state)))
        entries.append(sgCustomToggle(id, performanceSection, self.playVideoInBackgroundSetting, value: state.mediaDisplaySettings.playVideoInBackground, text: sgString("SuperGram.App.PlayVideoInBackground", state)))
        entries.append(sgNotice(id, performanceSection, sgString("SuperGram.App.PerformanceMode.Notice", state)))

        let privacySection = SuperGramSettingsSection(self.group, block: 2)
        entries.append(sgToggle(id, privacySection, \.sgDisableReadMetrics, text: sgString("SuperGram.App.DisableReadMetrics", state)))
        entries.append(sgNotice(id, privacySection, sgString("SuperGram.App.DisableReadMetrics.Notice", state)))

        let diagnosticsSection = SuperGramSettingsSection(self.group, block: 3)
        entries.append(sgHeader(id, diagnosticsSection, sgString("SuperGram.App.Diagnostics.Header", state)))
        entries.append(sgToggle(id, diagnosticsSection, \.sgFileLogging, text: sgString("SuperGram.App.FileLogging", state), restart: true))
        entries.append(sgToggle(id, diagnosticsSection, \.sgNetworkLogging, text: sgString("SuperGram.App.NetworkLogging", state), restart: true))
        entries.append(sgNotice(id, diagnosticsSection, sgString("SuperGram.App.Logging.Notice", state)))

        return entries
    }

    static func setBoolValue(_ setting: String, value: Bool, actions: SuperGramSettingsActions) -> Bool {
        let accountManager = actions.context.sharedContext.accountManager
        switch setting {
        case self.performanceModeSetting:
            let _ = updateMediaDisplaySettingsInteractively(accountManager: accountManager, {
                $0.withUpdatedPerformanceMode(value)
            }).start()
        case self.playVideoInBackgroundSetting:
            let _ = updateMediaDisplaySettingsInteractively(accountManager: accountManager, {
                $0.withUpdatedPlayVideoInBackground(value)
            }).start()
        default:
            return false
        }
        return true
    }
}
