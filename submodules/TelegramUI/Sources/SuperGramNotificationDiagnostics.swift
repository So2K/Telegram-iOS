import Foundation
import UIKit
import UserNotifications
import TelegramCore

// SuperGram: a small always-on journal of the notification pipeline (keep-alive state, local fallback decisions,
// what iOS has on screen, taps), written to <rootPath>/logs/sg-notifications.txt in the app group container so it
// can be read off the device with `devicectl device copy from --domain-type appGroupDataContainer`. Independent of
// the regular (off by default) file logging. Message text is never written, only its length.
final class SuperGramNotificationDiagnostics {
    static let shared = SuperGramNotificationDiagnostics()

    private static let maxFileSize: UInt64 = 768 * 1024

    private let queue = DispatchQueue(label: "SuperGramNotificationDiagnostics")
    private var path: String?
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private init() {
    }

    func setRootPath(_ rootPath: String) {
        let directory = rootPath + "/logs"
        self.queue.async {
            let _ = try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
            self.path = directory + "/sg-notifications.txt"
        }
    }

    func log(_ text: String) {
        let date = Date()
        let applicationState: String
        if Thread.isMainThread {
            applicationState = SuperGramNotificationDiagnostics.describe(UIApplication.shared.applicationState)
        } else {
            applicationState = "?"
        }
        self.queue.async {
            guard let path = self.path else {
                return
            }
            let line = "\(self.dateFormatter.string(from: date)) [\(applicationState)] \(text)\n"
            guard let data = line.data(using: .utf8) else {
                return
            }
            if let attributes = try? FileManager.default.attributesOfItem(atPath: path), let size = attributes[.size] as? UInt64, size > SuperGramNotificationDiagnostics.maxFileSize {
                let previousPath = path + ".1"
                let _ = try? FileManager.default.removeItem(atPath: previousPath)
                let _ = try? FileManager.default.moveItem(atPath: path, toPath: previousPath)
            }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                let _ = try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }

    /// One line per notification iOS currently shows for this app (Notification Center / lock screen), newest first.
    func dumpDeliveredNotifications(reason: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings(completionHandler: { settings in
            let previews: String
            switch settings.showPreviewsSetting {
            case .always:
                previews = "always"
            case .whenAuthenticated:
                previews = "whenUnlocked"
            case .never:
                previews = "never"
            @unknown default:
                previews = "unknown"
            }
            self.log("settings(\(reason)): auth=\(settings.authorizationStatus.rawValue) alert=\(settings.alertSetting.rawValue) lockScreen=\(settings.lockScreenSetting.rawValue) center=\(settings.notificationCenterSetting.rawValue) previews=\(previews)")
        })
        center.getDeliveredNotifications(completionHandler: { notifications in
            let sorted = notifications.sorted(by: { $0.date > $1.date })
            self.log("delivered(\(reason)): \(sorted.count)")
            for notification in sorted.prefix(15) {
                self.log("  " + SuperGramNotificationDiagnostics.describe(notification))
            }
        })
    }

    static func describe(_ notification: UNNotification) -> String {
        let content = notification.request.content
        let userInfo = content.userInfo
        let isFallback = (userInfo[telegramLocalNotificationFallbackKey] as? Bool) == true
        var fields: [String] = []
        fields.append("id=\(notification.request.identifier)")
        fields.append("at=\(Int(notification.date.timeIntervalSince1970))")
        fields.append(isFallback ? "src=local" : "src=remote")
        fields.append("title=\(content.title.isEmpty ? "<empty>" : "\(content.title.count)ch")")
        fields.append("body=\(content.body.isEmpty ? "<empty>" : "\(content.body.count)ch")")
        fields.append("cat=\(content.categoryIdentifier)")
        for key in ["peerId", "threadId", "msg_id", "from_id", "chat_id", "channel_id", "accountId", "user_id", "topic_id", "loc-key"] {
            if let value = userInfo[key] {
                fields.append("\(key)=\(value)")
            }
        }
        if let aps = userInfo["aps"] as? [AnyHashable: Any], let alert = aps["alert"] as? [AnyHashable: Any], let locKey = alert["loc-key"] {
            fields.append("aps.loc-key=\(locKey)")
        }
        return fields.joined(separator: " ")
    }

    static func describe(_ state: UIApplication.State) -> String {
        switch state {
        case .active:
            return "fg"
        case .inactive:
            return "inactive"
        case .background:
            return "bg"
        @unknown default:
            return "?"
        }
    }
}

/// Logs to the regular logger (tag "NotificationFallback") and to the SuperGram notification journal.
func superGramNotificationLog(_ text: String) {
    Logger.shared.log("NotificationFallback", text)
    SuperGramNotificationDiagnostics.shared.log(text)
}
