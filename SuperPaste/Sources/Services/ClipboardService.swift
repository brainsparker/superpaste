import AppKit

/// Service for reading from and writing to the system clipboard.
/// No permissions required - uses standard NSPasteboard APIs.
final class ClipboardService {
    static let shared = ClipboardService()

    private let pasteboard = NSPasteboard.general

    private init() {}

    /// Read current clipboard contents as string
    func read() -> String? {
        pasteboard.string(forType: .string)
    }

    /// Write string to clipboard, replacing existing contents
    func write(_ string: String) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Full-fidelity snapshot of everything on the clipboard — images, files,
    /// rich text, all of it. A plain-string snapshot silently destroys
    /// anything that isn't text when it's "restored".
    func snapshotItems() -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    /// Put a snapshot back on the clipboard.
    func restore(_ items: [NSPasteboardItem]) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
    }

    /// Get clipboard change count (useful for detecting external changes)
    var changeCount: Int {
        pasteboard.changeCount
    }
}
