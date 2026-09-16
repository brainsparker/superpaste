import SwiftUI

/// Menu-bar dropdown: the only ambient indication that SuperPaste is armed,
/// and the fastest route to pause, recovery, and updates.
struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var updateController = UpdateController.shared

    var body: some View {
        Group {
            statusSection

            LastFailureMenu(hudState: appState.hudState)
            CaptureExclusionMenu(store: appState.captureExclusions, app: appState.captureApp)

            Divider()

            Button(appState.isPaused ? "Resume SuperPaste" : "Pause SuperPaste") {
                appState.setPaused(!appState.isPaused)
            }

            Button("Copy Last Response") {
                appState.copyLastResponse()
            }
            .disabled(appState.lastResponse == nil)

            Divider()

            if let update = updateController.availableUpdate {
                Button {
                    updateController.installAvailableUpdate()
                } label: {
                    Label("Install SuperPaste \(update.version)…", systemImage: "arrow.down.circle.fill")
                }
            } else if updateController.isChecking {
                Button("Checking for Updates…") {}
                    .disabled(true)
            } else {
                Button("Check for Updates…") {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
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
        if appState.hasCompetingInstance {
            Text("Another SuperPaste is running — quit one copy")
        } else if !appState.screenRecordingEnabled || !appState.accessibilityEnabled {
            Text("Setup required — check permissions")
        } else if appState.hotkeyUnavailable {
            Text("Hotkey unavailable — open Diagnostics")
        } else if appState.isPaused {
            Text("Paused — hotkey released")
        } else if appState.isProcessing {
            Text("Working…")
        } else if let provider = UserCredentialStore.activeProvider {
            Text("Ready (\(provider.displayName)) — \(HotkeyPreset.current.shortName)")
        } else if appState.isLicensed {
            Text("Ready — \(HotkeyPreset.current.shortName)")
        } else if let days = appState.trialDaysRemaining {
            Text("Trial: \(days) day\(days == 1 ? "" : "s") left — \(HotkeyPreset.current.shortName)")
        } else {
            Text("Ready — \(HotkeyPreset.current.shortName)")
        }
    }
}
private struct LastFailureMenu: View {
    @ObservedObject var hudState: HUDState

    var body: some View {
        if let failure = hudState.lastFailure {
            Button("Show Last Issue…") {
                hudState.showError(failure)
            }
        }
    }
}

private struct CaptureExclusionMenu: View {
    @ObservedObject var store: CaptureExclusions
    let app: NSRunningApplication?

    var body: some View {
        if let id = app?.bundleIdentifier {
            Button(store.contains(id) ? "Allow capture in \(app?.localizedName ?? id)" : "Never capture \(app?.localizedName ?? id)") {
                store.setExcluded(!store.contains(id), bundleID: id)
            }
        }
    }
}
