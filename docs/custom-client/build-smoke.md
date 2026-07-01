# Build Smoke Log

Last run: 2026-07-02

## Project Generation Smoke Test

Purpose: verify the upstream build path as far as possible without real signing credentials.

Latest command shape:

```sh
python3 build-system/Make/Make.py \
  --overrideXcodeVersion \
  --cacheDir="$HOME/telegram-bazel-cache" \
  generateProject \
  --configurationPath=build-system/appstore-configuration.json \
  --xcodeManagedCodesigning \
  --disableProvisioningProfiles \
  --disableExtensions
```

Result:

- Downloaded and verified `build-input/bazel-8.4.2-darwin-arm64`.
- Built `//Telegram:Telegram_xcodeproj` runner successfully.
- Failed during Xcode project generation Bazel analysis at `//Telegram:Telegram`.
- No installable `Telegram.app` was produced.

Blocking error:

```text
Found Icon Composer .icon bundles among the assigned app_icons. These are only supported on Xcode 26 or later.
```

Conclusion: local device build/install is blocked by the installed Xcode `16.2`. The upstream repo currently requires Xcode `26.2`.

## Device / Install Check

Current local state:

- XcodeBuildMCP is available, but only simulator workflow tools are enabled in this session.
- XcodeBuildMCP session defaults are empty: no project/workspace, scheme, simulator, or device is configured.
- `xcodebuild -showsdks` reports iOS SDK `18.2`, while current upstream Telegram iOS requires Xcode `26.2`.
- `xcrun devicectl list devices` currently reports iOS-like device records in sanitized output, including available records. Device visibility is not the main blocker.
- No untracked development configuration with a personal `api_id`, `api_hash`, bundle id, and team id currently exists in the workspace.

Conclusion: installation on a physical iPhone is not attempted in this state because project generation fails before producing an app bundle. It requires Xcode `26.2`, a valid local signing/development configuration, a generated Xcode project, and then an installable `.app` or archive.
