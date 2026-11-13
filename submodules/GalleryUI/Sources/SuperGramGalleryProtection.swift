import Foundation
import Postbox
import TelegramCore

// SuperGram: client-side save/copy/external-share gate for protected (noforwards) content in the gallery.
// Forwarding stays a server restriction and keeps using isCopyProtected().
// Secret chats, self-destructing secret media and view-once media are never unlocked.
enum SuperGramGalleryProtection {
    static let allowSaveProtectedContentKey = "sgAllowSaveProtectedContent"

    static var allowSaveProtectedContent: Bool {
        return UserDefaults.standard.object(forKey: allowSaveProtectedContentKey) as? Bool ?? true
    }
}

extension Message {
    func sgGalleryIsSecretContent(isSecret: Bool) -> Bool {
        if isSecret {
            return true
        }
        if self.id.peerId.namespace == Namespaces.Peer.SecretChat {
            return true
        }
        if self.containsSecretMedia || self.minAutoremoveOrClearTimeout == viewOnceTimeout {
            return true
        }
        return false
    }

    /// Whether gallery save/copy/share-to-iOS actions may be offered for this message.
    /// Unprotected content keeps the upstream behavior (allowed).
    func sgGalleryCanSaveContent(peerIsCopyProtected: Bool, isSecret: Bool = false) -> Bool {
        if isSecret {
            return false
        }
        guard self.isCopyProtected() || peerIsCopyProtected else {
            return true
        }
        if self.sgGalleryIsSecretContent(isSecret: isSecret) {
            return false
        }
        return SuperGramGalleryProtection.allowSaveProtectedContent
    }
}
