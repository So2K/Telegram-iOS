// SuperGram: chat screen, bubbles and input panel (API: output/ultra/impl/W1-INFRA.md).
// Shared file: W2-CHATUI-HISTORY owns the "// MARK: History" blocks (list blocks 16...23),
// W2-CHATUI-INPUT owns the "// MARK: Input" blocks. Callback functions try History first, then Input.
import Foundation
import SGItemListUI
import SGSimpleSettings
import SGStrings

enum SuperGramChatUISection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .chatUI

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        var entries: [SuperGramSettingsEntry] = []

        // MARK: History
        entries.append(contentsOf: self.historyEntries(state: state, id: id))

        // MARK: Input
        entries.append(contentsOf: self.inputEntries(state: state, id: id))

        return entries
    }

    static func setOneFromManyValue(_ setting: String, actions: SuperGramSettingsActions) -> Bool {
        // MARK: History
        if self.historySetOneFromManyValue(setting, actions: actions) {
            return true
        }

        // MARK: Input

        return false
    }

    static func updateSliderValue(_ setting: String, value: Int32, actions: SuperGramSettingsActions) -> Bool {
        // MARK: Input
        if self.inputUpdateSliderValue(setting, value: value, actions: actions) {
            return true
        }

        return false
    }
}

// MARK: History
// Hooks: ChatMessageDateAndStatusNode (secondsInMessages, hideReactions), ChatMessageBubbleItemNode
// (wideChannelPosts, messageDoubleTapActionOutgoing), ChatHistoryListNode + ChatMessageContextControllerContentSource
// (disableSnapDeletionEffect), ChatControllerContentData (disableScrollToNextChannel/Topic),
// ChatMessageItemImpl (messageFilterKeywords).
extension SuperGramChatUISection {
    private static let historyDoubleTapOutgoingSetting = "chatUI.history.doubleTapOutgoing"
    private static let historyMessageFilterSetting = "chatUI.history.messageFilter"

    private static func historyDoubleTapActionTitle(_ action: String, lang: String) -> String {
        switch action {
        case SGSimpleSettings.MessageDoubleTapAction.edit.rawValue:
            return i18n("SuperGram.ChatUI.History.DoubleTapOutgoing.Edit", lang)
        case SGSimpleSettings.MessageDoubleTapAction.none.rawValue:
            return i18n("SuperGram.ChatUI.History.DoubleTapOutgoing.None", lang)
        default:
            return i18n("SuperGram.ChatUI.History.DoubleTapOutgoing.Reaction", lang)
        }
    }

    static func historyEntries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        var entries: [SuperGramSettingsEntry] = []

        let appearanceSection = SuperGramSettingsSection(self.group, block: 16)
        entries.append(sgHeader(id, appearanceSection, sgString("SuperGram.ChatUI.History.Header", state)))
        entries.append(sgToggle(id, appearanceSection, \.secondsInMessages, text: sgString("Settings.secondsInMessages", state)))
        entries.append(sgToggle(id, appearanceSection, \.hideReactions, text: sgString("Settings.HideReactions", state)))
        entries.append(sgToggle(id, appearanceSection, \.wideChannelPosts, text: sgString("Settings.wideChannelPosts", state)))
        entries.append(sgToggle(id, appearanceSection, \.sgShowShareButton, text: sgString("SuperGram.ChatUI.History.ShareButton", state)))
        entries.append(sgNotice(id, appearanceSection, sgString("SuperGram.ChatUI.History.Appearance.Notice", state)))

        let effectsSection = SuperGramSettingsSection(self.group, block: 17)
        entries.append(sgInvertedToggle(id, effectsSection, \.disableSnapDeletionEffect, text: sgString("Settings.SnapDeletionEffect", state)))
        entries.append(sgInvertedToggle(id, effectsSection, \.disableScrollToNextChannel, text: sgString("Settings.PullToNextChannel", state)))
        entries.append(sgInvertedToggle(id, effectsSection, \.disableScrollToNextTopic, text: sgString("Settings.PullToNextTopic", state)))
        entries.append(sgNotice(id, effectsSection, sgString("SuperGram.ChatUI.History.Effects.Notice", state)))

        let doubleTapSection = SuperGramSettingsSection(self.group, block: 18)
        entries.append(.oneFromManySelector(id: id.count, section: doubleTapSection, settingName: self.historyDoubleTapOutgoingSetting, text: sgString("SuperGram.ChatUI.History.DoubleTapOutgoing", state), value: self.historyDoubleTapActionTitle(SGSimpleSettings.shared.messageDoubleTapActionOutgoing, lang: state.lang), enabled: true))
        entries.append(sgNotice(id, doubleTapSection, sgString("SuperGram.ChatUI.History.DoubleTapOutgoing.Notice", state)))

        let filterSection = SuperGramSettingsSection(self.group, block: 19)
        let keywordCount = SGSimpleSettings.shared.messageFilterKeywords.count
        let filterValue = keywordCount == 0 ? sgString("SuperGram.ChatUI.History.MessageFilter.Off", state) : "\(keywordCount)"
        entries.append(.oneFromManySelector(id: id.count, section: filterSection, settingName: self.historyMessageFilterSetting, text: sgString("SuperGram.ChatUI.History.MessageFilter", state), value: filterValue, enabled: true))
        entries.append(sgNotice(id, filterSection, sgString("SuperGram.ChatUI.History.MessageFilter.Notice", state)))

