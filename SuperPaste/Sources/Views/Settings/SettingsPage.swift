import SwiftUI
import ServiceManagement
import HotKey

/// Settings configuration page
struct SettingsPage: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("hudPosition") private var hudPosition: HUDPosition = .topRight
    @AppStorage("playSoundOnReady") private var playSoundOnReady = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("responseTone") private var responseTone: ResponseTone = .matchContext
    @AppStorage("responseLength") private var responseLength: ResponseLength = .balanced

    @State private var currentHotkey = "\u{2325}V"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.title2.bold())

                // Hotkey section
                hotkeySection

                // Response behavior
                responseBehaviorSection

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
            }

            Text("Press \u{2325}V from any app to instantly fill the focused field.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Response Behavior Section

    private var responseBehaviorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Response behavior")
                .font(.headline)

            // Tone picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Tone")
                    .font(.subheadline.weight(.medium))

                Picker("Tone", selection: $responseTone) {
                    ForEach(ResponseTone.allCases) { tone in
                        Text(tone.displayName).tag(tone)
                    }
                }
                .pickerStyle(.segmented)

                Text(responseTone.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Length picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Length")
                    .font(.subheadline.weight(.medium))

                Picker("Length", selection: $responseLength) {
                    ForEach(ResponseLength.allCases) { length in
                        Text(length.displayName).tag(length)
                    }
                }
                .pickerStyle(.segmented)

                Text(responseLength.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - HUD Position Section

    private var hudPositionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HUD Position")
                .font(.headline)

            Text("Where the progress indicator appears")
                .font(.caption)
                .foregroundColor(.secondary)

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
            Toggle("Play sound when ready", isOn: $playSoundOnReady)

            Toggle("Launch SuperPaste at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    updateLaunchAtLogin(newValue)
                }
        }
    }

    // MARK: - Actions

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
