#!/bin/bash
set -euo pipefail

BUNDLE_ID="${SUPERPASTE_BUNDLE_ID:-com.superpaste.app}"
APP_NAME="${SUPERPASTE_APP_NAME:-SuperPaste}"
RESET_TCC=false

usage() {
    cat <<EOF
Usage: ./bin/reset-onboarding.sh [--permissions]

Resets SuperPaste's local onboarding state for development testing.

Options:
  --permissions   Also reset macOS Screen Recording and Accessibility grants
                  for ${BUNDLE_ID}. The next launch will exercise the full
                  permissions onboarding flow again.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --permissions)
            RESET_TCC=true
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

echo "Stopping ${APP_NAME}..."
pkill -x "${APP_NAME}" 2>/dev/null || true
for _ in {1..20}; do
    if ! pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

echo "Resetting onboarding defaults for ${BUNDLE_ID}..."
for key in \
    hasSeenWelcome \
    hasConfiguredLaunchAtLogin \
    hasTriedOnce \
    useCount \
    launchAtLogin \
    trialExpiredLocally \
    trialStartDate; do
    defaults delete "${BUNDLE_ID}" "${key}" 2>/dev/null || true
done

if [[ "${RESET_TCC}" == true ]]; then
    echo "Resetting macOS permissions for ${BUNDLE_ID}..."
    tccutil reset ScreenCapture "${BUNDLE_ID}" 2>/dev/null || true
    tccutil reset Accessibility "${BUNDLE_ID}" 2>/dev/null || true
fi

echo "Done."
