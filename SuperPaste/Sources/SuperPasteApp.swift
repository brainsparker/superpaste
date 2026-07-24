import SwiftUI
import Darwin

/// SuperPaste main application entry point
@main
struct SuperPasteApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updateController = UpdateController.shared
    @State private var hudManager: HUDManager?

    init() {
        if CommandLine.arguments.contains("--permissions-status") {
            exit(PermissionStatusReporter.printStatus())
        }
    }

    var body: some Scene {
        // Main window
        WindowGroup {
            MainWindowView()
                .environmentObject(appState)
                .onAppear {
                    setupApp()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 400, height: 350)
        .commands {
            // Remove unwanted menu items
            CommandGroup(replacing: .newItem) {}
        }

        // Settings window (⌘,)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        // Menu bar presence — the only ambient signal that the hotkey is
        // armed, plus pause / recovery / updates without the main window.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: menuBarSymbol)

                if updateController.availableUpdate != nil {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                        .overlay(
                            Circle()
                                .stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1)
                        )
                        .offset(x: 4, y: -3)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityLabel(
                updateController.availableUpdate == nil
                    ? "SuperPaste"
                    : "SuperPaste, update available"
            )
        }
    }

    private var menuBarSymbol: String {
        if appState.isPaused { return "pause.circle" }
        if appState.isProcessing { return "ellipsis.circle" }
        return "option"
    }

    private func setupApp() {
        // Initialize HUD manager
        if hudManager == nil {
            hudManager = HUDManager(hudState: appState.hudState)
            hudManager?.setupKeyboardMonitoring()
        }

        // Register hotkey and start services
        appState.setup()
    }
}
