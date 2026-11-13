import Foundation
import SGAppGroupIdentifier
import SGLogging

let APP_GROUP_IDENTIFIER = sgAppGroupIdentifier()

public class SGSimpleSettings {
    
    public static let shared = SGSimpleSettings()
    
    private init() {
        // SuperGram: preCacheValues() removed (it raced background reads against main-thread reads of the
        // cached values). Every property is lazily cached on first read anyway.
        //
        // Registering defaults and migrating both post UserDefaults.didChangeNotification synchronously. Doing
        // that inside this once-initializer would re-enter `SGSimpleSettings.shared` (and dead-lock) as soon as an
        // observer reads a setting, so both run right after init. Reads don't depend on the registration:
        // UserDefault falls back to `defaultValues` / `groupDefaultValues` for absent keys.
        DispatchQueue.main.async {
            SGSimpleSettings.registerDefaults()
            SGSimpleSettings.shared.migrate()
        }
    }

    private static let registerDefaultsOnce: Void = {
        UserDefaults.standard.register(defaults: SGSimpleSettings.defaultValues)
        // Just in case group defaults will be nil
        UserDefaults.standard.register(defaults: SGSimpleSettings.groupDefaultValues)
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            groupUserDefaults.register(defaults: SGSimpleSettings.groupDefaultValues)
        }
    }()

    /// SuperGram: registers every default (Swiftgram + SuperGram keys) in `UserDefaults.standard`, so raw
    /// `UserDefaults.standard.object(forKey:)` readers in modules that don't link SGSimpleSettings see the same
    /// values. Idempotent and thread-safe; also called by `SGSimpleSettings.shared`.
    public static func registerDefaults() {
        let _ = SGSimpleSettings.registerDefaultsOnce
    }
    
    private func migrate() {
        let showRepostToStoryMigrationKey = "migrated_\(Keys.showRepostToStory.rawValue)"
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            if !groupUserDefaults.bool(forKey: showRepostToStoryMigrationKey) {
                self.showRepostToStoryV2 = self.showRepostToStory
                groupUserDefaults.set(true, forKey: showRepostToStoryMigrationKey)
                SGLogger.shared.log("SGSimpleSettings", "Migrated showRepostToStory. \(self.showRepostToStory) -> \(self.showRepostToStoryV2)")
            }
        } else {
            SGLogger.shared.log("SGSimpleSettings", "Unable to migrate showRepostToStory. Shared UserDefaults suite is not available for '\(APP_GROUP_IDENTIFIER)'.")
        }

        let chatListLinesMigrationKey = "migrated_\(Keys.chatListLines.rawValue)"
        if !UserDefaults.standard.bool(forKey: chatListLinesMigrationKey) {
            let legacyCompactMessagePreviewKey = "compactMessagePreview"
            if UserDefaults.standard.object(forKey: legacyCompactMessagePreviewKey) != nil {
                if UserDefaults.standard.bool(forKey: legacyCompactMessagePreviewKey) {
                    self.chatListLines = ChatListLines.one.rawValue
                }
                UserDefaults.standard.removeObject(forKey: legacyCompactMessagePreviewKey)
                SGLogger.shared.log("SGSimpleSettings", "Migrated compactMessagePreview -> chatListLines. \(self.chatListLines)")
            }
            UserDefaults.standard.set(true, forKey: chatListLinesMigrationKey)
        }
    }
    
    public func synchronizeShared() {
        if let groupUserDefaults = UserDefaults(suiteName: APP_GROUP_IDENTIFIER) {
            groupUserDefaults.synchronize()
        }
    }
    
    public enum Keys: String, CaseIterable {
        case hidePhoneInSettings
        case showTabNames
        case startTelescopeWithRearCam
        case accountColorsSaturation
        case uploadSpeedBoost
        case downloadSpeedBoost
        case bottomTabStyle
        case rememberLastFolder
        case lastAccountFolders
        case localDNSForProxyHost
        case sendLargePhotos
        case outgoingPhotoQuality
        case storyStealthMode
        case canUseStealthMode
        case disableSwipeToRecordStory
        case quickTranslateButton
        case outgoingLanguageTranslation
        case hideReactions
        case showRepostToStory
        case showRepostToStoryV2
        case contextShowSelectFromUser
        case contextShowSaveToCloud
        case contextShowRestrict
        // case contextShowBan
        case contextShowHideForwardName
        case contextShowReport
        case contextShowReply
        case contextShowPin
        case contextShowSaveMedia
        case contextShowMessageReplies
        case contextShowJson
        case disableScrollToNextChannel
        case disableScrollToNextTopic
        case disableChatSwipeOptions
        case disableDeleteChatSwipeOption
        case disableGalleryCamera
        case disableGalleryCameraPreview
        case disableSendAsButton
        case disableSnapDeletionEffect
        case stickerSize
        case stickerTimestamp
        case hideRecordingButton
        case hideTabBar
        case showDC
        case showCreationDate
        case showRegDate
        case regDateCache
        case compactChatList
        case chatListLines
        case compactFolderNames
        case allChatsTitleLengthOverride
//        case allChatsFolderPositionOverride
        case allChatsHidden
        case defaultEmojisFirst
        case messageDoubleTapActionOutgoing
        case wideChannelPosts
        case forceEmojiTab
        case forceBuiltInMic
        case secondsInMessages
        case hideChannelBottomButton
        case forceSystemSharing
        case confirmCalls
        case videoPIPSwipeDirection
        case legacyNotificationsFix
        case messageFilterKeywords
        case inputToolbar
        case pinnedMessageNotifications
        case mentionsAndRepliesNotifications
        case primaryUserId
        case status
        case dismissedSGSuggestions
        case duckyAppIconAvailable
        case transcriptionBackend
        case translationBackend
        case customAppBadge
        case canUseNY
        case nyStyle
        case wideTabBar
        case tabBarSearchEnabled
        case hideStories
        case warnOnStoriesOpen
        case showProfileId
        case sendWithReturnKey

        // MARK: SuperGram keys (registry in SUPERGRAM_ULTRA_PLAN.md). Raw values are the UserDefaults keys.
        case sgStreamAllVideos
        case sgPreferDownloadedOriginal
        case sgDownloadLimiter
        case sgPauseDownloadsUnderPressure
        case sgInlineAutoplayVideos
        case sgBackgroundKeepAlive
        case sgFileLogging
        case sgNetworkLogging
        case sgDisableReadMetrics
        case sgAllowSaveProtectedContent
        case sgAllowScreenCaptureProtected
        case sgStoryHDWithoutPremium
        case sgTelescopeButton
        case sgSkipReadReceipts
        case sgStoryGhostMode
        case sgDownloadSpeedMode
        case sgBackgroundDownloads
        case sgShowShareButton
        case sgChatListHistoryButton
        case sgKeepNavigationStack
        case sgDoubleTapSelectsText
    }
    
    public enum DownloadSpeedBoostValues: String, CaseIterable {
        case none
        case medium
        case maximum
    }
    
    public enum BottomTabStyleValues: String, CaseIterable {
        case telegram
        case ios
    }
    
    public enum AllChatsTitleLengthOverride: String, CaseIterable {
        case none
        case short
        case long
    }
    
    public enum AllChatsFolderPositionOverride: String, CaseIterable {
        case none
        case last
        case hidden
    }

    public enum ChatListLines: String, CaseIterable {
        case three = "3"
        case two = "2"
        case one = "1"

        public static let defaultValue: ChatListLines = .three
    }
    
    public enum MessageDoubleTapAction: String, CaseIterable {
        case `default`
        case none
        case edit
    }
    
    public enum VideoPIPSwipeDirection: String, CaseIterable {
        case up
        case down
        case none
    }

    public enum TranscriptionBackend: String, CaseIterable {
        case `default`
        case apple
    }

    public enum TranslationBackend: String, CaseIterable {
        case `default`
        case gtranslate
        case system
        // Make sure to update TranslationConfiguration
    }
        
    public enum PinnedMessageNotificationsSettings: String, CaseIterable {
        case `default`
        case silenced
        case disabled
    }
    
    public enum MentionsAndRepliesNotificationsSettings: String, CaseIterable {
        case `default`
        case silenced
        case disabled
    }

    public enum NYStyle: String, CaseIterable {
        case `default`
        case snow
        case lightning
    }
    
    // SuperGram: defaults of the SuperGram key registry. Readers outside SGSimpleSettings must use
    // `UserDefaults.standard.object(forKey: key) as? Bool ?? <same default>`.
    public static let superGramDefaultValues: [String: Any] = [
        Keys.sgStreamAllVideos.rawValue: true,
        Keys.sgPreferDownloadedOriginal.rawValue: true,
        Keys.sgDownloadLimiter.rawValue: true,
        Keys.sgPauseDownloadsUnderPressure.rawValue: true,
        Keys.sgInlineAutoplayVideos.rawValue: true,
        Keys.sgBackgroundKeepAlive.rawValue: true,
        Keys.sgFileLogging.rawValue: false,
        Keys.sgNetworkLogging.rawValue: false,
        Keys.sgDisableReadMetrics.rawValue: true,
        Keys.sgAllowSaveProtectedContent.rawValue: true,
        Keys.sgAllowScreenCaptureProtected.rawValue: true,
        Keys.sgStoryHDWithoutPremium.rawValue: true,
        Keys.sgTelescopeButton.rawValue: true,
        Keys.sgSkipReadReceipts.rawValue: false,
        Keys.sgStoryGhostMode.rawValue: false,
        Keys.sgDownloadSpeedMode.rawValue: Int32(1),
        Keys.sgBackgroundDownloads.rawValue: true,
        Keys.sgShowShareButton.rawValue: false,
        Keys.sgChatListHistoryButton.rawValue: true,
        Keys.sgKeepNavigationStack.rawValue: true,
        Keys.sgDoubleTapSelectsText.rawValue: true
    ]

    /// SuperGram keys that live in their own stream file instead of `Keys` (`ContextKeys.swift`, `GhostKeys.swift`,
    /// `TranslateKeys.swift`, `NetworkKeys.swift`, `ChatInputKeys.swift`). They must be registered too, otherwise a
    /// raw `UserDefaults.standard` reader in a module without the SGSimpleSettings dependency would see `nil` where
    /// these properties return their default.
    public static let superGramExtensionDefaultValues: [String: Any] = SGSimpleSettings.contextDefaultValues
        .merging(SGSimpleSettings.ghostDefaultValues, uniquingKeysWith: { _, rhs in rhs })
        .merging(SGSimpleSettings.translateDefaultValues, uniquingKeysWith: { _, rhs in rhs })
        .merging(SGSimpleSettings.networkDefaultValues, uniquingKeysWith: { _, rhs in rhs })
        .merging(SGSimpleSettings.chatInputDefaultValues, uniquingKeysWith: { _, rhs in rhs })

    public static let defaultValues: [String: Any] = SGSimpleSettings.swiftgramDefaultValues
        .merging(SGSimpleSettings.superGramDefaultValues, uniquingKeysWith: { _, rhs in rhs })
        .merging(SGSimpleSettings.superGramExtensionDefaultValues, uniquingKeysWith: { _, rhs in rhs })

    // SuperGram: hidePhoneInSettings false, showRegDate false (needs the Swiftgram API), wideTabBar true,
    // confirmCalls false (Swiftgram: true — stock Telegram asks nothing before placing a call).
    public static let swiftgramDefaultValues: [String: Any] = [
        Keys.forceBuiltInMic.rawValue: false,
        Keys.hidePhoneInSettings.rawValue: false,
        Keys.showTabNames.rawValue: true,
        Keys.startTelescopeWithRearCam.rawValue: false,
        Keys.accountColorsSaturation.rawValue: 100,
        Keys.uploadSpeedBoost.rawValue: false,
        Keys.downloadSpeedBoost.rawValue: DownloadSpeedBoostValues.none.rawValue,
        Keys.rememberLastFolder.rawValue: false,
        Keys.bottomTabStyle.rawValue: BottomTabStyleValues.telegram.rawValue,
        Keys.lastAccountFolders.rawValue: [:],
        Keys.localDNSForProxyHost.rawValue: false,
        Keys.sendLargePhotos.rawValue: false,
        Keys.outgoingPhotoQuality.rawValue: 70,
        Keys.storyStealthMode.rawValue: false,
        Keys.canUseStealthMode.rawValue: true,
        Keys.disableSwipeToRecordStory.rawValue: false,
        Keys.quickTranslateButton.rawValue: false,
        Keys.outgoingLanguageTranslation.rawValue: [:],
        Keys.hideReactions.rawValue: false,
        Keys.showRepostToStory.rawValue: true,
        Keys.contextShowSelectFromUser.rawValue: true,
        Keys.contextShowSaveToCloud.rawValue: true,
        Keys.contextShowRestrict.rawValue: true,
        // Keys.contextShowBan.rawValue: true,
        Keys.contextShowHideForwardName.rawValue: true,
        Keys.contextShowReport.rawValue: true,
        Keys.contextShowReply.rawValue: true,
        Keys.contextShowPin.rawValue: true,
        Keys.contextShowSaveMedia.rawValue: true,
        Keys.contextShowMessageReplies.rawValue: true,
        Keys.contextShowJson.rawValue: false,
        Keys.disableScrollToNextChannel.rawValue: false,
        Keys.disableScrollToNextTopic.rawValue: false,
        Keys.disableChatSwipeOptions.rawValue: false,
        Keys.disableDeleteChatSwipeOption.rawValue: false,
        Keys.disableGalleryCamera.rawValue: false,
        Keys.disableGalleryCameraPreview.rawValue: false,
        Keys.disableSendAsButton.rawValue: false,
        Keys.disableSnapDeletionEffect.rawValue: false,
        Keys.stickerSize.rawValue: 100,
        Keys.stickerTimestamp.rawValue: true,
        Keys.hideRecordingButton.rawValue: false,
        Keys.hideTabBar.rawValue: false,
        Keys.showDC.rawValue: false,
        Keys.showCreationDate.rawValue: true,
        Keys.showRegDate.rawValue: false,
        Keys.regDateCache.rawValue: [:],
        Keys.compactChatList.rawValue: false,
        Keys.chatListLines.rawValue: ChatListLines.defaultValue.rawValue,
        Keys.compactFolderNames.rawValue: false,
        Keys.allChatsTitleLengthOverride.rawValue: AllChatsTitleLengthOverride.none.rawValue,
//        Keys.allChatsFolderPositionOverride.rawValue: AllChatsFolderPositionOverride.none.rawValue
        Keys.allChatsHidden.rawValue: false,
        Keys.defaultEmojisFirst.rawValue: false,
        Keys.messageDoubleTapActionOutgoing.rawValue: MessageDoubleTapAction.default.rawValue,
        Keys.wideChannelPosts.rawValue: false,
        Keys.forceEmojiTab.rawValue: false,
        // SuperGram: ON by default — no Mute / Gift / Direct panel under channels the user follows (all three live
        // in the channel profile); search and scroll-down move under the avatar.
        Keys.hideChannelBottomButton.rawValue: true,
        Keys.secondsInMessages.rawValue: false,
        Keys.forceSystemSharing.rawValue: false,
        // SuperGram: OFF by default (Swiftgram ships it ON). Stock Telegram places a call on the first tap; an
        // extra confirmation alert on every call is a surprise for someone coming from stock. The row stays.
        Keys.confirmCalls.rawValue: false,
        Keys.videoPIPSwipeDirection.rawValue: VideoPIPSwipeDirection.up.rawValue,
        Keys.messageFilterKeywords.rawValue: [],
        Keys.inputToolbar.rawValue: false,
        Keys.primaryUserId.rawValue: "",
        Keys.dismissedSGSuggestions.rawValue: [],
        Keys.duckyAppIconAvailable.rawValue: true,
        Keys.transcriptionBackend.rawValue: TranscriptionBackend.default.rawValue,
        // register(defaults:) leaves an explicit persisted Telegram/server choice intact.
        Keys.translationBackend.rawValue: {
            if #available(iOS 18.0, *) {
                return TranslationBackend.system.rawValue
            } else {
                return TranslationBackend.default.rawValue
            }
        }(),
        Keys.customAppBadge.rawValue: "",
        Keys.canUseNY.rawValue: false,
        Keys.nyStyle.rawValue: NYStyle.default.rawValue,
        Keys.wideTabBar.rawValue: true,
        Keys.tabBarSearchEnabled.rawValue: true,
        Keys.hideStories.rawValue: false,
        Keys.warnOnStoriesOpen.rawValue: false,
        Keys.showProfileId.rawValue: true,
        Keys.sendWithReturnKey.rawValue: false
    ]
    
    public static let groupDefaultValues: [String: Any] = [
        Keys.legacyNotificationsFix.rawValue: false,
        Keys.pinnedMessageNotifications.rawValue: PinnedMessageNotificationsSettings.default.rawValue,
        Keys.mentionsAndRepliesNotifications.rawValue: MentionsAndRepliesNotificationsSettings.default.rawValue,
        Keys.status.rawValue: 1,
        Keys.showRepostToStoryV2.rawValue: true,
    ]
    
    @UserDefault(key: Keys.hidePhoneInSettings.rawValue)
    public var hidePhoneInSettings: Bool
    
    @UserDefault(key: Keys.showTabNames.rawValue)
    public var showTabNames: Bool
    
    @UserDefault(key: Keys.startTelescopeWithRearCam.rawValue)
    public var startTelescopeWithRearCam: Bool
    
    @UserDefault(key: Keys.accountColorsSaturation.rawValue)
    public var accountColorsSaturation: Int32
    
    @UserDefault(key: Keys.uploadSpeedBoost.rawValue)
    public var uploadSpeedBoost: Bool
    
    @UserDefault(key: Keys.downloadSpeedBoost.rawValue)
    public var downloadSpeedBoost: String
    
    @UserDefault(key: Keys.rememberLastFolder.rawValue)
    public var rememberLastFolder: Bool
    
    // Disabled while Telegram is migrating to Glass
    // @UserDefault(key: Keys.bottomTabStyle.rawValue)
    public var bottomTabStyle: String {
        set {}
        get {
            return BottomTabStyleValues.ios.rawValue
        }
    }
    
    public var lastAccountFolders = UserDefaultsBackedDictionary<String, Int32>(userDefaultsKey: Keys.lastAccountFolders.rawValue, threadSafe: true)
    
    @UserDefault(key: Keys.localDNSForProxyHost.rawValue)
    public var localDNSForProxyHost: Bool
    
    @UserDefault(key: Keys.sendLargePhotos.rawValue)
    public var sendLargePhotos: Bool
    
    @UserDefault(key: Keys.outgoingPhotoQuality.rawValue)
    public var outgoingPhotoQuality: Int32

    @UserDefault(key: Keys.hideStories.rawValue)
    public var hideStories: Bool

    @UserDefault(key: Keys.warnOnStoriesOpen.rawValue)
    public var warnOnStoriesOpen: Bool
    
    @UserDefault(key: Keys.storyStealthMode.rawValue)
    public var storyStealthMode: Bool
    
    @UserDefault(key: Keys.canUseStealthMode.rawValue)
    public var canUseStealthMode: Bool    
    
    @UserDefault(key: Keys.disableSwipeToRecordStory.rawValue)
    public var disableSwipeToRecordStory: Bool   
    
    @UserDefault(key: Keys.quickTranslateButton.rawValue)
    public var quickTranslateButton: Bool
    
    public var outgoingLanguageTranslation = UserDefaultsBackedDictionary<String, String>(userDefaultsKey: Keys.outgoingLanguageTranslation.rawValue, threadSafe: true)
    
    @UserDefault(key: Keys.hideReactions.rawValue)
    public var hideReactions: Bool

    // @available(*, deprecated, message: "Use showRepostToStoryV2 instead")
    @UserDefault(key: Keys.showRepostToStory.rawValue)
    public var showRepostToStory: Bool

    @UserDefault(key: Keys.showRepostToStoryV2.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var showRepostToStoryV2: Bool

    @UserDefault(key: Keys.contextShowRestrict.rawValue)
    public var contextShowRestrict: Bool

    /*@UserDefault(key: Keys.contextShowBan.rawValue)
    public var contextShowBan: Bool*/

    @UserDefault(key: Keys.contextShowSelectFromUser.rawValue)
    public var contextShowSelectFromUser: Bool

    @UserDefault(key: Keys.contextShowSaveToCloud.rawValue)
    public var contextShowSaveToCloud: Bool

    @UserDefault(key: Keys.contextShowHideForwardName.rawValue)
    public var contextShowHideForwardName: Bool

    @UserDefault(key: Keys.contextShowReport.rawValue)
    public var contextShowReport: Bool

    @UserDefault(key: Keys.contextShowReply.rawValue)
    public var contextShowReply: Bool

    @UserDefault(key: Keys.contextShowPin.rawValue)
    public var contextShowPin: Bool

    @UserDefault(key: Keys.contextShowSaveMedia.rawValue)
    public var contextShowSaveMedia: Bool

    @UserDefault(key: Keys.contextShowMessageReplies.rawValue)
    public var contextShowMessageReplies: Bool
    
    @UserDefault(key: Keys.contextShowJson.rawValue)
    public var contextShowJson: Bool
    
    @UserDefault(key: Keys.disableScrollToNextChannel.rawValue)
    public var disableScrollToNextChannel: Bool

    @UserDefault(key: Keys.disableScrollToNextTopic.rawValue)
    public var disableScrollToNextTopic: Bool

    @UserDefault(key: Keys.disableChatSwipeOptions.rawValue)
    public var disableChatSwipeOptions: Bool

    @UserDefault(key: Keys.disableDeleteChatSwipeOption.rawValue)
    public var disableDeleteChatSwipeOption: Bool

    @UserDefault(key: Keys.disableGalleryCamera.rawValue)
    public var disableGalleryCamera: Bool

    @UserDefault(key: Keys.disableGalleryCameraPreview.rawValue)
    public var disableGalleryCameraPreview: Bool

    @UserDefault(key: Keys.disableSendAsButton.rawValue)
    public var disableSendAsButton: Bool

    @UserDefault(key: Keys.disableSnapDeletionEffect.rawValue)
    public var disableSnapDeletionEffect: Bool
    
    @UserDefault(key: Keys.stickerSize.rawValue)
    public var stickerSize: Int32
    
    @UserDefault(key: Keys.stickerTimestamp.rawValue)
    public var stickerTimestamp: Bool    

    @UserDefault(key: Keys.hideRecordingButton.rawValue)
    public var hideRecordingButton: Bool
    
    @UserDefault(key: Keys.hideTabBar.rawValue)
    public var hideTabBar: Bool

    @UserDefault(key: Keys.showProfileId.rawValue)
    public var showProfileId: Bool
    
    @UserDefault(key: Keys.showDC.rawValue)
    public var showDC: Bool
    
    @UserDefault(key: Keys.showCreationDate.rawValue)
    public var showCreationDate: Bool

    @UserDefault(key: Keys.showRegDate.rawValue)
    public var showRegDate: Bool

    public var regDateCache = UserDefaultsBackedDictionary<String, Data>(userDefaultsKey: Keys.regDateCache.rawValue, threadSafe: true)
    
    @UserDefault(key: Keys.compactChatList.rawValue)
    public var compactChatList: Bool

    @UserDefault(key: Keys.chatListLines.rawValue)
    public var chatListLines: String

    @UserDefault(key: Keys.compactFolderNames.rawValue)
    public var compactFolderNames: Bool
    
    @UserDefault(key: Keys.allChatsTitleLengthOverride.rawValue)
    public var allChatsTitleLengthOverride: String
//    
//    @UserDefault(key: Keys.allChatsFolderPositionOverride.rawValue)
//    public var allChatsFolderPositionOverride: String
    @UserDefault(key: Keys.allChatsHidden.rawValue)
    public var allChatsHidden: Bool

    @UserDefault(key: Keys.defaultEmojisFirst.rawValue)
    public var defaultEmojisFirst: Bool
    
    @UserDefault(key: Keys.messageDoubleTapActionOutgoing.rawValue)
    public var messageDoubleTapActionOutgoing: String
    
    @UserDefault(key: Keys.wideChannelPosts.rawValue)
    public var wideChannelPosts: Bool

    @UserDefault(key: Keys.forceEmojiTab.rawValue)
    public var forceEmojiTab: Bool
    
    @UserDefault(key: Keys.forceBuiltInMic.rawValue)
    public var forceBuiltInMic: Bool
    
    @UserDefault(key: Keys.secondsInMessages.rawValue)
    public var secondsInMessages: Bool
    
    @UserDefault(key: Keys.hideChannelBottomButton.rawValue)
    public var hideChannelBottomButton: Bool

    @UserDefault(key: Keys.forceSystemSharing.rawValue)
    public var forceSystemSharing: Bool

    @UserDefault(key: Keys.confirmCalls.rawValue)
    public var confirmCalls: Bool
    
    @UserDefault(key: Keys.videoPIPSwipeDirection.rawValue)
    public var videoPIPSwipeDirection: String

    @UserDefault(key: Keys.legacyNotificationsFix.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var legacyNotificationsFix: Bool
    
    @UserDefault(key: Keys.status.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var status: Int64

    public var ephemeralStatus: Int64 = 1
    
    @UserDefault(key: Keys.messageFilterKeywords.rawValue)
    public var messageFilterKeywords: [String]
    
    @UserDefault(key: Keys.inputToolbar.rawValue)
    public var inputToolbar: Bool

    @UserDefault(key: Keys.sendWithReturnKey.rawValue)
    public var sendWithReturnKey: Bool
    
    @UserDefault(key: Keys.pinnedMessageNotifications.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var pinnedMessageNotifications: String
    
    @UserDefault(key: Keys.mentionsAndRepliesNotifications.rawValue, userDefaults: UserDefaults(suiteName: APP_GROUP_IDENTIFIER) ?? .standard)
    public var mentionsAndRepliesNotifications: String
    
    @UserDefault(key: Keys.primaryUserId.rawValue)
    public var primaryUserId: String

    @UserDefault(key: Keys.dismissedSGSuggestions.rawValue)
    public var dismissedSGSuggestions: [String]

    @UserDefault(key: Keys.duckyAppIconAvailable.rawValue)
    public var duckyAppIconAvailable: Bool

    @UserDefault(key: Keys.transcriptionBackend.rawValue)
    public var transcriptionBackend: String

    @UserDefault(key: Keys.translationBackend.rawValue)
    public var translationBackend: String

    @UserDefault(key: Keys.customAppBadge.rawValue)
    public var customAppBadge: String

    @UserDefault(key: Keys.canUseNY.rawValue)
    public var canUseNY: Bool

    @UserDefault(key: Keys.nyStyle.rawValue)
    public var nyStyle: String

    @UserDefault(key: Keys.wideTabBar.rawValue)
    public var wideTabBar: Bool
    
    @UserDefault(key: Keys.tabBarSearchEnabled.rawValue)
    public var tabBarSearchEnabled: Bool

    // MARK: SuperGram

    /// Any video (except secret chats) is played as a stream.
    @UserDefault(key: Keys.sgStreamAllVideos.rawValue, defaultValue: true)
    public var sgStreamAllVideos: Bool

    /// Prefer the downloaded / partially downloaded original over HLS.
    @UserDefault(key: Keys.sgPreferDownloadedOriginal.rawValue, defaultValue: true)
    public var sgPreferDownloadedOriginal: Bool

    /// Global budget of parallel download parts.
    @UserDefault(key: Keys.sgDownloadLimiter.rawValue, defaultValue: true)
    public var sgDownloadLimiter: Bool

    /// Pause background downloads / prefetch under memory pressure, serious thermal state or Low Power Mode.
    @UserDefault(key: Keys.sgPauseDownloadsUnderPressure.rawValue, defaultValue: true)
    public var sgPauseDownloadsUnderPressure: Bool

    /// Autoplay videos / GIFs inline in chats. Default ON, like stock Telegram: the number of simultaneously
    /// attached inline players is bounded by `SuperGramInlineVideoPlaybackBudget`, so it no longer needs a
    /// blanket off switch. The raw reader in `SuperGramInlineMediaPlayback.swift` uses the same default.
    @UserDefault(key: Keys.sgInlineAutoplayVideos.rawValue, defaultValue: true)
    public var sgInlineAutoplayVideos: Bool

    /// Silent audio keep-alive for notifications while in background.
    @UserDefault(key: Keys.sgBackgroundKeepAlive.rawValue, defaultValue: true)
    public var sgBackgroundKeepAlive: Bool

    /// Application file logs.
    @UserDefault(key: Keys.sgFileLogging.rawValue, defaultValue: false)
    public var sgFileLogging: Bool

    /// MTProto / FetchV2 logs.
    @UserDefault(key: Keys.sgNetworkLogging.rawValue, defaultValue: false)
    public var sgNetworkLogging: Bool

    /// Don't send messages.reportReadMetrics.
    @UserDefault(key: Keys.sgDisableReadMetrics.rawValue, defaultValue: true)
    public var sgDisableReadMetrics: Bool

    /// Save / copy protected content (never secret chats or view-once media).
    @UserDefault(key: Keys.sgAllowSaveProtectedContent.rawValue, defaultValue: true)
    public var sgAllowSaveProtectedContent: Bool

    /// Screenshots / screen recording of protected content (never secret chats or view-once media).
    @UserDefault(key: Keys.sgAllowScreenCaptureProtected.rawValue, defaultValue: true)
    public var sgAllowScreenCaptureProtected: Bool

    /// HD stories without Premium.
    @UserDefault(key: Keys.sgStoryHDWithoutPremium.rawValue, defaultValue: true)
    public var sgStoryHDWithoutPremium: Bool

    /// "Send as round video" button in the video editor.
    @UserDefault(key: Keys.sgTelescopeButton.rawValue, defaultValue: true)
    public var sgTelescopeButton: Bool

    /// Don't send read receipts (and voice/round "listened" marks).
    @UserDefault(key: Keys.sgSkipReadReceipts.rawValue, defaultValue: false)
    public var sgSkipReadReceipts: Bool

    /// View stories without marking them as seen on the server.
    @UserDefault(key: Keys.sgStoryGhostMode.rawValue, defaultValue: false)
    public var sgStoryGhostMode: Bool

    /// Download speed mode: 0 = standard, 1 = fast, 2 = maximum (larger parts, more parallel requests).
    @UserDefault(key: Keys.sgDownloadSpeedMode.rawValue, defaultValue: 1)
    public var sgDownloadSpeedMode: Int32

    /// Keep downloading while the app is in background (keeps the app awake only while downloads are active).
    @UserDefault(key: Keys.sgBackgroundDownloads.rawValue, defaultValue: true)
    public var sgBackgroundDownloads: Bool

    /// Show the share / repost button next to messages (off by default: it is easy to hit by accident).
    @UserDefault(key: Keys.sgShowShareButton.rawValue, defaultValue: false)
    public var sgShowShareButton: Bool

    /// Chat list header: History button on the left and Edit on the right instead of the new story / new message buttons.
    @UserDefault(key: Keys.sgChatListHistoryButton.rawValue, defaultValue: true)
    public var sgChatListHistoryButton: Bool

    /// Opening a chat from another screen keeps the chain of screens instead of dropping back to the chat list.
    @UserDefault(key: Keys.sgKeepNavigationStack.rawValue, defaultValue: true)
    public var sgKeepNavigationStack: Bool

    /// Double tap on a message selects the word under the finger (text selection with copy/quote actions) instead
    /// of sending the default reaction; reactions stay on long press.
    @UserDefault(key: Keys.sgDoubleTapSelectsText.rawValue, defaultValue: true)
    public var sgDoubleTapSelectsText: Bool
}

extension SGSimpleSettings {
    public var isStealthModeEnabled: Bool {
        return storyStealthMode && canUseStealthMode
    }
    
    public static func makeOutgoingLanguageTranslationKey(accountId: Int64, peerId: Int64) -> String {
        return "\(accountId):\(peerId)"
    }
}

extension SGSimpleSettings {
    public var translationBackendEnum: SGSimpleSettings.TranslationBackend {
        return TranslationBackend(rawValue: translationBackend) ?? .default
    }
    
    public var transcriptionBackendEnum: SGSimpleSettings.TranscriptionBackend {
        return TranscriptionBackend(rawValue: transcriptionBackend) ?? .default
    }
}

extension SGSimpleSettings {
    public var isNYEnabled: Bool {
        return canUseNY && NYStyle(rawValue: nyStyle) != .default
    }
}

public func getSGDownloadPartSize(_ default: Int64, fileSize: Int64?) -> Int64 {
    let currentDownloadSetting = SGSimpleSettings.shared.downloadSpeedBoost
    // Increasing chunk size for small files make it worse in terms of overall download performance
    let smallFileSizeThreshold = 1 * 1024 * 1024 // 1 MB
    switch (currentDownloadSetting) {
        case SGSimpleSettings.DownloadSpeedBoostValues.medium.rawValue:
            if let fileSize, fileSize <= smallFileSizeThreshold {
                return `default`
            }
            return 512 * 1024
        case SGSimpleSettings.DownloadSpeedBoostValues.maximum.rawValue:
            if let fileSize, fileSize <= smallFileSizeThreshold {
                return `default`
            }
            return 1024 * 1024
        default:
            return `default`
    }
}

public func getSGMaxPendingParts(_ default: Int) -> Int {
    let currentDownloadSetting = SGSimpleSettings.shared.downloadSpeedBoost
    switch (currentDownloadSetting) {
        case SGSimpleSettings.DownloadSpeedBoostValues.medium.rawValue:
            return 8
        case SGSimpleSettings.DownloadSpeedBoostValues.maximum.rawValue:
            return 12
        default:
            return `default`
    }
}

public func sgUseShortAllChatsTitle(_ default: Bool) -> Bool {
    let currentOverride = SGSimpleSettings.shared.allChatsTitleLengthOverride
    switch (currentOverride) {
        case SGSimpleSettings.AllChatsTitleLengthOverride.short.rawValue:
            return true
        case SGSimpleSettings.AllChatsTitleLengthOverride.long.rawValue:
            return false
        default:
            return `default`
    }
}
