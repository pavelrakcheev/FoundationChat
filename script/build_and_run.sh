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
GENERATED_ICON="$ROOT_DIR/Resources/AppIcon.icns"

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
  XCODE_CONTENTS_DIR="$(dirname "$DEVELOPER_DIR")"
  ICTOOL="$XCODE_CONTENTS_DIR/Applications/Icon Composer.app/Contents/Executables/ictool"
  if [[ -x "$ICTOOL" ]]; then
    ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"

    for size in 16 32 128 256 512; do
      "$ICTOOL" "$ICON_SOURCE" \
        --export-image \
        --output-file "$ICONSET_DIR/icon_${size}x${size}.png" \
        --platform macOS \
        --rendition Default \
        --width "$size" \
        --height "$size" \
        --scale 1 \
        --design-generation 27 >/dev/null
      "$ICTOOL" "$ICON_SOURCE" \
        --export-image \
        --output-file "$ICONSET_DIR/icon_${size}x${size}@2x.png" \
        --platform macOS \
        --rendition Default \
        --width "$size" \
        --height "$size" \
        --scale 2 \
        --design-generation 27 >/dev/null
    done

    iconutil --convert icns --output "$GENERATED_ICON" "$ICONSET_DIR"
  fi
fi

if [[ -f "$GENERATED_ICON" ]]; then
  cp "$GENERATED_ICON" "$APP_RESOURCES/AppIcon.icns"
fi

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
