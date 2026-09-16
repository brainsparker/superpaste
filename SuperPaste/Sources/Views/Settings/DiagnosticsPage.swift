import SwiftUI

@MainActor
struct DiagnosticsPage: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Diagnostics")
                    .font(.title2.bold())

                Text("Everything below is read from this Mac. No screenshots, responses, API keys, or window titles are included.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                row("Bundle identifier", Bundle.main.bundleIdentifier ?? "unknown")
                row("Version", "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
                row("Screen Recording", appState.screenRecordingEnabled ? "granted" : "missing")
                row("Accessibility", appState.accessibilityEnabled ? "granted" : "missing")
                row("Hotkey registered", appState.hotkeyService.isRegistered ? "yes" : "no")
                row("Competing SuperPaste", appState.hasCompetingInstance ? "yes — quit one copy" : "no")
                row("Paused", appState.isPaused ? "yes" : "no")
                row("Provider", appState.providerConfig.provider.displayName)
                row("Last failure code", appState.hudState.lastFailure?.code.rawValue ?? "none")
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).frame(width: 200, alignment: .leading)
            Spacer()
            Text(value).foregroundColor(value == "missing" || value.contains("yes —") ? .orange : .secondary)
        }
        .font(.subheadline)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
