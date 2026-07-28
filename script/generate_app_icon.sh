#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/Resources/AppIcon/AppIcon-1024.png"
ICONSET="$ROOT_DIR/Resources/AppIcon/AppIcon.iconset"
OUTPUT="$ROOT_DIR/Resources/AppIcon.icns"
CONTENTS="$ROOT_DIR/Resources/AppIcon/Contents.json"
DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

test -f "$SOURCE"
test -f "$CONTENTS"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

while read -r pixels filename; do
  /usr/bin/sips -z "$pixels" "$pixels" "$SOURCE" \
    --out "$ICONSET/$filename" >/dev/null
done <<'SIZES'
16 icon_16x16.png
32 icon_16x16@2x.png
32 icon_32x32.png
64 icon_32x32@2x.png
128 icon_128x128.png
256 icon_128x128@2x.png
256 icon_256x256.png
512 icon_256x256@2x.png
512 icon_512x512.png
1024 icon_512x512@2x.png
SIZES

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mfan-app-icon.XXXXXX")"
ASSET_CATALOG="$STAGING_DIR/MFanControl.xcassets"
APPICON_SET="$ASSET_CATALOG/AppIcon.appiconset"
COMPILED_DIR="$STAGING_DIR/compiled"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$APPICON_SET" "$COMPILED_DIR"
cp "$CONTENTS" "$APPICON_SET/Contents.json"
cp "$ICONSET"/*.png "$APPICON_SET/"

env DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
  /usr/bin/xcrun actool "$ASSET_CATALOG" \
  --compile "$COMPILED_DIR" \
  --platform macosx \
  --minimum-deployment-target 15.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$STAGING_DIR/partial-info.plist" \
  >/dev/null

test -f "$COMPILED_DIR/AppIcon.icns"
test -f "$COMPILED_DIR/Assets.car"
cp "$COMPILED_DIR/AppIcon.icns" "$OUTPUT"
cp "$COMPILED_DIR/Assets.car" "$ROOT_DIR/Resources/Assets.car"
echo "$OUTPUT"
