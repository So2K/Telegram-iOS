import Foundation

// SuperGram: runtime switches used by the story viewer and the profile story grid.
// Keys come from the SuperGram key registry (SUPERGRAM_ULTRA_PLAN.md) and are read from
// UserDefaults.standard without importing SGSimpleSettings. Values are cached and the cache
// is dropped on UserDefaults.didChangeNotification, so layout paths never hit UserDefaults.
public enum SuperGramStoryGates {
    private struct Values {
        var allowSaveProtectedContent: Bool
        var allowScreenCaptureProtected: Bool
        var storyHDWithoutPremium: Bool
    }

    private static let lock = NSLock()
    private static var cachedValues: Values?
    private static var cacheGeneration: Int = 0
    private static var observer: NSObjectProtocol?

    private static func readValues() -> Values {
        let defaults = UserDefaults.standard
        return Values(
            allowSaveProtectedContent: defaults.object(forKey: "sgAllowSaveProtectedContent") as? Bool ?? true,
            allowScreenCaptureProtected: defaults.object(forKey: "sgAllowScreenCaptureProtected") as? Bool ?? true,
            storyHDWithoutPremium: defaults.object(forKey: "sgStoryHDWithoutPremium") as? Bool ?? true
        )
    }

    private static var values: Values {
        self.lock.lock()
        let cached = self.cachedValues
        let generation = self.cacheGeneration
        if self.observer == nil {
            self.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil, using: { _ in
                SuperGramStoryGates.invalidate()
            })
        }
        self.lock.unlock()

        if let cached {
            return cached
        }

        // Read outside of the lock: UserDefaults posts didChangeNotification synchronously.
        let result = self.readValues()

        self.lock.lock()
        if self.cacheGeneration == generation {
            self.cachedValues = result
        }
        self.lock.unlock()

        return result
    }

    private static func invalidate() {
        self.lock.lock()
        self.cachedValues = nil
        self.cacheGeneration += 1
        self.lock.unlock()
    }

    /// sgAllowSaveProtectedContent: allow "Save to Gallery" for noforwards (protected) stories.
    public static var allowSaveProtectedContent: Bool {
        return self.values.allowSaveProtectedContent
    }

    /// sgAllowScreenCaptureProtected: do not hide protected stories from screenshots / screen recording.
    public static var allowScreenCaptureProtected: Bool {
        return self.values.allowScreenCaptureProtected
    }

    /// sgStoryHDWithoutPremium: honour the "HD stories" preference without Premium.
    public static var storyHDWithoutPremium: Bool {
        return self.values.storyHDWithoutPremium
    }

    /// Premium upsells in the story viewer (save, HD, stealth, views list) are never shown.
    public static var hidePremiumUpsell: Bool {
        return true
    }
}
