// SuperGram (DOWNLOAD-DIAGNOSTICS): Settings -> SuperGram -> Downloads -> "Download diagnostics".
//
// A live view of the download pipeline for a user who has no logs: pressure level and what raised it,
// FetchV2 budget, every media resource with a live MediaBox context (received bytes, status, how long it has
// been standing still), FetchManager counts and the speed mode. Refreshes once a second, and only while it is
// actually on screen — the sampler is started from didAppear, stopped from didDisappear, and suspended while
// the app is in the background (didDisappear does not fire for backgrounding).
//
// Two buttons: copy the whole snapshot as text (so the user can paste it to us) and reset every download that
// has not moved for `superGramDownloadStallThreshold` (60 s).
import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import TextFormat
import UndoUI
import SGStrings

private final class SuperGramDownloadsDiagnosticsArguments {
    let copyReport: () -> Void
    let resetStalled: () -> Void

    init(copyReport: @escaping () -> Void, resetStalled: @escaping () -> Void) {
        self.copyReport = copyReport
        self.resetStalled = resetStalled
    }
}

private enum SuperGramDownloadsDiagnosticsSection: Int32 {
    case state = 0
    case budget = 1
    case fetchManager = 2
    case fetches = 3
    case actions = 4
}

private enum SuperGramDownloadsDiagnosticsEntry: ItemListNodeEntry {
    case header(id: Int32, section: Int32, text: String)
    case value(id: Int32, section: Int32, label: String, text: String, isAlert: Bool)
    case notice(id: Int32, section: Int32, text: String)
    case action(id: Int32, section: Int32, text: String, isDestructive: Bool)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _):
            return section
        case let .value(_, section, _, _, _):
            return section
        case let .notice(_, section, _):
            return section
        case let .action(_, section, _, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _):
            return id
        case let .value(id, _, _, _, _):
            return id
        case let .notice(id, _, _):
            return id
        case let .action(id, _, _, _):
            return id
        }
    }

    static func ==(lhs: SuperGramDownloadsDiagnosticsEntry, rhs: SuperGramDownloadsDiagnosticsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lhsId, lhsSection, lhsText), .header(rhsId, rhsSection, rhsText)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsText == rhsText
        case let (.value(lhsId, lhsSection, lhsLabel, lhsText, lhsIsAlert), .value(rhsId, rhsSection, rhsLabel, rhsText, rhsIsAlert)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsLabel == rhsLabel && lhsText == rhsText && lhsIsAlert == rhsIsAlert
        case let (.notice(lhsId, lhsSection, lhsText), .notice(rhsId, rhsSection, rhsText)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsText == rhsText
        case let (.action(lhsId, lhsSection, lhsText, lhsIsDestructive), .action(rhsId, rhsSection, rhsText, rhsIsDestructive)):
            return lhsId == rhsId && lhsSection == rhsSection && lhsText == rhsText && lhsIsDestructive == rhsIsDestructive
        default:
            return false
        }
    }

    static func <(lhs: SuperGramDownloadsDiagnosticsEntry, rhs: SuperGramDownloadsDiagnosticsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SuperGramDownloadsDiagnosticsArguments
        switch self {
        case let .header(_, _, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .value(_, _, label, text, isAlert):
            return ItemListTextWithLabelItem(presentationData: presentationData, label: label, text: text, style: .blocks, labelColor: isAlert ? .accent : .primary, textColor: .primary, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: nil)
        case let .notice(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .action(_, _, text, isDestructive):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: text, kind: isDestructive ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if isDestructive {
                    arguments.resetStalled()
                } else {
                    arguments.copyReport()
                }
            })
        }
    }
}

