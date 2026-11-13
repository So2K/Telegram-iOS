import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import AccountContext
import ItemListUI
import ItemListPeerItem
import PresentationDataUtils
import SGStrings

// SuperGram: "History" screen — every chat the user opened, newest first, reopened at the place they left off.

/// A history entry whose peer could be resolved, ready to display or open.
public struct SuperGramResolvedHistoryEntry: Equatable {
    public let entry: SuperGramChatHistoryEntry
    public let peer: EnginePeer
}

/// Resolves the stored history of the current account to peers (entries whose peer is gone are skipped).
public func superGramResolvedChatHistory(context: AccountContext, excludingPeerId: EnginePeer.Id? = nil) -> Signal<[SuperGramResolvedHistoryEntry], NoError> {
    return SuperGramChatHistory.shared.entries(accountPeerId: context.account.peerId)
    |> mapToSignal { entries -> Signal<[SuperGramResolvedHistoryEntry], NoError> in
        let filtered = entries.filter { $0.enginePeerId != excludingPeerId }
        if filtered.isEmpty {
            return .single([])
        }
        var peerIds: [EnginePeer.Id] = []
        for entry in filtered where !peerIds.contains(entry.enginePeerId) {
            peerIds.append(entry.enginePeerId)
        }
        return context.engine.data.subscribe(EngineDataMap(peerIds.map(TelegramEngine.EngineData.Item.Peer.Peer.init(id:))))
        |> map { peers -> [SuperGramResolvedHistoryEntry] in
            var result: [SuperGramResolvedHistoryEntry] = []
            for entry in filtered {
                if let maybePeer = peers[entry.enginePeerId], let peer = maybePeer {
                    result.append(SuperGramResolvedHistoryEntry(entry: entry, peer: peer))
                }
            }
            return result
        }
    }
}

/// Opens a history entry at the saved position (or at the latest messages when no position was saved).
public func superGramOpenHistoryEntry(context: AccountContext, navigationController: NavigationController, entry: SuperGramResolvedHistoryEntry) {
    let messageId = entry.entry.savedMessageId
    if let threadId = entry.entry.threadId {
        let _ = context.sharedContext.navigateToForumThread(context: context, peerId: entry.peer.id, threadId: threadId, messageId: messageId, navigationController: navigationController, activateInput: nil, scrollToEndIfExists: false, keepStack: .never, animated: true).startStandalone()
    } else {
        let subject: ChatControllerSubject? = messageId.flatMap { messageId in
            return .message(id: .id(messageId), highlight: nil, timecode: nil, setupReply: false)
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(entry.peer), subject: subject, keepStack: .never, useExisting: subject == nil))
    }
}

/// "5 min ago" style label for a history entry, plus a hint when a reading position is saved.
public func superGramHistoryEntrySubtitle(entry: SuperGramChatHistoryEntry, lang: String) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = Locale(identifier: lang)
    formatter.unitsStyle = .full
    let date = Date(timeIntervalSince1970: TimeInterval(entry.timestamp))
    var text: String
    if Date().timeIntervalSince(date) < 60.0 {
        text = i18n("SuperGram.History.JustNow", lang)
    } else {
        text = formatter.localizedString(for: date, relativeTo: Date())
    }
    if entry.threadId != nil, !entry.title.isEmpty {
        text = entry.title + " · " + text
    }
    if entry.savedMessageId != nil {
        text += " · " + i18n("SuperGram.History.PositionSaved", lang)
    }
    return text
}

private final class SuperGramChatHistoryArguments {
    let context: AccountContext
    let open: (SuperGramResolvedHistoryEntry) -> Void
    let remove: (SuperGramChatHistoryEntry) -> Void
    /// (revealed key, key of the item reporting the change) — mirrors ItemListPeerItem's (peerId, fromPeerId).
    let setRevealed: (String?, String?) -> Void

    init(context: AccountContext, open: @escaping (SuperGramResolvedHistoryEntry) -> Void, remove: @escaping (SuperGramChatHistoryEntry) -> Void, setRevealed: @escaping (String?, String?) -> Void) {
        self.context = context
        self.open = open
        self.remove = remove
        self.setRevealed = setRevealed
    }
}

private func superGramHistoryEntryKey(_ entry: SuperGramChatHistoryEntry) -> String {
    if let threadId = entry.threadId {
        return "\(entry.peerId):\(threadId)"
    } else {
        return "\(entry.peerId)"
    }
}

