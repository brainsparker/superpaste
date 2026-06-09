import SwiftUI

/// Settings tab identifier
enum SettingsTab: String, CaseIterable, Identifiable {
    case about = "About"
    case howItWorks = "How It Works"
    case permissions = "Permissions"
    case settings = "Settings"
    case resources = "Resources"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .about: return "info.circle"
        case .howItWorks: return "sparkles"
        case .permissions: return "lock.shield"
        case .settings: return "gear"
        case .resources: return "arrow.up.right"
        }
    }
}

/// Main settings window container with sidebar navigation
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .about

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(160)
        } detail: {
            // Content
            switch selectedTab {
            case .about:
                AboutPage()
            case .howItWorks:
                HowItWorksPage()
            case .permissions:
                PermissionsView()
                    .environmentObject(appState)
            case .settings:
                SettingsPage()
                    .environmentObject(appState)
            case .resources:
                ResourcesPage()
            }
        }
        .frame(width: 650, height: 500)
    }
}
