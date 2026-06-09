import SwiftUI

/// Main window view that routes to the appropriate state view.
struct MainWindowView: View {
    @EnvironmentObject var appState: AppState

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
    }
}