private enum SuperGramChatHistoryListEntry: ItemListNodeEntry {
    case item(index: Int32, resolved: SuperGramResolvedHistoryEntry, subtitle: String, revealed: Bool, dateTimeFormat: PresentationDateTimeFormat, nameDisplayOrder: PresentationPersonNameOrder)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .item:
            return 0
        case .footer:
            return 1
        }
    }

    var stableId: String {
        switch self {
        case let .item(_, resolved, _, _, _, _):
            return superGramHistoryEntryKey(resolved.entry)
        case .footer:
            return "footer"
        }
    }

    static func ==(lhs: SuperGramChatHistoryListEntry, rhs: SuperGramChatHistoryListEntry) -> Bool {
        switch lhs {
        case let .item(lhsIndex, lhsResolved, lhsSubtitle, lhsRevealed, lhsDateTimeFormat, lhsNameDisplayOrder):
            if case let .item(rhsIndex, rhsResolved, rhsSubtitle, rhsRevealed, rhsDateTimeFormat, rhsNameDisplayOrder) = rhs {
                return lhsIndex == rhsIndex && lhsResolved == rhsResolved && lhsSubtitle == rhsSubtitle && lhsRevealed == rhsRevealed && lhsDateTimeFormat == rhsDateTimeFormat && lhsNameDisplayOrder == rhsNameDisplayOrder
            }
            return false
        case let .footer(lhsText):
            if case let .footer(rhsText) = rhs {
                return lhsText == rhsText
            }
            return false
        }
    }

    static func <(lhs: SuperGramChatHistoryListEntry, rhs: SuperGramChatHistoryListEntry) -> Bool {
        switch lhs {
        case let .item(lhsIndex, _, _, _, _, _):
            if case let .item(rhsIndex, _, _, _, _, _) = rhs {
                return lhsIndex < rhsIndex
            }
            return true
        case .footer:
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SuperGramChatHistoryArguments
        switch self {
        case let .item(_, resolved, subtitle, revealed, dateTimeFormat, nameDisplayOrder):
            let lang = presentationData.strings.baseLanguageCode
            let key = superGramHistoryEntryKey(resolved.entry)
            let revealOptions = ItemListPeerItemRevealOptions(options: [ItemListPeerItemRevealOption(type: .destructive, title: i18n("SuperGram.History.Remove", lang), action: {
                arguments.remove(resolved.entry)
            })])
            return ItemListPeerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: dateTimeFormat, nameDisplayOrder: nameDisplayOrder, context: arguments.context, peer: resolved.peer, presence: nil, text: .text(subtitle, .secondary), label: .none, editing: ItemListPeerItemEditing(editable: true, editing: false, revealed: revealed), revealOptions: revealOptions, switchValue: nil, enabled: true, selectable: true, sectionId: self.section, action: {
                arguments.open(resolved)
            }, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
                arguments.setRevealed(peerId != nil ? key : nil, fromPeerId != nil ? key : nil)
            }, removePeer: { _ in
                arguments.remove(resolved.entry)
            })
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func superGramChatHistoryScreen(context: AccountContext) -> ViewController {
    var navigationControllerImpl: (() -> NavigationController?)?
    var presentImpl: ((ViewController) -> Void)?

    let revealedKey = ValuePromise<String?>(nil, ignoreRepeated: true)
    let revealedKeyValue = Atomic<String?>(value: nil)

    let arguments = SuperGramChatHistoryArguments(context: context, open: { resolved in
        guard let navigationController = navigationControllerImpl?() else {
            return
        }
        superGramOpenHistoryEntry(context: context, navigationController: navigationController, entry: resolved)
    }, remove: { entry in
        SuperGramChatHistory.shared.remove(accountPeerId: context.account.peerId, peerId: entry.peerId, threadId: entry.threadId)
    }, setRevealed: { key, fromKey in
        // Same rule as the stock peer lists: a closing item may only clear its own reveal, so revealing another
        // row is not undone by the previous row reporting that it closed.
        var updated = false
        let _ = revealedKeyValue.modify { current in
            if (key == nil && fromKey == current) || (key != nil && fromKey == nil) {
                updated = true
                return key
            }
            return current
        }
        if updated {
            revealedKey.set(key)
        }
    })

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, superGramResolvedChatHistory(context: context), revealedKey.get())
    |> map { presentationData, resolvedEntries, revealed -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode

        var rightNavigationButton: ItemListNavigationButton?
        if !resolvedEntries.isEmpty {
            rightNavigationButton = ItemListNavigationButton(content: .text(i18n("SuperGram.History.Clear", lang)), style: .regular, enabled: true, action: {
                let alert = textAlertController(context: context, title: i18n("SuperGram.History.ClearTitle", lang), text: i18n("SuperGram.History.ClearText", lang), actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: i18n("SuperGram.History.Clear", lang), action: {
                        SuperGramChatHistory.shared.clear(accountPeerId: context.account.peerId)
                    })
                ])
                presentImpl?(alert)
            })
        }

        var entries: [SuperGramChatHistoryListEntry] = []
        for (index, resolved) in resolvedEntries.enumerated() {
            let key = superGramHistoryEntryKey(resolved.entry)
            entries.append(.item(index: Int32(index), resolved: resolved, subtitle: superGramHistoryEntrySubtitle(entry: resolved.entry, lang: lang), revealed: key == revealed, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder))
        }
        if !entries.isEmpty {
            entries.append(.footer(i18n("SuperGram.History.Footer", lang)))
        }

        var emptyStateItem: ItemListControllerEmptyStateItem?
        if resolvedEntries.isEmpty {
            emptyStateItem = ItemListTextEmptyStateItem(text: i18n("SuperGram.History.Empty", lang))
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("SuperGram.History.Title", lang)), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, emptyStateItem: emptyStateItem, animateChanges: true, scrollEnabled: emptyStateItem == nil)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