private func superGramDownloadsDiagnosticsEntries(snapshot: SuperGramDownloadsDiagnosticsSnapshot, lang: String) -> [SuperGramDownloadsDiagnosticsEntry] {
    var entries: [SuperGramDownloadsDiagnosticsEntry] = []
    let unavailable = i18n("SuperGram.Downloads.Diagnostics.Unavailable", lang)
    let onText = i18n("SuperGram.Downloads.Diagnostics.On", lang)
    let offText = i18n("SuperGram.Downloads.Diagnostics.Off", lang)

    let stateSection = SuperGramDownloadsDiagnosticsSection.state.rawValue
    entries.append(.header(id: 0, section: stateSection, text: i18n("SuperGram.Downloads.Diagnostics.State", lang)))
    entries.append(.value(id: 1, section: stateSection, label: i18n("SuperGram.Downloads.Diagnostics.Pressure", lang), text: "\(snapshot.pressureLevelName) (\(snapshot.pressureLevelValue))", isAlert: snapshot.pressureLevelValue > 0))
    entries.append(.value(id: 2, section: stateSection, label: i18n("SuperGram.Downloads.Diagnostics.Thermal", lang), text: snapshot.thermalStateName, isAlert: false))
    entries.append(.value(id: 3, section: stateSection, label: i18n("SuperGram.Downloads.Diagnostics.LowPower", lang), text: snapshot.isLowPowerModeEnabled ? onText : offText, isAlert: false))
    let memoryText: String
    if snapshot.isMemoryPressureInferred {
        memoryText = snapshot.isPressureReasonExact ? onText : i18n("SuperGram.Downloads.Diagnostics.Memory.Inferred", lang)
    } else {
        memoryText = offText
    }
    entries.append(.value(id: 4, section: stateSection, label: i18n("SuperGram.Downloads.Diagnostics.Memory", lang), text: memoryText, isAlert: snapshot.isMemoryPressureInferred))
    entries.append(.value(id: 5, section: stateSection, label: i18n("SuperGram.Downloads.Diagnostics.SpeedMode", lang), text: "\(snapshot.speedModeName) (\(snapshot.speedModeValue))", isAlert: false))
    entries.append(.value(id: 6, section: stateSection, label: i18n("SuperGram.Downloads.Diagnostics.Limiter", lang), text: snapshot.isDownloadLimiterEnabled ? onText : offText, isAlert: false))
    // Collected for the report anyway, and it is one of the two settings that decide whether a download is
    // allowed to make progress at all, so it belongs on screen next to the limiter.
    entries.append(.value(id: 7, section: stateSection, label: i18n("SuperGram.Downloads.Background", lang), text: snapshot.isBackgroundDownloadsEnabled ? onText : offText, isAlert: false))
    entries.append(.notice(id: 8, section: stateSection, text: i18n("SuperGram.Downloads.Diagnostics.Notice", lang)))

    let budgetSection = SuperGramDownloadsDiagnosticsSection.budget.rawValue
    entries.append(.header(id: 10, section: budgetSection, text: i18n("SuperGram.Downloads.Diagnostics.Budget", lang)))
    if let budget = snapshot.budget {
        entries.append(.value(id: 11, section: budgetSection, label: i18n("SuperGram.Downloads.Diagnostics.Budget.Interactive", lang), text: "\(budget.interactiveParts)/\(budget.interactiveLimit), \(superGramDownloadsFormatBytes(budget.interactiveBytes))", isAlert: false))
        entries.append(.value(id: 12, section: budgetSection, label: i18n("SuperGram.Downloads.Diagnostics.Budget.Background", lang), text: "\(budget.backgroundParts)/\(budget.backgroundLimit), \(superGramDownloadsFormatBytes(budget.backgroundBytes))", isAlert: false))
        var waitersText = "\(budget.waiterCount)"
        if let oldestWaiterAge = budget.oldestWaiterAge {
            waitersText += " · \(superGramDownloadsFormatSeconds(oldestWaiterAge))"
        }
        entries.append(.value(id: 13, section: budgetSection, label: i18n("SuperGram.Downloads.Diagnostics.Budget.Waiters", lang), text: waitersText, isAlert: (budget.oldestWaiterAge ?? 0.0) >= superGramDownloadStallThreshold))
    } else {
        entries.append(.value(id: 11, section: budgetSection, label: i18n("SuperGram.Downloads.Diagnostics.Budget.Interactive", lang), text: unavailable, isAlert: false))
        entries.append(.value(id: 12, section: budgetSection, label: i18n("SuperGram.Downloads.Diagnostics.Budget.Background", lang), text: unavailable, isAlert: false))
        entries.append(.value(id: 13, section: budgetSection, label: i18n("SuperGram.Downloads.Diagnostics.Budget.Waiters", lang), text: unavailable, isAlert: false))
    }

    let fetchManagerSection = SuperGramDownloadsDiagnosticsSection.fetchManager.rawValue
    entries.append(.header(id: 20, section: fetchManagerSection, text: i18n("SuperGram.Downloads.Diagnostics.FetchManager", lang)))
    var fetchManagerId: Int32 = 21
    if let categories = snapshot.categories {
        for category in categories {
            var text = "\(category.active)"
            if let limit = category.limit {
                text += "/\(limit)"
            }
            text += " · \(category.queued)"
            entries.append(.value(id: fetchManagerId, section: fetchManagerSection, label: category.name, text: text, isAlert: false))
            fetchManagerId += 1
            // Ids 29+ belong to the rows below; a provider that reports more categories than expected must not
            // silently overwrite them.
            if fetchManagerId >= 29 {
                break
            }
        }
    } else {
        entries.append(.value(id: fetchManagerId, section: fetchManagerSection, label: i18n("SuperGram.Downloads.Diagnostics.FetchManager.Categories", lang), text: unavailable, isAlert: false))
        fetchManagerId += 1
    }
    entries.append(.value(id: 29, section: fetchManagerSection, label: i18n("SuperGram.Downloads.Diagnostics.FetchManager.Entries", lang), text: snapshot.fetchManagerVisibleEntries.flatMap({ "\($0)" }) ?? unavailable, isAlert: false))

    let fetchesSection = SuperGramDownloadsDiagnosticsSection.fetches.rawValue
    let fetchingCount = snapshot.fetches.filter({ $0.isFetching }).count
    entries.append(.header(id: 30, section: fetchesSection, text: "\(i18n("SuperGram.Downloads.Diagnostics.Fetches", lang)) · \(fetchingCount)/\(snapshot.totalResourceContexts)"))
    if snapshot.fetches.isEmpty {
        entries.append(.value(id: 31, section: fetchesSection, label: i18n("SuperGram.Downloads.Diagnostics.Fetches.Empty", lang), text: "—", isAlert: false))
    } else {
        var fetchId: Int32 = 31
        for fetch in snapshot.fetches {
            var label = fetch.shortResourceId
            let isStalled = fetch.isFetching && fetch.secondsSinceProgress >= superGramDownloadStallThreshold
            if isStalled {
                label = "\(i18n("SuperGram.Downloads.Diagnostics.Stalled", lang)) · \(label)"
            }

            var fields: [String] = []
            fields.append(fetch.statusDescription)
            if let totalSize = fetch.totalSize {
                fields.append("\(superGramDownloadsFormatBytes(fetch.receivedBytes)) / \(superGramDownloadsFormatBytes(totalSize))\(fetch.isTotalSizeEstimated ? "~" : "")")
            } else {
                fields.append("\(superGramDownloadsFormatBytes(fetch.receivedBytes)) / ?")
            }
            if let inFlightParts = fetch.inFlightParts {
                fields.append("\(i18n("SuperGram.Downloads.Diagnostics.Fetch.Parts", lang)) \(inFlightParts)")
            }
            if let lane = fetch.lane {
                fields.append(lane.rawValue)
            }
            if fetch.isBudgetWaiter == true {
                fields.append(i18n("SuperGram.Downloads.Diagnostics.Fetch.Waiting", lang))
            }
            fields.append("\(i18n("SuperGram.Downloads.Diagnostics.Fetch.NoProgress", lang)) \(superGramDownloadsFormatSeconds(fetch.secondsSinceProgress))\(fetch.isProgressObservationTruncated ? "+" : "")")

            entries.append(.value(id: fetchId, section: fetchesSection, label: label, text: fields.joined(separator: " · "), isAlert: isStalled))
            fetchId += 1
            if fetchId >= 130 {
                break
            }
        }
    }

    let actionsSection = SuperGramDownloadsDiagnosticsSection.actions.rawValue
    entries.append(.action(id: 200, section: actionsSection, text: i18n("SuperGram.Downloads.Diagnostics.Copy", lang), isDestructive: false))
    entries.append(.action(id: 201, section: actionsSection, text: i18n("SuperGram.Downloads.Diagnostics.Reset", lang), isDestructive: true))
    entries.append(.notice(id: 202, section: actionsSection, text: i18n("SuperGram.Downloads.Diagnostics.Reset.Notice", lang)))

    return entries
}

