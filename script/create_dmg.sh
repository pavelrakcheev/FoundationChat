#!/usr/bin/env bash
set -euo pipefail

APP_NAME="FoundationChat"
DISPLAY_NAME="Foundation Chat"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
OUTPUT_DMG="${1:-$DIST_DIR/FoundationChat-$VERSION-macOS27-arm64.dmg}"

STAGING_DIR="$(mktemp -d "$DIST_DIR/DMG.XXXXXX")"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

FOUNDATIONCHAT_BUILD_CONFIGURATION=release \
  "$ROOT_DIR/script/build_and_run.sh" --build

cp -R "$DIST_DIR/$APP_NAME.app" "$STAGING_DIR/$DISPLAY_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$OUTPUT_DMG"
diskutil image create from \
  --volumeName "$DISPLAY_NAME" \
  --format UDZO \
  "$STAGING_DIR" \
  "$OUTPUT_DMG"

hdiutil verify "$OUTPUT_DMG"
shasum -a 256 "$OUTPUT_DMG"
