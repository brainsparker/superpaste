#!/bin/bash
#
# release.sh — build, sign, (optionally notarize), package, and publish
# a SuperPaste release to GitHub.
#
# Usage: scripts/release.sh [--skip-notarize]
#
# Signing: uses a "Developer ID Application" identity when one exists
# (required for downloads to pass Gatekeeper). Falls back to the local
# "SuperPaste Developer" cert with a loud warning so test releases still build.
#
# Notarization: runs automatically when a `notarytool` keychain profile named
# "superpaste-notary" exists. Create it once after Apple Developer enrollment:
#   xcrun notarytool store-credentials superpaste-notary \
#     --apple-id you@example.com --team-id TEAMID --password <app-specific-pw>
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SPM="$REPO/SuperPaste"
DIST="$REPO/dist"
APP="$DIST/SuperPaste.app"
DMG="$DIST/SuperPaste.dmg"
SKIP_NOTARIZE=false
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=true

VERSION=$(plutil -extract CFBundleShortVersionString raw "$SPM/Resources/Info.plist")
TAG="v$VERSION"

echo "==> Building SuperPaste $VERSION"
cd "$SPM"
swift build -c release --product SuperPaste

echo "==> Packaging .app"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SPM/.build/release/SuperPaste"  "$APP/Contents/MacOS/"
cp "$SPM/Resources/Info.plist"       "$APP/Contents/"
cp "$SPM/Resources/AppIcon.icns"     "$APP/Contents/Resources/"
if [ -d "$SPM/.build/release/SuperPaste_SuperPaste.bundle" ]; then
    cp -r "$SPM/.build/release/SuperPaste_SuperPaste.bundle/." "$APP/Contents/Resources/"
fi

echo "==> Signing"
DEV_ID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"') || true
if [ -n "${DEV_ID:-}" ]; then
    echo "    Using $DEV_ID"
    codesign -s "$DEV_ID" --force --deep --options runtime --timestamp "$APP"
else
    echo ""
    echo "    ⚠️  No 'Developer ID Application' certificate found."
    echo "    Signing with the local 'SuperPaste Developer' cert — downloads"
    echo "    will be BLOCKED by Gatekeeper on other Macs. Enroll in the"
    echo "    Apple Developer Program and re-run for a distributable build."
    echo ""
    codesign -s "SuperPaste Developer" --force --deep "$APP"
fi

echo "==> Creating DMG"
STAGING="$DIST/dmg-staging"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "SuperPaste" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

# Sign the DMG container itself (app inside is already signed) so even
# container-level Gatekeeper checks pass. Must happen before notarization.
if [ -n "${DEV_ID:-}" ]; then
    codesign -s "$DEV_ID" --timestamp "$DMG"
fi

if [ "$SKIP_NOTARIZE" = false ] && [ -n "${DEV_ID:-}" ] && \
   xcrun notarytool history --keychain-profile superpaste-notary >/dev/null 2>&1; then
    echo "==> Notarizing (this can take a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile superpaste-notary --wait
    xcrun stapler staple "$DMG"
else
    echo "==> Skipping notarization (no Developer ID or no 'superpaste-notary' profile)"
fi

echo "==> Publishing GitHub release $TAG"
cd "$REPO"
if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG" --clobber
    echo "    Updated existing release $TAG"
else
    gh release create "$TAG" "$DMG" \
        --title "SuperPaste $VERSION" \
        --notes "Press ⌥V. Text appears.

- Download \`SuperPaste.dmg\`, open it, and drag SuperPaste to Applications.
- Requires macOS 14 (Sonoma) or later.
- 7-day free trial, no card required. \$5/month after, or compile from source free."
fi

echo ""
echo "Done: https://github.com/brainsparker/superpaste/releases/tag/$TAG"
