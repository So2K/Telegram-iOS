// SuperGram: chat list, folders, tab bar and navigation. Owned by W2-CHATLIST.
// Rows follow the Swiftgram "Tabs", "Chat Folders", "Chat List" and "Stories" blocks (SGSettingsController.swift in
// swiftgram/master) with the same keys and defaults. Hooks: ChatListUI, TabBarUI, TelegramRootController, CallListSettings.
import Foundation
import SwiftSignalKit
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import SGItemListUI
import SGSimpleSettings
import SGStrings

enum SuperGramChatListSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .chatList

    /// Title of one "All Chats" title option. Used both for the row's current value and for the option sheet, so the
    /// two always agree, and an unknown stored value falls back to "Default" instead of showing a raw i18n key.
    private static func allChatsTitleTitle(_ value: SGSimpleSettings.AllChatsTitleLengthOverride, strings: PresentationStrings, lang: String) -> String {
        switch value {
        case .short:
            return "\"\(strings.ChatList_Tabs_All)\""
        case .long:
            return "\"\(strings.ChatList_Tabs_AllChats)\""
        default:
            return i18n("Settings.Folders.AllChatsTitle.none", lang)
        }
    }

    // Settings stored outside SGSimpleSettings or shown inverted with a restart prompt.
    private static let showContactsTabSetting = "chatList.showContactsTab"
    private static let showCallsTabSetting = "chatList.showCallsTab"
    private static let foldersAtBottomSetting = "chatList.foldersAtBottom"
    private static let compactMessagePreviewSetting = "chatList.compactMessagePreview"
    private static let chatSwipeOptionsSetting = "chatList.chatSwipeOptions"
    private static let deleteChatSwipeOptionSetting = "chatList.deleteChatSwipeOption"
    private static let allChatsTitleSetting = "chatList.allChatsTitleLengthOverride"

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        let settings = SGSimpleSettings.shared
        let strings = state.strings
        let lang = state.lang
        var entries: [SuperGramSettingsEntry] = []

        // MARK: Tabs (SGUI-04, SGUI-09, SGUI-15)
        let tabsSection = SuperGramSettingsSection(self.group, block: 0)
        let tabBarVisible = !settings.hideTabBar
        entries.append(sgHeader(id, tabsSection, i18n("Settings.Tabs.Header", lang)))
        entries.append(sgToggle(id, tabsSection, \.hideTabBar, text: i18n("Settings.Tabs.HideTabBar", lang), restart: true))
        entries.append(sgCustomToggle(id, tabsSection, self.showContactsTabSetting, value: state.callListSettings.showContactsTab, text: i18n("Settings.Tabs.ShowContacts", lang), enabled: tabBarVisible))
        entries.append(sgCustomToggle(id, tabsSection, self.showCallsTabSetting, value: state.callListSettings.showTab, text: strings.CallSettings_TabIcon, enabled: tabBarVisible))
        entries.append(sgToggle(id, tabsSection, \.showTabNames, text: i18n("Settings.Tabs.ShowNames", lang), enabled: tabBarVisible, restart: true))
        entries.append(sgToggle(id, tabsSection, \.tabBarSearchEnabled, text: i18n("Settings.Tabs.SearchButton", lang), enabled: tabBarVisible))
        // No restart prompt: `wideTabBar` is read inside `TabBarContollerNode.containerLayoutUpdated` (like
        // `tabBarSearchEnabled` above) and only scales the bar's container width — nothing derived from it is
        // cached. Popping this screen makes the tab bar controller top again, and `NavigationContainer.makeChild`
        // calls `containerLayoutUpdated` on it, so the new width is applied on the way back.
        entries.append(sgToggle(id, tabsSection, \.wideTabBar, text: i18n("Settings.Tabs.WideTabBar", lang), enabled: tabBarVisible))
        entries.append(sgNotice(id, tabsSection, i18n("Settings.Tabs.WideTabBar.Notice", lang)))
        if settings.hideTabBar {
            entries.append(sgNotice(id, tabsSection, i18n("SuperGram.ChatList.HideTabBar.Notice", lang)))
        } else {
            id.increment(1)
        }

        // MARK: Folders (SGUI-08, SGUI-10, SGUI-16)
        let foldersSection = SuperGramSettingsSection(self.group, block: 1)
        entries.append(sgHeader(id, foldersSection, strings.Settings_ChatFolders.uppercased()))
        entries.append(sgCustomToggle(id, foldersSection, self.foldersAtBottomSetting, value: state.experimentalUISettings.foldersTabAtBottom, text: i18n("Settings.Folders.BottomTab", lang)))
        entries.append(sgToggle(id, foldersSection, \.allChatsHidden, text: i18n("Settings.Folders.AllChatsHidden", lang, strings.ChatList_Tabs_AllChats), restart: true))
        entries.append(sgToggle(id, foldersSection, \.compactFolderNames, text: i18n("Settings.Folders.CompactNames", lang), restart: true))
        let allChatsTitleOverride = SGSimpleSettings.AllChatsTitleLengthOverride(rawValue: settings.allChatsTitleLengthOverride) ?? SGSimpleSettings.AllChatsTitleLengthOverride.none
        entries.append(.oneFromManySelector(id: id.count, section: foldersSection, settingName: self.allChatsTitleSetting, text: i18n("Settings.Folders.AllChatsTitle", lang), value: self.allChatsTitleTitle(allChatsTitleOverride, strings: strings, lang: lang), enabled: true))
        entries.append(sgToggle(id, foldersSection, \.rememberLastFolder, text: i18n("Settings.Folders.RememberLast", lang)))
        entries.append(sgNotice(id, foldersSection, i18n("Settings.Folders.RememberLast.Notice", lang)))

        // MARK: Chat list (SGUI-11)
        let chatListSection = SuperGramSettingsSection(self.group, block: 2)
        entries.append(sgHeader(id, chatListSection, i18n("Settings.ChatList.Header", lang)))
        entries.append(sgToggle(id, chatListSection, \.compactChatList, text: i18n("Settings.CompactChatList", lang), restart: true))
        entries.append(sgCustomToggle(id, chatListSection, self.compactMessagePreviewSetting, value: settings.chatListLines != SGSimpleSettings.ChatListLines.three.rawValue, text: i18n("Settings.CompactMessagePreview", lang)))
        entries.append(sgCustomToggle(id, chatListSection, self.chatSwipeOptionsSetting, value: !settings.disableChatSwipeOptions, text: i18n("Settings.ChatSwipeOptions", lang)))
        entries.append(sgCustomToggle(id, chatListSection, self.deleteChatSwipeOptionSetting, value: !settings.disableDeleteChatSwipeOption, text: i18n("Settings.DeleteChatSwipeOption", lang), enabled: !settings.disableChatSwipeOptions))

        // MARK: Stories in the chat list (SGUI-02)
        let storiesSection = SuperGramSettingsSection(self.group, block: 3)
        entries.append(sgHeader(id, storiesSection, strings.AutoDownloadSettings_Stories.uppercased()))
        entries.append(sgToggle(id, storiesSection, \.hideStories, text: i18n("Settings.Stories.Hide", lang)))
        entries.append(sgToggle(id, storiesSection, \.disableSwipeToRecordStory, text: i18n("Settings.Stories.DisableSwipeToRecord", lang)))
        entries.append(sgNotice(id, storiesSection, i18n("SuperGram.ChatList.HideStories.Notice", lang)))

        // MARK: SuperGram — chat history button
        let historySection = SuperGramSettingsSection(self.group, block: 30)
        entries.append(sgToggle(id, historySection, \.sgChatListHistoryButton, text: i18n("SuperGram.History.Setting", lang), restart: true))
        entries.append(sgNotice(id, historySection, i18n("SuperGram.History.Setting.Notice", lang)))
        let navigationSection = SuperGramSettingsSection(self.group, block: 31)
        entries.append(sgToggle(id, navigationSection, \.sgKeepNavigationStack, text: i18n("SuperGram.Navigation.KeepStack", lang)))
        entries.append(sgNotice(id, navigationSection, i18n("SuperGram.Navigation.KeepStack.Notice", lang)))

        return entries
    }

    static func setBoolValue(_ setting: String, value: Bool, actions: SuperGramSettingsActions) -> Bool {
        let accountManager = actions.context.sharedContext.accountManager
        switch setting {
        case self.showContactsTabSetting:
            let _ = updateCallListSettingsInteractively(accountManager: accountManager, {
                $0.withUpdatedShowContactsTab(value)
            }).start()
        case self.showCallsTabSetting:
            let _ = updateCallListSettingsInteractively(accountManager: accountManager, {
                $0.withUpdatedShowTab(value)
            }).start()
        case self.foldersAtBottomSetting:
            let _ = updateExperimentalUISettingsInteractively(accountManager: accountManager, { settings in
                var settings = settings
                settings.foldersTabAtBottom = value
                return settings
            }).start()
        case self.compactMessagePreviewSetting:
            SGSimpleSettings.shared.chatListLines = value ? SGSimpleSettings.ChatListLines.one.rawValue : SGSimpleSettings.ChatListLines.three.rawValue
            actions.reload()
            actions.askForRestart()
        case self.chatSwipeOptionsSetting:
            SGSimpleSettings.shared.disableChatSwipeOptions = !value
            actions.reload()
            actions.askForRestart()
        case self.deleteChatSwipeOptionSetting:
            SGSimpleSettings.shared.disableDeleteChatSwipeOption = !value
            actions.reload()
            actions.askForRestart()
        default:
            return false
        }
        return true
    }

    static func setOneFromManyValue(_ setting: String, actions: SuperGramSettingsActions) -> Bool {
        guard setting == self.allChatsTitleSetting else {
            return false
        }
        let presentationData = actions.presentationData
        let lang = presentationData.strings.baseLanguageCode
        let currentValue = SGSimpleSettings.shared.allChatsTitleLengthOverride
        let options = SGSimpleSettings.AllChatsTitleLengthOverride.allCases.map { value -> (title: String, isSelected: Bool, action: () -> Void) in
            let title = self.allChatsTitleTitle(value, strings: presentationData.strings, lang: lang)
            return (title: title, isSelected: value.rawValue == currentValue, action: {
                SGSimpleSettings.shared.allChatsTitleLengthOverride = value.rawValue
                actions.reload()
            })
        }
        actions.presentOptions(options)
        return true
    }
}
