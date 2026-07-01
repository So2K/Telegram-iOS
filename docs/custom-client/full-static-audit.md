# Full Static Audit

Generated UTC: `2026-07-01T21:45:15Z`
Branch: `codex/stable-custom-client`
Commit: `6e370e06`
Tracked Swift files: `4454`
Changed/untracked Swift files: `204`

## Toolchain

```
# Toolchain Check
required_xcode=26.2
required_bazel=8.4.2:45e9388abf21d1107e146ea366ad080eb93cb6a5f3a4a3b048f78de0bc3faffa
required_macos=26

xcodebuild:
Xcode 16.2
Build version 16C5032a

bazel (build-input/bazel-8.4.2-darwin-arm64):
bazel 8.4.2

git:
## codex/stable-custom-client
 M Telegram/BroadcastUpload/BroadcastUploadExtension.swift
 M Telegram/NotificationService/Sources/NotificationService.swift
 M Telegram/SiriIntents/IntentContacts.swift
 M Telegram/SiriIntents/IntentHandler.swift
 M Telegram/WatchApp/Packages/OpusKit/Sources/OpusKit/OpusDecoder.swift
 M Telegram/WatchApp/Packages/OpusKit/Sources/OpusKit/OpusEncoder.swift
 M Telegram/WatchApp/Packages/RLottieKit/Sources/RLottieKit/LottieAnimation.swift
 M Telegram/WatchApp/Packages/RLottieKit/Sources/RLottieKit/TgsDecompress.swift
 M Telegram/WatchApp/Packages/TDShim/Sources/TDShim/Transport/TDLibClientManager.swift
 M Telegram/WidgetKitWidget/PeerNode.swift
 M submodules/AccountContext/Sources/DeviceContactData.swift
 M submodules/AnimatedAvatarSetNode/Sources/AnimatedAvatarSetNode.swift
 M submodules/AnimatedNavigationStripeNode/Sources/AnimatedNavigationStripeNode.swift
 M submodules/AnimatedStickerNode/Sources/AnimatedStickerFrameSource.swift
 M submodules/AnimatedStickerNode/Sources/AnimatedStickerNode.swift
 M submodules/AnimatedStickerNode/Sources/FrameCompression.swift
 M submodules/AnimatedStickerNode/Sources/VideoStickerFrameSource.swift
 M submodules/AnimationCompression/Sources/AnimationCompressor.swift
 M submodules/AnimationCompression/Sources/Buffer.swift
 M submodules/AnimationCompression/Sources/CompressedImageRenderer.swift
 M submodules/AudioWaveform/Sources/AudioWaveform.swift
 M submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift
 M submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpControllerNode.swift
 M submodules/AuthorizationUI/Sources/AuthorizationSequenceSplashController.swift
 M submodules/AvatarNode/Sources/AvatarNode.swift
 M submodules/AvatarNode/Sources/PeerAvatar.swift
 M submodules/BrowserUI/Sources/BrowserMarkdown.swift
 M submodules/ChatListUI/Sources/ChatListController.swift
 M submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift
 M submodules/ChatListUI/Sources/ChatListShimmerNode.swift
 M submodules/ChatListUI/Sources/Node/ChatListNode.swift
 M submodules/ChatListUI/Sources/Node/ChatListStatusNode.swift
 M submodules/ChatMessageBackground/Sources/ChatMessageBackground.swift
 M submodules/ChatTitleActivityNode/Sources/ChatChoosingStickerActivityContentNode.swift
 M submodules/ChatTitleActivityNode/Sources/ChatPlayingActivityContentNode.swift
 M submodules/ChatTitleActivityNode/Sources/ChatRecordingVideoActivityContentNode.swift
 M submodules/ChatTitleActivityNode/Sources/ChatRecordingVoiceActivityContentNode.swift
 M submodules/ChatTitleActivityNode/Sources/ChatTypingActivityContentNode.swift
 M submodules/ChatTitleActivityNode/Sources/ChatUploadingActivityContentNode.swift
 M submodules/CheckNode/Sources/CheckNode.swift
 M submodules/ComponentFlow/Source/Components/RoundedRectangle.swift
 M submodules/Components/ReactionButtonListComponent/Sources/ReactionButtonListComponent.swift
 M submodules/ConfettiEffect/Sources/ConfettiView.swift
 M submodules/ContactListUI/Sources/ContactListNode.swift
 M submodules/DebugSettingsUI/Sources/DebugController.swift
 M submodules/DirectMediaImageCache/Sources/DirectMediaImageCache.swift
 M submodules/DirectionalPanGesture/Sources/DirectionalPanGestureRecognizer.swift
 M submodules/Display/Source/GenerateImage.swift
 M submodules/Display/Source/ImageCorners.swift
 M submodules/Display/Source/InteractiveTransitionGestureRecognizer.swift
 M submodules/Display/Source/ListView.swift
 M submodules/Display/Source/NavigationBackButtonNode.swift
 M submodules/Display/Source/TextNode.swift
 M submodules/Display/Source/TransformImageNode.swift
 M submodules/Display/Source/UIKitUtils.swift
 M submodules/DrawingUI/Sources/ColorPickerScreen.swift
 M submodules/DrawingUI/Sources/DrawingLinkEntityView.swift
 M submodules/DrawingUI/Sources/DrawingLocationEntityView.swift
 M submodules/DrawingUI/Sources/DrawingMetalView.swift
 M submodules/DrawingUI/Sources/DrawingStickerEntityView.swift
 M submodules/DrawingUI/Sources/DrawingWeatherEntityView.swift
 M submodules/GalleryUI/Sources/GalleryPagerNode.swift
 M submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift
 M submodules/GradientBackground/Sources/SoftwareGradientBackground.swift
 M submodules/GraphCore/Sources/Helpers/UIImage+Utils.swift
 M submodules/ImageTransparency/Sources/ImageTransparency.swift
 M submodules/InstantPageUI/Sources/InstantPageDetailsNode.swift
 M submodules/InstantPageUI/Sources/InstantPageScrollableNode.swift
 M submodules/InstantPageUI/Sources/InstantPageTileNode.swift
 M submodules/InvisibleInkDustNode/Sources/InvisibleInkDustNode.swift
 M submodules/InviteLinksUI/Sources/InviteLinkViewController.swift
 M submodules/ItemListPeerItem/Sources/ItemListPeerItem.swift
 M submodules/ItemListUI/Sources/Items/ItemListEditableItem.swift
 M submodules/LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift
 M submodules/ListMessageItem/Sources/ListMessageFileItemNode.swift
 M submodules/ListMessageItem/Sources/ListMessageHoleItem.swift
 M submodules/LiveLocationPositionNode/Sources/ChatMessageLiveLocationPositionNode.swift
 M submodules/LiveLocationTimerNode/Sources/ChatMessageLiveLocationTimerNode.swift
 M submodules/LiveLocationTimerNode/Sources/LiveLocationWavesNode.swift
 M submodules/LocationUI/Sources/LocationActionListItem.swift
 M submodules/LocationUI/Sources/LocationMapNode.swift
 M submodules/ManagedFile/Sources/ManagedFile.swift
 M submodules/MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift
 M submodules/MediaPlayer/Sources/ChunkMediaPlayerV2.swift
 M submodules/MediaPlayer/Sources/FFMpegAudioFrameDecoder.swift
 M submodules/MediaPlayer/Sources/FFMpegFileReader.swift
 M submodules/MediaPlayer/Sources/FFMpegMediaFrameSourceContext.swift
 M submodules/MediaPlayer/Sources/FFMpegMediaPassthroughVideoFrameDecoder.swift
 M submodules/MediaPlayer/Sources/FFMpegMediaVideoFrameDecoder.swift
 M submodules/MediaPlayer/Sources/MediaPlayerAudioRenderer.swift
 M submodules/MediaPlayer/Sources/MediaPlayerFramePreview.swift
 M submodules/MediaPlayer/Sources/MediaPlayerNode.swift
 M submodules/MediaPlayer/Sources/MediaPlayerTimeTextNode.swift
 M submodules/MediaPlayer/Sources/RingByteBuffer.swift
 M submodules/MediaPlayer/Sources/SoftwareVideoSource.swift
 M submodules/MediaPlayer/Sources/UniversalSoftwareVideoSource.swift
 M submodules/OpenInExternalAppUI/Sources/OpenInAppIconResources.swift
 M submodules/PasscodeInputFieldNode/Sources/PasscodeInputFieldNode.swift
 M submodules/PasscodeUI/Sources/PasscodeBackground.swift
 M submodules/PasscodeUI/Sources/PasscodeEntryKeyboardNode.swift
 M submodules/PasscodeUI/Sources/PasscodeInputFieldNode.swift
 M submodules/PasscodeUI/Sources/PasscodeLockIconNode.swift
 M submodules/PassportUI/Sources/Form/FormControllerScrollerNode.swift
 M submodules/PassportUI/Sources/SecureIdLocalResource.swift
 M submodules/PasswordSetupUI/Sources/TwoFactorAuthDataInputScreen.swift
 M submodules/PeerInfoAvatarListNode/Sources/PeerInfoAvatarListNode.swift
 M submodules/PhotoResources/Sources/PhotoResources.swift
 M submodules/PremiumUI/Sources/DataRainView.swift
 M submodules/PremiumUI/Sources/PremiumLimitScreen.swift
 M submodules/QrCode/Sources/QrCode.swift
 M submodules/QrCodeUI/Sources/GlassButtonNode.swift
 M submodules/RadialStatusNode/Sources/RadialCheckContentNode.swift
 M submodules/RadialStatusNode/Sources/RadialCloudProgressContentNode.swift
 M submodules/RadialStatusNode/Sources/RadialProgressContentNode.swift
 M submodules/RadialStatusNode/Sources/RadialStatusIconContentNode.swift
 M submodules/RadialStatusNode/Sources/RadialStatusSecretTimeoutContentNode.swift
 M submodules/ReactionSelectionNode/Sources/ReactionContextNode.swift
 M submodules/SemanticStatusNode/Sources/SemanticStatusNode.swift
 M submodules/SemanticStatusNode/Sources/SemanticStatusNodeIconContext.swift
 M submodules/SemanticStatusNode/Sources/SemanticStatusNodeSecretTimeoutContext.swift
 M submodules/SettingsUI/Sources/BubbleSettings/BubbleSettingsController.swift
 M "submodules/SettingsUI/Sources/Text Size/TextSizeSelectionController.swift"
 M submodules/SettingsUI/Sources/Themes/ThemePreviewControllerNode.swift
 M submodules/SettingsUI/Sources/Themes/ThemeSettingsAccentColorItem.swift
 M submodules/SettingsUI/Sources/Themes/ThemeSettingsAppIconItem.swift
 M submodules/ShimmerEffect/Sources/ShimmerEffect.swift
 M submodules/SparseItemGrid/Sources/SparseDiscreteScrollingArea.swift
 M submodules/SparseItemGrid/Sources/SparseItemGrid.swift
 M submodules/SparseItemGrid/Sources/SparseItemGridScrollingArea.swift
 M submodules/StickerResources/Sources/StickerResources.swift
 M submodules/TabBarUI/Sources/TabBarNode.swift
 M submodules/TelegramAnimatedStickerNode/Sources/AnimatedStickerUtils.swift
 M submodules/TelegramApi/Sources/Buffer.swift
 M submodules/TelegramBaseController/Sources/MediaNavigationAccessoryHeaderNode.swift
 M submodules/TelegramCallsUI/Sources/CallControllerButton.swift
 M submodules/TelegramCallsUI/Sources/CallControllerStatusNode.swift
 M submodules/TelegramCallsUI/Sources/CallControllerToastNode.swift
 M submodules/TelegramCallsUI/Sources/LegacyCallControllerButton.swift
 M submodules/TelegramCallsUI/Sources/LegacyCallControllerStatusNode.swift
 M submodules/TelegramCallsUI/Sources/PresentationCall.swift
 M submodules/TelegramCallsUI/Sources/VideoChatEncryptionKeyComponent.swift
 M submodules/TelegramCallsUI/Sources/VideoChatScreenMoreMenu.swift
 M submodules/TelegramCallsUI/Sources/VideoChatVideoLoadingEffectView.swift
 M submodules/TelegramCallsUI/Sources/VoiceChatAccountHeaderActionSheetItem.swift
 M submodules/TelegramCallsUI/Sources/VoiceChatController.swift
 M submodules/TelegramCallsUI/Sources/VoiceChatFullscreenParticipantItem.swift
 M submodules/TelegramCallsUI/Sources/VoiceChatHeaderButton.swift
 M submodules/TelegramCallsUI/Sources/VoiceChatMainStageNode.swift
 M submodules/TelegramCallsUI/Sources/VoiceChatMicrophoneNode.swift
 M submodules/TelegramCallsUI/Sources/VoiceChatPinNode.swift
 M submodules/TelegramCallsUI/Sources/VoiceChatRecordingSetupController.swift
 M submodules/TelegramCallsUI/Sources/VoiceChatSpeakerNode.swift
 M submodules/TelegramCallsUI/Sources/VoiceChatTileItemNode.swift
 M submodules/TelegramCore/Sources/Network/MultipartFetch.swift
 M submodules/TelegramCore/Sources/Network/MultipartUpload.swift
 M submodules/TelegramIntents/Sources/TelegramIntents.swift
 M submodules/TelegramPresentationData/Sources/ChatControllerBackgroundNode.swift
 M submodules/TelegramPresentationData/Sources/ChatMessageBubbleImages.swift
 M submodules/TelegramPresentationData/Sources/PresentationThemeEssentialGraphics.swift
 M submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesChat.swift
 M submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesChatList.swift
 M submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesItemList.swift
 M submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesSettings.swift
 M submodules/TelegramUI/Components/MediaEditor/Sources/AdjustmentsRenderPass.swift
 M submodules/TelegramUI/Components/MediaEditor/Sources/EnhanceRenderPass.swift
 M submodules/TelegramUI/Components/MediaEditor/Sources/HistogramCalculationPass.swift
 M submodules/TelegramUI/Components/MediaEditor/Sources/MediaEditor.swift
 M submodules/TelegramUI/Components/MediaEditor/Sources/MediaEditorComposer.swift
 M submodules/TelegramUI/Components/MediaEditor/Sources/StickerOutlineRenderPass.swift
 M submodules/TelegramUI/Components/MediaEditor/Sources/VideoFinishPass.swift
 M submodules/TelegramUI/Components/MediaEditor/Sources/VideoInputPass.swift
 M submodules/TelegramUI/Components/MediaEditorScreen/Sources/StickerCutoutOutlineView.swift
 M submodules/TelegramUI/Components/MediaScrubberComponent/Sources/MediaScrubberComponent.swift
 M submodules/TelegramUI/Components/OpenUserGeneratedUrl/Sources/OpenUserGeneratedUrl.swift
 M submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/PeerInfoStoryPaneNode.swift
 M submodules/TelegramUI/Components/PeerInfo/PeerInfoVisualMediaPaneNode/Sources/PeerInfoVisualMediaPaneNode.swift
 M submodules/TelegramUI/Components/ShareExtensionContext/Sources/ShareExtensionContext.swift
 M submodules/TelegramUI/Sources/AppDelegate.swift
 M submodules/TelegramUI/Sources/ChatController.swift
 M submodules/TelegramUI/Sources/ChatControllerForwardMessages.swift
 M submodules/TelegramUI/Sources/ChatControllerNode.swift
 M submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift
 M submodules/TelegramUI/Sources/ChatHistoryListNode.swift
 M submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift
 M submodules/TelegramUI/Sources/FetchCachedRepresentations.swift
 M submodules/TelegramUI/Sources/ManagedAudioRecorder.swift
 M submodules/TelegramUI/Sources/OpenResolvedUrl.swift
 M submodules/TelegramUI/Sources/OpenUrl.swift
 M submodules/TelegramUI/Sources/SaveMediaToFiles.swift
 M submodules/TelegramUI/Sources/SharedAccountContext.swift
 M submodules/TelegramUI/Sources/SharedNotificationManager.swift
 M submodules/TelegramUI/Sources/SpotlightContacts.swift
 M submodules/TelegramUI/Sources/TransformOutgoingMessageMedia.swift
 M submodules/TelegramUIPreferences/Sources/ExperimentalUISettings.swift
 M submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift
 M submodules/TelegramUniversalVideoContent/Sources/HLSVideoContent.swift
 M submodules/TelegramUniversalVideoContent/Sources/HLSVideoJSNativeContentNode.swift
 M submodules/TextFormat/Sources/GenerateTextEntities.swift
 M submodules/TextFormat/Sources/StringWithAppliedEntities.swift
 M submodules/UrlWhitelist/Sources/UrlWhitelist.swift
 M submodules/WallpaperBackgroundNode/Sources/WallpaperBackgroundNode.swift
 M submodules/WallpaperResources/Sources/WallpaperResources.swift
 M submodules/WebUI/Sources/WebAppLocationAlertController.swift
?? .swiftlint.yml
?? build-system/custom-client-template-development-configuration.json
?? docs/custom-client/
?? scripts/custom-client/
?? submodules/AuthorizationUI/Sources/AuthorizationApiCredentials.swift

blocked_by=xcode:16.2
exit_status=1
```

