#!/bin/bash
# Confirm the Swift toolchain needed to build SuperPaste is available.

set -euo pipefail

if ! command -v swift >/dev/null 2>&1; then
  cat >&2 <<EOF
SuperPaste needs Apple's Swift toolchain to build from source.

Install Xcode or Command Line Tools, then re-run this command:
  xcode-select --install
EOF
  exit 1
fi

if ! swift -version >/dev/null 2>&1; then
  echo "Swift is installed but did not run successfully. Check your Xcode or Command Line Tools installation." >&2
  exit 1
fi

exit 0
