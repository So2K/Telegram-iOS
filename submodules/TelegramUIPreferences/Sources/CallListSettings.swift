import Foundation
import TelegramCore
import SwiftSignalKit

public struct CallListSettings: Codable, Equatable {
    // MARK: Swiftgram
    public var showContactsTab: Bool
    public var _showTab: Bool?

    public static var defaultSettings: CallListSettings {
        // SuperGram: Contacts and Calls tabs are off by default (both stay reachable from Settings)
        return CallListSettings(showContactsTab: false, showTab: false)
    }
    
    public var showTab: Bool {
        get {
            if let value = self._showTab {
                return value
            } else {
                return true
            }
        } set {
            self._showTab = newValue
        }
    }
    
    public init(showContactsTab: Bool = true, showTab: Bool?) {
        self.showContactsTab = showContactsTab
        self._showTab = showTab
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        // MARK: Swiftgram
        // SuperGram: decodeIfPresent (Swiftgram uses decode), so settings stored before this key existed still decode
        // and keep the user's Calls tab choice.
        self.showContactsTab = ((try container.decodeIfPresent(Int32.self, forKey: "showContactsTab")) ?? 1) != 0
        if let value = try container.decodeIfPresent(Int32.self, forKey: "showTab") {
            self._showTab = value != 0
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        // MARK: Swiftgram
        try container.encode((self.showContactsTab ? 1 : 0) as Int32, forKey: "showContactsTab")
        if let showTab = self._showTab {
            try container.encode((showTab ? 1 : 0) as Int32, forKey: "showTab")
        } else {
            try container.encodeNil(forKey: "showTab")
        }
    }
    
    public static func ==(lhs: CallListSettings, rhs: CallListSettings) -> Bool {
        return lhs.showContactsTab == rhs.showContactsTab && lhs._showTab == rhs._showTab
    }

    public func withUpdatedShowTab(_ showTab: Bool) -> CallListSettings {
        return CallListSettings(showContactsTab: self.showContactsTab, showTab: showTab)
    }

    // MARK: Swiftgram
    public func withUpdatedShowContactsTab(_ showContactsTab: Bool) -> CallListSettings {
        return CallListSettings(showContactsTab: showContactsTab, showTab: self._showTab)
    }
}

public func updateCallListSettingsInteractively(accountManager: AccountManager<TelegramAccountManagerTypes>, _ f: @escaping (CallListSettings) -> CallListSettings) -> Signal<Void, NoError> {
    return accountManager.transaction { transaction -> Void in
        transaction.updateSharedData(ApplicationSpecificSharedDataKeys.callListSettings, { entry in
            let currentSettings: CallListSettings
            if let entry = entry?.get(CallListSettings.self) {
                currentSettings = entry
            } else {
                currentSettings = CallListSettings.defaultSettings
            }
            return SharedPreferencesEntry(f(currentSettings))
        })
    }
}
