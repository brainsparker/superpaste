#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
source "$REPO/scripts/dev-config.sh"
SPM="$REPO/SuperPaste"
APP="$DEV_APP"
RESET_ONBOARDING=false
RESET_PERMISSIONS=false
LAUNCH_APP=true

usage() {
    cat <<EOF
Usage: ./build.sh [--fresh] [--fresh-permissions] [--no-launch]

Options:
  --fresh              Reset local onboarding defaults before launching.
  --fresh-permissions  Reset onboarding defaults plus Screen Recording and
                       Accessibility TCC grants before launching.
  --no-launch          Build, package, and sign without opening the app.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fresh)
            RESET_ONBOARDING=true
            shift
            ;;
        --fresh-permissions)
            RESET_ONBOARDING=true
            RESET_PERMISSIONS=true
            shift
            ;;
        --no-launch)
            LAUNCH_APP=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

CERT_NAME="SuperPaste Developer"
if ! security find-identity -v -p codesigning 2>/dev/null | grep "\"${CERT_NAME}\"" >/dev/null; then
    echo "Stable signing identity missing. Run ./setup_codesign.sh before building." >&2
    exit 1
fi

if [[ "${RESET_ONBOARDING}" == true ]]; then
    RESET_ARGS=()
    if [[ "${RESET_PERMISSIONS}" == true ]]; then
        RESET_ARGS+=(--permissions)
    fi
    "$REPO/bin/reset-onboarding.sh" "${RESET_ARGS[@]}"
fi

echo "Building..."
cd "$SPM"
swift build -c release --product SuperPaste

echo "Packaging..."
pkill -x "$DEV_EXECUTABLE" 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$SPM/.build/release/SuperPaste"  "$APP/Contents/MacOS/$DEV_EXECUTABLE"
cp "$SPM/Resources/Info.plist"       "$APP/Contents/"
cp "$SPM/Resources/AppIcon.icns"     "$APP/Contents/Resources/"

/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $DEV_BUNDLE_ID" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $DEV_APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DEV_APP_NAME" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $DEV_EXECUTABLE" "$APP/Contents/Info.plist"
# Development builds must never install the release app under their identity.
/usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUAutomaticallyUpdate false" "$APP/Contents/Info.plist"

# Copy asset catalog resources if present
if [ -d "$SPM/.build/release/SuperPaste_SuperPaste.bundle" ]; then
    cp -r "$SPM/.build/release/SuperPaste_SuperPaste.bundle/." "$APP/Contents/Resources/"
fi

"$REPO/scripts/embed-sparkle.sh" "$SPM" "$APP"

echo "Signing..."
# Persistent self-signed cert keeps macOS TCC grants (Accessibility, Screen Recording)
# alive across rebuilds. Ad-hoc signing ties the grant to a cdhash that changes on every
# recompile, forcing the user back into System Settings each time.
codesign -s "${CERT_NAME}" --force --deep "$APP"

if [[ "${LAUNCH_APP}" == true ]]; then
    echo "Launching..."
    open "$APP"
fi
echo "Done."
