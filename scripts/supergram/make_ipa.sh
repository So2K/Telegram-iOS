#!/bin/bash
# Package the Bazel-built Telegram.app as a signed SuperGram IPA.
#
# Usage: scripts/supergram/make_ipa.sh <build-number> [tag] [--install] [--allow-no-notification-extensions] --build-receipt=<path> [--check-only] [--notification-service --strict-signer=<path> --signing-certificate=<public-cert>]
#   Run scripts/supergram/build_check.sh //Telegram:Telegram first.
#   NotificationService and compatible profiles are required by default.
#   NotificationContent is optional and validated if present.
#   The explicit legacy opt-out packages the app without repairing notifications.
#
# Signing material lives in ipa-signing-work/ (gitignored). The p12 password is
# read from ipa-signing-work/secrets/certificate_info.txt and never printed.
set -euo pipefail
export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO"

BUILD_NUMBER="${1:?build number required, e.g. 10017}"
shift
TAG="Ultra"
if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then
  TAG="$1"
  shift
fi
INSTALL=""
ALLOW_NO_NOTIFICATION_EXTENSIONS=0
BUILD_RECEIPT=""
CHECK_ONLY=0
NOTIFICATION_SERVICE=0
STRICT_SIGNER=""
SIGNING_CERTIFICATE=""
for option in "$@"; do
  case "$option" in
    --install) INSTALL=--install ;;
    --build-receipt=*) BUILD_RECEIPT="${option#*=}" ;;
    --check-only) CHECK_ONLY=1 ;;
    --notification-service) NOTIFICATION_SERVICE=1 ;;
    --strict-signer=*) STRICT_SIGNER="${option#*=}" ;;
    --signing-certificate=*) SIGNING_CERTIFICATE="${option#*=}" ;;
    --allow-no-notification-extensions) ALLOW_NO_NOTIFICATION_EXTENSIONS=1 ;;
    *) echo "unknown packaging option: $option"; exit 1 ;;
  esac
done
if [ "$NOTIFICATION_SERVICE" = "1" ]; then
  [ "$ALLOW_NO_NOTIFICATION_EXTENSIONS" = "0" ] || { echo "notification-service and legacy opt-out are mutually exclusive"; exit 1; }
  [ -n "$STRICT_SIGNER" ] && [ -n "$SIGNING_CERTIFICATE" ] || { echo "notification-service requires an explicit reviewed --strict-signer and public --signing-certificate"; exit 1; }
elif [ -n "$STRICT_SIGNER" ] || [ -n "$SIGNING_CERTIFICATE" ]; then
  echo "strict-signer/signing-certificate require the explicit notification-service opt-in"; exit 1
fi

BUNDLE_ID=app.tomato7991.lime1486
TEAM_ID=G6TLPRYW6Y
APP_GROUP=group.ffcd1c12e1a9728e.1
DEVICE_ID=00008130-0004298110698D3A
APP_VERSION=$(python3 -c 'import json;print(json.load(open("versions.json"))["app"])')
OUTPUT_BASE="${BUILD_OUTPUT_BASE:-}"
PROJECT="$REPO/Telegram/Telegram.xcodeproj/project.pbxproj"
ARTIFACT_HELPER="$REPO/scripts/supergram/build_artifact.py"
SECRETS=ipa-signing-work/secrets/$DEVICE_ID
ENTITLEMENTS=ipa-signing-work/entitlements/SuperGram-10016.entitlements
ZSIGN=ipa-signing-work/tools/zsign-src/bin/zsign
STAGE=output/SuperGram-$BUILD_NUMBER-stage
IPA=output/SuperGram-$APP_VERSION-$BUILD_NUMBER-$TAG.ipa
VALIDATOR="$REPO/scripts/supergram/validate_notification_package.py"

[ -n "$BUILD_RECEIPT" ] || { echo "explicit successful full-app --build-receipt is required"; exit 1; }
ARTIFACT_ARGS=()
if [ "$ALLOW_NO_NOTIFICATION_EXTENSIONS" = "1" ]; then
  ARTIFACT_ARGS=(--legacy)
else
  ARTIFACT_ARGS=(--require-notification-service)
