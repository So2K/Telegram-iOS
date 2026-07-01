# Bug Backlog

Last reviewed: 2026-07-02

This backlog is seeded from GitHub issues and local source inspection. Re-run `scripts/custom-client/fetch_github_bug_backlog.sh` before each bug-fix pass.

## P0 / P1 Candidates

| Area | Issue | Status | First code target |
| --- | --- | --- | --- |
| Media editor / scrubber | Local source audit | Hardened locally; needs runtime proof | sticker cutout, video scrubber frames |
| Appearance crash | [#2196 App crushes in theme appearance section](https://github.com/TelegramMessenger/Telegram-iOS/issues/2196) | Mitigated locally; needs runtime proof | `TelegramUIPreferences/Sources/PresentationThemeSettings.swift`, `SettingsUI` theme picker / theme preview |
| Startup crash | [#2011 App Crash on Startup for iOS Contact with URL](https://github.com/TelegramMessenger/Telegram-iOS/issues/2011) | Fixed locally | `AccountContext/Sources/DeviceContactData.swift`, `Telegram/SiriIntents/IntentContacts.swift` |
| Saved Messages freeze | [#2059 The app freezes when I open Saved Messages](https://github.com/TelegramMessenger/Telegram-iOS/issues/2059) | Mitigated locally; needs runtime proof | chat history load, media cache, voice waveform layout |
| Voice recording / waveform crash risk | Local source audit, adjacent to #2059 | Hardened locally; needs runtime proof | `ManagedAudioRecorder`, waveform preview, recorded audio finalization |
| Share extension freeze | [#2134 Photos app freezes when sharing to Telegram while Telegram is not logged in](https://github.com/TelegramMessenger/Telegram-iOS/issues/2134) | Fixed locally | `ShareExtensionContext/Sources/ShareExtensionContext.swift` |
| Siri/widget intent crashes | Local source audit, related to Siri/notification issue feed | Hardened locally; needs runtime proof | `Telegram/SiriIntents/IntentHandler.swift` |
| Broadcast upload extension crash risk | Local source audit | Hardened locally; needs runtime proof | `Telegram/BroadcastUpload/BroadcastUploadExtension.swift` |
| GIF crash | [#2019 The app crashes when you select a gif](https://github.com/TelegramMessenger/Telegram-iOS/issues/2019) | Mitigated locally; needs runtime proof | entity keyboard, GIF picker, media preview |
| Animation compression / sticker frame cache crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `AnimatedStickerNode/Sources/FrameCompression.swift`, `AnimationCompression` |
| Telegram API buffer serialization crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `TelegramApi/Sources/Buffer.swift` |
| Video crash | [#1934 EXC_BAD_ACCESS on UniversalSoftwareVideoSource](https://github.com/TelegramMessenger/Telegram-iOS/issues/1934) | Mitigated locally; needs runtime proof | `TelegramUniversalVideoContent`, media player |
| HLS video playlist/cache crash risk | Local full-repo static audit, adjacent to #1934 | Hardened locally; needs runtime proof | `TelegramUniversalVideoContent/Sources/HLSVideoContent.swift`, `HLSVideoJSNativeContentNode.swift` |
| Multipart media transfer crash risk | Local full-repo static audit, adjacent to media/cache/performance reports | Hardened locally; needs runtime proof | `TelegramCore/Sources/Network/MultipartFetch.swift`, `MultipartUpload.swift` |
| Chat opening crash | [#1739 Telegram iOS App Crashes When Opening Chats](https://github.com/TelegramMessenger/Telegram-iOS/issues/1739) | Partially mitigated locally; needs runtime proof | chat history transitions, bot callback payloads, sticker/media history |
| Scrolling freeze | [#1668 iOS 18.2 Telegram app freezing randomly, dubbed "Scrolling Bug"](https://github.com/TelegramMessenger/Telegram-iOS/issues/1668) | Needs profiling; source guards added in adjacent history paths | `ChatHistoryListNode`, list transactions, incoming-message update while scrolling |
| Chat list/context menu edge cases | Local source audit | Hardened locally; needs runtime proof | chat list gesture recognizer, message context menu option reduction |
| Chat list graphics crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `ChatListShimmerNode`, `ChatListSearchListPaneNode`, `ChatListStatusNode` |
| Shared Display/UI graphics crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `Display/Source`, `ChatTitleActivityNode`, `CheckNode`, `ConfettiEffect` |
| Presentation/wallpaper resource graphics crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `TelegramPresentationData/Sources`, `WallpaperResources/Sources/WallpaperResources.swift`, `TelegramIntents/Sources/TelegramIntents.swift` |
| Gradient/message background graphics crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `ChatMessageBackground`, `GradientBackground` |
| Drawing/gallery reaction graphics crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `DrawingUI`, `GalleryUI`, `ReactionButtonListComponent`, `GraphCore`, `ImageTransparency` |
| Instant page/location/list graphics crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `InstantPageUI`, `InvisibleInkDustNode`, `InviteLinksUI`, `ItemListPeerItem`, `ItemListUI`, `LiveLocation*`, `LocationUI`, `ManagedFile` |
| Legacy media picker payload crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift` |
| Passcode/passport/external-app graphics crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `Passcode*`, `PassportUI`, `PasswordSetupUI`, `OpenInExternalAppUI`, `MediaPlayerTimeTextNode` |
| Peer info avatar/photo resources crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `PeerInfoAvatarListNode`, `PhotoResources` |
| Status/QR/settings/shimmer graphics crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `QrCode*`, `RadialStatusNode`, `SemanticStatusNode`, `SettingsUI`, `ShimmerEffect`, `SparseItemGrid`, `StickerResources`, `TabBarUI`, `TelegramCallsUI` |
| Contact attachment edge cases | Local source audit | Hardened locally; needs runtime proof | `ChatControllerOpenAttachmentMenu`, device contacts without phone numbers |
| Avatar/sign-up graphics crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `AuthorizationSequenceSignUpControllerNode`, `AvatarNode`, `PeerAvatar` |
| Audio file export crash | [#2031 A crash will occur if the metadata of a saved audio file contains a "/"](https://github.com/TelegramMessenger/Telegram-iOS/issues/2031) | Fixed locally | `TelegramUI/Sources/SaveMediaToFiles.swift` |
| Data link crash | [#1189 Data links (base64 encoded) cause crash](https://github.com/TelegramMessenger/Telegram-iOS/issues/1189) | Fixed locally | `TextFormat`, `UrlWhitelist`, URL opening |
| Browser markdown parser crash risk | Local full-repo static audit | Fixed locally | `BrowserUI/Sources/BrowserMarkdown.swift` |
| iPad notification freeze | [#623 iPad is freezed after notification was receiving](https://github.com/TelegramMessenger/Telegram-iOS/issues/623) | Partially mitigated locally; needs runtime proof | notification presentation, split view state |
| Watch notification replacement | [#2193 Apple Watch notifications replace previous ones](https://github.com/TelegramMessenger/Telegram-iOS/issues/2193) | Needs repro | notification identifiers, Watch extension |
| Generic notification body | [#2037 Notification body is always "You have a new message"](https://github.com/TelegramMessenger/Telegram-iOS/issues/2037), [#833 Notifications are only "You have a new message"](https://github.com/TelegramMessenger/Telegram-iOS/issues/833) | Partially mitigated locally; needs runtime proof | notification service payload decrypt/format |
| Widget / Watch extension crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `WidgetKitWidget/PeerNode`, Watch Opus/RLottie/TDShim packages |
| Video editor text position | [#2052 Message text does not move up after applying moving up in video editor](https://github.com/TelegramMessenger/Telegram-iOS/issues/2052) | Needs repro; render paths hardened locally | media editor composer/export |
| Group photo editor crash | [#954 iOS 16.2 crashes when modifying group profile pictures](https://github.com/TelegramMessenger/Telegram-iOS/issues/954) | Needs repro; render paths hardened locally | media picker/editor render passes |
| Media thumbnail/cache crash risk | Local source audit, adjacent to media/editor crash reports | Hardened locally; needs runtime proof | `FetchCachedRepresentations`, album artwork, sticker AJPEG, video first frame |
| Direct media image cache crash risk | Local full-repo static audit | Hardened locally; needs runtime proof | `DirectMediaImageCache` |
| Outgoing media / Spotlight image crash risk | Local source audit | Hardened locally; needs runtime proof | `TransformOutgoingMessageMedia`, `SpotlightContacts` |
| Battery drain | [#81 Background activity drains battery very fast](https://github.com/TelegramMessenger/Telegram-iOS/issues/81) | Needs profiling | background fetch, media preloads, network activity |
| iOS performance | [#1554 Significant performance issue on iOS18](https://github.com/TelegramMessenger/Telegram-iOS/issues/1554) | Needs profiling | chat list, message list, media pipeline |
| iPad memory growth | [#447 Severe performance issue on iPad, suspecting a memory leak](https://github.com/TelegramMessenger/Telegram-iOS/issues/447) | Needs profiling | chat switching, GIF panel, media cache churn |

## Recently Updated Bug Feed

Observed from GitHub search on 2026-07-02:

- [#2037 Notification body is always "You have a new message"](https://github.com/TelegramMessenger/Telegram-iOS/issues/2037)
- [#833 Notifications are only "You have a new message"](https://github.com/TelegramMessenger/Telegram-iOS/issues/833)
- [#2157 Quick white flash when sending message after watching video in another app](https://github.com/TelegramMessenger/Telegram-iOS/issues/2157)
- [#2127 No AV1/Opus support in Telegram for iPhone](https://github.com/TelegramMessenger/Telegram-iOS/issues/2127)
- [#2052 Message text does not move up after applying moving up in video editor](https://github.com/TelegramMessenger/Telegram-iOS/issues/2052)
- [#1543 Autocomplete bug](https://github.com/TelegramMessenger/Telegram-iOS/issues/1543)
- [#2129 No pop-up notifications on official Telegram app](https://github.com/TelegramMessenger/Telegram-iOS/issues/2129)
- [#2185 Double-clicking a group tab opens duplicate windows](https://github.com/TelegramMessenger/Telegram-iOS/issues/2185)
- [#2181 Pinned messages hidden by Chat Automation banner in private chats on iOS](https://github.com/TelegramMessenger/Telegram-iOS/issues/2181)
- [#2139 Large emoji render does not update correctly after editing emoji count on iOS](https://github.com/TelegramMessenger/Telegram-iOS/issues/2139)
- [#2138 Autocorrect suggestion merges with typed text](https://github.com/TelegramMessenger/Telegram-iOS/issues/2138)
- [#2124 Incorrect hit target mapping](https://github.com/TelegramMessenger/Telegram-iOS/issues/2124)
- [#1739 Telegram iOS App Crashes When Opening Chats](https://github.com/TelegramMessenger/Telegram-iOS/issues/1739)
- [#1668 iOS 18.2 Telegram app freezing randomly, dubbed "Scrolling Bug"](https://github.com/TelegramMessenger/Telegram-iOS/issues/1668)
- [#447 Severe performance issue on iPad, suspecting a memory leak](https://github.com/TelegramMessenger/Telegram-iOS/issues/447)

## First Fix Order

1. Build/toolchain unblock and baseline profiling.
2. Reproduce #2196 because it is recent, specific, and likely contained in `SettingsUI`.
3. Reproduce #2019 and #1934 because media crashes can also explain scrolling/channel instability.
4. Reproduce #2134 because share extension freezes are isolated from main app UI and easier to regression test.
5. Profile #81/#1554 after the client can run for long sessions.

## Fixed Locally

### #2031 Audio metadata slash export crash

Source: GitHub issue [#2031](https://github.com/TelegramMessenger/Telegram-iOS/issues/2031).

Patch: `TelegramUI/Sources/SaveMediaToFiles.swift` now sanitizes metadata-derived export filename components before creating the temporary hard link for `UIDocumentPickerViewController`.

Regression scenario:

- Save/export an audio file whose title or artist metadata contains `/`, `:`, `\`, an empty component, or a path traversal-like prefix.
- Expected: Files export sheet opens with a valid local URL; the fallback media symlink remains valid if the metadata-derived link cannot be created.

### #1189 Data URL crash

Source: GitHub issue [#1189](https://github.com/TelegramMessenger/Telegram-iOS/issues/1189).

Patch:

- `TextFormat/Sources/GenerateTextEntities.swift` skips auto-generated and composer `TextUrl` entities for `data:` URLs and URLs longer than 8192 UTF-16 code units.
- `TextFormat/Sources/StringWithAppliedEntities.swift` does not turn unsafe incoming `.Url` / `.TextUrl` entities into tappable URL attributes.
- `UrlWhitelist/Sources/UrlWhitelist.swift`, `OpenUserGeneratedUrl.swift`, and `OpenUrl.swift` block unsafe user-generated URLs before resolve/open handling.

Regression scenario:

- Paste/send `data:application/pdf;base64,...` with a large payload, then reopen and scroll the chat.
- Expected: message text remains renderable and does not enter webpage preview/open-url handling; the app must not crash.

### #2011 Contact `@id-...` startup crash

Source: GitHub issue [#2011](https://github.com/TelegramMessenger/Telegram-iOS/issues/2011).

Patch:

- `AccountContext/Sources/DeviceContactData.swift` and `Telegram/SiriIntents/IntentContacts.swift` now reject non-positive ids in `https://t.me/@id...` contact references.

Regression scenario:

- Create an iOS contact with URL label `Telegram` and URL `https://t.me/@id-50012345678` matching an existing group id.
- Expected: contact import/intents matching ignores the URL as an invalid user reference; app startup must not crash.

### #2134 Share extension freeze while logged out

Source: GitHub issue [#2134](https://github.com/TelegramMessenger/Telegram-iOS/issues/2134).

Patch:

- `TelegramUI/Components/ShareExtensionContext/Sources/ShareExtensionContext.swift` now fails the share-extension account-loading signal with `.unauthorized` when no valid logged-in account exists instead of returning `.never()`.
- The existing unauthorized alert/completion path is used, so the host share sheet is not left waiting forever.
- The same pass removed force-try regex setup from chat-import share handling.

Regression scenario:

- Install the app but do not log in.
- Share a photo from iOS Photos to Telegram.
- Expected: extension shows the login-required flow or exits cleanly; Photos/share sheet must not freeze.

### #2196 Appearance/theme crash mitigation

Source: GitHub issue [#2196](https://github.com/TelegramMessenger/Telegram-iOS/issues/2196).

Patch:

- `TelegramUIPreferences/Sources/PresentationThemeSettings.swift` now tolerates invalid builtin theme raw values and malformed local theme resource records.
- Theme-specific wallpaper/accent-color dictionaries fall back to empty maps if older or damaged settings entries cannot be decoded.

Remaining proof needed:

- Reproduce Settings -> Appearance -> change/edit theme on Xcode 26.x/iOS 26.x.
- If it still crashes, capture crash log and inspect `SettingsUI` theme picker/preview stack.

### #1934 Software video callback hardening

Source: GitHub issue [#1934](https://github.com/TelegramMessenger/Telegram-iOS/issues/1934).

Patch:

- `MediaPlayer/Sources/UniversalSoftwareVideoSource.swift` now rejects invalid FFmpeg callback inputs, clamps read ranges to the known resource size, caps `memcpy` to the destination buffer size, clamps seek offsets, marks source initialization failure explicitly, and passes through the existing `hintVP9` flag.
- `MediaPlayer/Sources/SoftwareVideoSource.swift` applies the same invalid callback and seek-boundary hardening for local-file software decoding, software audio decoding, video reader decoding, and FFmpeg media info extraction.
- `MediaPlayer/Sources/MediaPlayerFramePreview.swift` now avoids `try!` regex setup and rejects overflowing HLS byte ranges while parsing frame previews.
- `TelegramUniversalVideoContent/Sources/HLSVideoContent.swift` and `HLSVideoJSNativeContentNode.swift` now avoid `try!` playlist regex setup, reject overflowing HLS byte ranges, guard cached-part buffer base addresses, and skip invalid JS bridge JSON serialization.
- `MediaPlayer/Sources/ChunkMediaPlayerDirectFetchSourceImpl.swift` and `FFMpegFileReader.swift` now validate FFmpeg callback `userData`, destination buffers, buffer sizes, data base addresses, copied byte counts, and seek offsets before reading direct-fetch or file/resource media.
- `MediaPlayer/Sources/FFMpegMediaVideoFrameDecoder.swift`, `FFMpegAudioFrameDecoder.swift`, `FFMpegMediaPassthroughVideoFrameDecoder.swift`, `FFMpegMediaFrameSourceContext.swift`, `ChunkMediaPlayerV2.swift`, `MediaPlayerNode.swift`, `MediaPlayerAudioRenderer.swift`, and `RingByteBuffer.swift` now avoid high-risk force unwraps around sample-buffer attachments, FFmpeg callback user data, pixel-buffer planes, packet/audio allocations, and ring-buffer dequeue.
- `TelegramUI/Sources/AppDelegate.swift` now treats startup/write-test and background-upload buffer allocation failure as recoverable instead of force-unwrapping allocation results.
- `TelegramCore/Sources/Network/MultipartFetch.swift` and `MultipartUpload.swift` now validate AES key/IV buffers, encrypted chunk alignment, generated upload keys, MD5/fingerprint buffers, CDN CTR IV mutation, and decrypted CDN output before writing fetched media or completing encrypted uploads.

Remaining proof needed:

- Reproduce the reported channel/media scroll scenario on Xcode 26.x/iOS 26.x.
- Expected: corrupt or partially available video/audio/HLS data returns EOF, skips invalid frames/playlist ranges, or waits for data instead of crashing in FFmpeg, sample-buffer attachment, pixel-buffer plane, frame-preview, HLS cache-copy, or JS bridge code.
- Expected: corrupt encrypted multipart chunks, missing AES buffers, invalid CDN IV data, or failed upload key/fingerprint buffers fail the transfer path cleanly instead of crashing or writing corrupted media bytes.

### #2019 GIF / animated sticker picker hardening

Source: GitHub issue [#2019](https://github.com/TelegramMessenger/Telegram-iOS/issues/2019).

Patch:

- `AnimatedStickerNode/Sources/AnimatedStickerFrameSource.swift` now rejects malformed cached animation headers before reading frame metadata, bounds frame dimensions/rate/count/buffer size, rejects invalid compressed frame lengths, and clamps direct-source seek indexes.
- `AnimatedStickerNode/Sources/AnimatedStickerNode.swift` now clamps playback frame rate before creating timers and avoids timestamp seek math on invalid timestamps/durations.
- `AnimatedStickerNode/Sources/VideoStickerFrameSource.swift` now clamps decoded video sticker frame rate, rejects invalid WebP `cgImage`/sample-buffer pixel data instead of force-unwrapping it, and clamps seek indexes.
- `AnimatedStickerNode/Sources/FrameCompression.swift` now treats invalid frame dimensions, allocation failure, and compression failure as `nil` compressed frames instead of force-unwrapping raw allocation results.
- `AnimationCompression/Sources/AnimationCompressor.swift`, `Buffer.swift`, and `CompressedImageRenderer.swift` now validate frame sizes, buffer lengths, `Data` base addresses, Metal readback data, and DCT/Huffman payloads before copying or rendering compressed animation frames.
- `TelegramAnimatedStickerNode/Sources/AnimatedStickerUtils.swift` now validates render dimensions, allocation results, generated `CGImage`s, AJPEG destinations, and video sticker pixel buffers before encoding first-frame, lottie-frame, or video-sticker cache data.

Remaining proof needed:

- Reproduce the reported GIF/sticker picker flow on Xcode 26.x/iOS 26.x.
- Expected: malformed cached animation/video frames are skipped or shown as placeholders; selecting GIFs or animated stickers must not crash the app.

### Telegram API buffer serialization hardening

Source: local full-repo static audit of TL/API byte buffer boundaries.

Patch:

- `TelegramApi/Sources/Buffer.swift` now treats zero-length buffers as valid without dereferencing backing memory.
- `serializeBytes`, `serializeString`, `Buffer.init(data:)`, `appendBytes`, `readBuffer`, and `withReadBufferNoCopy` now require real backing storage before copying non-empty payload bytes.
- `appendBytes`, `appendBuffer`, integer/double reads, and debug descriptions now avoid force-unwrapping raw allocation or source buffer pointers.

Remaining proof needed:

- Run login/authorization, contact sync, notification open, media send, GIF/sticker selection, large chat history load, and account switching on Xcode 26.x/iOS 26.x.
- Expected: empty or malformed local TL/API payloads are skipped, serialized as empty where allowed, or fail decode gracefully instead of crashing on `baseAddress`, `data`, or allocation unwraps.

### Avatar, sign-up, chat-list, and markdown graphics hardening

Source: local full-repo static audit of CoreGraphics context/gradient/image boundaries and static regex initialization.

Patch:

- `AuthorizationUI/Sources/AuthorizationSequenceSignUpControllerNode.swift` now falls back to the selected sign-up photo if avatar clipping mask generation or `CGImage` extraction fails.
- `AvatarNode/Sources/AvatarNode.swift` now guards graphics contexts, avatar bubble SVG path conversion, avatar gradients, and optional icon `CGImage` values.
- `AvatarNode/Sources/PeerAvatar.swift` now guards rounded-corner mask generation, blurred-avatar image generation, peer-avatar gradients, and optional icon `CGImage` values.
- `ChatListUI/Sources/ChatListShimmerNode.swift`, `ChatListSearchListPaneNode.swift`, and `Node/ChatListStatusNode.swift` now skip missing gradients/contexts instead of crashing during chat-list shimmer/status rendering.
- `Display/Source/GenerateImage.swift`, `ImageCorners.swift`, `TextNode.swift`, `TransformImageNode.swift`, `UIKitUtils.swift`, `InteractiveTransitionGestureRecognizer.swift`, `ListView.swift`, and `NavigationBackButtonNode.swift` now guard shared image generation, gradients, sample-buffer attachments, overlay casts, empty touch sets, and generated image contexts.
- `ChatTitleActivityNode`, `CheckNode`, `ComponentFlow/RoundedRectangle`, and `ConfettiEffect` now guard missing drawing contexts, gradients, and generated sprite images.
- `TelegramPresentationData/Sources/ChatControllerBackgroundNode.swift`, `ChatMessageBubbleImages.swift`, `PresentationThemeEssentialGraphics.swift`, `Resources/PresentationResources*.swift`, and `WallpaperResources/Sources/WallpaperResources.swift` now guard chat wallpaper gradients, wallpaper preview thumbnails, pattern masks, message bubble masks/tails/outlines, bubble gradient images, chat input icons, settings/list icons, premium/star/gift gradients, and legacy image contexts.
- `TelegramIntents/Sources/TelegramIntents.swift` now falls back safely if the Saved Messages intent avatar gradient or icon image cannot be generated.
- `ChatMessageBackground/Sources/ChatMessageBackground.swift` and `GradientBackground/Sources/SoftwareGradientBackground.swift` now tolerate missing `CGImage` values, invalid gradient input, allocation failure, and drawing-context/image-generation failure during message-background and wallpaper/background animation rendering.
- `BrowserUI/Sources/BrowserMarkdown.swift` now uses optional regex setup for raw HTML tag and formula placeholder scanning. If initialization ever fails, markdown handling falls back to plain/no-op scanning instead of aborting module initialization.

Remaining proof needed:

- Register with a profile photo, edit profile/group avatars, open peers with missing/corrupt avatar resources, scroll/search chat list while shimmer/status nodes are visible, render typing/recording/check/confetti UI, exercise image overlay/tinted text attachments, perform edge/back/list gestures, and open browser/instant-page markdown with raw HTML-like text and formula placeholders.
- Open chats with incoming/outgoing grouped bubbles, tail/no-tail bubbles, outline-only bubbles, shadows, settings/item-list rows, chat input controls, premium/star/gift resource icons, Saved Messages Siri/intent avatar donation, and gradient wallpapers.
- Toggle dynamic wallpapers/backgrounds and open chats that use animated bubble/background image transitions.
- Expected: missing generated images, gradients, contexts, regexes, or `CGImage` assets degrade to fallback render/plain scanning and do not crash.

### #2059 Saved Messages voice waveform hardening

Source: GitHub issue [#2059](https://github.com/TelegramMessenger/Telegram-iOS/issues/2059).

Patch:

- `AudioWaveform/Sources/AudioWaveform.swift` now validates waveform bitstream length/bit depth, avoids raw pointer force unwraps, clamps waveform sample count, prevents negative-length `memcpy`, and avoids division by zero when encoding bitstreams.
- `TelegramUI/Sources/ManagedAudioRecorder.swift` now guards audio input/tone buffer allocations, handles unavailable `Data` base addresses, avoids nil `AudioBuffer.mData` copies, and tolerates empty compressed waveform samples when finalizing a recording.

Remaining proof needed:

- Reproduce recording a voice message, cancelling a recording, sending it to Saved Messages, and reopening Saved Messages on Xcode 26.x/iOS 26.x.
- If the app still freezes, capture Time Profiler while frozen and inspect chat history loading, `ManagedAudioRecorder`, `AudioWaveform`, and `ListMessageFileItemNode` voice layout.

### Media editor / scrubber source hardening

Source: local audit of media editor and scrubber code paths, informed by current iOS media/GIF crash reports and GitHub issues [#2052](https://github.com/TelegramMessenger/Telegram-iOS/issues/2052), [#954](https://github.com/TelegramMessenger/Telegram-iOS/issues/954).

Patch:

- `InstantPageUI/Sources/InstantPageDetailsNode.swift`, `InstantPageScrollableNode.swift`, and `InstantPageTileNode.swift` now skip async drawing if UIKit does not provide a current graphics context.
- `InvisibleInkDustNode/Sources/InvisibleInkDustNode.swift`, `InviteLinksUI/Sources/InviteLinkViewController.swift`, `ItemListPeerItem/Sources/ItemListPeerItem.swift`, `ListMessageItem/Sources/ListMessageFileItemNode.swift`, `LiveLocationPositionNode`, `LiveLocationTimerNode`, and `LocationUI` now guard gradients, tinted icon `CGImage`s, and live-location drawing contexts.
- `ItemListUI/Sources/Items/ItemListEditableItem.swift` now fails its reveal gesture cleanly on an empty touch set.
- `ManagedFile/Sources/ManagedFile.swift` now treats an unavailable `Data` base address as a zero-byte write instead of force-unwrapping it.
- `LegacyMediaPickerUI/Sources/LegacyMediaPickers.swift` now validates Objective-C picker payload dictionaries, required image/asset/video metadata, combine-signal output arrays, and legacy scaled thumbnails/covers before building enqueue items.
- `MediaPlayer/Sources/MediaPlayerTimeTextNode.swift`, `OpenInExternalAppUI/Sources/OpenInAppIconResources.swift`, `PasscodeInputFieldNode`, `PasscodeUI`, `PassportUI`, and `PasswordSetupUI` now guard graphics contexts, generated passcode images, `DrawingContext` creation, backing `CGImage`s, layer contents animations, and empty touch sets.
- `PeerInfoAvatarListNode/Sources/PeerInfoAvatarListNode.swift` now treats avatar strip/shadow gradients and generated shadow `CGImage`s as optional drawing inputs.
- `PhotoResources/Sources/PhotoResources.swift` now uses optional HLS playlist regex setup, skips blurred-thumbnail draws without a backing `CGImage`, and falls back to a solid call-background fill if gradient creation fails.
- `QrCode`, `QrCodeUI`, `RadialStatusNode`, `SemanticStatusNode`, `SettingsUI`, `ShimmerEffect`, `SparseItemGrid`, `StickerResources`, `TabBarUI`, `ReactionSelectionNode`, `PremiumUI`, `TelegramBaseController`, and `TelegramCallsUI` now guard missing CoreGraphics contexts, gradients, mask images, sticker thumbnail `CGImage`s, call/voice-chat avatar images, call sample-buffer attachments, Metal premium pipeline creation, and layer contents animations.
- `Components/ReactionButtonListComponent/Sources/ReactionButtonListComponent.swift` now animates reaction layer contents only when both old and new contents are backed by `CGImage`.
- `ContactListUI/Sources/ContactListNode.swift` now falls back to an empty dropdown icon if a temporary graphics context or image cannot be created.
- `DrawingUI/Sources/ColorPickerScreen.swift`, `DrawingLinkEntityView.swift`, `DrawingLocationEntityView.swift`, `DrawingWeatherEntityView.swift`, `DrawingStickerEntityView.swift`, and `DrawingMetalView.swift` now guard bundled image `CGImage`s, icon gradients, Metal brush pipeline creation, texture clear buffers, and oriented sticker drawing.
- `GalleryUI/Sources/GalleryPagerNode.swift` and `Items/ChatImageGalleryItem.swift` now skip missing fade gradients and missing cached scaled-image `CGImage`s instead of crashing gallery paging/tiling.
- `GraphCore/Sources/Helpers/UIImage+Utils.swift` now handles invalid dimensions and allocation/provider failure in its image generator.
- `ImageTransparency/Sources/ImageTransparency.swift` now falls back to a device RGB color space and returns `nil` when vImage setup/histogram calculation cannot be completed.
- `TelegramUI/Sources/FetchCachedRepresentations.swift` now avoids force-unwrapping `cgImage` values and generated images while writing sticker AJPEG, scaled image, scaled video-first-frame, blurred wallpaper, and album-artwork cached representations.
- `DirectMediaImageCache/Sources/DirectMediaImageCache.swift` now guards thumbnail `CGImage` extraction, RGB565 cache allocation, cached payload header reads, cached data base addresses, and scaled image rendering.
- `TelegramUI/Sources/OpenResolvedUrl.swift` now ignores empty story media-editor result batches instead of force-unwrapping the first upload target.
- `TelegramUI/Sources/TransformOutgoingMessageMedia.swift` now reuses the already-created `CGImage` when generating outgoing-image thumbnails instead of force-unwrapping `UIImage.cgImage`.
- `TelegramUI/Sources/SpotlightContacts.swift` now tolerates missing Core Graphics contexts/images and skips Spotlight avatar generation if the avatar or mask image lacks a `CGImage`.
- `TelegramUI/Components/MediaEditorScreen/Sources/StickerCutoutOutlineView.swift` now balances `CVPixelBufferLockBaseAddress` with `defer`, rejects invalid pixel buffers/base addresses, handles empty contour points, avoids unsafe tolerance unwraps, and removes an unreachable duplicate branch in `BezierPath`.
- `TelegramUI/Components/MediaScrubberComponent/Sources/MediaScrubberComponent.swift` now skips invalid thumbnail `cgImage` values, avoids force-casting layer contents to `CGImage`, and skips the audio-content mask gradient if CoreGraphics cannot create it.
- `MediaEditor/Sources/StickerOutlineRenderPass.swift`, `MediaEditorComposer.swift`, `VideoInputPass.swift`, `AdjustmentsRenderPass.swift`, `HistogramCalculationPass.swift`, `EnhanceRenderPass.swift`, `VideoFinishPass.swift`, and `MediaEditor.swift` now avoid force-unwrapping generated mask images, gradients, drawing contexts, cached Metal textures, and gradient colors.

Remaining proof needed:

- Exercise sticker cutout, media editor crop/trim/scrub, video cover selection, story editor sticker flows, group photo editing, album artwork extraction, sticker AJPEG cache generation, blurred wallpaper cache generation, direct media image cache read/write, outgoing image thumbnail generation, Spotlight contact avatar generation, and #2052 edit-message video-text movement on Xcode 26.x/iOS 26.x.
- Expected: invalid frames, cutout buffers, generated mask images, missing cached textures, nil `cgImage` values, or failed render allocations are skipped/fallback to input texture; editor UI remains responsive and does not crash. #2052 text-position correctness still needs runtime proof.

### Static crash-risk scan

Patch:

- `scripts/custom-client/run_crash_risk_scan.sh` scans changed Swift files for high-confidence force unwraps in media/C-boundary, UIKit touch, CoreGraphics gradient/context, and payload code.
- Current changed-scope scan passes after hardening FFmpeg callbacks, media sample buffers, animation cache reads, notification payload parsing, UIKit gesture recognizers, and extension avatar rendering.
- `scripts/custom-client/run_full_static_audit.sh` records the all-repo Swift file count, changed-file gates, repository-wide crash-risk inventory, configured SwiftLint module pass, whitespace check, and current toolchain blocker.

Regression scenario:

- Run `scripts/custom-client/run_crash_risk_scan.sh` before each bug-fix pass.
- Expected: no changed Swift file contains `try!`, `cgImage!`, `baseAddress!`, `userData!`, `imageBuffer!`, `sampleBuffer!`, `cachedTexture!`, media attachment force casts, FFmpeg frame plane force unwraps, or raw allocation force unwraps covered by the script.

### Notification payload parsing hardening

Source: GitHub issues [#623](https://github.com/TelegramMessenger/Telegram-iOS/issues/623), [#2193](https://github.com/TelegramMessenger/Telegram-iOS/issues/2193), and [#833](https://github.com/TelegramMessenger/Telegram-iOS/issues/833), plus local `AppDelegate` source audit.

Patch:

- `TelegramUI/Sources/AppDelegate.swift` now parses notification payload ids through typed helpers instead of force-casting `userInfo` values to `NSString`.
- `TelegramUI/Sources/SharedNotificationManager.swift` now uses the same typed parsing style for foreground/decrypted notification payloads, deleted-message payloads, read-history payloads, message ids, random ids, and secret-chat encryption ids.
- Delivered-notification cleanup and notification tap handling now ignore invalid numeric ids instead of constructing `PeerId(0)` or crashing on unexpected payload types.
- `Telegram/NotificationService/Sources/NotificationService.swift` now accepts string, numeric, and `NSNumber` payload ids consistently for message/story/call/read-history fields.
- Notification service delivered-notification cleanup now uses the same typed parsing path and ignores malformed ids safely.
- Notification custom emoji glyph generation no longer uses `try!`; malformed emoji assets are skipped instead of crashing the service.
- Notification service media/custom-emoji fetch buffering now clamps source/target ranges and avoids `baseAddress!` when copying fetched resource data.
- Notification avatar rendering now guards missing graphics contexts, color spaces, gradients, and generated fallback images before attaching notification media.
- `Telegram/WidgetKitWidget/PeerNode.swift` now guards widget avatar graphics contexts, gradients, `CGImage` assets, and saved-messages fallback generation.
- Watch `OpusKit` and `RLottieKit` packages now guard audio/lottie buffer base addresses instead of force-unwrapping them.
- Watch `TDShim` now handles TDLib query encoding/response parsing failures with typed errors/logging instead of `try!` and forced casts.

Remaining proof needed:

- Reproduce iPad notification delivery with passcode/hidden previews, notification tap handling, widget avatar rendering, and Watch notification delivery on Xcode 26.x/iOS 26.x/watchOS hardware.
- Reproduce generic notification-body reports #2037/#833 with mutable-content notification payloads and encrypted payload decryption enabled.
- Expected: malformed or unexpected notification payload fields are ignored safely; notification cleanup/open handling must not crash or block the app. Message body rendering still needs runtime proof because APNs/server payload contents remain server-authoritative.

### Chat opening / history callback hardening

Source: GitHub issues [#1739](https://github.com/TelegramMessenger/Telegram-iOS/issues/1739), [#1668](https://github.com/TelegramMessenger/Telegram-iOS/issues/1668), plus local `ChatController` / `ChatHistoryListNode` source audit.

Patch:

- `TelegramUI/Sources/ChatController.swift` no longer force-unwraps one-byte callback payload buffers for gift offers, copy-protection prompts, suggested posts, or thread-navigation callbacks; it reads `Data.first` after the existing count check.
- `TelegramUI/Sources/ChatController.swift` ignores empty `sendScheduledMessagesNow` batches instead of force-unwrapping `messageIds.first`.
- `TelegramUI/Sources/ChatHistoryListNode.swift` now renders an empty grouped-message transition as a lightweight list hole item instead of indexing `messages[0]`.
- `ChatListUI/Sources/Node/ChatListNode.swift`, `DirectionalPanGesture/Sources/DirectionalPanGestureRecognizer.swift`, and peer-info media/story pane recognizers now fail cleanly if UIKit delivers an empty touch set instead of force-unwrapping the first touch.
- `TelegramUI/Sources/ChatInterfaceStateContextMenus.swift` now reduces action options from an optional first value instead of force-unwrapping `optionsMap.values.first`.
- `ListMessageItem/Sources/ListMessageHoleItem.swift` exposes the existing hole item for this cross-module fallback.
- `TelegramUI/Sources/SharedAccountContext.swift` now returns the existing lightweight hole item for empty chat-message preview input instead of force-unwrapping `messages.first`.
- `TelegramUI/Sources/SharedAccountContext.swift` treats an empty bot-preview editor result as cancellation instead of force-unwrapping `results.first`.
- `TelegramUI/Sources/SharedAccountContext.swift` now uses a safe first peer id when starting a one-recipient call from selection UI.
- `TelegramUI/Sources/ChatControllerOpenAttachmentMenu.swift` now uses safe first-phone extraction for peer/device contacts instead of direct `phoneNumbers[0]` indexing.

Remaining proof needed:

- Reproduce opening chats after sticker/GIF activity, secret-chat sticker history, incoming-message updates while scrolling, scheduled-message actions, contact attachment flows, empty-preview callers, peer media selection gestures, and bot callback buttons on Xcode 26.x/iOS 26.x.
- Expected: empty or malformed local callback/history/contact/touch batches are ignored or displayed as transient loading state; chat opening, peer media selection, and contact attachment must not crash. Scroll freezes still need Time Profiler evidence because they may be lock/layout churn rather than a crash.

### Siri/widget and broadcast extension hardening

Source: local extension source audit, informed by notification/Siri issue feed including [#1960](https://github.com/TelegramMessenger/Telegram-iOS/issues/1960).

Patch:

- `Telegram/SiriIntents/IntentHandler.swift` now ignores malformed message identifiers, avoids single-item array indexing when returning filtered intent sections, and falls back safely when avatar/tinted-image CoreGraphics resources are unavailable.
- `Telegram/BroadcastUpload/BroadcastUploadExtension.swift` now guards audio-converter output buffer pointers and optional CoreMedia sample attachments before marking frames as display-immediate.

Remaining proof needed:

- Reproduce Siri/Shortcuts friend selection, widget friend option population, saved messages avatar generation, and broadcast upload start/stop on Xcode 26.x/iOS 26.x.
- Expected: malformed intent identifiers, missing avatar assets, failed graphics contexts, or missing sample attachments must not crash extensions. Functional Siri matching and broadcast delivery still need device proof.

### WidgetKit / Watch package hardening

Source: `scripts/custom-client/run_full_static_audit.sh` repository-wide crash-risk inventory.

Patch:

- `Telegram/WidgetKitWidget/PeerNode.swift` now returns fallback avatars when widget CoreGraphics contexts, gradients, tinted icons, or `CGImage` assets are unavailable.
- `Telegram/WatchApp/Packages/OpusKit` now guards Opus encoder/decoder buffer pointers and returns typed errors instead of force-unwrapping base addresses.
- `Telegram/WatchApp/Packages/RLottieKit` now treats missing render/decompression buffers as nil/error instead of force-unwrapping base addresses.
- `Telegram/WatchApp/Packages/TDShim` now logs TDLib async query encoding failures and throws typed errors for malformed execute responses instead of using `try!` / forced response casts.

Static proof:

- `swift test` passes for `Telegram/WatchApp/Packages/OpusKit` with 8 tests.
- `swift test` passes for `Telegram/WatchApp/Packages/RLottieKit` with 7 tests.
- TDShim path lint and crash-risk scan pass; full TDShim package build was stopped after several minutes because the external TDLibFramework build produced no further output.

Remaining proof needed:

- Run WidgetKit, Watch notification, Watch voice note, and Watch animated sticker/lottie flows on the required Xcode 26.x/watchOS/iOS hardware toolchain.
