#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:-$ROOT_DIR/Products/MFanControl.app}"
PACKAGE="$APP_BUNDLE/Contents/Resources/MFanControlHelper.pkg"
EXPANSION_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mfan-verify-pkg.XXXXXX")"
EXPANDED_PACKAGE="$EXPANSION_ROOT/expanded"

cleanup() {
  rm -rf "$EXPANSION_ROOT"
}
trap cleanup EXIT

test -x "$APP_BUNDLE/Contents/MacOS/MFanControlApp"
test -f "$PACKAGE"
test -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
test -f "$APP_BUNDLE/Contents/Resources/Assets.car"
test ! -d "$APP_BUNDLE/Contents/Library/LaunchDaemons"

/usr/bin/plutil -lint "$APP_BUNDLE/Contents/Info.plist"
/usr/bin/codesign --verify --strict --verbose=2 "$APP_BUNDLE"
APP_TEAM="$(
  /usr/bin/codesign -dvvv "$APP_BUNDLE" 2>&1 \
    | /usr/bin/sed -n 's/^TeamIdentifier=//p'
)"
test -n "$APP_TEAM"
test "$APP_TEAM" != "not set"
test "$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" \
    "$APP_BUNDLE/Contents/Info.plist"
)" = "AppIcon"
test "$(
  /usr/libexec/PlistBuddy -c "Print :CFBundleIconName" \
    "$APP_BUNDLE/Contents/Info.plist"
)" = "AppIcon"

/usr/sbin/pkgutil --expand-full "$PACKAGE" "$EXPANDED_PACKAGE"
HELPER="$EXPANDED_PACKAGE/Payload/Library/PrivilegedHelperTools/io.clover.mfancontrol.helper"
DAEMON_PLIST="$EXPANDED_PACKAGE/Payload/Library/LaunchDaemons/io.clover.mfancontrol.helper.plist"
POSTINSTALL="$EXPANDED_PACKAGE/Scripts/postinstall"
PACKAGE_INFO="$EXPANDED_PACKAGE/PackageInfo"

test -x "$HELPER"
test -f "$DAEMON_PLIST"
test -x "$POSTINSTALL"
/usr/bin/plutil -lint "$DAEMON_PLIST"
/usr/bin/codesign --verify --strict --verbose=2 "$HELPER"
HELPER_TEAM="$(
  /usr/bin/codesign -dvvv "$HELPER" 2>&1 \
    | /usr/bin/sed -n 's/^TeamIdentifier=//p'
)"
test -n "$HELPER_TEAM"
test "$HELPER_TEAM" != "not set"
test "$APP_TEAM" = "$HELPER_TEAM"

test "$(/usr/bin/stat -f "%Lp" "$HELPER")" = "755"
test "$(/usr/bin/stat -f "%Lp" "$DAEMON_PLIST")" = "644"
test "$(/usr/bin/xmllint --xpath "string(/pkg-info/@identifier)" "$PACKAGE_INFO")" \
  = "io.clover.mfancontrol.helper.pkg"
test "$(/usr/bin/xmllint --xpath "string(/pkg-info/@version)" "$PACKAGE_INFO")" \
  = "0.1.2"
/usr/bin/grep -q 'while \[ "$attempt" -lt 10 \]' "$POSTINSTALL"
test "$(/usr/bin/grep -c '/bin/launchctl bootstrap system' "$POSTINSTALL")" = "1"
test "$(
  /usr/libexec/PlistBuddy -c "Print :Program" "$DAEMON_PLIST"
)" = "/Library/PrivilegedHelperTools/io.clover.mfancontrol.helper"
test "$(
  /usr/libexec/PlistBuddy -c "Print :ProgramArguments:0" "$DAEMON_PLIST"
)" = "/Library/PrivilegedHelperTools/io.clover.mfancontrol.helper"
test "$(
  /usr/libexec/PlistBuddy -c "Print :ProgramArguments:1" "$DAEMON_PLIST"
)" = "--service-managed"
test "$(
  /usr/libexec/PlistBuddy -c "Print :MachServices:io.clover.mfancontrol.helper" "$DAEMON_PLIST"
)" = "true"

echo "Verified $APP_BUNDLE and bundled helper package"
