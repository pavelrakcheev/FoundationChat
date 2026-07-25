#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="FoundationChat"
BUNDLE_ID="dev.pavelrakcheev.FoundationChat"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Resources/FoundationChat.entitlements"
ICON_SOURCE="$ROOT_DIR/Resources/AppIcon.icon"

if [[ -d "/Applications/Xcode-beta.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcrun swift build --package-path "$ROOT_DIR"
BUILD_DIR="$(xcrun swift build --package-path "$ROOT_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"

if [[ -d "$ICON_SOURCE" ]]; then
  ICON_ASSET_DIR="$(mktemp -d "$DIST_DIR/IconAssets.XXXXXX")"
  xcrun actool "$ICON_SOURCE" \
    --compile "$ICON_ASSET_DIR" \
    --platform macosx \
    --minimum-deployment-target 27.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ICON_ASSET_DIR/icon-info.plist" \
    --warnings \
    --notices \
    --output-format human-readable-text
  cp "$ICON_ASSET_DIR/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
  cp "$ICON_ASSET_DIR/Assets.car" "$APP_RESOURCES/Assets.car"
fi

INTENTS_TEMP_DIR="$(mktemp -d "$DIST_DIR/AppIntents.XXXXXX")"
find "$ROOT_DIR/Sources/FoundationChat" -name '*.swift' -print \
  >"$INTENTS_TEMP_DIR/sources.list"
find "$ROOT_DIR/.build" -name '*.swiftconstvalues' \
  -path '*FoundationChat-p.build*' -print \
  >"$INTENTS_TEMP_DIR/const-values.list"
XCODE_BUILD_VERSION="$(xcodebuild -version | awk '/Build version/{print $3}')"
SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
xcrun appintentsmetadataprocessor \
  --output "$APP_RESOURCES" \
  --toolchain-dir "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain" \
  --module-name "$APP_NAME" \
  --sdk-root "$SDK_ROOT" \
  --xcode-version "$XCODE_BUILD_VERSION" \
  --platform-family macOS \
  --deployment-target 27.0 \
  --target-triple arm64-apple-macos27.0 \
  --source-file-list "$INTENTS_TEMP_DIR/sources.list" \
  --swift-const-vals-list "$INTENTS_TEMP_DIR/const-values.list" \
  --force \
  --force-metadata-output

if [[ -n "${FOUNDATIONCHAT_PROVISIONING_PROFILE:-}" ]]; then
  cp "$FOUNDATIONCHAT_PROVISIONING_PROFILE" "$APP_CONTENTS/embedded.provisionprofile"
fi

SIGNING_IDENTITY="${FOUNDATIONCHAT_SIGNING_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_BUNDLE"
else
  codesign \
    --force \
    --deep \
    --options runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
