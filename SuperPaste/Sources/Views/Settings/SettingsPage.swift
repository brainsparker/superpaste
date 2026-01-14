import SwiftUI
import ServiceManagement
import HotKey

/// Settings configuration page
struct SettingsPage: View {
    @AppStorage("hudPosition") private var hudPosition: HUDPosition = .topRight
    @AppStorage("playSoundOnReady") private var playSoundOnReady = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var isRecordingHotkey = false
    @State private var currentHotkey = "⌥S"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text("Settings")
                    .font(.title2.bold())

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

    // MARK: - Launch at Login

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
