# Custom Client Stabilization Track

Last reviewed: 2026-07-02

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

This machine currently reports Xcode `16.2`. The upstream build system downloaded the pinned local Bazel binary to `build-input/bazel-8.4.2-darwin-arm64`, so Bazel itself is no longer the blocker.

A project-generation smoke test with `--overrideXcodeVersion`, `--disableProvisioningProfiles`, and `--disableExtensions` reached Bazel analysis, then failed because upstream Telegram now assigns Icon Composer `.icon` bundles that are only supported by Xcode 26 or later. Build, profiling, and device installation remain blocked until Xcode is upgraded to the required Xcode `26.2` toolchain.

The connected iPhone is visible through `xcrun devicectl`; device visibility is not the active blocker. The missing pieces for a physical install are Xcode `26.2`, a local development configuration with personal `api_id` / `api_hash` / bundle id / team id, generated project files, and a signed app bundle.

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
