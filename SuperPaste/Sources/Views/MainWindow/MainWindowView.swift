import SwiftUI
import ServiceManagement

/// Main window view showing app status and instructions
struct MainWindowView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            // Header section
            headerSection
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // Status section
            statusSection
                .padding(.vertical, 16)

            // Instructions section
            instructionsSection
                .padding(.horizontal, 24)

            Divider()
                .padding(.top, 16)

            // Footer section
            footerSection
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            // App icon placeholder
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SuperPaste")
                .font(.title.bold())

            Text("Copy context. ⌥S. Paste.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        HStack(spacing: 8) {
            if appState.isProcessing {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Processing...")
                    .foregroundColor(.secondary)
            } else if let error = appState.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Ready")
                    .foregroundColor(.secondary)
            }
        }
        .font(.subheadline)
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How it works:")
                .font(.headline)

            InstructionRow(number: 1, text: "Copy some text for context (optional)")
            InstructionRow(number: 2, text: "Press ⌥S anywhere")
            InstructionRow(number: 3, text: "Press ⌘V to paste the response")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { newValue in
                        updateLaunchAtLogin(newValue)
                    }

                Spacer()

                Button {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                } label: {
                    Image(systemName: "gear")
                    Text("Settings")
                }
            }
            .font(.subheadline)

            Text("Powered by You.com")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Launch at Login

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently fail - not critical
            print("Failed to update launch at login: \(error)")
        }
    }
}

/// A single instruction row
struct InstructionRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.blue))

            Text(text)
                .font(.subheadline)
        }
    }
}
