// SuperGram: shared infrastructure of the "SuperGram" settings screen.
//
// Every feature stream owns exactly one section builder file in `SuperGramSections/`. A builder
// declares its group, returns its rows and (optionally) handles custom row callbacks. Adding rows
// never requires touching this file or SGSettingsController.swift.
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import AccountContext
import SGItemListUI
import SGSimpleSettings
import SGStrings

/// Top-level groups of the SuperGram screen, in display order. One group per stream.
enum SuperGramSettingsGroup: Int32 {
    case search = 0
    case media
    case downloads
    case transcription
    case protectedContent
    case sending
    case context
    case protect
    case ghost
    case chatList
    case chatUI
    case network
    case translate
    case app
}

/// Visual block (list section with rounded corners). A group can use up to 32 blocks.
struct SuperGramSettingsSection: SGItemListSection, Hashable {
    let rawValue: Int32

    init(_ group: SuperGramSettingsGroup, block: Int32 = 0) {
        self.rawValue = group.rawValue * 32 + max(0, min(31, block))
    }
}

/// How a toggle row writes its value.
enum SuperGramBoolSetting: Hashable {
    /// Writes the value into an SGSimpleSettings Bool property.
    case simple(ReferenceWritableKeyPath<SGSimpleSettings, Bool>)
    /// Same as `.simple`, then offers to restart the app.
    case simpleWithRestart(ReferenceWritableKeyPath<SGSimpleSettings, Bool>)
    /// The row shows ON when the stored flag is false (for `disableX`-style keys).
    case inverted(ReferenceWritableKeyPath<SGSimpleSettings, Bool>)
    /// Handled by the owning builder's `setBoolValue`. Use a stream-prefixed name, e.g. "transcription.local".
    case custom(String)
}

/// Row type of the SuperGram screen. Slider / one-from-many / disclosure / action ids are stream-prefixed strings.
typealias SuperGramSettingsEntry = SGItemListUIEntry<SuperGramSettingsSection, SuperGramBoolSetting, String, String, String, String>

/// Snapshot of everything a builder may need to produce its rows.
struct SuperGramSettingsState {
    let context: AccountContext
    let presentationData: PresentationData
    let mediaDisplaySettings: MediaDisplaySettings
    let experimentalUISettings: ExperimentalUISettings
    let callListSettings: CallListSettings

    var strings: PresentationStrings {
        return self.presentationData.strings
    }

    /// Language code for `i18n`.
    var lang: String {
        return self.presentationData.strings.baseLanguageCode
    }
}

/// Callbacks available to builders when a row is used.
final class SuperGramSettingsActions {
    let context: AccountContext
    fileprivate(set) var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    fileprivate(set) var pushControllerImpl: ((ViewController) -> Void)?
    fileprivate(set) var askForRestartImpl: (() -> Void)?
    fileprivate(set) var reloadImpl: (() -> Void)?

    init(context: AccountContext) {
        self.context = context
    }

    var presentationData: PresentationData {
        return self.context.sharedContext.currentPresentationData.with { $0 }
    }

    func present(_ controller: ViewController, _ arguments: ViewControllerPresentationArguments? = nil) {
        self.presentControllerImpl?(controller, arguments)
    }

    func push(_ controller: ViewController) {
        self.pushControllerImpl?(controller)
    }

    /// Shows the "Restart required" toast with a "Restart Now" button.
    func askForRestart() {
        self.askForRestartImpl?()
    }

    /// Rebuilds the rows (use after changing an SGSimpleSettings value that other rows depend on).
    func reload() {
        self.reloadImpl?()
    }

    /// Presents an action sheet with one button per option; the current option is bold.
    func presentOptions(_ options: [(title: String, isSelected: Bool, action: () -> Void)]) {
        let presentationData = self.presentationData
        let actionSheet = ActionSheetController(presentationData: presentationData)
        var items: [ActionSheetItem] = []
        for option in options {
            let action = option.action
            items.append(ActionSheetButtonItem(title: option.title, color: .accent, font: option.isSelected ? .bold : .default, action: { [weak actionSheet] in
                actionSheet?.dismissAnimated()
                action()
            }))
        }
        actionSheet.setItemGroups([
            ActionSheetItemGroup(items: items),
            ActionSheetItemGroup(items: [
                ActionSheetButtonItem(title: presentationData.strings.Common_Cancel, color: .accent, font: .bold, action: { [weak actionSheet] in
                    actionSheet?.dismissAnimated()
                })
            ])
        ])
        self.present(actionSheet, ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
    }
}

extension SuperGramSettingsActions {
    func bindPresent(_ f: @escaping (ViewController, ViewControllerPresentationArguments?) -> Void) {
        self.presentControllerImpl = f
    }

