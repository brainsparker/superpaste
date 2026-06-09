#!/bin/bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="${SUPERPASTE_APP_PATH:-$REPO/SuperPaste.app}"
BIN="$APP/Contents/MacOS/SuperPaste"

usage() {
    cat <<EOF
Usage: ./bin/permissions-probe.sh

Runs the built, signed SuperPaste app binary in permission-status mode.
This checks the permissions for SuperPaste.app itself, not for this shell script.
Exits 0 when SuperPaste is ready to capture and paste; exits 1 when a permission
is missing; exits 2 when the built app is missing.

Environment:
  SUPERPASTE_APP_PATH   Built app path to inspect. Defaults to ./SuperPaste.app.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

if [[ ! -x "$BIN" ]]; then
    echo "SuperPaste binary not found at: $BIN" >&2
    echo "Run ./build.sh first." >&2
    exit 2
fi

"$BIN" --permissions-status
