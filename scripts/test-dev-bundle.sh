#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO/scripts/dev-config.sh"
INFO="$DEV_APP/Contents/Info.plist"

test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO")" = "$DEV_BUNDLE_ID"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INFO")" = "$DEV_APP_NAME"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$INFO")" = "$DEV_APP_NAME"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO")" = "$DEV_EXECUTABLE"
test -x "$DEV_APP/Contents/MacOS/$DEV_EXECUTABLE"
test "$(/usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' "$INFO")" = false
test "$(/usr/libexec/PlistBuddy -c 'Print :SUAutomaticallyUpdate' "$INFO")" = false
if /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$INFO" >/dev/null 2>&1; then
    echo "Development app must not use the release update feed" >&2
    exit 1
fi
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_INFO_PLIST")" != "$DEV_BUNDLE_ID"
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$SOURCE_INFO_PLIST" >/dev/null
codesign --verify --deep --strict "$DEV_APP"
echo "Development bundle isolation checks passed."
