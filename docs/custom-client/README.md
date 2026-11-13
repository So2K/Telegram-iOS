# Custom Client Stabilization Track

Last reviewed: 2026-10-10

## Fix guides (аудит 2026-09-15)

Разбор багов с готовыми инструкциями «какой файл/строка, что менять, как проверять» — начните с навигатора:

- [`fix-guide.md`](fix-guide.md) — навигатор: топ-блокеры, порядок волн, чеклист ревью, связь с `SUPERGRAM_ULTRA_PLAN.md`.
- [`fix-guide-media.md`](fix-guide-media.md) — overlay/мини-плеер (MEDIA-25/26/27, VIS-14), плеер, gallery, жесты, HLS, сеть.
- [`fix-guide-voice.md`](fix-guide-voice.md) — локальная расшифровка голосовых и её настройки.
- [`fix-guide-push.md`](fix-guide-push.md) — расширения, push, app group, bundle id, локальный fallback.
- [`fix-guide-build.md`](fix-guide-build.md) — сборка, подпись, иконки, релиз-чеклист.
- [`fix-guide-misc.md`](fix-guide-misc.md) — реклама, hideStories, override api_id, остатки бэклога.

## Baseline

- Upstream base: `TelegramMessenger/Telegram-iOS` `master`.
- Working branch: `codex/stable-custom-client`.
- Reference remote: `swiftgram` (`Swiftgram/Telegram-iOS`) for small, reviewable iOS patches only.
- Desktop references: AyuGram and 64Gram are not merge bases; use them only for behavior ideas and issue triage.

## Local Policy

- Do not spoof Premium state, subscription state, server limits, API capabilities, or download entitlements.
- Local-only cleanup is allowed: hiding Stories surfaces, hiding upsell UI, and avoiding client-side preloads when a local switch disables a surface.
- Keep each patch small enough to cherry-pick or drop during upstream rebases.

## Current Implementation

- Added `ExperimentalUISettings.hideStories`, defaulting to `false`.
- Added a Debug settings switch: `Hide Stories [Restart App]`.
- When enabled at startup, the root chat list hides the Stories header, skips the main story/archive subscriptions, skips upload progress observation, and clears story preload resources before any media fetch starts.
- Added a login-screen API credentials action for development builds. The gear button on the welcome screen stores a local `api_id` / `api_hash` override from `my.telegram.org/apps`; it does not store auth tokens, spoof sessions, or unlock server-side capabilities.

## Toolchain Status

Upstream `versions.json` currently requires:

- Xcode `26.2`
- Bazel `8.4.2`
- macOS `26`

This machine uses Xcode `16.2` / SDK `18.2`, macOS `15.1`, and the pinned local Bazel binary at `build-input/bazel-8.4.2-darwin-arm64`. The original upstream toolchain check still fails; it does not describe the outcome of the current local compatibility build.

With the existing local compatibility changes and explicit Xcode override, complete device builds succeed. Main-only `10030` was signed, installed and checked on the phone; unsigned `10032` also compiled NotificationService. Main-only `10033`, `10034` and `10035` completed with matching app and five-framework build numbers. These are historical checkpoints, not the latest installed-version claim. No OS or Xcode upgrade was performed. The latest build, signing, installation, source-review coverage and phone checks are recorded separately in [the stability review](stability-review-2026-10-07.md).

The remaining NotificationService signing blocker is a genuine compatible profile for `app.tomato7991.lime1486.NotificationService`, team `G6TLPRYW6Y`, and App Group `group.ffcd1c12e1a9728e.1`. A main-only IPA does not repair sender/preview processing in encrypted incoming push. Apple FoundationModels is unavailable in the installed SDK; generation is not entirely local. Gallery OS picture-in-picture remains disabled and has not been restored by this stability pass.

Run:

```sh
scripts/custom-client/check_toolchain.sh
```

## Static Analysis

SwiftLint is wired as a free local static-analysis gate.

Run on changed Swift files:

```sh
scripts/custom-client/run_static_analysis.sh
```

Run on one file:

```sh
scripts/custom-client/run_static_analysis.sh --path submodules/AuthorizationUI/Sources/AuthorizationApiCredentials.swift
```

Run the broader configured module pass:

```sh
scripts/custom-client/run_static_analysis.sh --all
```

Use the changed-file mode before every patch. Use `--all` before a release candidate; it can expose pre-existing upstream style issues outside the current patch.

Run the full audit report:

```sh
scripts/custom-client/run_full_static_audit.sh
```

The report is written to `docs/custom-client/full-static-audit.md`. Current audit scope counts all tracked Swift files, runs the changed-file crash-risk gate, records a repository-wide crash-risk inventory, runs changed-file SwiftLint, runs the configured SwiftLint module pass, and records the toolchain/build blocker.

A custom crash-risk scan is also wired for high-confidence force unwraps at media/C/payload, UIKit touch, and CoreGraphics context boundaries:

```sh
scripts/custom-client/run_crash_risk_scan.sh
```

It scans changed Swift files by default. Use `--all` before a release candidate, and `--path file.swift` while working on a specific subsystem.

## Build Flow

1. Copy `build-system/custom-client-template-development-configuration.json` to an untracked local config.
2. Fill in your own `api_id`, `api_hash`, bundle id, and team id.
3. Generate the Xcode project:

```sh
python3 build-system/Make/Make.py \
  --cacheDir="$HOME/telegram-bazel-cache" \
  generateProject \
  --configurationPath=build-system/custom-client-development-configuration.json \
  --xcodeManagedCodesigning
```

For simulator-only work with manual profiles unavailable, follow upstream README guidance and use `--disableProvisioningProfiles` with an appropriate configuration.

## Issue Audit Flow

Refresh GitHub bug candidates:

```sh
scripts/custom-client/fetch_github_bug_backlog.sh --output docs/custom-client/github-bug-snapshot.md
```

Use `GITHUB_TOKEN` if rate limits hit:

```sh
GITHUB_TOKEN=... scripts/custom-client/fetch_github_bug_backlog.sh
```

Patch rule: do not fix from a vague title alone. Each bug fix should include the issue link, suspected subsystem, reproduction path, and post-fix regression scenario.
