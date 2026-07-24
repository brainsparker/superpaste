#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: scripts/embed-sparkle.sh <swift-package-dir> <app-bundle>" >&2
    exit 64
fi

SPM_DIR="$1"
APP_BUNDLE="$2"
SPARKLE_FRAMEWORK="$SPM_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "Sparkle.framework was not found at:" >&2
    echo "  $SPARKLE_FRAMEWORK" >&2
    echo "Run 'swift package resolve' from $SPM_DIR first." >&2
    exit 1
fi

mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Sparkle.framework contains versioned symlinks and signed helper tools.
# ditto preserves that bundle structure; cp -r can flatten it incorrectly.
ditto "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
