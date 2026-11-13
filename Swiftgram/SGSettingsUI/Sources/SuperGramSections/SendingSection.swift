// SuperGram: sending (hooks: W1-TELESCOPE).
import Foundation
import SGItemListUI
import SGSimpleSettings

enum SuperGramSendingSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .sending

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        let section = SuperGramSettingsSection(self.group)
        var entries: [SuperGramSettingsEntry] = []
        entries.append(sgHeader(id, section, sgString("SuperGram.Sending.Header", state)))
        entries.append(sgToggle(id, section, \.sgTelescopeButton, text: sgString("SuperGram.Sending.TelescopeButton", state)))
        // The round video camera reads `startTelescopeWithRearCam` (LegacyInstantVideoController,
        // VideoMessageCameraScreen); without this row the setting had no way to be changed.
        entries.append(sgToggle(id, section, \.startTelescopeWithRearCam, text: sgString("Settings.VideoNotes.StartWithRearCam", state)))
        entries.append(sgNotice(id, section, sgString("SuperGram.Sending.TelescopeButton.Notice", state)))
        return entries
    }
}
