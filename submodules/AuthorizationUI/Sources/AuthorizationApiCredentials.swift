import Foundation

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

    public static func currentOverride() -> AuthorizationApiCredentials? {
        let defaults = UserDefaults.standard
        guard let apiIdNumber = defaults.object(forKey: self.apiIdKey) as? NSNumber else {
            return nil
        }
        guard let apiHash = defaults.string(forKey: self.apiHashKey), self.isValidApiHash(apiHash) else {
            return nil
        }
        let apiId = apiIdNumber.int32Value
        guard apiId > 0 else {
            return nil
        }
        return AuthorizationApiCredentials(apiId: apiId, apiHash: apiHash)
    }

    public static func current(fallbackApiId: Int32, fallbackApiHash: String) -> AuthorizationApiCredentials {
        return self.currentOverride() ?? AuthorizationApiCredentials(apiId: fallbackApiId, apiHash: fallbackApiHash)
    }

    public static func store(_ credentials: AuthorizationApiCredentials) {
        let defaults = UserDefaults.standard
        defaults.set(Int(credentials.apiId), forKey: self.apiIdKey)
        defaults.set(credentials.apiHash.lowercased(), forKey: self.apiHashKey)
    }

    public static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: self.apiIdKey)
        defaults.removeObject(forKey: self.apiHashKey)
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
