// SuperGram: media playback & streaming (hooks: W1-PLAYER, W1-CHATMEDIA).
import Foundation
import SGItemListUI
import SGSimpleSettings

enum SuperGramMediaSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .media

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        let section = SuperGramSettingsSection(self.group)
        var entries: [SuperGramSettingsEntry] = []
        entries.append(sgHeader(id, section, sgString("SuperGram.Media.Header", state)))
        entries.append(sgToggle(id, section, \.sgStreamAllVideos, text: sgString("SuperGram.Media.StreamAllVideos", state)))
        entries.append(sgNotice(id, section, sgString("SuperGram.Media.StreamAllVideos.Notice", state)))

        let originalSection = SuperGramSettingsSection(self.group, block: 1)
        entries.append(sgToggle(id, originalSection, \.sgPreferDownloadedOriginal, text: sgString("SuperGram.Media.PreferDownloadedOriginal", state)))
        entries.append(sgNotice(id, originalSection, sgString("SuperGram.Media.PreferDownloadedOriginal.Notice", state)))

        let autoplaySection = SuperGramSettingsSection(self.group, block: 2)
        entries.append(sgToggle(id, autoplaySection, \.sgInlineAutoplayVideos, text: sgString("SuperGram.Media.InlineAutoplayVideos", state)))
        entries.append(sgNotice(id, autoplaySection, sgString("SuperGram.Media.InlineAutoplayVideos.Notice", state)))
        return entries
    }
}
