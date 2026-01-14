import SwiftUI
import ServiceManagement
import HotKey

/// Settings configuration page
struct SettingsPage: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("hudPosition") private var hudPosition: HUDPosition = .topRight
    @AppStorage("playSoundOnReady") private var playSoundOnReady = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var isRecordingHotkey = false
    @State private var currentHotkey = "\u{2325}S"

    // API Key state
    @State private var apiKeyDisplay = ""
    @State private var isTestingKey = false
    @State private var apiKeyTestResult: APIKeyTestResult?

    enum APIKeyTestResult {
        case success
        case error(String)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text("Settings")
                    .font(.title2.bold())

                // API Key section
                apiKeySection

                Divider()

                // Hotkey section
                hotkeySection

                // HUD Position section
                hudPositionSection

                Divider()

                // Other settings
                otherSettingsSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            updateAPIKeyDisplay()
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("API Key")
                .font(.headline)

            // Current key display or empty state
            HStack {
                if APIConfig.hasAPIKey {
                    Text(apiKeyDisplay)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                } else {
                    Text("No API key configured")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if APIConfig.hasAPIKey {
                    Button("Test") {
                        testAPIKey()
                    }
                    .disabled(isTestingKey)

                    Button("Clear") {
                        clearAPIKey()
                    }
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            // Test result
            if isTestingKey {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Testing...")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            } else if let result = apiKeyTestResult {
                switch result {
                case .success:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Key is valid")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                case .error(let message):
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(message)
                            .foregroundColor(.red)
                    }
                    .font(.caption)
                }
            }

            // Help link
            Button {
                NSWorkspace.shared.open(APIConfig.anthropicConsoleURL)
            } label: {
                HStack(spacing: 4) {
                    Text("Get API Key from Anthropic")
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Hotkey Section

    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hotkey")
                .font(.headline)

            HStack {
                Text(currentHotkey)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                Spacer()

                Button("Record New Hotkey") {
                    // TODO: Implement hotkey recording
                    // For now, the hotkey is fixed to Option+S
                }
                .disabled(true)  // Hotkey customization not implemented in v1.0
            }

            Text("Press your preferred key combination")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - HUD Position Section

    private var hudPositionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HUD Position")
                .font(.headline)

            Text("Where the progress indicator appears")
                .font(.caption)
                .foregroundColor(.secondary)

            // Corner picker grid
            HStack(spacing: 4) {
                CornerButton(position: .topLeft, selected: hudPosition == .topLeft) {
                    hudPosition = .topLeft
                }
                CornerButton(position: .topRight, selected: hudPosition == .topRight) {
                    hudPosition = .topRight
                }
            }
            HStack(spacing: 4) {
                CornerButton(position: .bottomLeft, selected: hudPosition == .bottomLeft) {
                    hudPosition = .bottomLeft
                }
                CornerButton(position: .bottomRight, selected: hudPosition == .bottomRight) {
                    hudPosition = .bottomRight
                }
            }
        }
    }

    // MARK: - Other Settings Section

    private var otherSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Play sound when ready to paste", isOn: $playSoundOnReady)

            Toggle("Launch SuperPaste at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    updateLaunchAtLogin(newValue)
                }
        }
    }

    // MARK: - Actions

    private func updateAPIKeyDisplay() {
        if let key = APIConfig.apiKey, !key.isEmpty {
            // Show masked version: first 12 chars...last 4 chars
            if key.count > 20 {
                let prefix = String(key.prefix(12))
                let suffix = String(key.suffix(4))
                apiKeyDisplay = "\(prefix)...\(suffix)"
            } else {
                apiKeyDisplay = String(repeating: "*", count: key.count)
            }
        } else {
            apiKeyDisplay = ""
        }
    }

    private func testAPIKey() {
        guard let key = APIConfig.apiKey else { return }

        isTestingKey = true
        apiKeyTestResult = nil

        Task {
            do {
                _ = try await LLMService.shared.testAPIKey(key)
                await MainActor.run {
                    apiKeyTestResult = .success
                    isTestingKey = false
                }
            } catch let error as LLMService.LLMError {
                await MainActor.run {
                    apiKeyTestResult = .error(error.userFriendlyMessage)
                    isTestingKey = false
                }
            } catch {
                await MainActor.run {
                    apiKeyTestResult = .error("Test failed")
                    isTestingKey = false
                }
            }
        }
    }

    private func clearAPIKey() {
        do {
            try APIConfig.clearAPIKey()
            updateAPIKeyDisplay()
            apiKeyTestResult = nil
            appState.refreshAPIKeyStatus()
        } catch {
            print("Failed to clear API key: \(error)")
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
        }
    }
}

/// A corner selection button
struct CornerButton: View {
    let position: HUDPosition
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: position.icon)
                Text(position.displayName.replacingOccurrences(of: " ", with: "\n"))
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 80, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.blue.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.blue : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
