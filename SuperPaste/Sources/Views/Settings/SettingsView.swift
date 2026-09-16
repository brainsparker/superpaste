import SwiftUI

/// Settings tab identifier
enum SettingsTab: String, CaseIterable, Identifiable {
    case about = "About"
    case quickStart = "Quick Start"
    case permissions = "Permissions"
    case general = "General"
    case help = "Help"
    case diagnostics = "Diagnostics"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .about: return "info.circle"
        case .quickStart: return "sparkles"
        case .permissions: return "lock.shield"
        case .general: return "gear"
        case .diagnostics: return "stethoscope"
        case .help: return "questionmark.circle"
        }
    }
}

/// Main settings window container with sidebar navigation
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var updateController = UpdateController.shared
    @State private var selectedTab: SettingsTab = .about

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                HStack {
                    Label(tab.rawValue, systemImage: tab.icon)
                    Spacer()
                    if tab == .about && updateController.availableUpdate != nil {
                        Circle()
                            .fill(.red)
                            .frame(width: 7, height: 7)
                            .accessibilityLabel("Update available")
                    }
                }
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(160)
        } detail: {
            // Content
            switch selectedTab {
            case .about:
                AboutPage()
            case .quickStart:
                HowItWorksPage()
            case .permissions:
                PermissionsView()
                    .environmentObject(appState)
            case .general:
                SettingsPage()
                    .environmentObject(appState)
            case .diagnostics:
                DiagnosticsPage()
                    .environmentObject(appState)
            case .help:
                ResourcesPage()
            }
        }
        .frame(width: 650, height: 500)
    }
}
