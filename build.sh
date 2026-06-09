#!/bin/bash
set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
SPM="$REPO/SuperPaste"
APP="$REPO/SuperPaste.app"
RESET_ONBOARDING=false
RESET_PERMISSIONS=false

usage() {
    cat <<EOF
Usage: ./build.sh [--fresh] [--fresh-permissions]

Options:
  --fresh              Reset local onboarding defaults before launching.
  --fresh-permissions  Reset onboarding defaults plus Screen Recording and
                       Accessibility TCC grants before launching.
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
