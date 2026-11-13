// SuperGram: media quality, browser, network and storage presets. Owned by W2-NET.
// Hooks: TelegramUI OpenUrl / ChatControllerOpenLinkContextMenu (SGM-F4), LocalMediaResources +
// LegacyMediaPickerUI + LegacyComponents (SGM-F5), MtProtoKit MTTcpConnection (SGM-F7 / SGP-02),
// MediaPickerUI (SGM-F9 / SGUI-06), StorageUsageScreen (SGM-F15 / SGP-04), TelegramBaseController +
// NotificationMuteSettingsUI + SettingsUI RecentSessionScreen (SGP-10).
//
// Do not expose Swiftgram's downloadSpeedBoost / uploadSpeedBoost (conflicts with the download limiter, INFRA-12).
import Foundation
import SGItemListUI
import SGSimpleSettings
import SGStrings

enum SuperGramNetworkSection: SuperGramSettingsSectionBuilder {
    static let group: SuperGramSettingsGroup = .network

    private static let outgoingPhotoQualitySetting = "network.outgoingPhotoQuality"

    /// Lowest quality the slider may store. `SGSimpleSettings.outgoingPhotoQualityFactor` clamps to the same
    /// floor; below roughly 30% JPEG artefacts make an outgoing photo useless, and the value is also used for
    /// the thumbnails Telegram attaches to every uploaded image.
    private static let minimumOutgoingPhotoQuality: Int32 = 30

    static func entries(state: SuperGramSettingsState, id: SGItemListCounter) -> [SuperGramSettingsEntry] {
        let settings = SGSimpleSettings.shared
        let lang = state.lang
        var entries: [SuperGramSettingsEntry] = []

        // MARK: Browser (SGM-F4)
        let browserSection = SuperGramSettingsSection(self.group, block: 0)
        entries.append(sgHeader(id, browserSection, sgString("SuperGram.Network.Browser.Header", state)))
        entries.append(sgToggle(id, browserSection, \.sgOpenLinksInAppSafari, text: sgString("SuperGram.Network.InAppSafari", state)))
        entries.append(sgNotice(id, browserSection, sgString("SuperGram.Network.InAppSafari.Notice", state)))

        // MARK: Outgoing photos (SGM-F5)
        let photoSection = SuperGramSettingsSection(self.group, block: 1)
        entries.append(sgHeader(id, photoSection, sgString("SuperGram.Network.Photo.Header", state)))
        entries.append(.percentageSlider(id: id.count, section: photoSection, settingName: self.outgoingPhotoQualitySetting, value: settings.outgoingPhotoQuality))
        entries.append(sgNotice(id, photoSection, i18n("Settings.Photo.Quality.Notice", lang)))
        entries.append(sgToggle(id, photoSection, \.sendLargePhotos, text: i18n("Settings.Photo.SendLarge", lang)))
        entries.append(sgNotice(id, photoSection, i18n("Settings.Photo.SendLarge.Notice", lang)))

        // MARK: Camera tile in the attachment picker (SGM-F9 / SGUI-06)
        let cameraSection = SuperGramSettingsSection(self.group, block: 2)
        entries.append(sgHeader(id, cameraSection, sgString("SuperGram.Network.Camera.Header", state)))
        entries.append(sgInvertedToggle(id, cameraSection, \.disableGalleryCamera, text: i18n("Settings.GalleryCamera", lang)))
        entries.append(sgInvertedToggle(id, cameraSection, \.disableGalleryCameraPreview, text: i18n("Settings.GalleryCameraPreview", lang), enabled: !settings.disableGalleryCamera))
        entries.append(sgNotice(id, cameraSection, sgString("SuperGram.Network.Camera.Notice", state)))

        // MARK: Connection (SGM-F7 / SGP-02)
        let connectionSection = SuperGramSettingsSection(self.group, block: 3)
        entries.append(sgHeader(id, connectionSection, sgString("SuperGram.Network.Connection.Header", state)))
        entries.append(sgToggle(id, connectionSection, \.localDNSForProxyHost, text: i18n("ProxySettings.UseSystemDNS", lang)))
        entries.append(sgNotice(id, connectionSection, i18n("ProxySettings.UseSystemDNS.Notice", lang)))

        // MARK: Storage presets (SGM-F15 / SGP-04 / CRIT-13)
        let storageSection = SuperGramSettingsSection(self.group, block: 4)
        entries.append(sgHeader(id, storageSection, sgString("SuperGram.Network.Storage.Header", state)))
        entries.append(sgToggle(id, storageSection, \.sgAggressiveCachePresets, text: sgString("SuperGram.Network.CachePresets", state), restart: true))
        entries.append(sgNotice(id, storageSection, sgString("SuperGram.Network.CachePresets.Notice", state)))

        // MARK: Small UX switches (SGP-10)
        let otherSection = SuperGramSettingsSection(self.group, block: 5)
        entries.append(sgHeader(id, otherSection, sgString("SuperGram.Network.Other.Header", state)))
        entries.append(sgToggle(id, otherSection, \.sgMusicPlaybackRateButton, text: sgString("SuperGram.Network.MusicRateButton", state)))
        entries.append(sgToggle(id, otherSection, \.sgExtraMutePresets, text: sgString("SuperGram.Network.MutePresets", state)))
        entries.append(sgToggle(id, otherSection, \.sgShowSessionIP, text: sgString("SuperGram.Network.SessionIP", state)))
        entries.append(sgNotice(id, otherSection, sgString("SuperGram.Network.SessionIP.Notice", state)))

        return entries
    }

    static func updateSliderValue(_ setting: String, value: Int32, actions: SuperGramSettingsActions) -> Bool {
        guard setting == self.outgoingPhotoQualitySetting else {
            return false
        }
        let clampedValue = max(self.minimumOutgoingPhotoQuality, min(100, value))
        if SGSimpleSettings.shared.outgoingPhotoQuality != clampedValue {
            SGSimpleSettings.shared.outgoingPhotoQuality = clampedValue
            actions.reload()
        }
        return true
    }
}
