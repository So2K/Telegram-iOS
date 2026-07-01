# Runtime Repro Map

Last reviewed: 2026-07-02

This file maps public bug reports to local source targets. Do not patch these areas from titles alone; use this map to capture a repro, stack trace, and regression scenario once the required Xcode toolchain is available.

## Appearance / Theme Crash

Issue: [#2196 App crushes in theme appearance section](https://github.com/TelegramMessenger/Telegram-iOS/issues/2196)

Reported flow:

1. Settings
2. Appearance
3. Change or edit theme

Primary code targets:

- `submodules/SettingsUI/Sources/ThemePickerController.swift`
- `submodules/SettingsUI/Sources/ThemePickerGridItem.swift`
- `submodules/SettingsUI/Sources/Themes/EditThemeController.swift`
- `submodules/SettingsUI/Sources/Themes/ThemePreviewController.swift`
- `submodules/SettingsUI/Sources/Themes/ThemePreviewControllerNode.swift`
- `submodules/SettingsUI/Sources/Themes/ThemeSettingsController.swift`
- `submodules/TelegramPresentationData/Sources/MakePresentationTheme.swift`
- `submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift`
- `submodules/WallpaperResources/Sources/WallpaperResources.swift`

Runtime evidence needed:

- Crash log with exception type and top 30 frames.
- Whether it happens on default themes, imported themes, edited themes, or app icon changes.
- Main-thread checker result while opening Appearance and while tapping Edit.
- Custom gradient/pattern wallpaper previews, imported theme wallpaper previews, and theme icon/bubble previews.

Local mitigation:

- `submodules/TelegramUIPreferences/Sources/PresentationThemeSettings.swift` no longer force unwraps builtin theme raw values or local theme resources during settings decode.
- Corrupt theme-specific wallpaper/accent dictionaries now fall back to empty dictionaries.
- `submodules/WallpaperResources/Sources/WallpaperResources.swift` now guards generated wallpaper preview images, pattern masks, pattern overlays, theme-image gradients, and theme icon/bubble preview gradients.

## Saved Messages Freeze

Issue: [#2059 The app freezes when I open Saved Messages](https://github.com/TelegramMessenger/Telegram-iOS/issues/2059)

Reported flow:

1. Send a voice message to Saved Messages.
2. Open Saved Messages from chat list or forward popup.
3. App stops responding.

Primary code targets:

- `submodules/TelegramUI/Components/SavedMessages/SavedMessagesScreen/Sources/SavedMessagesScreen.swift`
- `submodules/TelegramCore/Sources/TelegramEngine/Messages/ChatList.swift`
- `submodules/TelegramCore/Sources/State/ChatHistoryPreloadManager.swift`
- `submodules/Postbox/Sources/ChatListView.swift`
- `submodules/Postbox/Sources/PeerChatInterfaceStateTable.swift`
- `submodules/ListMessageItem/Sources/ListMessageFileItemNode.swift`
- `submodules/TelegramUI/Components/MediaScrubberComponent/Sources/MediaScrubberComponent.swift`

Runtime evidence needed:

- Time Profiler sample while frozen.
- Whether CPU is busy or main thread is blocked on a lock/database/media decode.
- Voice-message metadata and waveform presence for the message that triggers the freeze.

Local mitigation:

- `submodules/AudioWaveform/Sources/AudioWaveform.swift` now treats malformed or oversized waveform data as empty/clamped data instead of forcing raw pointer reads, negative-length copies, or zero-peak division.
- `submodules/TelegramUI/Sources/ManagedAudioRecorder.swift` now guards audio input/tone buffer allocations, `Data` base addresses, nil `AudioBuffer` source data, waveform compression buffers, and empty compressed waveform finalization.

## Chat Opening / Scrolling Freeze

Issues:

- [#1739 Telegram iOS App Crashes When Opening Chats](https://github.com/TelegramMessenger/Telegram-iOS/issues/1739)
- [#1668 iOS 18.2 Telegram app freezing randomly, dubbed "Scrolling Bug"](https://github.com/TelegramMessenger/Telegram-iOS/issues/1668)
- [#447 Severe performance issue on iPad, suspecting a memory leak](https://github.com/TelegramMessenger/Telegram-iOS/issues/447)

Reported flows:

1. Open any chat after sticker/GIF activity; in #1739 the report says chats crash immediately after previous sticker usage.
2. Scroll a message thread while another message arrives; #1668 reports UI/scroll gestures becoming stuck until force quit.
3. On iPad, repeatedly switch active chats and open GIF panel; #447 reports memory growth and eventual severe slowdown.

Primary code targets:

- `submodules/TelegramUI/Sources/ChatController.swift`
- `submodules/TelegramUI/Sources/ChatHistoryListNode.swift`
- `submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift`
- `submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift`
- `submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift`
- `submodules/TelegramUI/Sources/SharedAccountContext.swift`
- `submodules/ChatListUI/Sources/Node/ChatListNode.swift`
- `submodules/Postbox/Sources/MessageHistoryView.swift`
- `submodules/ListMessageItem/Sources/ListMessageItem.swift`
- `submodules/ChatMessageItemImpl/Sources`
- `submodules/AnimatedStickerNode/Sources`

Runtime evidence needed:

- Crash log when opening the affected chat, especially after sticker/GIF messages are present.
- Time Profiler sample while the scroll freeze is active.
- Allocations/leaks profile while switching chats and repeatedly opening/closing the GIF panel on iPad.
- Whether the stuck state is a main-thread stall, list transaction loop, media decode, or database lock.
- Contact attachment sending with Telegram peers, device contacts, device contacts without phone numbers, and filtered vCard contacts.
- Chat-message preview callers with empty and non-empty message arrays.
- One-recipient call start from selection UI.

Local mitigation:

- `submodules/TelegramUI/Sources/ChatController.swift` now avoids unsafe one-byte `Data` pointer reads in bot/gift/copy-protection/suggested-post callback payload handling.
- `submodules/TelegramUI/Sources/ChatController.swift` now ignores empty scheduled-message action batches instead of force-unwrapping `messageIds.first`.
- `submodules/TelegramUI/Sources/ChatHistoryListNode.swift` now tolerates empty grouped-message transition entries by showing the existing list hole item rather than indexing `messages[0]`.
- `submodules/ChatListUI/Sources/Node/ChatListNode.swift` now fails its gesture recognizer cleanly on an empty touch set.
- `submodules/DirectionalPanGesture/Sources/DirectionalPanGestureRecognizer.swift` and peer-info media/story pane selection recognizers now apply the same empty-touch-set failure path.
- `submodules/TelegramUI/Sources/ChatInterfaceStateContextMenus.swift` now handles empty action-option maps without force-unwrapping the first value.
- `submodules/TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift` now uses safe first-phone extraction for peer/device contacts and filtered contact completions.
- `submodules/TelegramUI/Sources/SharedAccountContext.swift` now falls back to the existing lightweight list hole item for empty chat-message preview input.
- `submodules/ListMessageItem/Sources/ListMessageHoleItem.swift` is public so `TelegramUI` can use the existing hole item as a cross-module fallback.
- `submodules/TelegramUI/Sources/SharedAccountContext.swift` treats empty bot-preview editor completion as cancellation.
- `submodules/TelegramUI/Sources/SharedAccountContext.swift` uses a safe first peer id for one-recipient call start from selection UI.

Static evidence:

- `scripts/custom-client/run_crash_risk_scan.sh` passes after the chat/history pass.
- `scripts/custom-client/run_static_analysis.sh` passes with warning-only SwiftLint findings.

## GIF / Animated Sticker Crash

Issue: [#2019 The app crashes when you select a gif](https://github.com/TelegramMessenger/Telegram-iOS/issues/2019)

Reported flow:

1. Open a chat.
2. Tap sticker/GIF entry point.
3. Select an animated sticker or GIF.

Primary code targets:

- `submodules/FeaturedStickersScreen/Sources/ChatMediaInputPane.swift`
- `submodules/FeaturedStickersScreen/Sources/ChatMediaInputTrendingPane.swift`
- `submodules/TelegramAnimatedStickerNode/Sources/TelegramAnimatedStickerNode.swift`
- `submodules/TelegramAnimatedStickerNode/Sources/AnimatedStickerUtils.swift`
- `submodules/AnimatedStickerNode/Sources/AnimatedStickerNode.swift`
- `submodules/AnimatedStickerNode/Sources/DirectAnimatedStickerNode.swift`
- `submodules/AnimatedStickerNode/Sources/VideoStickerFrameSource.swift`

Runtime evidence needed:

- Crash log and offending media/sticker id.
- Whether crash occurs before preview, during decode, or after send.
- Allocations profile for repeated GIF/sticker panel open/close.

Local mitigation:

- `submodules/AnimatedStickerNode/Sources/AnimatedStickerFrameSource.swift` now validates cached animation headers and compressed frame lengths before unsafe reads/allocation.
- `submodules/AnimatedStickerNode/Sources/AnimatedStickerNode.swift` now prevents zero/invalid frame-rate timer setup and invalid timestamp seek math.
- `submodules/AnimatedStickerNode/Sources/VideoStickerFrameSource.swift` now avoids forced unwraps for WebP `cgImage` and sample-buffer pixel buffers and clamps video-sticker seek indexes.
- `submodules/AnimatedStickerNode/Sources/FrameCompression.swift` now treats invalid frame dimensions, allocation failure, and compression failure as a missing compressed frame.
- `submodules/AnimationCompression/Sources/AnimationCompressor.swift`, `Buffer.swift`, and `CompressedImageRenderer.swift` now validate frame sizes, buffer lengths, `Data` base addresses, Metal readback data, and DCT/Huffman payloads before copy/render paths.
- `submodules/TelegramAnimatedStickerNode/Sources/AnimatedStickerUtils.swift` now rejects invalid render sizes, allocation failures, missing generated `CGImage`s, failed AJPEG image backing, and missing video sticker pixel buffers while generating cached sticker frames.

## Telegram API Buffer / Payload Serialization

Source: local full-repo static audit of TL/API byte buffer boundaries.

Primary code target:

- `submodules/TelegramApi/Sources/Buffer.swift`

Runtime evidence needed:

- Login/authorization with fresh API credentials and with an existing account.
- Contact sync/import and opening peers from imported contacts.
- Notification tap/open handling for message, story, call, and read-history payloads.
- Sending text, media, GIFs/stickers, voice messages, and grouped media.
- Large chat history load, Saved Messages open, and multi-account switching.
- Malformed local payload harness if available: zero-length strings/bytes, empty copied buffers, short int/double reads, and failed allocation simulation.

Local mitigation:

- String/bytes serialization now copies only when non-empty source buffers have backing storage.
- `Buffer.init(data:)`, `appendBytes`, `appendBuffer`, `readBuffer`, and `withReadBufferNoCopy` now handle zero-length data without dereferencing nil memory.
- Integer/double reads and debug descriptions now require valid backing storage before reading raw memory.
- Raw allocation/reallocation failures now return without force-unwrapping invalid destination pointers.

## Avatar / Chat List / Browser Markdown Graphics

Source: local full-repo static audit of CoreGraphics context/gradient/image boundaries and static regex initialization.

Primary code targets:

- `submodules/AuthorizationUI/Sources/AuthorizationSequenceSignUpControllerNode.swift`
- `submodules/AvatarNode/Sources/AvatarNode.swift`
- `submodules/AvatarNode/Sources/PeerAvatar.swift`
- `submodules/ChatListUI/Sources/ChatListShimmerNode.swift`
- `submodules/ChatListUI/Sources/ChatListSearchListPaneNode.swift`
- `submodules/ChatListUI/Sources/Node/ChatListStatusNode.swift`
- `submodules/Display/Source/GenerateImage.swift`
- `submodules/Display/Source/ImageCorners.swift`
- `submodules/Display/Source/TextNode.swift`
- `submodules/Display/Source/TransformImageNode.swift`
- `submodules/Display/Source/UIKitUtils.swift`
- `submodules/Display/Source/InteractiveTransitionGestureRecognizer.swift`
- `submodules/Display/Source/ListView.swift`
- `submodules/Display/Source/NavigationBackButtonNode.swift`
- `submodules/ChatTitleActivityNode/Sources`
- `submodules/CheckNode/Sources/CheckNode.swift`
- `submodules/ComponentFlow/Source/Components/RoundedRectangle.swift`
- `submodules/ConfettiEffect/Sources/ConfettiView.swift`
- `submodules/TelegramPresentationData/Sources/ChatControllerBackgroundNode.swift`
- `submodules/TelegramPresentationData/Sources/ChatMessageBubbleImages.swift`
- `submodules/TelegramPresentationData/Sources/PresentationThemeEssentialGraphics.swift`
- `submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesChat.swift`
- `submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesChatList.swift`
- `submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesItemList.swift`
- `submodules/TelegramPresentationData/Sources/Resources/PresentationResourcesSettings.swift`
- `submodules/TelegramIntents/Sources/TelegramIntents.swift`
- `submodules/WallpaperResources/Sources/WallpaperResources.swift`
- `submodules/ChatMessageBackground/Sources/ChatMessageBackground.swift`
- `submodules/GradientBackground/Sources/SoftwareGradientBackground.swift`
- `submodules/BrowserUI/Sources/BrowserMarkdown.swift`

Runtime evidence needed:

- Register with a profile photo and verify sign-up avatar clipping.
- Edit profile/group avatars and open peers with missing, corrupt, or CoreImage-backed avatar resources.
- Scroll/search chat list while shimmer placeholders and status check/failed nodes render.
- Render typing/recording/uploading/playing title activity indicators, check nodes, rounded-rectangle gradients, confetti sprites, text attachments/quote icons, and transformed/tinted images.
- Open chats with incoming/outgoing grouped bubbles, tail/no-tail bubbles, outline-only bubbles, shadows, chat input controls, item-list/settings rows, premium/star/gift resource icons, avatar lock badges, Saved Messages Siri/intent avatar donation, gradient wallpapers, pattern wallpapers, wallpaper thumbnails, theme images, and theme icon/bubble previews.
- Toggle dynamic/gradient wallpapers and open chats that animate between message-background images, dimmed background clones, and raw gradient clones.
- Exercise edge/back/list gestures with normal and cancelled touch sequences.
- Open browser/instant-page markdown with raw HTML-like text and formula placeholders.

Local mitigation:

- Sign-up avatar, peer avatar, and generic avatar rendering now guard missing graphics contexts, generated masks, gradients, `CGImage` assets, and avatar bubble path conversion.
- Chat-list shimmer/search/status drawing skips missing gradients or contexts instead of crashing.
- Shared Display image generation now guards raw allocation, `CGImage` extraction, gradients, image contexts, device graphics context fallback, sample-buffer attachments, image-corner masks, text attachment masks, transformed image overlays, and empty touch sets.
- Title activity/check/confetti UI drawing now guards missing contexts, gradients, and generated sprite images.
- Presentation resource generation now guards wallpaper gradients, message bubble mask/tail/outline images, chat input icon `CGImage`s, settings/list/premium/star/gift gradients, item-list mask images, and legacy graphics contexts.
- Saved Messages intent avatar generation now falls back if the gradient or icon image cannot be generated.
- Message-background, gradient-wallpaper, pattern-wallpaper, wallpaper-thumbnail, theme-image, and theme-icon rendering now guards missing `CGImage` values, invalid/empty gradient input, allocation failure, drawing-context failure, and animation value arrays that contain images without backing `CGImage`s.
- Browser markdown raw-HTML and formula placeholder regex setup is optional; failure falls back to plain/no-op scanning.

## Drawing / Gallery Graphics

Source: local full-repo static audit of reaction counters, contact icons, drawing editor, gallery paging, graph image generation, and image-transparency histogram paths.

Primary code targets:

- `submodules/Components/ReactionButtonListComponent/Sources/ReactionButtonListComponent.swift`
- `submodules/ContactListUI/Sources/ContactListNode.swift`
- `submodules/DrawingUI/Sources/ColorPickerScreen.swift`
- `submodules/DrawingUI/Sources/DrawingLinkEntityView.swift`
- `submodules/DrawingUI/Sources/DrawingLocationEntityView.swift`
- `submodules/DrawingUI/Sources/DrawingStickerEntityView.swift`
- `submodules/DrawingUI/Sources/DrawingWeatherEntityView.swift`
- `submodules/DrawingUI/Sources/DrawingMetalView.swift`
- `submodules/GalleryUI/Sources/GalleryPagerNode.swift`
- `submodules/GalleryUI/Sources/Items/ChatImageGalleryItem.swift`
- `submodules/GraphCore/Sources/Helpers/UIImage+Utils.swift`
- `submodules/ImageTransparency/Sources/ImageTransparency.swift`

Runtime evidence needed:

- React/unreact repeatedly in a busy chat and verify reaction counter contents animation.
- Open Contacts and contact sorting dropdown.
- Open media editor color picker, add link/location/weather/sticker entities, draw with Metal brushes, scale stickers, and save/send.
- Swipe through a large image gallery with cached scaled-image tiles.
- Run image transparency/subject detection on images with missing color space or unsupported bitmap layout.

Local mitigation:

- Reaction contents animations now require typed `CGImage` old/new contents and otherwise skip the animation.
- Contact dropdown image generation, drawing-editor icons, spectrum overlays, sticker orientation drawing, and gallery fade/tile paths now skip missing `CGImage`/gradient resources instead of force-unwrapping them.
- Drawing Metal brush setup now treats render-pipeline creation as optional and skips rendering until a pipeline exists.
- Graph image generation now rejects invalid dimensions/allocation failure, and image-transparency histogram setup returns `nil` on vImage/color-space failures.

## Instant Page / Location / List Graphics

Source: local full-repo static audit of Instant View drawing, invisible ink masks, invite links, item-list/reveal gestures, live-location rendering, location icons, and file writes.

Primary code targets:

- `submodules/InstantPageUI/Sources/InstantPageDetailsNode.swift`
- `submodules/InstantPageUI/Sources/InstantPageScrollableNode.swift`
- `submodules/InstantPageUI/Sources/InstantPageTileNode.swift`
- `submodules/InvisibleInkDustNode/Sources/InvisibleInkDustNode.swift`
- `submodules/InviteLinksUI/Sources/InviteLinkViewController.swift`
- `submodules/ItemListPeerItem/Sources/ItemListPeerItem.swift`
- `submodules/ItemListUI/Sources/Items/ItemListEditableItem.swift`
- `submodules/ListMessageItem/Sources/ListMessageFileItemNode.swift`
- `submodules/LiveLocationPositionNode/Sources/ChatMessageLiveLocationPositionNode.swift`
- `submodules/LiveLocationTimerNode/Sources`
- `submodules/LocationUI/Sources/LocationActionListItem.swift`
- `submodules/LocationUI/Sources/LocationMapNode.swift`
- `submodules/ManagedFile/Sources/ManagedFile.swift`

Runtime evidence needed:

- Open Instant View pages with details blocks, scrollable tiles, and tile backgrounds.
- Reveal/scrub item-list options with normal and cancelled touch sequences.
- Send/view files with extension icons and loading shimmer.
- Start, stop, extend, and render live location/proximity radius overlays.
- Open invite/subscription link screens and invisible ink content.
- Exercise media/file writes with empty and non-empty `Data` payloads.

Local mitigation:

- Instant Page draw callbacks now return if UIKit does not provide a current graphics context.
- Invisible ink, invite link, item-list peer shimmer, list-message file icons, live-location, and location UI now treat gradients and tinted icon `CGImage`s as optional.
- Item-list reveal gestures now fail cleanly on empty touch sets.
- `ManagedFile.write(Data)` now avoids force-unwrapping unavailable base addresses.

## Legacy Media Picker Payloads

Source: local full-repo static audit of the Objective-C legacy media picker to Swift enqueue boundary.

Primary code target:

- `submodules/LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift`

Runtime evidence needed:

- Send edited photos, captured photos, cloud photos, files, GIF/MP4 animations, library videos, camera videos, and camera live photos from the legacy picker.
- Repeat the same flows with captions, timers, spoilers, paid media, grouped media, covers, stickers, and HD toggle where applicable.
- Attempt malformed or partially missing picker payloads in debug/repro harness if available: missing `type`, missing image/asset, missing `dimensions`, missing `duration`, and failed thumbnail scaling.

Local mitigation:

- Picker dictionaries now require a valid `type` before branching and validate required image/asset/video fields with optional casts.
- File animation payloads fall back to regular file sending when dimensions or duration are missing.
- Video/camera-video payloads without mandatory dimensions/duration are skipped instead of crashing.
- Combine-signal results are validated as an array before enqueue iteration.
- GIF, image, file, and video preview/cover scaling now treats failed scaling as missing preview metadata instead of a process crash.

## Passcode / Passport / External App Graphics

Source: local full-repo static audit of media time labels, external app icons, passcode entry/background/keyboard/lock icons, passport scroller/resource scaling, and password setup icons.

Primary code targets:

- `submodules/MediaPlayer/Sources/MediaPlayerTimeTextNode.swift`
- `submodules/OpenInExternalAppUI/Sources/OpenInAppIconResources.swift`
- `submodules/PasscodeInputFieldNode/Sources/PasscodeInputFieldNode.swift`
- `submodules/PasscodeUI/Sources/PasscodeBackground.swift`
- `submodules/PasscodeUI/Sources/PasscodeEntryKeyboardNode.swift`
- `submodules/PasscodeUI/Sources/PasscodeInputFieldNode.swift`
- `submodules/PasscodeUI/Sources/PasscodeLockIconNode.swift`
- `submodules/PassportUI/Sources/Form/FormControllerScrollerNode.swift`
- `submodules/PassportUI/Sources/SecureIdLocalResource.swift`
- `submodules/PasswordSetupUI/Sources/TwoFactorAuthDataInputScreen.swift`

Runtime evidence needed:

- Enable, enter, update, and remove passcode with gradient and image-based passcode backgrounds.
- Tap passcode keyboard buttons with normal/highlighted transitions and lock/unlock icon animation.
- Open media player controls where time labels redraw.
- Open external-app icons using image-backed resources.
- Use passport/secure-id resource scaling and password setup text visibility toggle.
- Exercise passport form scrolling where touches are filtered/prevented.

Local mitigation:

- Async draw callbacks now return when the current graphics context is unavailable.
- Passcode dot/background/keyboard images and layer contents animations now require generated images and backing `CGImage`s before drawing/animating.
- Image-based passcode backgrounds now tolerate missing `DrawingContext`, generated images, and source `CGImage`.
- Passport touch filtering now handles empty touch sets, and passport/password image scaling/drawing now skips missing backing images.

## Peer Info Avatar / Photo Resources Graphics

Source: local full-repo static audit of peer avatar strip shadows, HLS playlist parsing, blurred photo thumbnails, and call background generation.

Primary code targets:

- `submodules/PeerInfoAvatarListNode/Sources/PeerInfoAvatarListNode.swift`
- `submodules/PhotoResources/Sources/PhotoResources.swift`

Runtime evidence needed:

- Open peer info screens with multiple avatars/stories and swipe the avatar strip until left/right highlight and top/bottom shadow overlays render.
- Open media-heavy chats where blurred photo thumbnails are generated from small/corrupt/partially cached images.
- Open video/photo resources that use HLS playlist preload parsing.
- Open call UI backgrounds where the default gradient resource is generated.

Local mitigation:

- Peer info avatar highlight/shadow generation now skips missing gradients and only draws generated shadow images when a backing `CGImage` exists.
- Photo resource HLS playlist parsing now returns no preload range if static regex setup fails.
- Blurred side-thumbnail rendering now requires a backing `CGImage`, and default call background generation falls back to a solid fill if gradient creation fails.

## Status / QR / Settings / Shimmer Graphics

Source: local full-repo static audit of status indicators, QR controls, Appearance masks, shimmer placeholders, sparse grid indicators, sticker thumbnails, tab icons, and call buttons.

Primary code targets:

- `submodules/QrCode/Sources/QrCode.swift`
- `submodules/QrCodeUI/Sources/GlassButtonNode.swift`
- `submodules/RadialStatusNode/Sources`
- `submodules/SemanticStatusNode/Sources`
- `submodules/SettingsUI/Sources/BubbleSettings/BubbleSettingsController.swift`
- `submodules/SettingsUI/Sources/Text Size/TextSizeSelectionController.swift`
- `submodules/SettingsUI/Sources/Themes`
- `submodules/ShimmerEffect/Sources/ShimmerEffect.swift`
- `submodules/SparseItemGrid/Sources`
- `submodules/StickerResources/Sources/StickerResources.swift`
- `submodules/TabBarUI/Sources/TabBarNode.swift`
- `submodules/ReactionSelectionNode/Sources/ReactionContextNode.swift`
- `submodules/PremiumUI/Sources`
- `submodules/TelegramBaseController/Sources/MediaNavigationAccessoryHeaderNode.swift`
- `submodules/TelegramCallsUI/Sources`

Runtime evidence needed:

- Generate and scan QR code screens, including glass buttons with filled/unfilled states.
- Render radial progress/check/cancel/download indicators and semantic play/pause/timeout status nodes.
- Open Appearance, bubble settings, text-size settings, theme preview/accent/app icon screens.
- Scroll chat lists and media grids while shimmer placeholders and sparse-grid indicators update.
- Open sticker thumbnails with blurred previews, switch tabs, open media navigation accessory headers, and exercise call accept/end button transitions, voice-chat headers, voice-chat tiles, video-chat loading, video-chat encryption key, and selected participant avatar states.
- Open premium limit/rain decoration surfaces only to verify local hiding does not leave a crash path if those controllers are still instantiated.

Local mitigation:

- Async status-node draw callbacks now return when UIKit does not provide a graphics context.
- QR, semantic status, tab, call, and sticker thumbnail drawing now requires a backing `CGImage` before using images as draw sources or masks.
- Settings, shimmer, sparse-grid, reaction, premium-limit, and media-navigation gradients now degrade to skipped gradient or solid fill instead of crashing.
- Sparse/call/QR layer contents animations now run only when both old and new contents have `CGImage` backing.
- Voice/video call status, header, tile, loading, recording, encryption-key, and participant-avatar drawing now treats contexts, gradients, sample attachments, avatar images, and masks as optional.
- Premium DataRain now fails initialization cleanly if Metal render pipeline creation fails.

## Multipart Media Transfer

Source: local full-repo static audit of encrypted media upload/download and CDN media fetch pointer boundaries.

Primary code targets:

- `submodules/TelegramCore/Sources/Network/MultipartFetch.swift`
- `submodules/TelegramCore/Sources/Network/MultipartUpload.swift`

Runtime evidence needed:

- Download encrypted and non-encrypted photos, videos, documents, voice notes, and stickers from regular and CDN-backed media.
- Upload encrypted secret-chat media and regular media from file, memory data, and temp-file sources.
- Exercise interrupted/resumed downloads and uploads with partial local files and background/foreground transitions.
- Reproduce malformed/corrupt transfer harness cases when possible: empty encrypted chunks, encrypted chunk sizes not aligned to 16 bytes, short AES IV buffers, failed `Data` backing storage, CDN CTR decrypt failure, and upload fingerprint digest failure.

Local mitigation:

- Multipart download now rejects encrypted chunks without decrypted size, AES backing buffers, valid offsets, or 16-byte alignment before decrypting/writing.
- CDN file fetch now validates IV length, IV buffer backing storage, and CTR decrypt output before returning fetched data.
- Multipart upload now treats missing generated AES key/IV buffers, failed encrypted part transforms, empty/non-backed MD5 buffers, and failed key-fingerprint writes as upload failures instead of process crashes.

Static evidence:

- `scripts/custom-client/run_crash_risk_scan.sh --path submodules/TelegramCore/Sources/Network/MultipartFetch.swift --path submodules/TelegramCore/Sources/Network/MultipartUpload.swift` passes.
- `scripts/custom-client/run_static_analysis.sh --path submodules/TelegramCore/Sources/Network/MultipartFetch.swift --path submodules/TelegramCore/Sources/Network/MultipartUpload.swift` passes with warning-only output.

## Software Video Crash

Issue: [#1934 EXC_BAD_ACCESS on UniversalSoftwareVideoSource](https://github.com/TelegramMessenger/Telegram-iOS/issues/1934)

Primary code targets:

- `submodules/MediaPlayer/Sources/UniversalSoftwareVideoSource.swift`
- `submodules/MediaPlayer/Sources/SoftwareVideoSource.swift`
- `submodules/MediaPlayer/Sources/MediaDataReader.swift`
- `submodules/MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift`
- `submodules/MediaPlayer/Sources/FFMpegFileReader.swift`
- `submodules/TelegramUniversalVideoContent/Sources/NativeVideoContent.swift`
- `submodules/TelegramUniversalVideoContent/Sources/HLSVideoContent.swift`
- `submodules/TelegramUniversalVideoContent/Sources/HLSVideoJSNativeContentNode.swift`

Runtime evidence needed:

- Exact crash frame around `UniversalSoftwareVideoSource`.
- Whether source thread is being stopped while `takeFrame` is in flight.
- Whether it reproduces only on channel scrolling, video opening, or background/foreground transitions.
- HLS/frame-preview parsing with malformed playlists and overflowing byte ranges.
- HLS JS-native bridge callbacks with invalid JSON-serializable payloads and cached part files whose `Data` buffer has no base address.
- Seek/restore around video chunks where sample-buffer attachments may be missing.
- Audio decode/render under memory pressure and zero-length sample/ring-buffer reads.
- Direct fetch/file reader callbacks with nil callback context, nil destination buffer, zero buffer size, missing `Data` base address, oversized fetched data, and out-of-range seeks.

Local mitigation:

- `submodules/MediaPlayer/Sources/UniversalSoftwareVideoSource.swift` now validates FFmpeg callback inputs, clamps requested read ranges to the known media size, caps copied bytes to the FFmpeg destination buffer, clamps seek offsets, forwards `hintVP9`, and publishes `.failed` if source initialization cannot create a decoder.
- `submodules/MediaPlayer/Sources/SoftwareVideoSource.swift` now validates callback inputs and clamps file seeks before reading local video, software audio, video reader, and media info data.
- `submodules/MediaPlayer/Sources/MediaPlayerFramePreview.swift` now rejects invalid preview regex setup and overflowing byte ranges.
- `submodules/TelegramUniversalVideoContent/Sources/HLSVideoContent.swift` and `HLSVideoJSNativeContentNode.swift` now avoid forced playlist regex setup, guard overflowing playlist byte ranges and cached-part buffer base addresses, and skip invalid JS bridge JSON callbacks.
- `submodules/MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift` and `FFMpegFileReader.swift` now validate direct-fetch/file FFmpeg callback inputs, clamp copied data to the provided buffer, avoid advancing offsets when no bytes are copied, and bound seek offsets.
- `submodules/MediaPlayer/Sources/FFMpegMediaVideoFrameDecoder.swift`, `FFMpegAudioFrameDecoder.swift`, `FFMpegMediaPassthroughVideoFrameDecoder.swift`, `FFMpegMediaFrameSourceContext.swift`, `ChunkMediaPlayerV2.swift`, `MediaPlayerNode.swift`, `MediaPlayerAudioRenderer.swift`, and `RingByteBuffer.swift` now avoid force-unwrapping FFmpeg callback user data, sample-buffer attachments, pixel-buffer planes, raw allocation results, and empty ring-buffer reads.

Static evidence:

- `scripts/custom-client/run_crash_risk_scan.sh` passes on the changed Swift scope with media-specific force-unwrap patterns enabled.

## Notification Payload / Watch Notification Regressions

Issues:

- [#623 iPad is freezed after notification was receiving](https://github.com/TelegramMessenger/Telegram-iOS/issues/623)
- [#2193 Apple Watch notifications replace previous ones](https://github.com/TelegramMessenger/Telegram-iOS/issues/2193)
- [#2037 Notification body is always "You have a new message"](https://github.com/TelegramMessenger/Telegram-iOS/issues/2037)
- [#833 Notifications are only "You have a new message"](https://github.com/TelegramMessenger/Telegram-iOS/issues/833)

Primary code targets:

- `submodules/TelegramUI/Sources/AppDelegate.swift`
- `submodules/TelegramUI/Sources/SharedNotificationManager.swift`
- `Telegram/NotificationService/Sources/NotificationService.swift`
- `Telegram/Watch/Extension/TGNotificationController.m`

Runtime evidence needed:

- Delivered notification cleanup with mixed legacy/current payloads.
- Tapping message/story notifications with string, number, and malformed id fields.
- Notification service decrypt/update flow with string, number, `NSNumber`, and malformed message/story/call/read-history fields.
- Custom emoji notification body rendering with corrupt or unavailable inline sticker resources.
- Watch notification delivery for several messages in the same conversation.
- Hidden-preview notification behavior on iPad.

Local mitigation:

- `submodules/TelegramUI/Sources/AppDelegate.swift` now parses notification payload ids with safe typed helpers and avoids force-casting payload values to `NSString`.
- `submodules/TelegramUI/Sources/SharedNotificationManager.swift` now parses decrypted/foreground notification ids with typed helpers and ignores malformed peer/message/random ids safely.
- `Telegram/NotificationService/Sources/NotificationService.swift` now parses notification payload ids through typed helpers, avoids force-casting notification content updates, skips malformed custom emoji glyphs, clamps fetched resource data copies, and falls back safely when avatar graphics contexts or gradients are unavailable.
- `Telegram/WidgetKitWidget/PeerNode.swift` now falls back safely when widget avatar graphics contexts, gradients, `CGImage` assets, or Saved Messages icons are unavailable.
- Watch `OpusKit` and `RLottieKit` packages now guard audio/lottie base-address buffers. Their SwiftPM test suites pass locally.
- Watch `TDShim` no longer uses `try!` or forced response casts for TDLib query encoding/execution paths.
- `scripts/custom-client/run_crash_risk_scan.sh` now fails changed Swift files that reintroduce high-risk payload, graphics, media-buffer, and touch-set force unwraps.

Runtime evidence still needed:

- Add/remove Telegram widgets with peers that have missing/corrupt avatar resources and Saved Messages.
- Deliver multiple Watch notifications for the same conversation and play/open Watch voice-note or animated sticker assets.
- Run Watch TDLib query send/execute flows with malformed or unexpected local payloads.

## Media Editor / Scrubber Hardening

Source: local audit of media editor and scrubber crash boundaries.

Issues:

- [#2052 Message text does not move up after applying moving up in video editor](https://github.com/TelegramMessenger/Telegram-iOS/issues/2052)
- [#954 iOS 16.2 crashes when modifying group profile pictures](https://github.com/TelegramMessenger/Telegram-iOS/issues/954)

Primary code targets:

- `submodules/TelegramUI/Sources/FetchCachedRepresentations.swift`
- `submodules/DirectMediaImageCache/Sources/DirectMediaImageCache.swift`
- `submodules/TelegramUI/Sources/OpenResolvedUrl.swift`
- `submodules/TelegramUI/Sources/TransformOutgoingMessageMedia.swift`
- `submodules/TelegramUI/Sources/SpotlightContacts.swift`
- `submodules/TelegramUI/Components/MediaEditorScreen/Sources/StickerCutoutOutlineView.swift`
- `submodules/TelegramUI/Components/MediaScrubberComponent/Sources/MediaScrubberComponent.swift`
- `submodules/TelegramUI/Components/MediaEditor/Sources/MediaEditorVideoExport.swift`
- `submodules/TelegramUI/Components/MediaEditor/Sources/MediaEditorRenderer.swift`
- `submodules/TelegramUI/Components/MediaEditor/Sources/*RenderPass.swift`
- `submodules/TelegramUI/Components/MediaEditor/Sources/MediaEditorComposer.swift`

Runtime evidence needed:

- Sticker cutout on transparent/non-transparent images.
- Video trim scrubber with valid, corrupt, and very short video assets.
- Video editor text/sticker position when editing an existing message, including #2052's move-up flow.
- Group photo editing and export flow.
- Story editor sticker/cutout flows and export completion.
- External/open-url story editor flow where the editor returns no media results because of cancellation or decode failure.
- Sticker AJPEG cache generation, scaled image cache generation, scaled first-video-frame generation, blurred wallpaper cache generation, and album artwork extraction with corrupt or `cgImage`-less image inputs.
- Direct media image cache RGB565 read/write with corrupt cache headers, short cached payloads, invalid dimensions, and `cgImage`-less image inputs.
- Outgoing image thumbnail generation for unusual image containers/orientations.
- Spotlight contact indexing with corrupt, missing, or CoreImage-backed avatar images.

Local mitigation:

- Cached media representation generation now skips invalid image sources/generated images instead of force-unwrapping `cgImage` values.
- Direct media image cache now guards thumbnail `CGImage` extraction, RGB565 cache allocation, cached payload header reads, cached data base addresses, and scaled image rendering.
- Open-url story editor completion now ignores empty result batches instead of force-unwrapping the first upload target.
- Outgoing media transformation now draws thumbnails from the existing decoded `CGImage` instead of force-unwrapping `UIImage.cgImage`.
- Spotlight contact avatar generation now skips avatar output if image/context generation fails or either source image lacks a `CGImage`.
- Cutout edge detection now validates pixel buffers and always unlocks successfully locked buffers.
- Cutout path simplification tolerates empty/short contour arrays.
- Video scrubber frame update skips nil `cgImage` frames and does not force-cast existing layer contents.
- Audio scrubber mask generation skips the optional gradient if CoreGraphics cannot create it.
- Render passes now avoid force-unwrapping generated mask images, cached Metal textures, gradient contexts, and gradient colors. Missing render resources fall back to input texture or skip the pass rather than crashing.

## Fixed Locally

Issue: [#2031 A crash will occur if the metadata of a saved audio file contains a "/"](https://github.com/TelegramMessenger/Telegram-iOS/issues/2031)

Patch:

- `submodules/TelegramUI/Sources/SaveMediaToFiles.swift`

Regression scenario:

- Export an audio file with title/artist metadata containing `/`, `:`, `\`, or path-traversal-like prefixes.
- The Files export sheet must receive an existing local URL.

Issue: [#1189 Data links (base64 encoded) cause crash](https://github.com/TelegramMessenger/Telegram-iOS/issues/1189)

Patch:

- `submodules/TextFormat/Sources/GenerateTextEntities.swift`
- `submodules/TextFormat/Sources/StringWithAppliedEntities.swift`
- `submodules/UrlWhitelist/Sources/UrlWhitelist.swift`
- `submodules/TelegramUI/Components/OpenUserGeneratedUrl/Sources/OpenUserGeneratedUrl.swift`
- `submodules/TelegramUI/Sources/OpenUrl.swift`

Regression scenario:

- Send or receive a raw `data:application/pdf;base64,...` URL with a large payload.
- Reopen the chat and scroll across the message.
- The message should render as plain text instead of a tappable URL, and URL resolution/webpage preview should not run for the payload.

Issue: [#2011 App Crash on Startup for iOS Contact with URL](https://github.com/TelegramMessenger/Telegram-iOS/issues/2011)

Patch:

- `Telegram/SiriIntents/IntentContacts.swift`
- `submodules/AccountContext/Sources/DeviceContactData.swift`

Regression scenario:

- Create an iOS contact with URL label `Telegram` and URL `https://t.me/@id-50012345678` matching an open group chat id.
- Restart the app with that group still in the chat list.
- The startup/contact matching path should ignore the negative `@id` reference and continue without a crash.

Issue: [#2134 Photos app freezes when sharing to Telegram while Telegram is not logged in](https://github.com/TelegramMessenger/Telegram-iOS/issues/2134)

Patch:

- `submodules/TelegramUI/Components/ShareExtensionContext/Sources/ShareExtensionContext.swift`

Regression scenario:

- Install the app with no authorized account.
- Open Photos, select a photo, and choose Telegram in the iOS share sheet.
- The share extension should enter the unauthorized completion path instead of keeping the host share sheet blocked on account loading.

Source: local Siri/widget intent and broadcast extension audit.

Patch:

- `Telegram/SiriIntents/IntentHandler.swift`
- `Telegram/BroadcastUpload/BroadcastUploadExtension.swift`

Regression scenario:

- Run Siri/Shortcuts friend resolution with valid and malformed message identifiers.
- Populate widget friend options with peers that have missing/corrupt avatar resources and Saved Messages.
- Start and stop a broadcast upload session and force sample-buffer paths that have no sample attachments.
- Intent and broadcast extensions should skip malformed data or use fallback avatars instead of crashing.
