#!/bin/bash
# Mutation check: temporarily break ClipboardService.restore so an empty
# snapshot clears the clipboard, then confirm PasteboardIntegrationTests
# catches it. Restores the file afterwards. Fails if the suite stays green.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/SuperPaste/Sources/Services/ClipboardService.swift"
BACKUP="$(mktemp)"
cp "$SRC" "$BACKUP"
restore() { cp "$BACKUP" "$SRC"; rm -f "$BACKUP"; }
trap restore EXIT

python3 - "$SRC" <<'PY'
import sys
path = sys.argv[1]
s = open(path).read()
needle = """    func restore(_ items: [NSPasteboardItem]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()"""
replacement = """    func restore(_ items: [NSPasteboardItem]) {
        pasteboard.clearContents()"""
assert needle in s, "mutation anchor not found"
open(path, "w").write(s.replace(needle, replacement, 1))
PY

if "$REPO/scripts/run-focused-tests.sh" > /tmp/mutation-run.log 2>&1; then
    echo "MUTATION SURVIVED — suite does not catch the regression" >&2
    exit 1
fi
echo "Mutation caught as expected:"
grep -E "✘|failed" /tmp/mutation-run.log | tail -4
