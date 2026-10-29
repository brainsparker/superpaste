#!/bin/bash
# Runs the full SuperPaste test suite.
#
# With the Command Line Tools toolchain selected, plain `swift test` builds
# the test bundle but silently runs zero tests. Passing the CLT framework
# paths on the command line (they apply to every target, including the
# generated test runner) makes test discovery work. With the Xcode toolchain
# selected, plain `swift test` works and the extra flags would shadow Xcode's
# Testing framework, so they are only added for the CLT case.
set -euo pipefail
cd "$(dirname "$0")/../SuperPaste"

if [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ]; then
  CLT_FW="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
  exec swift test --enable-swift-testing \
    -Xswiftc -F -Xswiftc "$CLT_FW" \
    -Xlinker -rpath -Xlinker "$CLT_FW" \
    -Xlinker -rpath -Xlinker "/Library/Developer/CommandLineTools/Library/Developer/usr/lib" \
    "$@"
fi

exec swift test "$@"
