import Foundation
import TelegramCore

public struct AuthorizationApiCredentials: Equatable {
    public let apiId: Int32
    public let apiHash: String

    public init(apiId: Int32, apiHash: String) {
        self.apiId = apiId
        self.apiHash = apiHash
    }
}

public enum AuthorizationApiCredentialsParseError: Error, Equatable {
    case invalidApiId
    case invalidApiHash

    public var displayText: String {
        switch self {
        case .invalidApiId:
            return "api_id must be a positive number."
        case .invalidApiHash:
            return "api_hash must be a 32-character hexadecimal string."
        }
    }
}

public enum AuthorizationApiCredentialsStore {
    private static let apiIdKey = "customClient.authorizationApiId"
    private static let apiHashKey = "customClient.authorizationApiHash"

    private static func legacyOverride() -> SharedApiCredentials? {
        let defaults = UserDefaults.standard
        guard let apiIdNumber = defaults.object(forKey: self.apiIdKey) as? NSNumber,
              let apiHash = defaults.string(forKey: self.apiHashKey) else {
            return nil
        }
        return SharedApiCredentials(apiIdNumber: apiIdNumber, apiHash: apiHash)
    }

    public static func currentOverride() -> AuthorizationApiCredentials? {
        let baseAppBundleId = Bundle.main.bundleIdentifier ?? ""
        guard let credentials = SharedApiCredentialsStore.currentOverride(baseAppBundleId: baseAppBundleId, migratingLegacy: {
            return self.legacyOverride()
        }) else {
            return nil
        }
        return AuthorizationApiCredentials(apiId: credentials.apiId, apiHash: credentials.apiHash)
    }

    public static func current(fallbackApiId: Int32, fallbackApiHash: String) -> AuthorizationApiCredentials {
        return self.currentOverride() ?? AuthorizationApiCredentials(apiId: fallbackApiId, apiHash: fallbackApiHash)
    }

    @discardableResult
    public static func store(_ credentials: AuthorizationApiCredentials) -> Bool {
        guard let validated = SharedApiCredentials(apiId: credentials.apiId, apiHash: credentials.apiHash) else {
            return false
        }
        return SharedApiCredentialsStore.store(validated, baseAppBundleId: Bundle.main.bundleIdentifier ?? "", commitLegacy: {
            let defaults = UserDefaults.standard
            defaults.set(Int(validated.apiId), forKey: self.apiIdKey)
            defaults.set(validated.apiHash, forKey: self.apiHashKey)
        })
    }

    @discardableResult
    public static func clear() -> Bool {
        return SharedApiCredentialsStore.clear(baseAppBundleId: Bundle.main.bundleIdentifier ?? "", commitLegacy: {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: self.apiIdKey)
            defaults.removeObject(forKey: self.apiHashKey)
        })
    }

    public static func parse(apiIdText: String, apiHashText: String) -> Result<AuthorizationApiCredentials, AuthorizationApiCredentialsParseError> {
        var apiIdText = apiIdText.trimmingCharacters(in: .whitespacesAndNewlines)
        var apiHashText = apiHashText.trimmingCharacters(in: .whitespacesAndNewlines)

        if apiHashText.isEmpty, let separatorRange = apiIdText.range(of: ":") {
            apiHashText = String(apiIdText[separatorRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            apiIdText = String(apiIdText[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let apiIdValue = Int32(apiIdText), apiIdValue > 0 else {
            return .failure(.invalidApiId)
        }
        guard self.isValidApiHash(apiHashText) else {
            return .failure(.invalidApiHash)
        }

        return .success(AuthorizationApiCredentials(apiId: apiIdValue, apiHash: apiHashText.lowercased()))
    }

    public static func isValid(apiId: Int32, apiHash: String) -> Bool {
        return apiId > 0 && self.isValidApiHash(apiHash)
    }

    private static func isValidApiHash(_ value: String) -> Bool {
        guard value.count == 32 else {
            return false
        }
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 48 ... 57, 65 ... 70, 97 ... 102:
                continue
            default:
                return false
            }
        }
        return true
    }
}
