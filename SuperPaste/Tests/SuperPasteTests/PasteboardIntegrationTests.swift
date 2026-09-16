import AppKit
import Testing
@testable import SuperPaste

/// Real NSPasteboard round-trip through ClipboardService (no mocks), plus the
/// transaction contract end-to-end. Tests mutate the shared pasteboard, so
/// every written value is unique and nothing asserts specific prior contents.
@MainActor
struct PasteboardIntegrationTests {
    @Test func writeAndReadRoundTrip() {
        let unique = "superpaste-integration-\(UUID().uuidString)"
        ClipboardService.shared.write(unique)
        #expect(ClipboardService.shared.read() == unique)
    }

    @Test func emptyRestoreIsANoOp() {
        let before = ClipboardService.shared.changeCount
        ClipboardService.shared.restore([])
        #expect(ClipboardService.shared.changeCount == before)
    }

    @Test func transactionRefusesStaleDestination() async {
        let service = ClipboardService.shared
        let previous = service.snapshotItems()
        var pasteCalls = 0
        let outcome = await PasteTransaction.run(
            isCurrent: { true },
            destinationMatches: { false },
            clipboardMatches: { true },
            prepareClipboard: { service.write("superpaste must never leave this on the clipboard") },
            restoreClipboard: { service.restore(previous) },
            paste: { pasteCalls += 1; return true },
            wait: {}
        )
        #expect(outcome == .destinationChanged)
        #expect(service.read() != "superpaste must never leave this on the clipboard")
        #expect(pasteCalls == 0)
    }

    @Test func transactionRefusesUserClipboardChange() async {
        var pasteCalls = 0
        let outcome = await PasteTransaction.run(
            isCurrent: { true },
            destinationMatches: { true },
            clipboardMatches: { false },
            prepareClipboard: { ClipboardService.shared.write("superseded-\(UUID().uuidString)") },
            restoreClipboard: {},
            paste: { pasteCalls += 1; return true },
            wait: {}
        )
        #expect(outcome == .clipboardChanged)
        #expect(pasteCalls == 0)
    }

    @Test func successfulRunPastesExactlyOnce() async {
        let service = ClipboardService.shared
        let unique = "superpaste-pasted-\(UUID().uuidString)"
        var pasteCalls = 0
        let outcome = await PasteTransaction.run(
            isCurrent: { true },
            destinationMatches: { true },
            clipboardMatches: { true },
            prepareClipboard: { service.write(unique) },
            restoreClipboard: {},
            paste: { pasteCalls += 1; return true },
            wait: {}
        )
        #expect(outcome == .pasted)
        #expect(pasteCalls == 1)
        #expect(service.read() == unique)
    }
}
