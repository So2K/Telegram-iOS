import Foundation
import Postbox

// SuperGram: client-side gates for protected (noforwards) content, shared by chat, gallery and document preview.
// Keys come from the SuperGram key registry (SUPERGRAM_ULTRA_PLAN.md) and match SGSimpleSettings.Keys; they are
// read from UserDefaults.standard because TelegramCore cannot depend on the settings modules.
// Forwarding stays a server restriction: forward gates keep using isCopyProtected() / isCopyProtectionEnabled.
// Privacy line: secret chats, self-destructing (<= 60 s) and view-once media are never unlocked.
// The Objective-C counterpart for layers is sgShouldDisableScreenCapture(isSecret:isCopyProtected:) in UIKitRuntimeUtils.
public enum SuperGramContentProtection {
    public static let allowSaveProtectedContentKey = "sgAllowSaveProtectedContent"
    public static let allowScreenCaptureProtectedKey = "sgAllowScreenCaptureProtected"

    private struct Values {
        var allowSaveProtectedContent: Bool
        var allowScreenCaptureProtected: Bool
    }

    private static let lock = NSLock()
    private static var cachedValues: Values?
    private static var cacheGeneration: Int = 0
    private static var observer: NSObjectProtocol?

    private static func readValues() -> Values {
        let defaults = UserDefaults.standard
        return Values(
            allowSaveProtectedContent: defaults.object(forKey: SuperGramContentProtection.allowSaveProtectedContentKey) as? Bool ?? true,
            allowScreenCaptureProtected: defaults.object(forKey: SuperGramContentProtection.allowScreenCaptureProtectedKey) as? Bool ?? true
        )
    }

    private static var values: Values {
        self.lock.lock()
        let cached = self.cachedValues
        let generation = self.cacheGeneration
        if self.observer == nil {
            self.observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil, using: { _ in
                SuperGramContentProtection.invalidate()
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

    /// sgAllowSaveProtectedContent (default true): save / copy / share-to-iOS for protected content.
    public static var allowSaveProtectedContent: Bool {
        return self.values.allowSaveProtectedContent
    }

    /// sgAllowScreenCaptureProtected (default true): screenshots / screen recording of protected content.
    public static var allowScreenCaptureProtected: Bool {
        return self.values.allowScreenCaptureProtected
    }

    /// Final value for a `captureProtected` / `preventsCapture` / `setLayerDisableScreenshots` flag.
    /// `isSecret` (secret chats, self-destructing or view-once media, paid media, login codes) always protects;
    /// `isCopyProtected` (noforwards message, group, channel or private chat) protects only while the toggle is off.
    public static func shouldDisableScreenCapture(isSecret: Bool, isCopyProtected: Bool) -> Bool {
        if isSecret {
            return true
        }
        return isCopyProtected && !self.allowScreenCaptureProtected
    }
}

public extension Message {
    /// Secret chats, self-destructing (<= 60 s) and view-once media: never unlocked by SuperGram.
    var sgIsSecretContent: Bool {
        if self.id.peerId.namespace == Namespaces.Peer.SecretChat {
            return true
        }
        if self.containsSecretMedia {
            return true
        }
        if self.minAutoremoveOrClearTimeout == viewOnceTimeout {
            return true
        }
        return false
    }

    /// Whether client-side save / copy / share-to-iOS actions may be offered for this message.
    /// Unprotected messages return true, so callers keep their own upstream secret-media and paid-content checks.
    /// Protected messages (`isCopyProtected()` or `peerIsCopyProtected`) return `sgAllowSaveProtectedContent`,
    /// except secret content, which stays locked. Forwarding must keep using `isCopyProtected()`.
    func sgCanSaveContent(peerIsCopyProtected: Bool = false) -> Bool {
        if !self.isCopyProtected() && !peerIsCopyProtected {
            return true
        }
        if self.sgIsSecretContent {
            return false
        }
        return SuperGramContentProtection.allowSaveProtectedContent
    }

    /// For capture-protection flags that upstream derives only from copy protection (chat bubbles, reply previews,
    /// round-video overlay). Returns `isCopyProtected` while sgAllowScreenCaptureProtected is off; when it is on,
    /// only secret content (e.g. view-once media in a protected chat) keeps protection.
    func sgCaptureProtected(isCopyProtected: Bool) -> Bool {
        if !isCopyProtected {
            return false
        }
        return SuperGramContentProtection.shouldDisableScreenCapture(isSecret: self.sgIsSecretContent, isCopyProtected: true)
    }
}

public extension EngineMessage {
    var sgIsSecretContent: Bool {
        return self._asMessage().sgIsSecretContent
    }

    func sgCanSaveContent(peerIsCopyProtected: Bool = false) -> Bool {
        return self._asMessage().sgCanSaveContent(peerIsCopyProtected: peerIsCopyProtected)
    }

    func sgCaptureProtected(isCopyProtected: Bool) -> Bool {
        return self._asMessage().sgCaptureProtected(isCopyProtected: isCopyProtected)
    }
}
