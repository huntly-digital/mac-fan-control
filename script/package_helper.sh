#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCTS_DIR="$ROOT_DIR/Products"
PACKAGE_PATH="$PRODUCTS_DIR/MFanControlHelper.pkg"
HELPER_INSTALL_PATH="Library/PrivilegedHelperTools/io.clover.mfancontrol.helper"
PLIST_INSTALL_PATH="Library/LaunchDaemons/io.clover.mfancontrol.helper.plist"
DEVELOPER_DIR_PATH="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
PACKAGE_VERSION="${PACKAGE_VERSION:-0.1.2}"

BUILD_DIR="${BUILD_DIR:-$(
  env \
    DEVELOPER_DIR="$DEVELOPER_DIR_PATH" \
    CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/mfan-clang-cache}" \
    SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-/tmp/mfan-swiftpm-cache}" \
    xcrun swift build -c release --show-bin-path --disable-sandbox
)}"

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mfan-helper-pkg.XXXXXX")"
PAYLOAD_ROOT="$STAGING_DIR/payload"
SCRIPTS_DIR="$STAGING_DIR/scripts"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p \
  "$PAYLOAD_ROOT/Library/PrivilegedHelperTools" \
  "$PAYLOAD_ROOT/Library/LaunchDaemons" \
  "$SCRIPTS_DIR" \
  "$PRODUCTS_DIR"

cp "$BUILD_DIR/fancontrold" "$PAYLOAD_ROOT/$HELPER_INSTALL_PATH"
cp "$ROOT_DIR/Resources/io.clover.mfancontrol.helper.plist" \
  "$PAYLOAD_ROOT/$PLIST_INSTALL_PATH"
cp "$ROOT_DIR/script/helper_pkg_scripts/postinstall" "$SCRIPTS_DIR/postinstall"

chmod 0755 "$PAYLOAD_ROOT/$HELPER_INSTALL_PATH" "$SCRIPTS_DIR/postinstall"
chmod 0644 "$PAYLOAD_ROOT/$PLIST_INSTALL_PATH"

codesign_args=(
  --force
  --identifier "io.clover.mfancontrol.helper"
  --sign "$CODE_SIGN_IDENTITY"
  --timestamp=none
)
/usr/bin/codesign "${codesign_args[@]}" "$PAYLOAD_ROOT/$HELPER_INSTALL_PATH"

rm -f "$PACKAGE_PATH"
/usr/bin/pkgbuild \
  --root "$PAYLOAD_ROOT" \
  --scripts "$SCRIPTS_DIR" \
  --identifier "io.clover.mfancontrol.helper.pkg" \
  --version "$PACKAGE_VERSION" \
  --install-location "/" \
  --ownership recommended \
  "$PACKAGE_PATH"

echo "$PACKAGE_PATH"
