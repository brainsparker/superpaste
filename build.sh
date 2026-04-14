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

# Copy asset catalog resources if present
if [ -d "$SPM/.build/release/SuperPaste_SuperPaste.bundle" ]; then
    cp -r "$SPM/.build/release/SuperPaste_SuperPaste.bundle/." "$APP/Contents/Resources/"
fi

echo "Signing..."
codesign -s - --force --deep "$APP"

# Kill any previous instance
pkill -x SuperPaste 2>/dev/null || true
sleep 0.5

echo "Launching..."
open "$APP"
echo "Done."