## Changed-File Crash-Risk Gate

```
Crash-risk scan passed.
exit_status=0
```

## Repository-Wide Crash-Risk Inventory

```
Crash-risk scan found force-unwrap patterns at C/media/payload/error boundaries:
Tests/AnimationCacheTest/Sources/ViewController.swift:66:                    let data = try! Data(contentsOf: URL(fileURLWithPath: path))
Tests/AnimationCacheTest/Sources/ViewController.swift:98:                    memcpy(context.bytes, bytes.baseAddress!, height * bytesPerRow)
Tests/LottieMetalTest/Sources/CompareToReferenceRendering.swift:14:    let lhsBuffer = try! vImage_Buffer(cgImage: lhs.cgImage!)
Tests/LottieMetalTest/Sources/CompareToReferenceRendering.swift:15:    let rhsBuffer = try! vImage_Buffer(cgImage: rhs.cgImage!)
Tests/LottieMetalTest/Sources/CompareToReferenceRendering.swift:16:    let deltaBuffer = try! vImage_Buffer(cgImage: lhs.cgImage!)
Tests/LottieMetalTest/Sources/CompareToReferenceRendering.swift:58:    let colorSpace = Unmanaged<CGColorSpace>.passRetained(lhs.cgImage!.colorSpace!)
Tests/LottieMetalTest/Sources/CompareToReferenceRendering.swift:59:    let deltaImage = try! deltaBuffer.createCGImage(format: vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace, bitmapInfo: lhs.cgImage!.bitmapInfo, version: 0, decode: nil, renderingIntent: .defaultIntent), flags: .doNotTile)
Tests/LottieMetalTest/Sources/CompareToReferenceRendering.swift:62:        let diffImage = try! lhsBuffer.createCGImage(format: vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace, bitmapInfo: lhs.cgImage!.bitmapInfo, version: 0, decode: nil, renderingIntent: .defaultIntent), flags: .doNotTile)
Tests/LottieMetalTest/Sources/CompareToReferenceRendering.swift:91:            let referenceImageData = try! Data(contentsOf: URL(fileURLWithPath: cacheFolderPath + "/frame\(frameIndex)"))
Tests/LottieMetalTest/Sources/CompareToReferenceRendering.swift:126:    for fileName in try! FileManager.default.contentsOfDirectory(atPath: directoryPath) {
Tests/LottieMetalTest/Sources/CompareToReferenceRendering.swift:159:    for fileName in try! FileManager.default.contentsOfDirectory(atPath: directoryPath) {
Tests/LottieMetalTest/Sources/CompareToReferenceRendering.swift:348:        try! compressImageFrame(image: referenceImage).write(to: URL(fileURLWithPath: cacheFolderPath + "/frame\(i)"))
Tests/LottieMetalTest/Sources/CompareToReferenceRendering.swift:351:    let _ = try! FileManager.default.moveItem(atPath: cacheFolderPath, toPath: targetFolderPath)
Tests/LottieMetalTest/Sources/ViewController.swift:82:            let baseCachePath = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true).path + "/frame-cache"
Tests/LottieMetalTest/Sources/ViewController.swift:282:            /*let animationData = try! Data(contentsOf: URL(fileURLWithPath: filePath))
Tests/LottieMetalTest/Sources/ViewController.swift:304:                let animationData = try! Data(contentsOf: URL(fileURLWithPath: filePath))
Tests/LottieMetalTest/Sources/ViewController.swift:332:                let animationInstance = LottieInstance(data: try! Data(contentsOf: URL(fileURLWithPath: filePath)), fitzModifier: .none, colorReplacements: nil, cacheKey: "")!
Tests/LottieMetalTest/Sources/ViewController.swift:335:                let frameBuffer = malloc(performanceFrameSize * 4 * performanceFrameSize)!
build-system/XcodeParse/Sources/main.swift:36:    // private static let variablePatternRegex = try! NSRegularExpression(pattern: "\\$\\(([^)]+)\\)", options: [])
build-system/XcodeParse/Sources/main.swift:39:    private static let simpleVariableRegex = try! NSRegularExpression(pattern: "\\$\\(([^$)]+)\\)", options: [])
build-system/XcodeParse/Sources/main.swift:42:    private static let nestedVariableRegex = try! NSRegularExpression(pattern: "\\$\\(([^$)]*\\$\\([^)]+\\)[^)]*)\\)", options: [])
submodules/Postbox/Sources/Coding.swift:52:private let emptyMemory = malloc(1)!
submodules/Postbox/Sources/Coding.swift:82:            self.memory = malloc(data.count)!
submodules/Postbox/Sources/Coding.swift:184:                self.memory = malloc(self.capacity)!
submodules/Postbox/Sources/Coding.swift:202:                self.memory = malloc(self.capacity)!
submodules/Postbox/Sources/Coding.swift:240:            self.read(buffer.baseAddress!, offset: 0, length: length)
submodules/Postbox/Sources/Coding.swift:246:        let result = MemoryBuffer(memory: malloc(length)!, capacity: length, length: length, freeWhenDone: true)
submodules/Postbox/Sources/Coding.swift:364:            self.buffer.write(bytes.baseAddress!, offset: 0, length: Int(length))
submodules/Postbox/Sources/Coding.swift:471:            self.buffer.write(UnsafeRawPointer(data.baseAddress!), offset: 0, length: Int(length) * 4)
submodules/Postbox/Sources/Coding.swift:483:            self.buffer.write(UnsafeRawPointer(data.baseAddress!), offset: 0, length: Int(length) * 8)
submodules/Postbox/Sources/Coding.swift:597:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/Coding.swift:691:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/Coding.swift:699:        try! value.encode(to: innerEncoder)
submodules/Postbox/Sources/Coding.swift:715:            try! object.encode(to: innerEncoder)
submodules/Postbox/Sources/Coding.swift:931:                return memcmp(bytes + (offset - Int(readKeyLength) - 1), keyBytes.baseAddress!, keyLength) == 0
submodules/Postbox/Sources/Coding.swift:975:            let keyBytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/Coding.swift:1925:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/MediaBox.swift:1107:                                            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/MediaBox.swift:1289:                                        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/MediaBoxFile.swift:256:                    let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/MediaBoxFile.swift:361:                        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/Postbox/Sources/MediaBoxFileContextV2Impl.swift:460:                                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/MediaBoxFileMap.swift:77:                    let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/MediaBoxFileMap.swift:146:                    let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/MessageHistoryTable.swift:1308:                sharedBuffer.write(buffer.baseAddress!, length: buffer.count)
submodules/Postbox/Sources/MessageHistoryTable.swift:2034:                    sharedBuffer.write(buffer.baseAddress!, length: buffer.count)
submodules/Postbox/Sources/MessageHistoryTable.swift:2323:                sharedBuffer.write(buffer.baseAddress!, length: buffer.count)
submodules/Postbox/Sources/MessageHistoryTable.swift:2554:            let attributesBytes = malloc(attributesLength)!
submodules/Postbox/Sources/MessageHistoryTable.swift:2567:            let embeddedMediaBytes = malloc(embeddedMediaLength)!
submodules/Postbox/Sources/OrderedItemListIndexTable.swift:34:            let id = MemoryBuffer(memory: malloc(key.length - 4)!, capacity: key.length - 4, length: key.length - 4, freeWhenDone: true)
submodules/Postbox/Sources/OrderedItemListTable.swift:249:            let id = MemoryBuffer(memory: malloc(key.length - 5)!, capacity: key.length - 5, length: key.length - 5, freeWhenDone: true)
submodules/Postbox/Sources/PostboxUpgrade_19to20.swift:327:                    let embeddedMediaBytes = malloc(embeddedMediaLength)!
submodules/Postbox/Sources/PostboxUpgrade_20to21.swift:329:                    let embeddedMediaBytes = malloc(embeddedMediaLength)!
submodules/Postbox/Sources/SqliteValueBox.swift:1390:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/SqliteValueBox.swift:1395:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/SqliteValueBox.swift:1400:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/SqliteValueBox.swift:1405:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/SqliteValueBox.swift:1431:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/SqliteValueBox.swift:1458:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/SqliteValueBox.swift:1482:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/SqliteValueBox.swift:1487:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/SqliteValueBox.swift:1511:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/SqliteValueBox.swift:1516:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/SqliteValueBox.swift:1521:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/SqliteValueBox.swift:2357:        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/StorageBox/StorageBox.swift:16:        return CryptoMD5(bytes.baseAddress!, Int32(bytes.count))
submodules/Postbox/Sources/StorageBox/StorageBox.swift:112:                    readBuffer.read(buffer.baseAddress!, offset: 0, length: buffer.count)
submodules/Postbox/Sources/StorageBox/StorageBox.swift:134:                writeBuffer.write(buffer.baseAddress!, length: Int(idLength))
submodules/Postbox/Sources/TimeBasedCleanup.swift:36:            let _ = fcntl(fd, F_GETPATH, buffer.baseAddress!)
submodules/Postbox/Sources/TimeBasedCleanup.swift:37:            let string = String(cString: buffer.baseAddress!.assumingMemoryBound(to: CChar.self))
submodules/Postbox/Sources/TimeBasedCleanup.swift:111:                        readBuffer.read(buffer.baseAddress!, offset: 0, length: buffer.count)
submodules/Postbox/Sources/Utils/Encoder/AdaptedPostboxKeyedEncodingContainer.swift:51:            try! value.encode(to: innerEncoder)
submodules/Postbox/Sources/Utils/Encoder/AdaptedPostboxUnkeyedEncodingContainer.swift:139:            try! value.encode(to: innerEncoder)
submodules/Postbox/Sources/ValueBoxKey.swift:21:        self.memory = malloc(length)!
submodules/Postbox/Sources/ValueBoxKey.swift:45:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/Postbox/Sources/ValueBoxKey.swift:52:        memcpy(self.memory + offset, value.baseAddress!.assumingMemoryBound(to: UInt8.self), value.count)
submodules/Postbox/Sources/ValueBoxKey.swift:95:            memcpy(bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), self.memory + offset, length)
submodules/Postbox/Sources/ValueBoxKey.swift:102:        let result = MemoryBuffer(memory: malloc(length)!, capacity: length, length: length, freeWhenDone: true)
submodules/Postbox/Sources/ValueBoxKey.swift:261:        let data = malloc(self.length)!
submodules/TelegramApi/Sources/Api20.swift:1653:                    serializeString(_data.phoneCountry!, buffer: buffer, boxed: false)
submodules/TelegramApi/Sources/Api38.swift:1191:                    serializeString(_data.disallowedCountry!, buffer: buffer, boxed: false)
submodules/TelegramApi/Sources/Api7.swift:907:                    serializeString(_data.country!, buffer: buffer, boxed: false)
submodules/TelegramCore/FlatBuffers/Sources/ByteBuffer.swift:132:      _storage.copy(from: bufferPointer.baseAddress!, count: bytes.count)
submodules/TelegramCore/FlatBuffers/Sources/ByteBuffer.swift:150:      _storage.copy(from: bufferPointer.baseAddress!, count: data.count)
submodules/TelegramCore/FlatBuffers/Sources/ByteBuffer.swift:181:      _storage.copy(from: buf.baseAddress!, count: buf.count)
submodules/TelegramCore/FlatBuffers/Sources/ByteBuffer.swift:254:        ptr.baseAddress!,
submodules/TelegramCore/FlatBuffers/Sources/ByteBuffer.swift:269:        ptr.baseAddress!,
submodules/TelegramCore/FlatBuffers/Sources/ByteBuffer.swift:285:        ptr.baseAddress!,
submodules/TelegramCore/FlatBuffers/Sources/ByteBuffer.swift:357:      bytes.baseAddress!,
submodules/TelegramCore/FlatBuffers/Sources/ByteBuffer.swift:492:    return String(cString: bufprt.baseAddress!)
submodules/TelegramCore/Sources/Account/Account.swift:604:        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/Account/Account.swift:634:        let bytes = rawBytes.baseAddress!
submodules/TelegramCore/Sources/Account/Account.swift:641:        let bytes = rawBytes.baseAddress!
submodules/TelegramCore/Sources/Account/Account.swift:648:        let bytes = rawBytes.baseAddress!
submodules/TelegramCore/Sources/Account/Account.swift:666:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/Account/Account.swift:675:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/Account/Account.swift:678:                    let sourceBytes = sourceBuffer.bindMemory(to: Int8.self).baseAddress!
submodules/TelegramCore/Sources/Account/Account.swift:728:        let aBytes = rawABytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/Account/Account.swift:730:            let bBytes = rawBBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/Account/Account.swift:751:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/Account/Account.swift:757:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/Account/Account.swift:760:                    let sourceBytes = sourceBuffer.bindMemory(to: Int8.self).baseAddress!
submodules/TelegramCore/Sources/Account/Account.swift:822:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/Account/Account.swift:837:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/Account/Account.swift:1007:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/Account/Account.swift:1055:        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/Account/AccountManager.swift:47:            let legacyRootObjectData = try! container.decode(AdaptedPostboxDecoder.RawObjectData.self, forKey: .legacyRootObject)
submodules/TelegramCore/Sources/Account/AccountManager.swift:49:                self = .backupData(try! AdaptedPostboxDecoder().decode(AccountBackupDataAttribute.self, from: legacyRootObjectData.data))
submodules/TelegramCore/Sources/Account/AccountManager.swift:51:                self = .environment(try! AdaptedPostboxDecoder().decode(AccountEnvironmentAttribute.self, from: legacyRootObjectData.data))
submodules/TelegramCore/Sources/Account/AccountManager.swift:53:                self = .sortOrder(try! AdaptedPostboxDecoder().decode(AccountSortOrderAttribute.self, from: legacyRootObjectData.data))
submodules/TelegramCore/Sources/Account/AccountManager.swift:55:                self = .loggedOut(try! AdaptedPostboxDecoder().decode(LoggedOutAccountAttribute.self, from: legacyRootObjectData.data))
submodules/TelegramCore/Sources/AccountManager/AccountManagerMetadataTable.swift:201:            let data = try! AdaptedPostboxEncoder().encode(record)
submodules/TelegramCore/Sources/AccountManager/AccountManagerRecordTable.swift:44:            let data = try! AdaptedPostboxEncoder().encode(record)
submodules/TelegramCore/Sources/ApiUtils/ReplyMarkupMessageAttribute.swift:34:            let memory = malloc(data.size)!
submodules/TelegramCore/Sources/Authorization.swift:46:        return try! NSRegularExpression(pattern: self.pattern, options: self.options)
submodules/TelegramCore/Sources/Network/FetchV2.swift:183:                    let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/Network/FetchV2.swift:185:                        let iv = rawIv.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/Network/FetchV2.swift:812:                                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/PendingMessages/PendingMessageUploadedContent.swift:424:            let seedBytes = malloc(32)!
submodules/TelegramCore/Sources/PendingMessages/PendingMessageUploadedContent.swift:478:                        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:14:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:24:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:35:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:45:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:55:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:58:                    memcpy(bytes, sha1A.baseAddress!.assumingMemoryBound(to: UInt8.self), 8)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:61:                    memcpy(bytes.advanced(by: 8), sha1B.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: 8), 12)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:64:                    memcpy(bytes.advanced(by: 8 + 12), sha1C.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: 4), 12)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:71:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:74:                    memcpy(bytes, sha1A.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: 8), 12)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:77:                    memcpy(bytes.advanced(by: 12), sha1B.baseAddress!.assumingMemoryBound(to: UInt8.self), 8)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:80:                    memcpy(bytes.advanced(by: 12 + 8), sha1C.baseAddress!.assumingMemoryBound(to: UInt8.self).advanced(by: 16), 4)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:83:                    memcpy(bytes.advanced(by: 12 + 8 + 4), sha1D.baseAddress!.assumingMemoryBound(to: UInt8.self), 8)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:156:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:168:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:178:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:201:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:240:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:262:        payloadData.append(bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 4)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:271:            let randomBuf = malloc(16)!
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:285:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:294:                encryptedPayload.append(bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 8)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:303:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:348:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatEncryption.swift:357:                encryptedPayload.append(bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), count: 8)
submodules/TelegramCore/Sources/SecretChats/SecretChatRekeySession.swift:19:                let aBytes = malloc(256)!
submodules/TelegramCore/Sources/SecretChats/SecretChatRekeySession.swift:66:                            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/SecretChatRekeySession.swift:121:                let bBytes = malloc(256)!
submodules/TelegramCore/Sources/SecretChats/UpdateSecretChat.swift:48:                        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/SecretChats/UpdateSecretChat.swift:99:                    let bBytes = malloc(256)!
submodules/TelegramCore/Sources/State/CachedSentMediaReferences.swift:15:                    let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/State/CachedSentMediaReferences.swift:23:                    let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/State/CallSessionManager.swift:745:        let bBytes = malloc(256)!
submodules/TelegramCore/Sources/State/CallSessionManager.swift:1114:                                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/State/CallSessionManager.swift:1381:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/State/CallSessionManager.swift:1395:        let aBytes = malloc(256)!
submodules/TelegramCore/Sources/State/ManagedCloudChatRemoveMessagesOperations.swift:57:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedConsumePersonalMessagesActions.swift:19:        return CryptoMD5(bytes.baseAddress!, Int32(bytes.count))
submodules/TelegramCore/Sources/State/ManagedConsumePersonalMessagesActions.swift:31:        let bytes = buffer.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/State/ManagedLocalizationUpdatesOperations.swift:57:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:94:                    result = entry.withUpdatedContents(updatedContents).mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:97:                    result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:245:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:360:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:394:            let randomBytes = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:414:            let randomBytes = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:434:            let randomBytes = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:454:            let randomBytes = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:1000:                    let randomBytesData = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:1086:                        let randomBytesData = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:1447:            let randomBytesData = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:1504:                    let randomBytesData = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:1521:                    let randomBytesData = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:1538:                    let randomBytesData = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:1565:                    let randomBytesData = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:1637:                    let randomBytesData = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSecretChatOutgoingOperations.swift:1654:                    let randomBytesData = malloc(15)!
submodules/TelegramCore/Sources/State/ManagedSynchronizeAppLogEventsOperations.swift:57:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizeChatInputStateOperations.swift:65:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizeConsumeMessageContentsOperations.swift:57:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizeEmojiKeywordsOperations.swift:57:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizeGroupedPeersOperations.swift:54:                    result.append(entry.mergedEntry!)
submodules/TelegramCore/Sources/State/ManagedSynchronizeInstalledStickerPacksOperations.swift:56:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizeMarkAllUnseenPersonalMessagesOperations.swift:56:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizeMarkFeaturedStickerPacksAsSeenOperations.swift:57:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizePeerStoriesOperations.swift:58:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizePinnedChatsOperations.swift:56:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizeRecentlyUsedMediaOperations.swift:57:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizeSavedGifsOperations.swift:57:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizeSavedStickersOperations.swift:57:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/State/ManagedSynchronizeViewStoriesOperations.swift:62:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/SyncCore/SyncCore_CachedResolvedByNamePeer.swift:13:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/SyncCore/SyncCore_CachedResolvedByPhonePeer.swift:13:                let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/SyncCore/SyncCore_FeaturedStickerPack.swift:21:        self.rawValue = MemoryBuffer(memory: malloc(8)!, capacity: 8, length: 8, freeWhenDone: true)
submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift:1555:        let parsedValue = try! InstantPage(flatBuffersObject: deserializedValue)
submodules/TelegramCore/Sources/SyncCore/SyncCore_InstantPage.swift:1751:                return try! InstantPage(flatBuffersObject: self._wrapped!)
submodules/TelegramCore/Sources/SyncCore/SyncCore_RecentMediaItem.swift:24:        self.rawValue = MemoryBuffer(memory: malloc(4 + 8)!, capacity: 4 + 8, length: 4 + 8, freeWhenDone: true)
submodules/TelegramCore/Sources/SyncCore/SyncCore_RecentMediaItem.swift:117:        self.rawValue = MemoryBuffer(memory: malloc(1 + 4 + 8)!, capacity: 1 + 4 + 8, length: 1 + 4 + 8, freeWhenDone: true)
submodules/TelegramCore/Sources/SyncCore/SyncCore_RecentMediaItem.swift:130:        self.rawValue = MemoryBuffer(memory: malloc(1 + 2 + data.count)!, capacity: 1 + 2 + data.count, length: 1 + 2 + data.count, freeWhenDone: true)
submodules/TelegramCore/Sources/SyncCore/SyncCore_RecentMediaItem.swift:135:            let _ = memcpy(self.rawValue.memory.advanced(by: 1 + 2), bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), bytes.count)
submodules/TelegramCore/Sources/SyncCore/SyncCore_RecentMediaItem.swift:223:        self.rawValue = MemoryBuffer(memory: malloc(1 + 4 + 8)!, capacity: 1 + 4 + 8, length: 1 + 4 + 8, freeWhenDone: true)
submodules/TelegramCore/Sources/SyncCore/SyncCore_RecentMediaItem.swift:236:        self.rawValue = MemoryBuffer(memory: malloc(1 + 2 + data.count)!, capacity: 1 + 2 + data.count, length: 1 + 2 + data.count, freeWhenDone: true)
submodules/TelegramCore/Sources/SyncCore/SyncCore_RecentMediaItem.swift:241:            let _ = memcpy(self.rawValue.memory.advanced(by: 1 + 2), bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), bytes.count)
submodules/TelegramCore/Sources/SyncCore/SyncCore_RecentMediaItem.swift:249:        self.rawValue = MemoryBuffer(memory: malloc(1)!, capacity: 1, length: 1, freeWhenDone: true)
submodules/TelegramCore/Sources/SyncCore/SyncCore_RecentMediaItem.swift:339:        self.rawValue = MemoryBuffer(memory: malloc(8)!, capacity: 8, length: 8, freeWhenDone: true)
submodules/TelegramCore/Sources/SyncCore/SyncCore_RecentPeerItem.swift:19:        self.rawValue = MemoryBuffer(memory: malloc(8)!, capacity: 8, length: 8, freeWhenDone: true)
submodules/TelegramCore/Sources/SyncCore/SyncCore_SecretChatState.swift:28:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int64.self)
submodules/TelegramCore/Sources/SyncCore/SyncCore_SecretChatState.swift:34:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int32.self)
submodules/TelegramCore/Sources/SyncCore/SyncCore_SecretChatState.swift:65:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int64.self)
submodules/TelegramCore/Sources/SyncCore/SyncCore_SecretChatState.swift:71:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int32.self)
submodules/TelegramCore/Sources/SyncCore/SyncCore_SecretChatState.swift:105:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int64.self)
submodules/TelegramCore/Sources/SyncCore/SyncCore_SecretChatState.swift:143:            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int64.self)
submodules/TelegramCore/Sources/SyncCore/SyncCore_StickerPackCollectionInfo.swift:114:        let parsedValue = try! StickerPackCollectionInfo(flatBuffersObject: deserializedValue)
submodules/TelegramCore/Sources/SyncCore/SyncCore_StickerPackCollectionInfo.swift:212:                return try! StickerPackCollectionInfo(flatBuffersObject: self._wrapped!)
submodules/TelegramCore/Sources/SyncCore/SyncCore_TelegramGroup.swift:218:        let parsedValue = try! TelegramGroup(flatBuffersObject: deserializedValue)
submodules/TelegramCore/Sources/SyncCore/SyncCore_TelegramMediaFile.swift:682:                return try! TelegramMediaFile(flatBuffersObject: self._wrapped!)
submodules/TelegramCore/Sources/SyncCore/SyncCore_TelegramMediaFile.swift:1506:                        return try! TelegramMediaFile.VideoThumbnail(flatBuffersObject: thumbnail)
submodules/TelegramCore/Sources/SyncCore/SyncCore_TelegramUser.swift:352:        let parsedValue = try! TelegramUser(flatBuffersObject: deserializedValue)
submodules/TelegramCore/Sources/SyncCore/SyncCore_WallapersState.swift:21:            return (try! AdaptedPostboxDecoder().decode(TelegramWallpaperNativeCodable.self, from: data)).value
submodules/TelegramCore/Sources/SyncCore/SyncCore_WallapersState.swift:29:            return try! AdaptedPostboxEncoder().encode(TelegramWallpaperNativeCodable(wallpaper))
submodules/TelegramCore/Sources/TelegramEngine/Contacts/ContactManagement.swift:9:        let bytes = rawBytes.baseAddress!
submodules/TelegramCore/Sources/TelegramEngine/Messages/BotWebView.swift:595:            arc4random_buf(buffer.assumingMemoryBound(to: UInt8.self).baseAddress!, buffer.count)
submodules/TelegramCore/Sources/TelegramEngine/Peers/ChatListFiltering.swift:1416:                result = entry.mergedEntry!
submodules/TelegramCore/Sources/TelegramEngine/Peers/CreateSecretChat.swift:19:                    let aBytes = malloc(256)!
submodules/TelegramCore/Sources/TelegramEngine/Peers/TelegramEnginePeers.swift:1135:                let _ = try! AdaptedPostboxDecoder().decode(InternalChatInterfaceState.self, from: data)
submodules/TelegramCore/Sources/TelegramEngine/SecureId/AccessSecureId.swift:21:        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/TelegramEngine/SecureId/AccessSecureId.swift:58:        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/TelegramEngine/SecureId/AccessSecureId.swift:74:        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/TelegramEngine/SecureId/AccessSecureId.swift:102:        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/TelegramEngine/SecureId/AccessSecureId.swift:111:        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/TelegramEngine/SecureId/AccessSecureId.swift:187:                    let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/TelegramEngine/SecureId/SaveSecureIdValue.swift:59:        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/TelegramEngine/SecureId/SecureIdPadding.swift:8:        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/TelegramEngine/SecureId/SecureIdPadding.swift:13:            let source = rawSource.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/TelegramEngine/SecureId/SecureIdValueAccessContext.swift:29:        let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/Utils/FlatBuffersUtils.swift:19:        return try! getCheckedRoot(byteBuffer: &byteBuffer, fileId: fileId, options: options)
submodules/TelegramCore/Sources/Utils/Log.swift:237:                            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: Int8.self)
submodules/TelegramCore/Sources/Utils/Log.swift:382:                            let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/Utils/Log.swift:491:                    let bytes = rawBytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
submodules/TelegramCore/Sources/Utils/MemoryBufferExtensions.swift:20:        let memory = malloc(buffer.length)!
submodules/TelegramCore/Sources/Utils/TelegramMedia_FlatBuffers.swift:64:                return try! TelegramMedia_parse(flatBuffersObject: self._wrapped!)
submodules/TelegramUI/Components/AudioWaveformComponent/Sources/AudioWaveformComponent.swift:527:                let samples = rawSamples.baseAddress!.assumingMemoryBound(to: UInt16.self)
submodules/TelegramUI/Components/AudioWaveformComponent/Sources/AudioWaveformComponent.swift:542:                let adjustedSamplesMemory = malloc(numSamples * 2)!
submodules/TelegramUI/Components/AudioWaveformNode/Sources/AudioWaveformNode.swift:87:        let context = UIGraphicsGetCurrentContext()!
submodules/TelegramUI/Components/AudioWaveformNode/Sources/AudioWaveformNode.swift:108:                    let samples = rawSamples.baseAddress!.assumingMemoryBound(to: UInt16.self)
submodules/TelegramUI/Components/AvatarEditorScreen/Sources/AvatarEditorScreen.swift:1470:                            memcpy(context.bytes, bytes.baseAddress!, height * bytesPerRow)
submodules/TelegramUI/Components/AvatarEditorScreen/Sources/ColorPickerComponent.swift:521:        let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: &locations)!
submodules/TelegramUI/Components/AvatarEditorScreen/Sources/ColorPickerComponent.swift:600:        let context = UIGraphicsGetCurrentContext()!
submodules/TelegramUI/Components/AvatarEditorScreen/Sources/ColorPickerComponent.swift:605:        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!
submodules/TelegramUI/Components/AvatarEditorScreen/Sources/ColorPickerComponent.swift:610:        let overlayGradient = CGGradient(colorsSpace: colorSpace, colors: overlayColors as CFArray, locations: &overlayLocations)!
submodules/TelegramUI/Components/BatchVideoRendering/Sources/BatchVideoRenderingContext.swift:389:        let dict: NSMutableDictionary = attachments[0] as! NSMutableDictionary
submodules/TelegramUI/Components/Calls/CallScreen/Sources/Components/PrivateCallPictureInPictureView.swift:37:    let dict: NSMutableDictionary = attachments[0] as! NSMutableDictionary
submodules/TelegramUI/Components/Calls/VideoChatMicButtonComponent/Sources/VideoChatMicButtonComponent.swift:509:                        let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: &locations)!
submodules/TelegramUI/Components/CameraScreen/Sources/CameraScreen.swift:288:                        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!
submodules/TelegramUI/Components/CameraScreen/Sources/CameraScreen.swift:4852:    let dict: NSMutableDictionary = attachments[0] as! NSMutableDictionary
submodules/TelegramUI/Components/CameraScreen/Sources/ShutterBlobView.swift:173:        self.drawPassthroughPipelineState = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
submodules/TelegramUI/Components/Chat/ChatMessageAnimatedStickerItemNode/Sources/ChatMessageAnimatedStickerItemNode.swift:3265:        let context = UIGraphicsGetCurrentContext()!
submodules/TelegramUI/Components/Chat/ChatMessageBubbleItemNode/Sources/ChatMessageBubbleItemNode.swift:7335:        let context = UIGraphicsGetCurrentContext()!
submodules/TelegramUI/Components/Chat/ChatMessageFactCheckBubbleContentNode/Sources/ChatMessageFactCheckBubbleContentNode.swift:29:        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!
... output truncated; total lines: 489
exit_status=1
```