public func superGramDownloadsDiagnosticsController(context: AccountContext) -> ViewController {
    let collector = SuperGramDownloadsDiagnosticsCollector(context: context)
    let latestSnapshot = Atomic<SuperGramDownloadsDiagnosticsSnapshot>(value: SuperGramDownloadsDiagnosticsSnapshot.empty())

    var presentImpl: ((ViewController) -> Void)?

    let presentToast: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentImpl?(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in
            return true
        }))
    }

    let arguments = SuperGramDownloadsDiagnosticsArguments(copyReport: {
        let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        UIPasteboard.general.string = superGramDownloadsDiagnosticsReport(latestSnapshot.with { $0 })
        presentToast(i18n("SuperGram.Downloads.Diagnostics.Copied", lang))
    }, resetStalled: {
        let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
        collector.resetStalledFetches(completion: { count in
            if count == 0 {
                presentToast(i18n("SuperGram.Downloads.Diagnostics.Reset.None", lang))
            } else {
                // `i18n` is a function value, so the variadic `args:` label is erased: extra arguments are
                // passed positionally, exactly like the other "%@" strings in SGLocalizable.strings.
                presentToast(i18n("SuperGram.Downloads.Diagnostics.Reset.Done", lang, "\(count)"))
            }
        })
    })

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        collector.snapshot
    )
    |> map { presentationData, snapshot -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let _ = latestSnapshot.swap(snapshot)
        let lang = presentationData.strings.baseLanguageCode

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(i18n("SuperGram.Downloads.Diagnostics", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: false)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: superGramDownloadsDiagnosticsEntries(snapshot: snapshot, lang: lang), style: .blocks, animateChanges: false)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    // The sampler is the only cost of this screen, and it runs only while the screen is actually visible.
    controller.didAppear = { _ in
        collector.start()
    }
    controller.didDisappear = { _ in
        collector.stop()
    }
    presentImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
