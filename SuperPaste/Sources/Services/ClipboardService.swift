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

    /// Get clipboard change count (useful for detecting external changes)
    var changeCount: Int {
        pasteboard.changeCount
    }
}
