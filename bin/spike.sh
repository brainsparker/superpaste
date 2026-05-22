#!/bin/bash
# Run the MLX VLM latency spike.
#
# Builds via xcodebuild (NOT `swift build`) because MLX's Metal shaders only
# compile under full Xcode — Command Line Tools alone won't produce a usable
# binary. See bin/check-toolchain.sh.
#
# Usage:  ./bin/spike.sh [model-id] [image-path] [prompt]
# Defaults: Qwen2.5-VL-3B-Instruct-4bit, ./SuperPaste/MLXSpike/test.jpg, generic prompt
#
# First run: downloads ~2GB of model weights to ~/Documents/huggingface — be patient.

set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
"$REPO/bin/check-toolchain.sh"

cd "$REPO/SuperPaste"

# Swift 6 toolchain quirks we have to work around at the consume side:
#   SWIFT_VERSION=5                 — mlx-swift-lm's MLXVLM has a file-scope `let context = CIContext()`
#                                     that strict concurrency rejects under Swift 6 mode.
#   -enable-bare-slash-regex        — swift-jinja uses regex literals the Swift 5 lexer otherwise
#                                     mis-parses as block comments.
BUILD_DIR="$REPO/SuperPaste/.build-xcode"

if [ ! -f "MLXSpike/test.jpg" ] && [ "$#" -lt 2 ]; then
  echo "No test image at SuperPaste/MLXSpike/test.jpg." >&2
  echo "Drop a screenshot there, or pass one as the second argument." >&2
  exit 1
fi

echo "Building MLXSpike via xcodebuild…"
xcodebuild \
  -scheme MLXSpike \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  SWIFT_VERSION=5 \
  OTHER_SWIFT_FLAGS='-enable-bare-slash-regex' \
  build \
  2>&1 | grep -E '(error:|warning:|\*\* BUILD)' || true

# Locate the produced binary
BIN="$(find "$BUILD_DIR/Build/Products" -name MLXSpike -type f -perm +111 | head -1)"
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
  echo "Error: MLXSpike binary not found after build." >&2
  echo "Inspect derived data at: $BUILD_DIR/Build/Products" >&2
  exit 1
fi

echo "Running spike → $BIN"
"$BIN" "$@"
