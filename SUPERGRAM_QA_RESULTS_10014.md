# SuperGram QA results: baseline 10014

## Environment

| Field | Value |
| --- | --- |
| Client | SuperGram 12.8 (10014) |
| Device | iPhone 15 Pro |
| iOS | 27.0 |
| UDID | `00008130-0004298110698D3A` |
| Run | `2026-08-22` |
| Artifacts | `output/qa/10014-baseline-20260822/` |

## Results

| ID | Result | Evidence / observation |
| --- | --- | --- |
| PRE-06 | PASS | Clean chat list opened with no stale player overlay |
| LIFE-02 | PASS | Warm resume from Home captured in about 424 ms; settled layout was correct |
| LIFE-03 | PASS | App returned to the same Data and Storage screen |
| LIST-01 | PASS | Chat list rendered correctly after vertical scroll |
| LIST-02 | PASS | Five rapid scroll events completed without blank cells or a hang |
| LIST-03 | PASS | Chat folder switched and rendered correct contents |
| LIST-04 | PARTIAL | One 45-degree gesture did not switch folders; full 20-gesture run remains |
| LIST-07 | PARTIAL | Search UI and loading/empty states rendered; hardware keyboard layout blocked the intended Latin query |
| CHAT-02 | PASS | Media-heavy DTF channel became usable in about 428 ms with no black screen |
| MEDIA-01 | PASS | Gallery opened in about 425 ms |
| MEDIA-25 | FAIL | Detached round-video overlay was previously reproduced across list/profile screens |
| MEDIA-26 | FAIL | Global video-message header can stack with chat/folder headers |
| MEDIA-27 | FAIL | `Unmute` tooltip remained over the bottom input/navigation region after 3.5 seconds |
| ADS-01 | PASS | No sponsored message appeared in the checked public channel |
| VOICE-01 | PASS | Cached transcript appeared in about 626 ms in the earlier baseline run |
| VOICE-02 | PASS | Fresh short Russian voice message was transcribed successfully |
| PUSH-03 | PASS | A real FerriteLabs Bugs message produced a foreground in-app banner while Settings was open |
| PUSH-05 | BLOCKED | No incoming message arrived during the 15-second background observation |
| VIS-02 | PASS | Settings/profile surfaces rendered without square glass panels |
| VIS-08 | PASS | Data and Storage controls rendered and remained clickable |
| VIS-14 | FAIL | Player-related overlays can occupy header and bottom-control layers simultaneously |
| PERF-02 | PASS | Current sampled chat opens: roughly 0.43-1.15 seconds, no black screen |

## Confirmed root causes

### Bottom Unmute overlay

`ChatControllerNode` schedules the volume-button tooltip for every visible playable non-round video after 2.5 seconds. The tooltip is unrelated to playback controls and occupies the bottom interaction area for 3.5 seconds.

### Detached round-video overlay

`SharedMediaPlayer` owns an `OverlayInstantVideoNode` at `.secondaryOverlay` priority. While the original chat cell is visible, its `.embedded` video node keeps the shared content. When the cell disappears or another screen opens, the overlay acquires the content and the global overlay controller moves it onscreen. The global playback header remains active with the same playlist.

## Baseline fixes selected

- Disable the standalone video-unmute tooltip.
- Keep round-video playback inside a visible embedded message.
- When an instant-video node becomes detached, stop its playlist before the floating overlay is shown.
- Leave regular gallery playback and photo zoom behavior unchanged.

## Required verification on the next build

1. Round video plays normally while its message is visible.
2. Scrolling the message away stops playback without showing a floating circle.
3. Leaving the chat removes the global `Video Message` header.
4. Opening an autoplay-capable public channel does not show the bottom `Unmute` tooltip.
5. Voice messages still use the shared player normally.
6. No new Telegram/SuperGram crash or hang report appears.
