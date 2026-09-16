#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO/scripts/dev-config.sh"
APP="${SUPERPASTE_APP_PATH:-$DEV_APP}"

usage() {
    cat <<EOF
Usage: ./bin/permissions-probe.sh

Runs the built, signed SuperPaste app binary in permission-status mode.
This checks the permissions for SuperPaste.app itself, not for this shell script.
Exits 0 when SuperPaste is ready to capture and paste; exits 1 when a permission
is missing; exits 2 when the built app is missing.

Environment:
  SUPERPASTE_APP_PATH   Built app path to inspect. Defaults to ./SuperPaste Dev.app.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! -f "$APP/Contents/Info.plist" ]]; then
    echo "SuperPaste app not found at: $APP" >&2
    echo "Run ./build.sh first." >&2
    exit 2
fi

EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/Info.plist")"
BIN="$APP/Contents/MacOS/$EXECUTABLE"
"$BIN" --permissions-status
