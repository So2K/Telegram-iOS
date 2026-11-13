import Foundation

// MARK: SuperGram
/// SuperGram (W2-CONTEXT, PROT-6): text selection Copy / Share in protected (noforwards) chats.
///
/// Reads the `sgAllowSaveProtectedContent` key of `SGSimpleSettings` (default true) straight from `UserDefaults.standard`,
/// so this low-level module needs no Swiftgram dependency. Callers must still keep secret chats and secret
/// (view-once / short TTL) media protected, and must keep Quote (a reply into another chat) on the original protection.
public enum TextSelectionSuperGramProtection {
    public static var allowCopyOfProtectedContent: Bool {
        return UserDefaults.standard.object(forKey: "sgAllowSaveProtectedContent") as? Bool ?? true
    }
}
