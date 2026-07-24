import SwiftUI

/// Main window view that routes to the appropriate state view.
struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            switch appState.mainWindowState {
            case .welcome:
                WelcomeView()
                    .environmentObject(appState)

            case .permissionRequired:
                PermissionsSetupView()
                    .environmentObject(appState)

            case .accessibilityRequired:
                PermissionsSetupView()
                    .environmentObject(appState)

            case .trialExpired:
                TrialExpiredView()
                    .environmentObject(appState)

            case .ready:
                ReadyView()
                    .environmentObject(appState)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.mainWindowState)
        .onAppear {
            // The HUD is hosted in a standalone NSHostingView, outside this
            // scene's environment. Bridge the supported Sonoma+ Settings
            // action from here instead of falling back to a dead selector.
            appState.hudState.onOpenSettings = {
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
