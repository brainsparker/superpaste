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
UPDATES_DIR="$DIST/updates"
APPCAST="$UPDATES_DIR/appcast.xml"
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
"$REPO/scripts/embed-sparkle.sh" "$SPM" "$APP"

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

echo "==> Generating signed Sparkle appcast"
GENERATE_APPCAST="$SPM/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
if [ ! -x "$GENERATE_APPCAST" ]; then
    echo "Sparkle's generate_appcast tool is missing. Run 'swift package resolve' in $SPM." >&2
    exit 1
fi

mkdir -p "$UPDATES_DIR"
cp "$DMG" "$UPDATES_DIR/SuperPaste.dmg"

NOTES_SOURCE="$REPO/release-notes/$VERSION.md"
NOTES_ASSET="$UPDATES_DIR/SuperPaste.md"
if [ -f "$NOTES_SOURCE" ]; then
    cp "$NOTES_SOURCE" "$NOTES_ASSET"
fi

ASSET_PREFIX="https://github.com/brainsparker/superpaste/releases/download/$TAG/"
"$GENERATE_APPCAST" \
    --account superpaste \
    --download-url-prefix "$ASSET_PREFIX" \
    --release-notes-url-prefix "$ASSET_PREFIX" \
    --full-release-notes-url "https://github.com/brainsparker/superpaste/releases/latest" \
    --link "https://superpaste.ai" \
    "$UPDATES_DIR"

if [ ! -f "$APPCAST" ]; then
    echo "Sparkle did not generate $APPCAST" >&2
    exit 1
fi

echo "==> Publishing GitHub release $TAG"
cd "$REPO"
RELEASE_ASSETS=("$DMG" "$APPCAST")
if [ -f "$NOTES_ASSET" ]; then
    RELEASE_ASSETS+=("$NOTES_ASSET")
fi

if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "${RELEASE_ASSETS[@]}" --clobber
    echo "    Updated existing release $TAG"
elif [ -f "$NOTES_SOURCE" ]; then
    gh release create "$TAG" "${RELEASE_ASSETS[@]}" \
        --title "SuperPaste $VERSION" \
        --notes-file "$NOTES_SOURCE"
else
    gh release create "$TAG" "${RELEASE_ASSETS[@]}" \
        --title "SuperPaste $VERSION" \
        --notes "Press ⌥V. Text appears.

- Updates now install securely from inside SuperPaste.
- Requires macOS 14 (Sonoma) or later.
- 7-day free trial, no card required. \$5/month after, or compile from source free."
fi

echo ""
echo "Done: https://github.com/brainsparker/superpaste/releases/tag/$TAG"
