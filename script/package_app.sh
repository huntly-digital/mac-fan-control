#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MFanControl"
APP_EXECUTABLE="MFanControlApp"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCTS_DIR="$ROOT_DIR/Products"
APP_BUNDLE="$PRODUCTS_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
CODE_SIGN_IDENTITY="$("$ROOT_DIR/script/resolve_code_sign_identity.sh")"

set +e
RUNNING_APP="$("/usr/bin/pgrep" -x "$APP_EXECUTABLE" 2>&1)"
PGREP_STATUS=$?
set -e
case "$PGREP_STATUS" in
  0)
    echo "Refusing to replace $APP_BUNDLE while $APP_EXECUTABLE is running:" >&2
    echo "$RUNNING_APP" >&2
    echo "Quit MFanControl or use script/build_and_run.sh." >&2
    exit 1
    ;;
  1)
    ;;
  *)
    echo "Could not verify whether $APP_EXECUTABLE is running:" >&2
    echo "$RUNNING_APP" >&2
    exit 1
    ;;
esac

BUILD_DIR="$(
  env \
    DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
    CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/mfan-clang-cache}" \
    SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/mfan-swiftpm-cache}" \
  xcrun swift build -c release --show-bin-path --disable-sandbox
)"

DEVELOPER_DIR="$DEVELOPER_DIR_PATH" "$ROOT_DIR/script/generate_app_icon.sh"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/$APP_EXECUTABLE" "$MACOS_DIR/$APP_EXECUTABLE"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT_DIR/Resources/Assets.car" "$RESOURCES_DIR/Assets.car"
cp "$ROOT_DIR/LICENSE" "$RESOURCES_DIR/LICENSE.txt"
cp "$ROOT_DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
BUILD_DIR="$BUILD_DIR" \
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
  "$ROOT_DIR/script/package_helper.sh"
cp "$PRODUCTS_DIR/MFanControlHelper.pkg" "$RESOURCES_DIR/MFanControlHelper.pkg"
chmod 0755 "$MACOS_DIR/$APP_EXECUTABLE"

/usr/bin/codesign --force --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE"
echo "$APP_BUNDLE"