fi
METADATA=$(mktemp)
SIGNING_INPUTS=""
VERIFY=""
cleanup() {
  rm -f "$METADATA"
  [ -z "$SIGNING_INPUTS" ] || rm -rf "$SIGNING_INPUTS"
  [ -z "$VERIFY" ] || rm -rf "$VERIFY"
}
trap cleanup EXIT
python3 "$ARTIFACT_HELPER" derive --project "$PROJECT" "${ARTIFACT_ARGS[@]}" --output "$METADATA"
APP_RELATIVE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["app_execroot_relative_path"])' "$METADATA")
if [ -z "$OUTPUT_BASE" ]; then
  OUTPUT_BASE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["generated_output_base"])' "$METADATA")
fi
APP="$OUTPUT_BASE/execroot/_main/$APP_RELATIVE"
# Validate unmodified source metadata/fingerprint before staging can mask a stale build.
python3 "$ARTIFACT_HELPER" verify --project "$PROJECT" --app "$APP" --build "$BUILD_NUMBER" --version "$APP_VERSION" --receipt "$BUILD_RECEIPT" "${ARTIFACT_ARGS[@]}" --output "$METADATA"
if [ "$CHECK_ONLY" = "1" ]; then
  echo "full-app artifact preflight PASS; no staging, profile read, signing or installation performed"
  exit 0
fi

rm -rf "$STAGE"
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/Telegram.app"
chmod -R u+w "$STAGE"

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier $BUNDLE_ID" \
  -c 'Set :CFBundleDisplayName SuperGram' \
  -c 'Set :CFBundleName SuperGram' \
  -c "Set :CFBundleShortVersionString $APP_VERSION" \
  -c "Set :CFBundleVersion $BUILD_NUMBER" \
  -c "Set :CFBundleURLTypes:0:CFBundleURLName $BUNDLE_ID" \
  -c "Set :CFBundleURLTypes:1:CFBundleURLName $BUNDLE_ID.compatibility" \
  -c "Set :BGTaskSchedulerPermittedIdentifiers:0 $BUNDLE_ID.refresh" \
  -c "Set :BGTaskSchedulerPermittedIdentifiers:1 $BUNDLE_ID.cleanup" \
  -c "Set :BGTaskSchedulerPermittedIdentifiers:2 $BUNDLE_ID.upload.*" \
  "$STAGE/Payload/Telegram.app/Info.plist"

# Source versions were verified, so only the approved service identity is rewritten.
if [ "$ALLOW_NO_NOTIFICATION_EXTENSIONS" != "1" ]; then
  SERVICE_PATH=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["artifact"]["extensions"][0]["path"])' "$METADATA")
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID.NotificationService" "$STAGE/Payload/Telegram.app/$SERVICE_PATH/Info.plist"
fi

# Public metadata/resource admission completes before the password/key read.
VALIDATION_ARGS=(--build "$BUILD_NUMBER" --version "$APP_VERSION" --bundle-id "$BUNDLE_ID"
  --team-id "$TEAM_ID" --app-group "$APP_GROUP" --device-id "$DEVICE_ID")
SIGNED_CERTIFICATE_ARGS=()
if [ "$NOTIFICATION_SERVICE" = "1" ]; then
  # These owned metadata copies are outside STAGE and never enter the archive.
  SIGNING_INPUTS=$(umask 0077; mktemp -d "${TMPDIR:-/tmp}/supergram-signing-inputs.XXXXXX")
  chmod 700 "$SIGNING_INPUTS"
  if ! python3 "$REPO/scripts/supergram/prepare_notification_signing.py" "$STAGE/Payload/Telegram.app" \
    "${VALIDATION_ARGS[@]}" --main-profile "$SECRETS.mobileprovision" \
    --service-profile "${NOTIFICATION_SERVICE_PROFILE:-$SECRETS-NotificationService.mobileprovision}" \
    --main-entitlements "$ENTITLEMENTS" --signing-certificate "$SIGNING_CERTIFICATE" \
    --strict-signer "$STRICT_SIGNER" --input-directory "$SIGNING_INPUTS" --output "$METADATA"; then
    echo "notification-service preflight failed before password/private-key access"
    rm -rf "$STAGE"
    exit 1
  fi
  SIGNING_MAP=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["signing_map"])' "$METADATA")
  PUBLIC_CERTIFICATE=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["certificate"])' "$METADATA")
  SIGNED_CERTIFICATE_ARGS=(--signing-certificate "$PUBLIC_CERTIFICATE")
