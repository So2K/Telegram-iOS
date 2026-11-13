// SuperGram (W2-CHATUI-HISTORY): editor for Swiftgram's message keyword filter (`messageFilterKeywords`).
// Swiftgram edits the list in a SwiftUI screen of its Pro module (needs SGSwiftUI); SuperGram uses a plain
// ItemList screen with one word or phrase per line. The dimming itself lives in ChatMessageItemImpl.
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import SGSimpleSettings
import SGStrings

private final class SuperGramMessageFilterControllerArguments {
    let updateText: (String) -> Void

    init(updateText: @escaping (String) -> Void) {
        self.updateText = updateText
    }
}

private enum SuperGramMessageFilterControllerSection: Int32 {
    case keywords
}

private enum SuperGramMessageFilterControllerEntry: ItemListNodeEntry {
    case keywords(text: String, placeholder: String)
    case notice(text: String)

    var section: ItemListSectionId {
        return SuperGramMessageFilterControllerSection.keywords.rawValue
    }

    var stableId: Int32 {
        switch self {
        case .keywords:
            return 0
        case .notice:
            return 1
        }
    }

    static func ==(lhs: SuperGramMessageFilterControllerEntry, rhs: SuperGramMessageFilterControllerEntry) -> Bool {
        switch lhs {
        case let .keywords(lhsText, lhsPlaceholder):
            if case let .keywords(rhsText, rhsPlaceholder) = rhs, lhsText == rhsText, lhsPlaceholder == rhsPlaceholder {
                return true
            } else {
                return false
            }
        case let .notice(lhsText):
            if case let .notice(rhsText) = rhs, lhsText == rhsText {
                return true
            } else {
                return false
            }
        }
    }

    static func <(lhs: SuperGramMessageFilterControllerEntry, rhs: SuperGramMessageFilterControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SuperGramMessageFilterControllerArguments
        switch self {
        case let .keywords(text, placeholder):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: placeholder, maxLength: nil, sectionId: self.section, style: .blocks, capitalization: false, autocorrection: false, minimalHeight: 120.0, textUpdated: { updatedText in
                arguments.updateText(updatedText)
            })
        case let .notice(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

/// Splits the editor text into keywords: one per line, trimmed, without empty lines and duplicates (case-insensitive).
func superGramParseMessageFilterKeywords(_ text: String) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    for line in text.components(separatedBy: CharacterSet.newlines) {
        let keyword = line.trimmingCharacters(in: CharacterSet.whitespaces)
        if keyword.isEmpty {
            continue
        }
        let normalized = keyword.lowercased()
        if seen.contains(normalized) {
            continue
        }
        seen.insert(normalized)
        result.append(keyword)
    }
    return result
}

func superGramMessageFilterController(context: AccountContext, completion: @escaping () -> Void) -> ViewController {
    let initialText = SGSimpleSettings.shared.messageFilterKeywords.joined(separator: "\n")
    let textPromise = ValuePromise(initialText, ignoreRepeated: true)
    let textValue = Atomic(value: initialText)

    var dismissImpl: (() -> Void)?

    let arguments = SuperGramMessageFilterControllerArguments(updateText: { text in
        textPromise.set(textValue.modify { _ in
            return text
        })
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        textPromise.get()
    )
    |> map { presentationData, text -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode

        let leftNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
            dismissImpl?()
        })
        let rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Done), style: .bold, enabled: true, action: {
            SGSimpleSettings.shared.messageFilterKeywords = superGramParseMessageFilterKeywords(textValue.with { $0 })
            completion()
            dismissImpl?()
        })

        let entries: [SuperGramMessageFilterControllerEntry] = [
            .keywords(text: text, placeholder: i18n("SuperGram.ChatUI.History.MessageFilter.Placeholder", lang)),
            .notice(text: i18n("SuperGram.ChatUI.History.MessageFilter.EditorNotice", lang))
        ]

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("SuperGram.ChatUI.History.MessageFilter", lang)), leftNavigationButton: leftNavigationButton, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: false)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .modal
    dismissImpl = { [weak controller] in
        controller?.view.endEditing(true)
        controller?.dismiss()
    }
    return controller
}
