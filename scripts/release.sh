#!/bin/bash
#
# release.sh — build, sign, notarize, package, and publish
# a SuperPaste release to GitHub.
#
# Usage: scripts/release.sh [--local] [--preflight-only]
# --skip-notarize is permitted only with --local.
#
# --local stops after building dist/SuperPaste.dmg (no appcast, no GitHub
# release) so the install window and first-launch flow can be tested.
#
# Signing: uses a "Developer ID Application" identity when one exists
# (required for public releases). Local-only artifacts may fall back to the
# "SuperPaste Developer" certificate.
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
LOCAL_ONLY=false
PREFLIGHT_ONLY=false
for arg in "$@"; do
    case "$arg" in
        --skip-notarize) SKIP_NOTARIZE=true ;;
        --preflight-only) PREFLIGHT_ONLY=true ;;
        --local) LOCAL_ONLY=true; SKIP_NOTARIZE=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

VERSION=$(plutil -extract CFBundleShortVersionString raw "$SPM/Resources/Info.plist")
TAG="v$VERSION"

PREFLIGHT_ARGS=(--repo "$REPO")
if [ "$LOCAL_ONLY" = true ]; then PREFLIGHT_ARGS+=(--local); fi
if [ "$SKIP_NOTARIZE" = true ]; then PREFLIGHT_ARGS+=(--skip-notarize); fi
python3 "$REPO/scripts/release_policy.py" "${PREFLIGHT_ARGS[@]}"
if [ "$PREFLIGHT_ONLY" = true ]; then exit 0; fi
SOURCE_COMMIT=$(git -C "$REPO" rev-parse HEAD)

echo "==> Building SuperPaste $VERSION"
cd "$SPM"
# Separate slices work with Command Line Tools as well as Xcode.
swift build -c release --arch arm64 --product SuperPaste
ARM_BIN=$(swift build -c release --arch arm64 --show-bin-path)
swift build -c release --arch x86_64 --product SuperPaste
INTEL_BIN=$(swift build -c release --arch x86_64 --show-bin-path)
BIN_DIR="$SPM/.build/universal-release"
mkdir -p "$BIN_DIR"
lipo -create "$ARM_BIN/SuperPaste" "$INTEL_BIN/SuperPaste" -output "$BIN_DIR/SuperPaste"
lipo "$BIN_DIR/SuperPaste" -verify_arch arm64 x86_64
if [ -d "$ARM_BIN/SuperPaste_SuperPaste.bundle" ]; then
    ditto "$ARM_BIN/SuperPaste_SuperPaste.bundle" "$BIN_DIR/SuperPaste_SuperPaste.bundle"
fi

echo "==> Packaging .app"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/SuperPaste"  "$APP/Contents/MacOS/"
cp "$SPM/Resources/Info.plist"       "$APP/Contents/"
cp "$SPM/Resources/AppIcon.icns"     "$APP/Contents/Resources/"
if [ -d "$BIN_DIR/SuperPaste_SuperPaste.bundle" ]; then
    cp -r "$BIN_DIR/SuperPaste_SuperPaste.bundle/." "$APP/Contents/Resources/"
fi
"$REPO/scripts/embed-sparkle.sh" "$SPM" "$APP"
/usr/libexec/PlistBuddy -c "Add :SuperPasteSourceCommit string $SOURCE_COMMIT" "$APP/Contents/Info.plist"
python3 "$REPO/scripts/release_policy.py" --verify-app "$APP"

echo "==> Signing"
DEV_ID=$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"') || true
if [ -n "${DEV_ID:-}" ]; then
    echo "    Using $DEV_ID"
    codesign -s "$DEV_ID" --force --deep --options runtime --timestamp "$APP"
else
    if [ "$LOCAL_ONLY" != true ]; then echo "Developer ID is required for public releases." >&2; exit 1; fi
    echo ""
    echo "    ⚠️  No 'Developer ID Application' certificate found."
    echo "    Signing with the local 'SuperPaste Developer' cert — downloads"
    echo "    will be BLOCKED by Gatekeeper on other Macs. Enroll in the"
    echo "    Apple Developer Program and re-run for a distributable build."
    echo ""
    codesign -s "SuperPaste Developer" --force --deep "$APP"
