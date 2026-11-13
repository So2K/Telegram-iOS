// SuperGram (DOWNLOAD-DIAGNOSTICS): the plain-text form of a snapshot, for the "Copy report" button.
//
// This is what the user pastes back to us when media hangs, so it is written to be read by us, not by them:
// untruncated resource ids, exact byte counts, explicit "n/a" for everything no source could supply, and the
// build/device header that tells us which binary produced it. Keep it ASCII and line-oriented.
import Foundation
import UIKit

private func superGramDeviceModelIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let mirror = Mirror(reflecting: systemInfo.machine)
    var identifier = ""
    for child in mirror.children {
        guard let value = child.value as? Int8, value != 0 else {
            continue
        }
        identifier.append(Character(UnicodeScalar(UInt8(bitPattern: value))))
    }
    return identifier.isEmpty ? "unknown" : identifier
}

public func superGramDownloadsDiagnosticsReport(_ snapshot: SuperGramDownloadsDiagnosticsSnapshot) -> String {
    var lines: [String] = []

    let info = Bundle.main.infoDictionary
    let shortVersion = (info?["CFBundleShortVersionString"] as? String) ?? "?"
    let build = (info?["CFBundleVersion"] as? String) ?? "?"

    let formatter = DateFormatter()
    // Fixed locale: a DateFormatter otherwise follows the device's calendar and hour cycle, so the same instant
    // is stamped "2569-…" on a Buddhist calendar or "…03:11:02 PM" on a 12-hour one — and this line is meant to
    // line up with server-side and log timestamps when several reports are compared.
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZ"

    lines.append("SuperGram download diagnostics")
    lines.append("app: \(shortVersion) (\(build))  ios: \(UIDevice.current.systemVersion)  device: \(superGramDeviceModelIdentifier())")
    lines.append("time: \(formatter.string(from: Date(timeIntervalSinceReferenceDate: snapshot.timestamp)))")
    lines.append("")

    lines.append("PRESSURE")
    lines.append("  level: \(snapshot.pressureLevelName) (\(snapshot.pressureLevelValue))")
    lines.append("  thermal: \(snapshot.thermalStateName)")
    lines.append("  low power mode: \(snapshot.isLowPowerModeEnabled ? "on" : "off")")
    lines.append("  pause-under-pressure setting: \(snapshot.isPauseUnderPressureEnabled ? "on" : "off")")
    if snapshot.isPressureReasonExact {
        lines.append("  memory pressure: \(snapshot.isMemoryPressureInferred ? "yes" : "no")")
    } else {
        lines.append("  memory pressure: \(snapshot.isMemoryPressureInferred ? "yes (inferred: level is above what thermal+low-power explain)" : "no (inferred)")")
    }
    lines.append("")

    lines.append("SETTINGS")
    lines.append("  speed mode: \(snapshot.speedModeName) (\(snapshot.speedModeValue))")
    lines.append("  parallel download limiter: \(snapshot.isDownloadLimiterEnabled ? "on" : "off")")
    lines.append("  background downloads: \(snapshot.isBackgroundDownloadsEnabled ? "on" : "off")")
    lines.append("")

    lines.append("FETCHV2 BUDGET")
    if let budget = snapshot.budget {
        lines.append("  interactive: \(budget.interactiveParts)/\(budget.interactiveLimit) parts, \(superGramDownloadsFormatBytes(budget.interactiveBytes)) in flight")
        lines.append("  background: \(budget.backgroundParts)/\(budget.backgroundLimit) parts, \(superGramDownloadsFormatBytes(budget.backgroundBytes)) in flight")
        lines.append("  bytes ceiling: \(superGramDownloadsFormatBytes(budget.maxInFlightBytes))")
        if let oldestWaiterAge = budget.oldestWaiterAge {
            lines.append("  waiters: \(budget.waiterCount) (\(budget.interactiveWaiterCount) interactive), oldest waiting \(superGramDownloadsFormatSeconds(oldestWaiterAge))")
        } else {
            lines.append("  waiters: \(budget.waiterCount) (\(budget.interactiveWaiterCount) interactive)")
        }
        for resourceId in budget.waiterResourceIds {
            lines.append("    waiter: \(resourceId)")
        }
    } else {
        lines.append("  n/a - TelegramCore does not expose the FetchV2 budget in this build")
    }
    lines.append("")

    lines.append("FETCH MANAGER")
    if let categories = snapshot.categories {
        for category in categories {
            if let limit = category.limit {
                lines.append("  \(category.name): active \(category.active)/\(limit), queued \(category.queued)")
            } else {
                lines.append("  \(category.name): active \(category.active), queued \(category.queued)")
            }
        }
    } else {
        lines.append("  per-category counts: n/a - FetchManagerImpl does not expose them in this build")
    }
    if let visibleEntries = snapshot.fetchManagerVisibleEntries {
        lines.append("  user-initiated entries visible through entriesSummary: \(visibleEntries)")
    } else {
        lines.append("  user-initiated entries visible through entriesSummary: n/a")
    }
    lines.append("")

    let fetchingCount = snapshot.fetches.filter({ $0.isFetching }).count
    lines.append("MEDIABOX RESOURCE CONTEXTS: \(snapshot.totalResourceContexts) live, \(snapshot.fetches.count) sampled, \(fetchingCount) fetching")
    if snapshot.fetches.isEmpty {
        lines.append("  (none)")
    }
    var index = 0
    for fetch in snapshot.fetches {
        index += 1
        var fields: [String] = []
        fields.append("status=\(fetch.statusDescription)")
        fields.append("recv=\(superGramDownloadsFormatBytes(fetch.receivedBytes))")
        if let totalSize = fetch.totalSize {
            fields.append("total=\(superGramDownloadsFormatBytes(totalSize))\(fetch.isTotalSizeEstimated ? "~" : "")")
        } else {
            fields.append("total=n/a")
        }
        if let inFlightParts = fetch.inFlightParts {
            fields.append("parts=\(inFlightParts)")
        } else {
            fields.append("parts=n/a")
        }
        if let lane = fetch.lane {
            fields.append("lane=\(lane.rawValue)")
        } else {
            fields.append("lane=n/a")
        }
        if let isBudgetWaiter = fetch.isBudgetWaiter {
            fields.append("waiter=\(isBudgetWaiter ? "yes" : "no")")
        } else {
            fields.append("waiter=n/a")
        }
        fields.append("noProgress=\(superGramDownloadsFormatSeconds(fetch.secondsSinceProgress))\(fetch.isProgressObservationTruncated ? "+" : "")")
        fields.append("observed=\(superGramDownloadsFormatSeconds(fetch.observedForSeconds))")
        lines.append("  [\(index)] \(fetch.resourceId)")
        lines.append("      " + fields.joined(separator: " "))
    }
    lines.append("")
    lines.append("legend:")
    lines.append("  noProgress \"+\": the resource never moved while the screen was open, so the real stall is")
    lines.append("    at least this long and probably older.")
    lines.append("  total \"~\": estimated from received bytes and reported progress, not read from the fetch.")
    lines.append("  status is MediaBox's own resource status. \"Fetching(idle)\" means a fetch exists but nothing")
    lines.append("    is in flight. \"Remote\" on a message that is showing a spinner means MediaBox is not")
    lines.append("    fetching at all and the entry is parked in the FetchManager queue for its category.")

    return lines.joined(separator: "\n")
}
