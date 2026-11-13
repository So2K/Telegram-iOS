import Foundation

public let FALLBACK_BASE_BUNDLE_ID: String = "app.swiftgram.ios"

// SuperGram: the provisioned app group of this build. Must stay in sync with
// `telegramAppGroupIdentifier` in submodules/TelegramUI/Sources/AppDelegate.swift.
public let SUPERGRAM_APP_GROUP_IDENTIFIER: String = "group.ffcd1c12e1a9728e.1"

public func sgBaseBundleIdentifier() -> String {
    let baseBundleId: String
    if let bundleId: String = Bundle.main.bundleIdentifier {
        if Bundle.main.bundlePath.hasSuffix(".appex") {
            if let lastDotRange: Range<String.Index> = bundleId.range(of: ".", options: [.backwards]) {
                baseBundleId = String(bundleId[..<lastDotRange.lowerBound])
            } else {
                baseBundleId = FALLBACK_BASE_BUNDLE_ID
            }
        } else {
            baseBundleId = bundleId
        }
    } else {
        baseBundleId = FALLBACK_BASE_BUNDLE_ID
    }
    return baseBundleId
}

public func sgAppGroupIdentifier() -> String {
    // SuperGram: the bundle-derived "group.<bundleId>" is not provisioned for this build,
    // so every consumer must use the same group as the main app.
    return SUPERGRAM_APP_GROUP_IDENTIFIER
}