fi

echo "==> Creating DMG"
# Build a read-write image first so Finder can lay out the install window
# (app on the left, arrow, Applications alias on the right), then compress.
STAGING="$DIST/dmg-staging"
RW_DMG="$DIST/SuperPaste-rw.dmg"
VOLNAME="SuperPaste"
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
swift "$REPO/scripts/generate-dmg-background.swift" "$STAGING/.background/background.tiff" >/dev/null

# A stale mount with the same name would make Finder style the wrong volume.
if [ -d "/Volumes/$VOLNAME" ]; then
    hdiutil detach "/Volumes/$VOLNAME" -force >/dev/null || true
fi

hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -ov -format UDRW "$RW_DMG" >/dev/null
MOUNT_DIR=$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*$' | head -1)

# Icon positions must match scripts/generate-dmg-background.swift.
if ! osascript <<EOF
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 800, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "SuperPaste.app" of container window to {150, 185}
        set position of item "Applications" of container window to {450, 185}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF
then
    echo "    ⚠️  Finder layout failed (grant Terminal Automation access to Finder)."
    echo "    The DMG still works but opens without the drag-to-install window."
fi

chmod -Rf go-w "$MOUNT_DIR" || true
sync
hdiutil detach "$MOUNT_DIR" >/dev/null
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" -ov >/dev/null
rm -rf "$STAGING" "$RW_DMG"

# Sign the DMG container itself (app inside is already signed) so even
# container-level Gatekeeper checks pass. Must happen before notarization.
if [ -n "${DEV_ID:-}" ]; then
    codesign -s "$DEV_ID" --timestamp "$DMG"
fi

if [ "$SKIP_NOTARIZE" = false ] && [ -n "${DEV_ID:-}" ] && \
   xcrun notarytool history --keychain-profile superpaste-notary >/dev/null 2>&1; then
    echo "==> Notarizing (this can take a few minutes)"
    NOTARY_RESULT="$DIST/notarization.json"
    xcrun notarytool submit "$DMG" --keychain-profile superpaste-notary --wait --output-format json > "$NOTARY_RESULT"
    python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("status") == "Accepted" else "Notarization was not accepted")' "$NOTARY_RESULT"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    codesign --verify --deep --strict "$APP"
else
    if [ "$LOCAL_ONLY" != true ]; then echo "Notarization is required before publishing." >&2; exit 1; fi
    echo "==> Local artifact: notarization skipped"
fi

if [ "$LOCAL_ONLY" = true ]; then
    echo "==> Local build ready: $DMG (not published)"
    exit 0
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

if [ "$(git -C "$REPO" rev-parse HEAD)" != "$SOURCE_COMMIT" ]; then
    echo "Source commit changed during packaging; refusing to publish." >&2
    exit 1
fi
python3 "$REPO/scripts/release_policy.py" --repo "$REPO"
echo "==> Publishing GitHub release $TAG"
cd "$REPO"
RELEASE_ASSETS=("$DMG" "$APPCAST")
if [ -f "$NOTES_ASSET" ]; then
    RELEASE_ASSETS+=("$NOTES_ASSET")
fi

if [ -f "$NOTES_SOURCE" ]; then
    gh release create "$TAG" "${RELEASE_ASSETS[@]}" --target "$SOURCE_COMMIT" \
        --title "SuperPaste $VERSION" \
        --notes-file "$NOTES_SOURCE"
else
    gh release create "$TAG" "${RELEASE_ASSETS[@]}" --target "$SOURCE_COMMIT" \
        --title "SuperPaste $VERSION" \
        --notes "Press ⌥V. Text appears.

- Updates now install securely from inside SuperPaste.
- Requires macOS 14 (Sonoma) or later.
- 7-day free trial, no card required. \$5/month after, or compile from source free."
fi

echo ""
echo "Done: https://github.com/brainsparker/superpaste/releases/tag/$TAG"
