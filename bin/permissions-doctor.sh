#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_INFO_PLIST="$REPO/SuperPaste/Resources/Info.plist"
APP="${SUPERPASTE_APP_PATH:-$REPO/SuperPaste.app}"
CERT_NAME="${SUPERPASTE_CERT_NAME:-SuperPaste Developer}"

usage() {
    cat <<EOF
Usage: ./bin/permissions-doctor.sh

Checks the local SuperPaste permission testing setup without resetting macOS TCC.

Environment:
  SUPERPASTE_APP_PATH   Built app path to inspect. Defaults to ./SuperPaste.app.
  SUPERPASTE_CERT_NAME  Signing identity to expect. Defaults to "SuperPaste Developer".
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

section() {
    echo ""
    echo "$1"
    echo "----------------------------------------"
}

SOURCE_BUNDLE_ID="$(plist_value "$SOURCE_INFO_PLIST" CFBundleIdentifier)"
SOURCE_NAME="$(plist_value "$SOURCE_INFO_PLIST" CFBundleName)"

section "Bundle"
echo "Source bundle id: ${SOURCE_BUNDLE_ID:-unknown}"
echo "Source app name:  ${SOURCE_NAME:-unknown}"

if [[ -d "$APP" ]]; then
    APP_INFO_PLIST="$APP/Contents/Info.plist"
    APP_BUNDLE_ID="$(plist_value "$APP_INFO_PLIST" CFBundleIdentifier)"
    APP_EXECUTABLE="$(plist_value "$APP_INFO_PLIST" CFBundleExecutable)"

    echo "Built app:        $APP"
    echo "Built bundle id:  ${APP_BUNDLE_ID:-unknown}"
    echo "Executable:       ${APP_EXECUTABLE:-unknown}"

    if [[ -n "$SOURCE_BUNDLE_ID" && "$APP_BUNDLE_ID" == "$SOURCE_BUNDLE_ID" ]]; then
        echo "Bundle match:     ok"
    else
        echo "Bundle match:     mismatch"
    fi
else
    echo "Built app:        missing at $APP"
fi

section "Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"${CERT_NAME}\""; then
    echo "Stable identity:  found (${CERT_NAME})"
else
    echo "Stable identity:  missing (${CERT_NAME})"
    echo "Fix:              ./setup_codesign.sh"
fi

if [[ -d "$APP" ]]; then
    SIGNING_DETAILS="$(codesign -dvvv "$APP" 2>&1 || true)"
    IDENTIFIER="$(printf "%s\n" "$SIGNING_DETAILS" | awk -F= '/^Identifier=/ {print $2; exit}')"
    AUTHORITY="$(printf "%s\n" "$SIGNING_DETAILS" | awk -F= '/^Authority=/ {print $2; exit}')"
    TEAM_ID="$(printf "%s\n" "$SIGNING_DETAILS" | awk -F= '/^TeamIdentifier=/ {print $2; exit}')"

    echo "Signed id:        ${IDENTIFIER:-unknown}"
    echo "Authority:        ${AUTHORITY:-ad-hoc or unknown}"
    echo "Team id:          ${TEAM_ID:-none}"

    if [[ "${AUTHORITY:-}" == "$CERT_NAME" ]]; then
        echo "TCC rebuilds:     stable"
    else
        echo "TCC rebuilds:     may prompt again after rebuild"
    fi
fi

section "Local Onboarding Defaults"
if [[ -z "$SOURCE_BUNDLE_ID" ]]; then
    echo "Skipped: source bundle id not found."
else
    for key in hasSeenWelcome hasTriedOnce useCount launchAtLogin trialExpiredLocally trialStartDate; do
        if value="$(defaults read "$SOURCE_BUNDLE_ID" "$key" 2>/dev/null)"; then
            echo "$key=$value"
        else
            echo "$key=(unset)"
        fi
    done
fi

section "Permission Test Commands"
echo "Check current app permission usability:"
echo "  ./bin/permissions-probe.sh"
echo ""
echo "Replay onboarding only:"
echo "  ./build.sh --fresh"
echo ""
echo "Replay full macOS permission prompts:"
echo "  ./build.sh --fresh-permissions"
echo ""
echo "If Screen Recording is enabled in System Settings but setup does not advance:"
echo "  Use the in-app Relaunch SuperPaste button."
