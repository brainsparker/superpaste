import AppKit
import Foundation

/// Lightweight update check against GitHub releases. "Updates" are part of
/// what subscribers pay for, so the app has to be able to tell users one
/// exists — without shipping a full Sparkle setup before launch.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct AvailableUpdate: Equatable {
        let version: String
        let url: URL
    }

    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isChecking = false

    private static let releasesAPI = "https://api.github.com/repos/brainsparker/superpaste/releases/latest"
    private static let releasesPage = "https://github.com/brainsparker/superpaste/releases/latest"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 3600

    private init() {}

    /// Auto-check at most once a day (called on launch).
    func checkIfStale() {
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > Self.checkInterval else { return }
        check()
    }

    /// Explicit check (menu bar → Check for Updates).
    func check() {
        guard !isChecking else { return }
        isChecking = true

        Task {
            defer { isChecking = false }
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)

            guard let url = URL(string: Self.releasesAPI) else { return }
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            struct Release: Decodable {
                let tag_name: String
                let html_url: String
            }

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = try? JSONDecoder().decode(Release.self, from: data) else {
                return
            }

            let latest = release.tag_name.hasPrefix("v")
                ? String(release.tag_name.dropFirst())
                : release.tag_name
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

            if latest.compare(current, options: .numeric) == .orderedDescending,
               let pageURL = URL(string: release.html_url) {
                availableUpdate = AvailableUpdate(version: latest, url: pageURL)
            } else {
                availableUpdate = nil
            }
        }
    }

    func openReleasePage() {
        let url = availableUpdate?.url ?? URL(string: Self.releasesPage)!
        NSWorkspace.shared.open(url)
    }
}
