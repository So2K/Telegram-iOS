#!/bin/bash
# Compile the complete SuperGram app through the warm rules_xcodeproj
# Bazel output base without going through xcodebuild.
#
# Usage: scripts/supergram/build_check.sh [target-label] [log-name] [--require-notification-service]
#   target-label defaults to //Telegram:Telegram
#
# Prints the log path, the error summary and the final Bazel status.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"

TARGET="${1:-//Telegram:Telegram}"
LOG_NAME="${2:-build-$(date +%Y%m%d-%H%M%S)}"
# SuperGram: the build number has to reach the build itself (xcodeproj.bazelrc pins 10000), otherwise the
# nested frameworks inside the app keep 10000 while make_ipa.sh stamps the requested number on the app.
BUILD_NUMBER="${BUILD_NUMBER:-10000}"
OUTPUT_BASE="${BUILD_OUTPUT_BASE:-}"
LOG_DIR="$REPO/build-output/ultra"
LOG="$LOG_DIR/$LOG_NAME.log"
mkdir -p "$LOG_DIR"
[[ "$TARGET" = "//Telegram:Telegram" || "$TARGET" = "@@//Telegram:Telegram" ]] || { echo "only the complete Telegram app target is supported"; exit 1; }
[[ "$LOG_NAME" =~ ^[A-Za-z0-9._-]+$ && "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "invalid log/build number"; exit 1; }
SERVICE_ARGS=()
case "${3:-}" in
  "") ;;
  --require-notification-service) SERVICE_ARGS=(--require-notification-service) ;;
  *) echo "unknown full-build option"; exit 1 ;;
esac
[ "$#" -le 3 ] || { echo "too many full-build arguments"; exit 1; }
PROJECT="$REPO/Telegram/Telegram.xcodeproj/project.pbxproj"
ARTIFACT_HELPER="$REPO/scripts/supergram/build_artifact.py"
APP_VERSION=$(python3 -c 'import json;print(json.load(open("versions.json"))["app"])')
RECEIPT="$LOG_DIR/$LOG_NAME.receipt.json"
# This receipt belongs to this named build attempt; a failed rerun cannot reuse it.
rm -f "$RECEIPT"
METADATA=$(mktemp)
trap 'rm -f "$METADATA"' EXIT
if ! python3 "$ARTIFACT_HELPER" derive --project "$PROJECT" ${SERVICE_ARGS[@]+"${SERVICE_ARGS[@]}"} --output "$METADATA"; then exit 1; fi
OUTPUT_GROUP=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["output_group"])' "$METADATA")
APP_RELATIVE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["app_execroot_relative_path"])' "$METADATA")
if [ -z "$OUTPUT_BASE" ]; then
  OUTPUT_BASE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["generated_output_base"])' "$METADATA")
fi
APP="$OUTPUT_BASE/execroot/_main/$APP_RELATIVE"

env -i HOME="$HOME" USER="$USER" TERM=dumb LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 PATH=/bin:/usr/bin:/usr/sbin \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer BUILD_WORKSPACE_DIRECTORY="$REPO" \
  "$REPO/build-input/bazel-8.4.2-darwin-arm64" --noworkspace_rc \
  --bazelrc=Telegram/Telegram.xcodeproj/rules_xcodeproj/bazel/xcodeproj.bazelrc --bazelrc=.bazelrc \
  --output_base "$OUTPUT_BASE" build \
  "--define=buildNumber=$BUILD_NUMBER" \
  --xcode_version=16C5032a --repo_env=DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  --repo_env=USE_CLANG_CL=16C5032a --repo_env=XCODE_VERSION=16C5032a \
  --bes_upload_mode=NOWAIT_FOR_UPLOAD_COMPLETE --config=_rules_xcodeproj_build --color=no --curses=no \
  --keep_going \
  "--output_groups=$OUTPUT_GROUP" \
  @@rules_xcodeproj++rules_repos+rules_xcodeproj_generated//generator/Telegram/Telegram_xcodeproj:Telegram_xcodeproj \
  > "$LOG" 2>&1
STATUS=$?

echo "log: $LOG"
echo "exit: $STATUS"
grep -E "error:" "$LOG" | sed -E "s#^$REPO/##" | sort -u | head -200
grep -E "^ERROR:|Build completed successfully|Build did NOT complete successfully|FAILED: Build|Elapsed time" "$LOG" | tail -20
if [ "$STATUS" != "0" ]; then exit "$STATUS"; fi
if ! python3 "$ARTIFACT_HELPER" capture --project "$PROJECT" --app "$APP" --build "$BUILD_NUMBER" --version "$APP_VERSION" --receipt "$RECEIPT" ${SERVICE_ARGS[@]+"${SERVICE_ARGS[@]}"} --output "$METADATA"; then
  echo "full command succeeded, but requested app/extension/framework artifact validation failed"
  exit 1
fi
echo "verified full-app receipt: $RECEIPT"
exit 0
