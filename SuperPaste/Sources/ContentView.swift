import SwiftUI

/// Root content view - delegates to MainWindowView
struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        MainWindowView()
            .environmentObject(appState)
    }
}
