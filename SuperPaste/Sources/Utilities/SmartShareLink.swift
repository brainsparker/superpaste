import Foundation

/// Recognizes a Smart Share campaign link sitting on the clipboard.
///
/// This is the whole trigger for Magic Copy: if the clipboard holds a campaign
/// link when the hotkey fires, SuperPaste writes a share post for the app you're
/// in instead of reading the window. Detection is deliberately narrow — it
/// matches only SuperPaste's own `/share#c=v1.…` links, so copying an ordinary
/// URL never changes what the hotkey does.
///
/// The token is not decoded here. The Worker owns campaign parsing, validation,
/// and expiry (server/src/smartshare/), so the app only has to spot a link and
/// hand it over. That keeps every campaign rule in one place and lets those
/// rules change without shipping a new build.
enum SmartShareLink {
    /// Hosts whose `/share` links are ours.
    private static let knownHosts: Set<String> = [
        "superpaste.ai",
        "www.superpaste.ai",
        "localhost",
        "127.0.0.1",
    ]

    /// Marks the campaign payload inside the fragment: `#c=v1.<base64url>`.
    private static let fragmentKey = "c"
    private static let tokenPrefix = "v1."

    /// A campaign link is a URL plus an encoded campaign, so it is far longer
    /// than a normal link but still bounded. Anything past this isn't ours.
    private static let maxLinkLength = 8192

    /// The campaign link on the clipboard, or nil if there isn't one.
    ///
    /// Returns the full link rather than the bare token so the Worker sees
    /// exactly what the user copied and does its own extraction.
    static func inClipboard(_ clipboard: ClipboardService = .shared) -> String? {
        guard let contents = clipboard.read() else { return nil }
        return campaignLink(in: contents)
    }

    /// Extract a campaign link from arbitrary clipboard text.
    ///
    /// Tolerant about surrounding whitespace, because links arrive pasted out of
    /// Slack messages and emails, but strict about the shape itself.
    static func campaignLink(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxLinkLength else { return nil }
        // A campaign link is a single token with no interior whitespace. Bailing
        // early keeps a long copied document from being scanned.
        guard !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }

        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(),
              knownHosts.contains(host),
              url.path == "/share" || url.path == "/share.html",
              let fragment = url.fragment,
              let token = token(inFragment: fragment)
        else {
            return nil
        }

        // The token is validated server-side; the app only checks it looks like
        // one so an unrelated `/share` link doesn't start a request.
        guard token.hasPrefix(tokenPrefix), token.count > tokenPrefix.count else { return nil }
        return trimmed
    }

    /// Pull `c=<token>` out of a URL fragment.
    ///
    /// Hand-parsed rather than via URLComponents: a fragment is not a query
    /// string, and URLComponents will not decode one as key/value pairs.
    private static func token(inFragment fragment: String) -> String? {
        for pair in fragment.split(separator: "&", omittingEmptySubsequences: true) {
            guard let separator = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[pair.startIndex..<separator])
            guard key == fragmentKey else { continue }
            let value = String(pair[pair.index(after: separator)...])
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
