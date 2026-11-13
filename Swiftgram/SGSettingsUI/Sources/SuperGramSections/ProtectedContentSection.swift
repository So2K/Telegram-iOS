// SuperGram: protected content unlocks (hooks: W1-STORIES, W1-GALLERY, W2-CONTEXT, W2-PROTECT).
// Privacy line: secret chats, view-once media and screenshot notifications in secret chats are never affected.
import Foundation
import SGItemListUI
import SGSimpleSettings

enum SuperGramProtectedContentSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .protectedContent

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        let section = SuperGramSettingsSection(self.group)
        var entries: [SuperGramSettingsEntry] = []
        entries.append(sgHeader(id, section, sgString("SuperGram.ProtectedContent.Header", state)))
        entries.append(sgToggle(id, section, \.sgAllowSaveProtectedContent, text: sgString("SuperGram.ProtectedContent.AllowSave", state)))
        entries.append(sgToggle(id, section, \.sgAllowScreenCaptureProtected, text: sgString("SuperGram.ProtectedContent.AllowScreenCapture", state)))
        entries.append(sgNotice(id, section, sgString("SuperGram.ProtectedContent.Notice", state)))

        let storiesSection = SuperGramSettingsSection(self.group, block: 1)
        entries.append(sgToggle(id, storiesSection, \.sgStoryHDWithoutPremium, text: sgString("SuperGram.ProtectedContent.StoryHD", state)))
        entries.append(sgNotice(id, storiesSection, sgString("SuperGram.ProtectedContent.StoryHD.Notice", state)))
        return entries
    }
}
