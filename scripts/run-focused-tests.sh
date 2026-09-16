#!/bin/bash
# Runs the focused SuperPaste test suites with the CLT framework flags the
# local runner needs. Kept in a file to avoid shell-quoting regressions.
set -euo pipefail
cd "$(dirname "$0")/.."
cd SuperPaste
exec swift test --enable-swift-testing \
  --filter 'PasteboardIntegrationTests|PasteTransactionTests|PasteFailureTests|ReadyCardStateTests' \
  -Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/Frameworks \
  -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/Library/Developer/usr/lib "$@"
