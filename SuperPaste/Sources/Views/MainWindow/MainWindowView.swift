import SwiftUI

/// Main window view that routes to the appropriate state view.
struct MainWindowView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            switch appState.mainWindowState {
            case .permissionRequired:
                PermissionRequestView()
                    .environmentObject(appState)

            case .accessibilityRequired:
                AccessibilityRequestView()
                    .environmentObject(appState)

            case .ready:
                ReadyView()
                    .environmentObject(appState)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.mainWindowState)
    }
}