## Changed-File SwiftLint Gate

```
swiftlint: Telegram/BroadcastUpload/BroadcastUploadExtension.swift
swiftlint: Telegram/NotificationService/Sources/NotificationService.swift
/Users/fackeuser/Documents/Telegram/Telegram/NotificationService/Sources/NotificationService.swift:620:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/Telegram/NotificationService/Sources/NotificationService.swift:273:42: warning: Void Return Violation: Prefer `-> Void` over `-> ()` (void_return)
/Users/fackeuser/Documents/Telegram/Telegram/NotificationService/Sources/NotificationService.swift:287:49: warning: Void Return Violation: Prefer `-> Void` over `-> ()` (void_return)
swiftlint: Telegram/SiriIntents/IntentContacts.swift
swiftlint: Telegram/SiriIntents/IntentHandler.swift
swiftlint: Telegram/WatchApp/Packages/OpusKit/Sources/OpusKit/OpusDecoder.swift
swiftlint: Telegram/WatchApp/Packages/OpusKit/Sources/OpusKit/OpusEncoder.swift
swiftlint: Telegram/WatchApp/Packages/RLottieKit/Sources/RLottieKit/LottieAnimation.swift
swiftlint: Telegram/WatchApp/Packages/RLottieKit/Sources/RLottieKit/TgsDecompress.swift
swiftlint: Telegram/WatchApp/Packages/TDShim/Sources/TDShim/Transport/TDLibClientManager.swift
swiftlint: Telegram/WidgetKitWidget/PeerNode.swift
swiftlint: submodules/AccountContext/Sources/DeviceContactData.swift
swiftlint: submodules/AnimatedAvatarSetNode/Sources/AnimatedAvatarSetNode.swift
swiftlint: submodules/AnimatedNavigationStripeNode/Sources/AnimatedNavigationStripeNode.swift
swiftlint: submodules/AnimatedStickerNode/Sources/AnimatedStickerFrameSource.swift
swiftlint: submodules/AnimatedStickerNode/Sources/AnimatedStickerNode.swift
swiftlint: submodules/AnimatedStickerNode/Sources/FrameCompression.swift
swiftlint: submodules/AnimatedStickerNode/Sources/VideoStickerFrameSource.swift
swiftlint: submodules/AnimationCompression/Sources/AnimationCompressor.swift
swiftlint: submodules/AnimationCompression/Sources/Buffer.swift
swiftlint: submodules/AnimationCompression/Sources/CompressedImageRenderer.swift
swiftlint: submodules/AudioWaveform/Sources/AudioWaveform.swift
swiftlint: submodules/AuthorizationUI/Sources/AuthorizationApiCredentials.swift
swiftlint: submodules/AuthorizationUI/Sources/AuthorizationSequenceController.swift
swiftlint: submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpControllerNode.swift
swiftlint: submodules/AuthorizationUI/Sources/AuthorizationSequenceSplashController.swift
swiftlint: submodules/AvatarNode/Sources/AvatarNode.swift
/Users/fackeuser/Documents/Telegram/submodules/AvatarNode/Sources/AvatarNode.swift:258:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
/Users/fackeuser/Documents/Telegram/submodules/AvatarNode/Sources/AvatarNode.swift:964:9: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
/Users/fackeuser/Documents/Telegram/submodules/AvatarNode/Sources/AvatarNode.swift:365:13: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
swiftlint: submodules/AvatarNode/Sources/PeerAvatar.swift
/Users/fackeuser/Documents/Telegram/submodules/AvatarNode/Sources/PeerAvatar.swift:127:111: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/AvatarNode/Sources/PeerAvatar.swift:128:133: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/AvatarNode/Sources/PeerAvatar.swift:428:17: warning: Unneeded Break in Switch Violation: Avoid using unneeded break statements (unneeded_break_in_switch)
swiftlint: submodules/BrowserUI/Sources/BrowserMarkdown.swift
/Users/fackeuser/Documents/Telegram/submodules/BrowserUI/Sources/BrowserMarkdown.swift:1464:19: warning: Empty Enum Arguments Violation: Arguments can be omitted when matching enums with associated values if they are not used (empty_enum_arguments)
/Users/fackeuser/Documents/Telegram/submodules/BrowserUI/Sources/BrowserMarkdown.swift:1464:62: warning: Empty Enum Arguments Violation: Arguments can be omitted when matching enums with associated values if they are not used (empty_enum_arguments)
/Users/fackeuser/Documents/Telegram/submodules/BrowserUI/Sources/BrowserMarkdown.swift:2454:23: warning: Empty Enum Arguments Violation: Arguments can be omitted when matching enums with associated values if they are not used (empty_enum_arguments)
swiftlint: submodules/ChatListUI/Sources/ChatListController.swift
swiftlint: submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift:1393:288: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift:1524:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
swiftlint: submodules/ChatListUI/Sources/ChatListShimmerNode.swift
swiftlint: submodules/ChatListUI/Sources/Node/ChatListNode.swift
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/Node/ChatListNode.swift:2655:33: warning: Unneeded Break in Switch Violation: Avoid using unneeded break statements (unneeded_break_in_switch)
swiftlint: submodules/ChatListUI/Sources/Node/ChatListStatusNode.swift
swiftlint: submodules/ChatMessageBackground/Sources/ChatMessageBackground.swift
swiftlint: submodules/ChatTitleActivityNode/Sources/ChatChoosingStickerActivityContentNode.swift
swiftlint: submodules/ChatTitleActivityNode/Sources/ChatPlayingActivityContentNode.swift
swiftlint: submodules/ChatTitleActivityNode/Sources/ChatRecordingVideoActivityContentNode.swift
swiftlint: submodules/ChatTitleActivityNode/Sources/ChatRecordingVoiceActivityContentNode.swift
swiftlint: submodules/ChatTitleActivityNode/Sources/ChatTypingActivityContentNode.swift
swiftlint: submodules/ChatTitleActivityNode/Sources/ChatUploadingActivityContentNode.swift
swiftlint: submodules/CheckNode/Sources/CheckNode.swift
swiftlint: submodules/ComponentFlow/Source/Components/RoundedRectangle.swift
swiftlint: submodules/Components/ReactionButtonListComponent/Sources/ReactionButtonListComponent.swift
swiftlint: submodules/ConfettiEffect/Sources/ConfettiView.swift
swiftlint: submodules/ContactListUI/Sources/ContactListNode.swift
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1597:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1598:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1599:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1600:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1601:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1602:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1603:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1930:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1931:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1932:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1933:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1934:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1935:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1936:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1937:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1938:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ContactListUI/Sources/ContactListNode.swift:1743:33: warning: Unused Control Flow Label Violation: Unused control flow label should be removed (unused_control_flow_label)
swiftlint: submodules/DebugSettingsUI/Sources/DebugController.swift
swiftlint: submodules/DirectMediaImageCache/Sources/DirectMediaImageCache.swift
swiftlint: submodules/DirectionalPanGesture/Sources/DirectionalPanGestureRecognizer.swift
swiftlint: submodules/Display/Source/GenerateImage.swift
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/GenerateImage.swift:639:49: warning: Void Return Violation: Prefer `-> Void` over `-> ()` (void_return)
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/GenerateImage.swift:653:56: warning: Void Return Violation: Prefer `-> Void` over `-> ()` (void_return)
swiftlint: submodules/Display/Source/ImageCorners.swift
swiftlint: submodules/Display/Source/InteractiveTransitionGestureRecognizer.swift
swiftlint: submodules/Display/Source/ListView.swift
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/ListView.swift:3866:51: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/ListView.swift:4376:86: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/ListView.swift:4435:98: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/ListView.swift:43:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/ListView.swift:13:5: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/ListView.swift:96:31: warning: Void Return Violation: Prefer `-> Void` over `-> ()` (void_return)
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/ListView.swift:98:36: warning: Void Return Violation: Prefer `-> Void` over `-> ()` (void_return)
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/ListView.swift:369:47: warning: Void Return Violation: Prefer `-> Void` over `-> ()` (void_return)
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/ListView.swift:609:83: warning: Void Return Violation: Prefer `-> Void` over `-> ()` (void_return)
swiftlint: submodules/Display/Source/NavigationBackButtonNode.swift
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/NavigationBackButtonNode.swift:78:9: warning: Implicit Getter Violation: Computed read-only properties should avoid using the get keyword (implicit_getter)
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/NavigationBackButtonNode.swift:148:13: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/Display/Source/NavigationBackButtonNode.swift:47:24: warning: Void Return Violation: Prefer `-> Void` over `-> ()` (void_return)
swiftlint: submodules/Display/Source/TextNode.swift
swiftlint: submodules/Display/Source/TransformImageNode.swift
swiftlint: submodules/Display/Source/UIKitUtils.swift
swiftlint: submodules/DrawingUI/Sources/ColorPickerScreen.swift
swiftlint: submodules/DrawingUI/Sources/DrawingLinkEntityView.swift
swiftlint: submodules/DrawingUI/Sources/DrawingLocationEntityView.swift
swiftlint: submodules/DrawingUI/Sources/DrawingMetalView.swift
swiftlint: submodules/DrawingUI/Sources/DrawingStickerEntityView.swift
swiftlint: submodules/DrawingUI/Sources/DrawingWeatherEntityView.swift
swiftlint: submodules/GalleryUI/Sources/GalleryPagerNode.swift
swiftlint: submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift
swiftlint: submodules/GradientBackground/Sources/SoftwareGradientBackground.swift
swiftlint: submodules/GraphCore/Sources/Helpers/UIImage+Utils.swift
swiftlint: submodules/ImageTransparency/Sources/ImageTransparency.swift
swiftlint: submodules/InstantPageUI/Sources/InstantPageDetailsNode.swift
/Users/fackeuser/Documents/Telegram/submodules/InstantPageUI/Sources/InstantPageDetailsNode.swift:172:9: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/InstantPageUI/Sources/InstantPageDetailsNode.swift:299:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/InstantPageUI/Sources/InstantPageScrollableNode.swift
/Users/fackeuser/Documents/Telegram/submodules/InstantPageUI/Sources/InstantPageScrollableNode.swift:44:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/InstantPageUI/Sources/InstantPageTileNode.swift
/Users/fackeuser/Documents/Telegram/submodules/InstantPageUI/Sources/InstantPageTileNode.swift:44:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/InvisibleInkDustNode/Sources/InvisibleInkDustNode.swift
/Users/fackeuser/Documents/Telegram/submodules/InvisibleInkDustNode/Sources/InvisibleInkDustNode.swift:3:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
swiftlint: submodules/InviteLinksUI/Sources/InviteLinkViewController.swift
swiftlint: submodules/ItemListPeerItem/Sources/ItemListPeerItem.swift
swiftlint: submodules/ItemListUI/Sources/Items/ItemListEditableItem.swift
swiftlint: submodules/LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift
swiftlint: submodules/ListMessageItem/Sources/ListMessageFileItemNode.swift
/Users/fackeuser/Documents/Telegram/submodules/ListMessageItem/Sources/ListMessageFileItemNode.swift:12:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
swiftlint: submodules/ListMessageItem/Sources/ListMessageHoleItem.swift
swiftlint: submodules/LiveLocationPositionNode/Sources/ChatMessageLiveLocationPositionNode.swift
swiftlint: submodules/LiveLocationTimerNode/Sources/ChatMessageLiveLocationTimerNode.swift
/Users/fackeuser/Documents/Telegram/submodules/LiveLocationTimerNode/Sources/ChatMessageLiveLocationTimerNode.swift:107:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/LiveLocationTimerNode/Sources/LiveLocationWavesNode.swift
/Users/fackeuser/Documents/Telegram/submodules/LiveLocationTimerNode/Sources/LiveLocationWavesNode.swift:120:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/LocationUI/Sources/LocationActionListItem.swift
swiftlint: submodules/LocationUI/Sources/LocationMapNode.swift
/Users/fackeuser/Documents/Telegram/submodules/LocationUI/Sources/LocationMapNode.swift:486:16: warning: Unavailable Condition Violation: Use #unavailable instead of #available with an empty body (unavailable_condition)
swiftlint: submodules/ManagedFile/Sources/ManagedFile.swift
/Users/fackeuser/Documents/Telegram/submodules/ManagedFile/Sources/ManagedFile.swift:139:43: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
swiftlint: submodules/MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift
/Users/fackeuser/Documents/Telegram/submodules/MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift:407:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift:418:13: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift:430:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
swiftlint: submodules/MediaPlayer/Sources/ChunkMediaPlayerV2.swift
swiftlint: submodules/MediaPlayer/Sources/FFMpegAudioFrameDecoder.swift
swiftlint: submodules/MediaPlayer/Sources/FFMpegFileReader.swift
swiftlint: submodules/MediaPlayer/Sources/FFMpegMediaFrameSourceContext.swift
swiftlint: submodules/MediaPlayer/Sources/FFMpegMediaPassthroughVideoFrameDecoder.swift
swiftlint: submodules/MediaPlayer/Sources/FFMpegMediaVideoFrameDecoder.swift
swiftlint: submodules/MediaPlayer/Sources/MediaPlayerAudioRenderer.swift
swiftlint: submodules/MediaPlayer/Sources/MediaPlayerFramePreview.swift
swiftlint: submodules/MediaPlayer/Sources/MediaPlayerNode.swift
swiftlint: submodules/MediaPlayer/Sources/MediaPlayerTimeTextNode.swift
/Users/fackeuser/Documents/Telegram/submodules/MediaPlayer/Sources/MediaPlayerTimeTextNode.swift:250:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/MediaPlayer/Sources/RingByteBuffer.swift
swiftlint: submodules/MediaPlayer/Sources/SoftwareVideoSource.swift
swiftlint: submodules/MediaPlayer/Sources/UniversalSoftwareVideoSource.swift
swiftlint: submodules/OpenInExternalAppUI/Sources/OpenInAppIconResources.swift
/Users/fackeuser/Documents/Telegram/submodules/OpenInExternalAppUI/Sources/OpenInAppIconResources.swift:15:12: warning: Legacy Hashing Violation: Prefer using the `hash(into:)` function instead of overriding `hashValue` (legacy_hashing)
swiftlint: submodules/PasscodeInputFieldNode/Sources/PasscodeInputFieldNode.swift
swiftlint: submodules/PasscodeUI/Sources/PasscodeBackground.swift
swiftlint: submodules/PasscodeUI/Sources/PasscodeEntryKeyboardNode.swift
/Users/fackeuser/Documents/Telegram/submodules/PasscodeUI/Sources/PasscodeEntryKeyboardNode.swift:65:9: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/PasscodeUI/Sources/PasscodeEntryKeyboardNode.swift:291:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/PasscodeUI/Sources/PasscodeEntryKeyboardNode.swift:294:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/PasscodeUI/Sources/PasscodeEntryKeyboardNode.swift:342:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/PasscodeUI/Sources/PasscodeEntryKeyboardNode.swift:349:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/PasscodeUI/Sources/PasscodeEntryKeyboardNode.swift:352:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/PasscodeUI/Sources/PasscodeEntryKeyboardNode.swift:355:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
swiftlint: submodules/PasscodeUI/Sources/PasscodeInputFieldNode.swift
swiftlint: submodules/PasscodeUI/Sources/PasscodeLockIconNode.swift
/Users/fackeuser/Documents/Telegram/submodules/PasscodeUI/Sources/PasscodeLockIconNode.swift:96:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/PassportUI/Sources/Form/FormControllerScrollerNode.swift
swiftlint: submodules/PassportUI/Sources/SecureIdLocalResource.swift
/Users/fackeuser/Documents/Telegram/submodules/PassportUI/Sources/SecureIdLocalResource.swift:15:12: warning: Legacy Hashing Violation: Prefer using the `hash(into:)` function instead of overriding `hashValue` (legacy_hashing)
swiftlint: submodules/PasswordSetupUI/Sources/TwoFactorAuthDataInputScreen.swift
/Users/fackeuser/Documents/Telegram/submodules/PasswordSetupUI/Sources/TwoFactorAuthDataInputScreen.swift:1006:9: warning: Unused Setter Value Violation: Setter value is not used (unused_setter_value)
swiftlint: submodules/PeerInfoAvatarListNode/Sources/PeerInfoAvatarListNode.swift
/Users/fackeuser/Documents/Telegram/submodules/PeerInfoAvatarListNode/Sources/PeerInfoAvatarListNode.swift:238:9: warning: Implicit Getter Violation: Computed read-only properties should avoid using the get keyword (implicit_getter)
/Users/fackeuser/Documents/Telegram/submodules/PeerInfoAvatarListNode/Sources/PeerInfoAvatarListNode.swift:90:12: warning: Legacy Hashing Violation: Prefer using the `hash(into:)` function instead of overriding `hashValue` (legacy_hashing)
swiftlint: submodules/PhotoResources/Sources/PhotoResources.swift
/Users/fackeuser/Documents/Telegram/submodules/PhotoResources/Sources/PhotoResources.swift:1761:270: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/PhotoResources/Sources/PhotoResources.swift:2441:13: warning: No Fallthrough only Violation: Fallthroughs can only be used if the `case` contains at least one other statement (no_fallthrough_only)
/Users/fackeuser/Documents/Telegram/submodules/PhotoResources/Sources/PhotoResources.swift:2443:13: warning: No Fallthrough only Violation: Fallthroughs can only be used if the `case` contains at least one other statement (no_fallthrough_only)
/Users/fackeuser/Documents/Telegram/submodules/PhotoResources/Sources/PhotoResources.swift:2392:23: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/PhotoResources/Sources/PhotoResources.swift:2394:25: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/PhotoResources/Sources/PhotoResources.swift:2396:25: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/PhotoResources/Sources/PhotoResources.swift:2398:26: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/PhotoResources/Sources/PhotoResources.swift:2400:31: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/PhotoResources/Sources/PhotoResources.swift:2402:33: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/PhotoResources/Sources/PhotoResources.swift:2404:33: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/PhotoResources/Sources/PhotoResources.swift:2406:34: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
swiftlint: submodules/PremiumUI/Sources/DataRainView.swift
/Users/fackeuser/Documents/Telegram/submodules/PremiumUI/Sources/DataRainView.swift:157:15: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/PremiumUI/Sources/DataRainView.swift:158:15: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/PremiumUI/Sources/DataRainView.swift:159:15: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/PremiumUI/Sources/DataRainView.swift:160:15: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/PremiumUI/Sources/DataRainView.swift:161:15: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/PremiumUI/Sources/DataRainView.swift:162:15: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
swiftlint: submodules/PremiumUI/Sources/PremiumLimitScreen.swift
/Users/fackeuser/Documents/Telegram/submodules/PremiumUI/Sources/PremiumLimitScreen.swift:1323:25: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
swiftlint: submodules/QrCode/Sources/QrCode.swift
/Users/fackeuser/Documents/Telegram/submodules/QrCode/Sources/QrCode.swift:287:21: warning: Unneeded Break in Switch Violation: Avoid using unneeded break statements (unneeded_break_in_switch)
swiftlint: submodules/QrCodeUI/Sources/GlassButtonNode.swift
swiftlint: submodules/RadialStatusNode/Sources/RadialCheckContentNode.swift
/Users/fackeuser/Documents/Telegram/submodules/RadialStatusNode/Sources/RadialCheckContentNode.swift:96:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/RadialStatusNode/Sources/RadialCloudProgressContentNode.swift
/Users/fackeuser/Documents/Telegram/submodules/RadialStatusNode/Sources/RadialCloudProgressContentNode.swift:117:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
/Users/fackeuser/Documents/Telegram/submodules/RadialStatusNode/Sources/RadialCloudProgressContentNode.swift:208:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/RadialStatusNode/Sources/RadialProgressContentNode.swift
/Users/fackeuser/Documents/Telegram/submodules/RadialStatusNode/Sources/RadialProgressContentNode.swift:121:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
/Users/fackeuser/Documents/Telegram/submodules/RadialStatusNode/Sources/RadialProgressContentNode.swift:228:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/RadialStatusNode/Sources/RadialStatusIconContentNode.swift
/Users/fackeuser/Documents/Telegram/submodules/RadialStatusNode/Sources/RadialStatusIconContentNode.swift:61:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/RadialStatusNode/Sources/RadialStatusSecretTimeoutContentNode.swift
/Users/fackeuser/Documents/Telegram/submodules/RadialStatusNode/Sources/RadialStatusSecretTimeoutContentNode.swift:220:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
/Users/fackeuser/Documents/Telegram/submodules/RadialStatusNode/Sources/RadialStatusSecretTimeoutContentNode.swift:16:5: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
swiftlint: submodules/ReactionSelectionNode/Sources/ReactionContextNode.swift
/Users/fackeuser/Documents/Telegram/submodules/ReactionSelectionNode/Sources/ReactionContextNode.swift:254:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/ReactionSelectionNode/Sources/ReactionContextNode.swift:305:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
swiftlint: submodules/SemanticStatusNode/Sources/SemanticStatusNode.swift
/Users/fackeuser/Documents/Telegram/submodules/SemanticStatusNode/Sources/SemanticStatusNode.swift:520:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/SemanticStatusNode/Sources/SemanticStatusNodeIconContext.swift
swiftlint: submodules/SemanticStatusNode/Sources/SemanticStatusNodeSecretTimeoutContext.swift
/Users/fackeuser/Documents/Telegram/submodules/SemanticStatusNode/Sources/SemanticStatusNodeSecretTimeoutContext.swift:209:5: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
swiftlint: submodules/SettingsUI/Sources/BubbleSettings/BubbleSettingsController.swift
swiftlint: submodules/SettingsUI/Sources/Text Size/TextSizeSelectionController.swift
swiftlint: submodules/SettingsUI/Sources/Themes/ThemePreviewControllerNode.swift
swiftlint: submodules/SettingsUI/Sources/Themes/ThemeSettingsAccentColorItem.swift
swiftlint: submodules/SettingsUI/Sources/Themes/ThemeSettingsAppIconItem.swift
swiftlint: submodules/ShimmerEffect/Sources/ShimmerEffect.swift
/Users/fackeuser/Documents/Telegram/submodules/ShimmerEffect/Sources/ShimmerEffect.swift:574:35: warning: Compiler Protocol Init Violation: Initializers declared in compiler protocol ExpressibleByFloatLiteral shouldn't be called directly (compiler_protocol_init)
/Users/fackeuser/Documents/Telegram/submodules/ShimmerEffect/Sources/ShimmerEffect.swift:575:33: warning: Compiler Protocol Init Violation: Initializers declared in compiler protocol ExpressibleByFloatLiteral shouldn't be called directly (compiler_protocol_init)
swiftlint: submodules/SparseItemGrid/Sources/SparseDiscreteScrollingArea.swift
swiftlint: submodules/SparseItemGrid/Sources/SparseItemGrid.swift
swiftlint: submodules/SparseItemGrid/Sources/SparseItemGridScrollingArea.swift
/Users/fackeuser/Documents/Telegram/submodules/SparseItemGrid/Sources/SparseItemGridScrollingArea.swift:864:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
swiftlint: submodules/StickerResources/Sources/StickerResources.swift
swiftlint: submodules/TabBarUI/Sources/TabBarNode.swift
swiftlint: submodules/TelegramAnimatedStickerNode/Sources/AnimatedStickerUtils.swift
/Users/fackeuser/Documents/Telegram/submodules/TelegramAnimatedStickerNode/Sources/AnimatedStickerUtils.swift:12:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
swiftlint: submodules/TelegramApi/Sources/Buffer.swift
swiftlint: submodules/TelegramBaseController/Sources/MediaNavigationAccessoryHeaderNode.swift
swiftlint: submodules/TelegramCallsUI/Sources/CallControllerButton.swift
swiftlint: submodules/TelegramCallsUI/Sources/CallControllerStatusNode.swift
/Users/fackeuser/Documents/Telegram/submodules/TelegramCallsUI/Sources/CallControllerStatusNode.swift:255:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/TelegramCallsUI/Sources/CallControllerToastNode.swift
/Users/fackeuser/Documents/Telegram/submodules/TelegramCallsUI/Sources/CallControllerToastNode.swift:205:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
swiftlint: submodules/TelegramCallsUI/Sources/LegacyCallControllerButton.swift
swiftlint: submodules/TelegramCallsUI/Sources/LegacyCallControllerStatusNode.swift
/Users/fackeuser/Documents/Telegram/submodules/TelegramCallsUI/Sources/LegacyCallControllerStatusNode.swift:196:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
swiftlint: submodules/TelegramCallsUI/Sources/PresentationCall.swift
/Users/fackeuser/Documents/Telegram/submodules/TelegramCallsUI/Sources/PresentationCall.swift:798:25: warning: Empty Enum Arguments Violation: Arguments can be omitted when matching enums with associated values if they are not used (empty_enum_arguments)
swiftlint: submodules/TelegramCallsUI/Sources/VideoChatEncryptionKeyComponent.swift
swiftlint: submodules/TelegramCallsUI/Sources/VideoChatScreenMoreMenu.swift
swiftlint: submodules/TelegramCallsUI/Sources/VideoChatVideoLoadingEffectView.swift
/Users/fackeuser/Documents/Telegram/submodules/TelegramCallsUI/Sources/VideoChatVideoLoadingEffectView.swift:49:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/TelegramCallsUI/Sources/VideoChatVideoLoadingEffectView.swift:154:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
swiftlint: submodules/TelegramCallsUI/Sources/VoiceChatAccountHeaderActionSheetItem.swift
swiftlint: submodules/TelegramCallsUI/Sources/VoiceChatController.swift
... output truncated; total lines: 368
exit_status=0
```

