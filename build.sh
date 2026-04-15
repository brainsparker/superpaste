#!/bin/bash
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
SPM="$REPO/SuperPaste"
APP="$REPO/SuperPaste.app"

echo "Building..."
cd "$SPM"
swift build -c release

echo "Packaging..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$SPM/.build/release/SuperPaste"  "$APP/Contents/MacOS/"
cp "$SPM/Resources/Info.plist"       "$APP/Contents/"
cp "$SPM/Resources/AppIcon.icns"     "$APP/Contents/Resources/"

# Copy asset catalog resources if present
if [ -d "$SPM/.build/release/SuperPaste_SuperPaste.bundle" ]; then
    cp -r "$SPM/.build/release/SuperPaste_SuperPaste.bundle/." "$APP/Contents/Resources/"
fi

echo "Signing..."
# Persistent self-signed cert keeps macOS TCC grants (Accessibility, Screen Recording)
# alive across rebuilds. Ad-hoc signing ties the grant to a cdhash that changes on every
# recompile, forcing the user back into System Settings each time.
CERT_NAME="SuperPaste Developer"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"${CERT_NAME}\""; then
    codesign -s "${CERT_NAME}" --force --deep "$APP"
else
    echo ""
    echo "  No '${CERT_NAME}' certificate found — falling back to ad-hoc signing."
    echo "  Accessibility permission will break on each rebuild."
    echo "  Run ./setup_codesign.sh once to fix this permanently."
    echo ""
    codesign -s - --force --deep "$APP"
fi

# Kill any previous instance
pkill -x SuperPaste 2>/dev/null || true
sleep 0.5

echo "Launching..."
open "$APP"
echo "Done."
