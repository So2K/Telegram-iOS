// MARK: Swiftgram
// SuperGram: restructured Swiftgram settings screen, titled "SuperGram".
// Rows are produced by the per-stream builders in SuperGramSections/*.swift (see SuperGramSettingsCore.swift).
// Removed from the Swiftgram original: SGAPIToken / content settings link, server web settings,
// Pro / paywall rows, New Year effects, registration date, and every row whose hook is not ported.
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import PresentationDataUtils
import AccountContext
import UndoUI
import SGItemListUI
import SGSimpleSettings
import SGStrings

private struct SGSettingsControllerState: Equatable {
    var searchQuery: String?
}

private let sortedSuperGramSettingsSectionBuilders: [SuperGramSettingsSectionBuilder.Type] = superGramSettingsSectionBuilders.sorted(by: { lhs, rhs in
    return lhs.group.rawValue < rhs.group.rawValue
})

private func SGControllerEntries(state: SuperGramSettingsState, controllerState: SGSettingsControllerState) -> [SuperGramSettingsEntry] {
    var entries: [SuperGramSettingsEntry] = []

    let searchId = SGItemListCounter()
    entries.append(.searchInput(id: searchId.count, section: SuperGramSettingsSection(.search), title: NSAttributedString(string: "🔍"), text: controllerState.searchQuery ?? "", placeholder: state.strings.Common_Search))

    for builder in sortedSuperGramSettingsSectionBuilders {
        // Stable ids are namespaced per group so rows of one stream never shift the ids of another.
        let id = SGItemListCounter()
        id.increment(Int(builder.group.rawValue) * 10000)
        entries.append(contentsOf: builder.entries(state: state, id: id))
    }

    return filterSGItemListUIEntrires(entries: entries, by: controllerState.searchQuery)
}

public func sgSettingsController(context: AccountContext) -> ViewController {
    let actions = SuperGramSettingsActions(context: context)

    let initialState = SGSettingsControllerState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((SGSettingsControllerState) -> SGSettingsControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    actions.bindReload({
        simplePromise.set(true)
    })

    let arguments = SGItemListArguments<SuperGramBoolSetting, String, String, String, String>(
        context: context,
        setBoolValue: { setting, value in
            switch setting {
            case let .simple(keyPath):
                SGSimpleSettings.shared[keyPath: keyPath] = value
                actions.reload()
            case let .simpleWithRestart(keyPath):
                SGSimpleSettings.shared[keyPath: keyPath] = value
                actions.reload()
                actions.askForRestart()
            case let .inverted(keyPath):
                SGSimpleSettings.shared[keyPath: keyPath] = !value
                actions.reload()
            case let .custom(name):
                for builder in sortedSuperGramSettingsSectionBuilders {
                    if builder.setBoolValue(name, value: value, actions: actions) {
                        break
                    }
                }
            }
        },
        updateSliderValue: { setting, value in
            for builder in sortedSuperGramSettingsSectionBuilders {
                if builder.updateSliderValue(setting, value: value, actions: actions) {
                    break
                }
            }
        },
        setOneFromManyValue: { setting in
            for builder in sortedSuperGramSettingsSectionBuilders {
                if builder.setOneFromManyValue(setting, actions: actions) {
                    break
                }
            }
        },
        openDisclosureLink: { link in
            for builder in sortedSuperGramSettingsSectionBuilders {
                if builder.openDisclosureLink(link, actions: actions) {
                    break
                }
            }
        },
        action: { action in
            for builder in sortedSuperGramSettingsSectionBuilders {
                if builder.performAction(action, actions: actions) {
                    break
                }
            }
        },
        searchInput: { searchQuery in
            updateState { state in
                var updatedState = state
                updatedState.searchQuery = searchQuery
                return updatedState
            }
        }
    )

    let sharedData = context.sharedContext.accountManager.sharedData(keys: [
        ApplicationSpecificSharedDataKeys.mediaDisplaySettings,
        ApplicationSpecificSharedDataKeys.experimentalUISettings,
        ApplicationSpecificSharedDataKeys.callListSettings
    ])

    let signal = combineLatest(queue: .mainQueue(),
        simplePromise.get(),
        statePromise.get(),
        context.sharedContext.presentationData,
        sharedData
    )
    |> map { _, controllerState, presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let mediaDisplaySettings = sharedData.entries[ApplicationSpecificSharedDataKeys.mediaDisplaySettings]?.get(MediaDisplaySettings.self) ?? MediaDisplaySettings.defaultSettings
        let experimentalUISettings = sharedData.entries[ApplicationSpecificSharedDataKeys.experimentalUISettings]?.get(ExperimentalUISettings.self) ?? ExperimentalUISettings.defaultSettings
        let callListSettings = sharedData.entries[ApplicationSpecificSharedDataKeys.callListSettings]?.get(CallListSettings.self) ?? CallListSettings.defaultSettings

        let state = SuperGramSettingsState(
            context: context,
            presentationData: presentationData,
            mediaDisplaySettings: mediaDisplaySettings,
            experimentalUISettings: experimentalUISettings,
            callListSettings: callListSettings
        )
        let entries = SGControllerEntries(state: state, controllerState: controllerState)

        let itemListControllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("SuperGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: nil, initialScrollToItem: nil)

        return (itemListControllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    actions.bindPresent({ [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    })
    actions.bindPush({ [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    })
    actions.bindAskForRestart({ [weak controller] in
        guard let controller else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        controller.present(
            UndoOverlayController(
                presentationData: presentationData,
                content: .info(title: nil,
                    text: i18n("Common.RestartRequired", lang),
                    timeout: nil,
                    customUndoText: i18n("Common.RestartNow", lang)
                ),
                elevatedLayout: false,
                action: { action in
                    if action == .undo {
                        exit(0)
                    }
                    return true
                }
            ),
            in: .window(.root)
        )
    })
    return controller
}