        return entries
    }

    static func historySetOneFromManyValue(_ setting: String, actions: SuperGramSettingsActions) -> Bool {
        switch setting {
        case self.historyDoubleTapOutgoingSetting:
            let lang = actions.presentationData.strings.baseLanguageCode
            let current = SGSimpleSettings.shared.messageDoubleTapActionOutgoing
            let values: [SGSimpleSettings.MessageDoubleTapAction] = [.default, .edit, .none]
            let options = values.map { value -> (title: String, isSelected: Bool, action: () -> Void) in
                return (title: self.historyDoubleTapActionTitle(value.rawValue, lang: lang), isSelected: value.rawValue == current, action: {
                    SGSimpleSettings.shared.messageDoubleTapActionOutgoing = value.rawValue
                    actions.reload()
                })
            }
            actions.presentOptions(options)
            return true
        case self.historyMessageFilterSetting:
            actions.push(superGramMessageFilterController(context: actions.context, completion: {
                actions.reload()
            }))
            return true
        default:
            return false
        }
    }
}

// MARK: Input
// Hooks: ChatTextInputPanelNode (hideRecordingButton, sendWithReturnKey, inputToolbar),
// ChatPresentationInterfaceState (disableSendAsButton), ChatControllerNode + ChatInterfaceStateInputPanels
// (hideChannelBottomButton), ChatController.displayMediaRecordingTooltip (sgHideRecordingTooltip),
// ChatEntityKeyboardInputNode + ChatInterfaceInputContexts (forceEmojiTab, defaultEmojisFirst),
// ChatMessageStickerItemNode + ChatMessageAnimatedStickerItemNode (stickerSize, stickerTimestamp).
extension SuperGramChatUISection {
    private static let inputStickerSizeSetting = "chatUI.input.stickerSize"

    static func inputEntries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        var entries: [SuperGramSettingsEntry] = []

        let buttonsSection = SuperGramSettingsSection(self.group, block: 24)
        entries.append(sgHeader(id, buttonsSection, sgString("SuperGram.ChatUI.Input.Header", state)))
        entries.append(sgInvertedToggle(id, buttonsSection, \.hideRecordingButton, text: sgString("Settings.RecordingButton", state)))
        entries.append(sgInvertedToggle(id, buttonsSection, \.sgHideRecordingTooltip, text: sgString("SuperGram.ChatUI.Input.RecordingTooltip", state)))
        entries.append(sgInvertedToggle(id, buttonsSection, \.disableSendAsButton, text: i18n("Settings.SendAsButton", state.lang, state.strings.Conversation_SendMesageAs)))
        entries.append(sgNotice(id, buttonsSection, sgString("SuperGram.ChatUI.Input.Buttons.Notice", state)))

        let channelSection = SuperGramSettingsSection(self.group, block: 25)
        entries.append(sgInvertedToggle(id, channelSection, \.hideChannelBottomButton, text: sgString("Settings.showChannelBottomButton", state)))
        entries.append(sgNotice(id, channelSection, sgString("SuperGram.ChatUI.Input.ChannelPanel.Notice", state)))

        let returnKeySection = SuperGramSettingsSection(self.group, block: 26)
        entries.append(sgToggle(id, returnKeySection, \.sendWithReturnKey, text: sgString("Settings.SendWithReturnKey", state)))
        entries.append(sgNotice(id, returnKeySection, sgString("SuperGram.ChatUI.Input.SendWithReturnKey.Notice", state)))

        let toolbarSection = SuperGramSettingsSection(self.group, block: 27)
        entries.append(sgToggle(id, toolbarSection, \.inputToolbar, text: sgString("SuperGram.ChatUI.Input.Toolbar", state)))
        entries.append(sgNotice(id, toolbarSection, sgString("SuperGram.ChatUI.Input.Toolbar.Notice", state)))

        let keyboardSection = SuperGramSettingsSection(self.group, block: 28)
        entries.append(sgHeader(id, keyboardSection, sgString("SuperGram.ChatUI.Input.Keyboard.Header", state)))
        entries.append(sgToggle(id, keyboardSection, \.forceEmojiTab, text: sgString("Settings.ForceEmojiTab", state)))
        entries.append(sgToggle(id, keyboardSection, \.defaultEmojisFirst, text: sgString("Settings.DefaultEmojisFirst", state)))
        entries.append(sgNotice(id, keyboardSection, sgString("SuperGram.ChatUI.Input.Keyboard.Notice", state)))

        let stickerSection = SuperGramSettingsSection(self.group, block: 29)
        entries.append(sgHeader(id, stickerSection, sgString("SuperGram.ChatUI.Input.Stickers.Header", state)))
        entries.append(sgHeader(id, stickerSection, sgString("Settings.Stickers.Size", state)))
        entries.append(.percentageSlider(id: id.count, section: stickerSection, settingName: self.inputStickerSizeSetting, value: SGSimpleSettings.shared.stickerSize))
        entries.append(sgToggle(id, stickerSection, \.stickerTimestamp, text: sgString("Settings.Stickers.Timestamp", state)))
        entries.append(sgNotice(id, stickerSection, sgString("SuperGram.ChatUI.Input.Stickers.Notice", state)))

        let doubleTapSection = SuperGramSettingsSection(self.group, block: 30)
        entries.append(sgToggle(id, doubleTapSection, \.sgDoubleTapSelectsText, text: sgString("SuperGram.ChatUI.DoubleTapSelectsText", state)))
        entries.append(sgNotice(id, doubleTapSection, sgString("SuperGram.ChatUI.DoubleTapSelectsText.Notice", state)))

        return entries
    }

    static func inputUpdateSliderValue(_ setting: String, value: Int32, actions: SuperGramSettingsActions) -> Bool {
        switch setting {
        case self.inputStickerSizeSetting:
            if SGSimpleSettings.shared.stickerSize != value {
                SGSimpleSettings.shared.stickerSize = value
            }
            return true
        default:
            return false
        }
    }
}
