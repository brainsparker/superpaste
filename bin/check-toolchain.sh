#!/bin/bash
# Confirm the active developer toolchain is full Xcode, not just Command Line Tools.
#
# MLX requires `xcrun metal` to compile its Metal shader library at build time.
# That binary ships only with full Xcode (the App). CLT-only setups silently
# produce a working-looking binary that then fails at runtime with
# "Failed to load the default metallib".
#
# Exits 0 on success, 1 with a remediation message otherwise.

set -e

DEV_DIR="$(xcode-select -p 2>/dev/null || true)"

if [[ "$DEV_DIR" == *"CommandLineTools"* ]] || [[ -z "$DEV_DIR" ]]; then
  cat >&2 <<EOF
SuperPaste needs full Xcode (not Command Line Tools) to compile MLX's Metal shaders.

Current active developer dir: ${DEV_DIR:-(none)}

Fix:
  1. Install Xcode from the App Store or https://developer.apple.com/xcode/
  2. sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  3. xcodebuild -runFirstLaunch          # accept the license, install components
  4. Re-run this command.
EOF
  exit 1
fi

if ! xcrun -sdk macosx --find metal >/dev/null 2>&1; then
  echo "Error: xcrun can't find 'metal'. Xcode appears installed but its Metal toolchain is missing." >&2
  echo "Try: xcodebuild -runFirstLaunch" >&2
  exit 1
fi

exit 0
