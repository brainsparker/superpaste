import SwiftUI
import ServiceManagement

/// View displayed when SuperPaste is fully configured and ready to use.
struct ReadyView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // Ready status
            readyStatusSection
                .padding(.vertical, 16)

            // Instructions
            instructionsSection
                .padding(.horizontal, 24)

            Divider()
                .padding(.top, 16)

            // Status indicators
            statusSection
                .padding(24)

            Divider()

            // Footer
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
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SuperPaste")
                .font(.title.bold())

            Text("Press \u{2325}V. Text appears.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Ready Status

    private var readyStatusSection: some View {
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
                Text("Ready to go!")
                    .foregroundColor(.green)
                    .fontWeight(.medium)
            }
        }
        .font(.subheadline)
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How it works:")
                .font(.headline)

            InstructionRow(number: 1, text: "Place your cursor in the field you want filled")
            InstructionRow(number: 2, text: "Press \u{2325}V")
            InstructionRow(number: 3, text: "Text appears automatically")
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Status Section

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)

            // Screen Recording status
            HStack {
                Image(systemName: "rectangle.inset.filled.and.cursorarrow")
                    .foregroundColor(.secondary)
                Text("Screen Recording")
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Enabled")
                        .foregroundColor(.green)
                }
            }
            .font(.subheadline)

            // Accessibility status
            HStack {
                Image(systemName: "figure.arms.open")
                    .foregroundColor(.secondary)
                Text("Accessibility")
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Enabled")
                        .foregroundColor(.green)
                }
            }
            .font(.subheadline)
        }
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

            Text("Powered by Claude AI")
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

/// A single instruction row (reused from original MainWindowView)
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