## Configured SwiftLint Module Pass

```
/Users/fackeuser/Documents/Telegram/submodules/AuthorizationUI/Sources/AuthorizationSequenceEmailEntryController.swift:141:12: warning: Unavailable Condition Violation: Use #unavailable instead of #available with an empty body (unavailable_condition)
/Users/fackeuser/Documents/Telegram/submodules/AuthorizationUI/Sources/AuthorizationSequenceCodeEntryControllerNode.swift:417:12: warning: Unavailable Condition Violation: Use #unavailable instead of #available with an empty body (unavailable_condition)
/Users/fackeuser/Documents/Telegram/submodules/AuthorizationUI/Sources/AuthorizationSequencePasswordRecoveryControllerNode.swift:139:1: warning: Trailing Newline Violation: Files should have a single trailing newline (trailing_newline)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListSearchMediaNode.swift:991:24: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListSearchMediaNode.swift:1033:44: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListSearchMediaNode.swift:928:43: warning: Void Return Violation: Prefer `-> Void` over `-> ()` (void_return)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListSearchMediaNode.swift:930:48: warning: Void Return Violation: Prefer `-> Void` over `-> ()` (void_return)
/Users/fackeuser/Documents/Telegram/submodules/AuthorizationUI/Sources/AuthorizationSequencePasswordRecoveryController.swift:108:1: warning: Trailing Newline Violation: Files should have a single trailing newline (trailing_newline)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListContainerItemNode.swift:157:74: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/AuthorizationUI/Sources/AuthorizationSequenceAwaitingAccountResetControllerNode.swift:176:1: warning: Trailing Newline Violation: Files should have a single trailing newline (trailing_newline)
/Users/fackeuser/Documents/Telegram/submodules/AuthorizationUI/Sources/AuthorizationSequencePhoneEntryControllerNode.swift:349:9: warning: Implicit Getter Violation: Computed read-only properties should avoid using the get keyword (implicit_getter)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListFilterPresetListController.swift:323:202: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListSearchMessageSelectionPanelNode.swift:5:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListSearchMessageSelectionPanelNode.swift:151:60: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListSearchMessageSelectionPanelNode.swift:152:69: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift:1393:288: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift:1524:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatContextMenus.swift:845:29: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatContextMenus.swift:845:37: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatContextMenus.swift:850:29: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatContextMenus.swift:850:37: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatContextMenus.swift:855:29: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatContextMenus.swift:855:37: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/Node/ChatListItem.swift:1868:96: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/Node/ChatListItem.swift:1868:144: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/Node/ChatListItem.swift:2991:115: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/Node/ChatListItem.swift:3006:103: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/Node/ChatListItem.swift:3009:103: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/Node/ChatListItem.swift:3012:103: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/Node/ChatListItem.swift:1306:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListFilterPresetController.swift:1136:46: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/ChatListFilterPresetController.swift:1096:10: warning: Generic Type Name Violation: Generic type name 'ItemGenerationArguments' should be between 1 and 20 characters long (generic_type_name)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/Node/ChatListNodeEntries.swift:595:5: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/Node/ChatListEmptyInfoItem.swift:276:1: warning: Trailing Newline Violation: Files should have a single trailing newline (trailing_newline)
/Users/fackeuser/Documents/Telegram/submodules/ChatListUI/Sources/Node/ChatListNode.swift:2655:33: warning: Unneeded Break in Switch Violation: Avoid using unneeded break statements (unneeded_break_in_switch)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUIPreferences/Sources/MediaAutoDownloadSettings.swift:197:22: warning: Redundant String Enum Value Violation: String enum values can be omitted when they are equal to the enumcase name (redundant_string_enum_value)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUIPreferences/Sources/MediaAutoDownloadSettings.swift:198:23: warning: Redundant String Enum Value Violation: String enum values can be omitted when they are equal to the enumcase name (redundant_string_enum_value)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUIPreferences/Sources/MediaAutoDownloadSettings.swift:199:25: warning: Redundant String Enum Value Violation: String enum values can be omitted when they are equal to the enumcase name (redundant_string_enum_value)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift:6:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift:758:33: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift:2006:62: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatTagSearchInputPanelNode.swift:37:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatTagSearchInputPanelNode.swift:57:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ContactSelectionController.swift:442:192: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/HorizontalStickerGridItem.swift:13:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ApplicationContext.swift:452:45: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerForwardMessages.swift:7:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatSearchTitleAccessoryPanelNode.swift:36:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatInterfaceTitlePanelNodes.swift:106:13: warning: Unneeded Break in Switch Violation: Avoid using unneeded break statements (unneeded_break_in_switch)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OpenResolvedUrl.swift:785:87: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OpenResolvedUrl.swift:1454:91: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OpenResolvedUrl.swift:96:13: warning: Unneeded Break in Switch Violation: Avoid using unneeded break statements (unneeded_break_in_switch)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ListMessagePlaybackOverlayNode.swift:87:66: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OverlayInstantVideoDecoration.swift:121:1: warning: Trailing Newline Violation: Files should have a single trailing newline (trailing_newline)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatMessageTransitionNode.swift:8:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerDisplayBusinessBotMessageTooltip.swift:7:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/TextLinkHandling.swift:8:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/CreateGroupController.swift:1281:15: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/CreateGroupController.swift:15:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift:606:71: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift:616:89: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift:631:85: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift:641:77: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift:1642:59: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift:1652:81: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift:1667:77: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift:1677:69: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift:196:39: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/CommandMenuChatInputContextPanelNode.swift:149:82: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerAdminBanUsers.swift:8:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerAdminBanUsers.swift:19:1: warning: Private over Fileprivate Violation: Prefer `private` over `fileprivate` declarations (private_over_fileprivate)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/SharedMediaPlayer.swift:235:192: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:6040:49: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:6040:57: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:6045:49: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:6045:57: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:6050:49: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:6050:57: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:125:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:133:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:3725:64: warning: First Where Violation: Prefer using `.first(where:)` over `.filter { }.first` in collections (first_where)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:549:9: warning: Implicit Getter Violation: Computed read-only properties should avoid using the get keyword (implicit_getter)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:6952:9: warning: Implicit Getter Violation: Computed read-only properties should avoid using the get keyword (implicit_getter)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:3668:35: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatController.swift:7970:12: warning: Unavailable Condition Violation: Use #unavailable instead of #available with an empty body (unavailable_condition)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerNode.swift:581:25: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatPremiumRequiredInputPanelNode.swift:35:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatPremiumRequiredInputPanelNode.swift:55:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatSearchResultsContollerNode.swift:466:1: warning: Trailing Newline Violation: Files should have a single trailing newline (trailing_newline)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/DeviceContactDataManager.swift:10:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ContactMultiselectionControllerNode.swift:552:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/EmojisChatInputContextPanelNode.swift:462:77: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/EmojisChatInputContextPanelNode.swift:609:1: warning: Trailing Newline Violation: Files should have a single trailing newline (trailing_newline)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OverlayAudioPlayerControllerNode.swift:257:37: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerEditChat.swift:7:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/SharedAccountContext.swift:2578:38: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/SharedAccountContext.swift:97:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerRemoveAd.swift:7:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/CreateChannelController.swift:13:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatHistoryNavigationButtons.swift:2:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatHistoryNavigationButtons.swift:13:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatHistoryNavigationButtons.swift:22:9: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ContactMultiselectionController.swift:245:13: warning: Unneeded Break in Switch Violation: Avoid using unneeded break statements (unneeded_break_in_switch)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ContactMultiselectionController.swift:418:21: warning: Unneeded Break in Switch Violation: Avoid using unneeded break statements (unneeded_break_in_switch)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/EditAccessoryPanelNode.swift:309:319: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatHistoryListNode.swift:4932:56: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatHistoryListNode.swift:4949:52: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatHistoryListNode.swift:16:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatHistoryListNode.swift:34:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatHistoryListNode.swift:187:40: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/HashtagChatInputContextPanelNode.swift:218:78: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/HashtagChatInputContextPanelNode.swift:10:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/CommandChatInputContextPanelNode.swift:271:198: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/CommandChatInputContextPanelNode.swift:362:78: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/PreparedChatHistoryViewTransition.swift:164:132: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/PreparedChatHistoryViewTransition.swift:177:140: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/PreparedChatHistoryViewTransition.swift:200:136: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/MediaManager.swift:312:71: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/MediaManager.swift:313:69: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/RadialProgressNode.swift:123:42: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/RadialProgressNode.swift:124:47: warning: Trailing Semicolon Violation: Lines should not have trailing semicolons (trailing_semicolon)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OpenChatMessage.swift:530:54: warning: First Where Violation: Prefer using `.first(where:)` over `.filter { }.first` in collections (first_where)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OverlayMediaControllerNode.swift:187:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OverlayMediaControllerNode.swift:191:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OverlayMediaControllerNode.swift:195:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OverlayMediaControllerNode.swift:203:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OverlayMediaControllerNode.swift:207:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OverlayMediaControllerNode.swift:211:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OverlayMediaControllerNode.swift:219:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OverlayMediaControllerNode.swift:223:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/OverlayMediaControllerNode.swift:227:17: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatControllerContentData.swift:17:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerNavigateToMessage.swift:146:201: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Weak.swift:2:1: warning: Trailing Newline Violation: Files should have a single trailing newline (trailing_newline)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerOpenPollOptionMedia.swift:63:25: warning: Unneeded Break in Switch Violation: Avoid using unneeded break statements (unneeded_break_in_switch)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerOpenMessageContextMenu.swift:18:1: warning: Duplicate Imports Violation: Imports should be unique (duplicate_imports)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift:925:25: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift:925:46: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift:925:49: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift:925:52: warning: Closure Parameter Position Violation: Closure parameters should be on the same line as opening brace (closure_parameter_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift:4326:143: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift:1856:52: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift:2045:44: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift:4229:21: warning: Statement Position Violation: Else and catch should be on the same line, one space after the previous declaration (statement_position)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/RadialTimeoutNode.swift:83:5: warning: Static Over Final Class Violation: Prefer `static` over `class` in a final class (static_over_final_class)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatHistoryViewForLocation.swift:203:69: warning: Is Disjoint Violation: Prefer using `Set.isDisjoint(with:)` over `Set.intersection(_:).isEmpty` (is_disjoint)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatHistoryViewForLocation.swift:202:41: warning: Unused Control Flow Label Violation: Unused control flow label should be removed (unused_control_flow_label)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/ChatHistoryViewForLocation.swift:342:5: warning: Unused Control Flow Label Violation: Unused control flow label should be removed (unused_control_flow_label)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerNavigationButtonAction.swift:654:107: warning: Comma Spacing Violation: There should be no space before and one after any comma (comma)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerOpenPollContextMenu.swift:75:97: warning: Closing Brace Spacing Violation: Closing brace with closing parenthesis should not have any whitespaces in the middle (closing_brace)
/Users/fackeuser/Documents/Telegram/submodules/TelegramUI/Sources/Chat/ChatControllerOpenPollContextMenu.swift:305:5: warning: Unneeded Synthesized Initializer Violation: This memberwise initializer would be synthesized automatically - you do not need to define it (unneeded_synthesized_initializer)
exit_status=0
```

## Whitespace Check

```
exit_status=0
```

