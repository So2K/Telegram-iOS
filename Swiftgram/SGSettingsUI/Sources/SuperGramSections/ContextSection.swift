// SuperGram: context menus and message selection. Owned by W2-CONTEXT.
// Hooks: TelegramUI ChatInterfaceStateContextMenus.swift (contextShow* keys, raw UserDefaults reads in
// SuperGramContextMenuSettings.swift) and ChatMessageSelectionInputPanelNode (sgSelectionBar* keys).
// The protected-content unlock used by the menu (sgAllowSaveProtectedContent) lives in ProtectedContentSection.swift.
import Foundation
import SGItemListUI
import SGSimpleSettings

enum SuperGramContextSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .context

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        var entries: [SuperGramSettingsEntry] = []

        // Swiftgram "Context Menu" section: ON = item in the main message menu, OFF = item in the "SuperGram" submenu.
        let menuSection = SuperGramSettingsSection(self.group)
        entries.append(sgHeader(id, menuSection, sgString("Settings.ContextMenu", state)))
        entries.append(sgToggle(id, menuSection, \.contextShowSaveToCloud, text: sgString("ContextMenu.SaveToCloud", state)))
        entries.append(sgToggle(id, menuSection, \.contextShowHideForwardName, text: state.strings.Conversation_ForwardOptions_HideSendersNames))
        entries.append(sgToggle(id, menuSection, \.contextShowSelectFromUser, text: sgString("ContextMenu.SelectFromUser", state)))
        entries.append(sgToggle(id, menuSection, \.contextShowRestrict, text: state.strings.Conversation_ContextMenuBan))
        entries.append(sgToggle(id, menuSection, \.contextShowReport, text: state.strings.Conversation_ContextMenuReport))
        entries.append(sgToggle(id, menuSection, \.contextShowReply, text: state.strings.Conversation_ContextMenuReply))
        entries.append(sgToggle(id, menuSection, \.contextShowPin, text: state.strings.Conversation_Pin))
        entries.append(sgToggle(id, menuSection, \.contextShowSaveMedia, text: state.strings.Conversation_SaveToFiles))
        entries.append(sgToggle(id, menuSection, \.contextShowMessageReplies, text: state.strings.Conversation_ContextViewThread))
        entries.append(sgNotice(id, menuSection, sgString("Settings.ContextMenu.Notice", state)))

        // Swiftgram selection-bar buttons (always on in Swiftgram).
        let selectionSection = SuperGramSettingsSection(self.group, block: 1)
        entries.append(sgHeader(id, selectionSection, sgString("SuperGram.Context.SelectionBar.Header", state)))
        entries.append(sgToggle(id, selectionSection, \.sgSelectionBarSaveToCloud, text: sgString("SuperGram.Context.SelectionBar.SaveToCloud", state)))
        entries.append(sgToggle(id, selectionSection, \.sgSelectionBarForwardHideNames, text: sgString("SuperGram.Context.SelectionBar.ForwardHideNames", state)))
        entries.append(sgNotice(id, selectionSection, sgString("SuperGram.Context.SelectionBar.Notice", state)))

        // Swiftgram message JSON viewer (debug, default off).
        let debugSection = SuperGramSettingsSection(self.group, block: 2)
        entries.append(sgToggle(id, debugSection, \.contextShowJson, text: sgString("SuperGram.Context.MessageJson", state)))
        entries.append(sgNotice(id, debugSection, sgString("SuperGram.Context.MessageJson.Notice", state)))
        return entries
    }
}