    func bindPush(_ f: @escaping (ViewController) -> Void) {
        self.pushControllerImpl = f
    }

    func bindAskForRestart(_ f: @escaping () -> Void) {
        self.askForRestartImpl = f
    }

    func bindReload(_ f: @escaping () -> Void) {
        self.reloadImpl = f
    }
}

/// One stream's part of the SuperGram screen. Only `group` and `entries` are required.
protocol SuperGramSettingsSectionBuilder {
    static var group: SuperGramSettingsGroup { get }

    /// Rows of this group. Use `SuperGramSettingsSection(Self.group, block: n)` for sections and `id.count` for ids.
    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry]

    /// Return true when `setting` belongs to this builder.
    static func setBoolValue(_ setting: String, value: Bool, actions: SuperGramSettingsActions) -> Bool
    static func setOneFromManyValue(_ setting: String, actions: SuperGramSettingsActions) -> Bool
    static func updateSliderValue(_ setting: String, value: Int32, actions: SuperGramSettingsActions) -> Bool
    static func openDisclosureLink(_ link: String, actions: SuperGramSettingsActions) -> Bool
    static func performAction(_ action: String, actions: SuperGramSettingsActions) -> Bool
}

extension SuperGramSettingsSectionBuilder {
    static func setBoolValue(_ setting: String, value: Bool, actions: SuperGramSettingsActions) -> Bool {
        return false
    }

    static func setOneFromManyValue(_ setting: String, actions: SuperGramSettingsActions) -> Bool {
        return false
    }

    static func updateSliderValue(_ setting: String, value: Int32, actions: SuperGramSettingsActions) -> Bool {
        return false
    }

    static func openDisclosureLink(_ link: String, actions: SuperGramSettingsActions) -> Bool {
        return false
    }

    static func performAction(_ action: String, actions: SuperGramSettingsActions) -> Bool {
        return false
    }
}

/// Display order of the builders. Each wave-2 stream already has its (initially empty) builder here.
let superGramSettingsSectionBuilders: [SuperGramSettingsSectionBuilder.Type] = [
    SuperGramMediaSection.self,
    SuperGramDownloadsSection.self,
    SuperGramTranscriptionSection.self,
    SuperGramProtectedContentSection.self,
    SuperGramSendingSection.self,
    SuperGramContextSection.self,
    SuperGramProtectSection.self,
    SuperGramGhostSection.self,
    SuperGramChatListSection.self,
    SuperGramChatUISection.self,
    SuperGramNetworkSection.self,
    SuperGramTranslateSection.self,
    SuperGramAppSection.self
]

// MARK: - Row helpers

/// Localized SuperGram string (SGLocalizable.strings, en/ru; other languages fall back to English).
func sgString(_ key: String, _ state: SuperGramSettingsState) -> String {
    return i18n(key, state.lang)
}

func sgHeader(_ id: SGItemListCounter, _ section: SuperGramSettingsSection, _ text: String) -> SuperGramSettingsEntry {
    return .header(id: id.count, section: section, text: text, badge: nil)
}

func sgNotice(_ id: SGItemListCounter, _ section: SuperGramSettingsSection, _ text: String) -> SuperGramSettingsEntry {
    return .notice(id: id.count, section: section, text: text)
}

/// Toggle bound directly to an SGSimpleSettings Bool property.
func sgToggle(_ id: SGItemListCounter, _ section: SuperGramSettingsSection, _ keyPath: ReferenceWritableKeyPath<SGSimpleSettings, Bool>, text: String, enabled: Bool = true, restart: Bool = false) -> SuperGramSettingsEntry {
    return .toggle(id: id.count, section: section, settingName: restart ? .simpleWithRestart(keyPath) : .simple(keyPath), value: SGSimpleSettings.shared[keyPath: keyPath], text: text, enabled: enabled)
}

/// Toggle shown ON when the SGSimpleSettings flag is false.
func sgInvertedToggle(_ id: SGItemListCounter, _ section: SuperGramSettingsSection, _ keyPath: ReferenceWritableKeyPath<SGSimpleSettings, Bool>, text: String, enabled: Bool = true) -> SuperGramSettingsEntry {
    return .toggle(id: id.count, section: section, settingName: .inverted(keyPath), value: !SGSimpleSettings.shared[keyPath: keyPath], text: text, enabled: enabled)
}

/// Toggle handled by the builder's `setBoolValue`.
func sgCustomToggle(_ id: SGItemListCounter, _ section: SuperGramSettingsSection, _ setting: String, value: Bool, text: String, enabled: Bool = true) -> SuperGramSettingsEntry {
    return .toggle(id: id.count, section: section, settingName: .custom(setting), value: value, text: text, enabled: enabled)
}
