// SuperGram: privacy / ghost mode, stories, profile details and calls. Owned by W2-GHOST.
// Hooks:
// - sgSkipReadReceipts: TelegramCore SuperGramGhostSettings -> ChatHistoryListNode (reads, reactions),
//   PeerMessagesMediaPlaylist (voice/round "listened"; secret chats and self-destructing media excluded).
// - sgStoryGhostMode: TelegramEngine.Messages.markStoryAsSeen keeps only the local seen state.
// - warnOnStoriesOpen: StoryContainerScreen + SGStoryWarnComponent; showRepostToStoryV2: SharePeersContainerNode.
// - showProfileId / showDC / showCreationDate / sgShowJoinedDate / showRegDate: PeerInfoScreenSuperGram.swift.
// - hidePhoneInSettings: PeerInfoHeaderNode (Settings header), PeerInfoProfileItems (My Profile).
// - confirmCalls: TelegramUI AccountContextImpl.requestCall.
import Foundation
import SGItemListUI
import SGSimpleSettings

enum SuperGramGhostSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .ghost

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        var entries: [SuperGramSettingsEntry] = []

        let readReceiptsSection = SuperGramSettingsSection(self.group)
        entries.append(sgHeader(id, readReceiptsSection, sgString("SuperGram.Ghost.Header", state)))
        entries.append(sgToggle(id, readReceiptsSection, \.sgSkipReadReceipts, text: sgString("SuperGram.Ghost.SkipReadReceipts", state)))
        entries.append(sgNotice(id, readReceiptsSection, sgString("SuperGram.Ghost.SkipReadReceipts.Notice", state)))

        let storyGhostSection = SuperGramSettingsSection(self.group, block: 1)
        entries.append(sgToggle(id, storyGhostSection, \.sgStoryGhostMode, text: sgString("SuperGram.Ghost.StoryGhostMode", state)))
        entries.append(sgNotice(id, storyGhostSection, sgString("SuperGram.Ghost.StoryGhostMode.Notice", state)))

        let storiesSection = SuperGramSettingsSection(self.group, block: 2)
        entries.append(sgHeader(id, storiesSection, sgString("SuperGram.Ghost.Stories.Header", state)))
        entries.append(sgToggle(id, storiesSection, \.warnOnStoriesOpen, text: sgString("Settings.Stories.WarnBeforeView", state)))
        entries.append(sgToggle(id, storiesSection, \.showRepostToStoryV2, text: sgString("SuperGram.Ghost.RepostToStory", state)))
        entries.append(sgNotice(id, storiesSection, sgString("SuperGram.Ghost.WarnOnStoriesOpen.Notice", state)))

        let profilesSection = SuperGramSettingsSection(self.group, block: 3)
        entries.append(sgHeader(id, profilesSection, sgString("Settings.Profiles.Header", state)))
        entries.append(sgToggle(id, profilesSection, \.showProfileId, text: sgString("Settings.ShowProfileID", state)))
        entries.append(sgToggle(id, profilesSection, \.showDC, text: sgString("Settings.ShowDC", state)))
        entries.append(sgToggle(id, profilesSection, \.showCreationDate, text: sgString("Settings.ShowCreationDate", state)))
        entries.append(sgToggle(id, profilesSection, \.sgShowJoinedDate, text: sgString("SuperGram.Ghost.ShowJoinedDate", state)))
        entries.append(sgToggle(id, profilesSection, \.showRegDate, text: sgString("Settings.ShowRegDate", state)))
        entries.append(sgNotice(id, profilesSection, sgString("SuperGram.Ghost.Profiles.Notice", state)))

        let phoneSection = SuperGramSettingsSection(self.group, block: 4)
        entries.append(sgToggle(id, phoneSection, \.hidePhoneInSettings, text: sgString("Settings.HidePhoneInSettingsUI", state)))
        entries.append(sgNotice(id, phoneSection, sgString("Settings.HidePhoneInSettingsUI.Notice", state)))

        let callsSection = SuperGramSettingsSection(self.group, block: 5)
        entries.append(sgHeader(id, callsSection, sgString("SuperGram.Ghost.Calls.Header", state)))
        entries.append(sgToggle(id, callsSection, \.confirmCalls, text: sgString("Settings.CallConfirmation", state)))
        entries.append(sgNotice(id, callsSection, sgString("Settings.CallConfirmation.Notice", state)))

        return entries
    }
}
