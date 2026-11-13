// SuperGram: screenshot / capture protection chokepoints. Owned by W2-PROTECT.
// Intentionally empty: every W2-PROTECT hook (UIKitRuntimeUtils sgShouldDisableScreenCapture, TelegramCore
// SuperGramContentProtection / Message.sgCanSaveContent, document preview share, auto-save to Photos) is driven by the
// registry toggles sgAllowSaveProtectedContent / sgAllowScreenCaptureProtected, whose rows and notice already live in
// ProtectedContentSection.swift. Duplicate rows here would show the same switch twice.
import Foundation
import SGItemListUI
import SGSimpleSettings

enum SuperGramProtectSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .protect

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        let entries: [SuperGramSettingsEntry] = []
        return entries
    }
}
