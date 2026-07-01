import SwiftUI

/// Menu-bar dropdown: the only ambient indication that SuperPaste is armed,
/// and the fastest route to pause, recovery, and updates.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var updateChecker = UpdateChecker.shared

    var body: some View {
        Group {
            statusSection

            Divider()

            Button(appState.isPaused ? "Resume SuperPaste" : "Pause SuperPaste") {
                appState.setPaused(!appState.isPaused)
            }

            Button("Copy Last Response") {
                appState.copyLastResponse()
            }
            .disabled(appState.lastResponse == nil)

            Divider()

            if let update = updateChecker.availableUpdate {
                Button("Update Available — v\(update.version)…") {
                    updateChecker.openReleasePage()
                }
            } else {
                Button("Check for Updates") {
                    updateChecker.check()
                }
            }

            SettingsLink {
                Text("Settings…")
            }

            Divider()

            Button("Quit SuperPaste") {
                NSApp.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if appState.isPaused {
            Text("Paused — hotkey released")
        } else if appState.isProcessing {
            Text("Working…")
        } else if appState.usingOwnAPIKey {
            Text("Ready (your API key) — \(HotkeyPreset.current.shortName)")
        } else if appState.isLicensed {
            Text("Ready — \(HotkeyPreset.current.shortName)")
        } else if let days = appState.trialDaysRemaining {
            Text("Trial: \(days) day\(days == 1 ? "" : "s") left — \(HotkeyPreset.current.shortName)")
        } else {
            Text("Ready — \(HotkeyPreset.current.shortName)")
        }
    }
}