else
  PREFLIGHT_ARGS=("${VALIDATION_ARGS[@]}" --main-profile "$SECRETS.mobileprovision")
  if [ "$ALLOW_NO_NOTIFICATION_EXTENSIONS" = "1" ]; then
    PREFLIGHT_ARGS+=(--allow-no-notification-extensions)
    VALIDATION_ARGS+=(--allow-no-notification-extensions)
    echo "legacy packaging: notification extensions are absent; sender/preview processing is not repaired"
  else
    PREFLIGHT_ARGS+=(--service-profile "${NOTIFICATION_SERVICE_PROFILE:-$SECRETS-NotificationService.mobileprovision}"
      --content-profile "${NOTIFICATION_CONTENT_PROFILE:-$SECRETS-NotificationContent.mobileprovision}")
  fi
  if ! python3 "$VALIDATOR" "$STAGE/Payload/Telegram.app" "${PREFLIGHT_ARGS[@]}"; then
    echo "notification packaging preflight failed; build NotificationService and provide a matching same-team profile"
    echo "required bundle ID: $BUNDLE_ID.NotificationService; shared group: $APP_GROUP"
    echo "NotificationContent is optional and requires its own matching profile if embedded"
    echo "only an explicitly requested legacy package may use --allow-no-notification-extensions"
    rm -rf "$STAGE"
    exit 1
  fi
  if [ "$ALLOW_NO_NOTIFICATION_EXTENSIONS" != "1" ]; then
    echo "notification profiles validated, but this signer applies one entitlement file to all bundles"
    echo "per-bundle entitlement signing is required before an extension-enabled IPA can be produced"
    rm -rf "$STAGE"
    exit 1
  fi

fi

P12_PASSWORD="$(sed -n 's/^Password:[[:space:]]*//p' ipa-signing-work/secrets/certificate_info.txt | head -n1)"
if [ "$NOTIFICATION_SERVICE" = "1" ]; then
  # The P12 may select a different leaf than -c. The strict signer checks its
  # actual selected leaf against every profile; the validator binds it to -c.
  if ! "$STRICT_SIGNER" -f -k "$SECRETS.p12" -p "$P12_PASSWORD" -c "$PUBLIC_CERTIFICATE" \
    --bundle-signing-map "$SIGNING_MAP" "$STAGE/Payload/Telegram.app" > "build-output/ultra/zsign-$BUILD_NUMBER.log" 2>&1; then
    unset P12_PASSWORD
    exit 1
  fi
  unset P12_PASSWORD
  python3 "$VALIDATOR" "$STAGE/Payload/Telegram.app" "${VALIDATION_ARGS[@]}" --signed ${SIGNED_CERTIFICATE_ARGS[@]+"${SIGNED_CERTIFICATE_ARGS[@]}"}
  codesign --verify --deep --strict "$STAGE/Payload/Telegram.app"
  # Archive only after selected-leaf and deep signature checks pass.
  /usr/bin/ditto -c -k --keepParent "$STAGE/Payload" "$IPA"
else
  "$ZSIGN" -f -z 9 -k "$SECRETS.p12" -p "$P12_PASSWORD" -m "$SECRETS.mobileprovision" \
    -e "$ENTITLEMENTS" -o "$IPA" "$STAGE/Payload/Telegram.app" > "build-output/ultra/zsign-$BUILD_NUMBER.log" 2>&1
  unset P12_PASSWORD
fi

unzip -tq "$IPA" > /dev/null
ROOTS=$(zipinfo -1 "$IPA" | cut -d/ -f1 | sort -u | tr '\n' ' ')
[ "$ROOTS" = "Payload " ] || { echo "unexpected zip roots: $ROOTS"; exit 1; }

VERIFY=$(mktemp -d)
unzip -q "$IPA" -d "$VERIFY"
python3 "$VALIDATOR" "$VERIFY/Payload/Telegram.app" "${VALIDATION_ARGS[@]}" --signed ${SIGNED_CERTIFICATE_ARGS[@]+"${SIGNED_CERTIFICATE_ARGS[@]}"}
codesign --verify --deep --strict "$VERIFY/Payload/Telegram.app"
codesign -dvv "$VERIFY/Payload/Telegram.app" 2>&1 | grep -E "^Identifier=|^TeamIdentifier=" || true
echo "CFBundleVersion: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$VERIFY/Payload/Telegram.app/Info.plist")"
rm -rf "$VERIFY" "$STAGE"

ls -lh "$IPA"
shasum -a 256 "$IPA"

if [ "$INSTALL" = "--install" ]; then
  xcrun devicectl device install app --device "$DEVICE_ID" "$IPA"
fi
