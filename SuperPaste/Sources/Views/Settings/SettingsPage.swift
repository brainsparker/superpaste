import SwiftUI

/// Settings configuration page
struct SettingsPage: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("hudPosition") private var hudPosition: HUDPosition = .topRight
    @AppStorage("playSoundOnReady") private var playSoundOnReady = false
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("personalContext") private var personalContext = ""
    @AppStorage("responseTone") private var responseTone: ResponseTone = .matchContext
    @AppStorage("responseLength") private var responseLength: ResponseLength = .balanced

    @AppStorage("hotkeyPreset") private var hotkeyPreset: HotkeyPreset = .optionV
    @State private var licenseKeyInput = ""
    @State private var apiKeyInput = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.title2.bold())

                // License section
                licenseSection

                // Bring-your-own-key section
                apiKeySection

                Divider()

                // About You section
                aboutYouSection

                Divider()

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

    // MARK: - License Section

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("License")
                .font(.headline)

            if appState.isLicensed {
                // Licensed state
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Licensed — thank you!")
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                    Spacer()
                    Button("Remove") {
                        appState.removeLicense()
                        licenseKeyInput = ""
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                }
                .font(.subheadline)
                .padding(.vertical, 4)
            } else {
                // Unlicensed — show entry field
                Text("Enter your license key to unlock full access.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("Paste license key", text: $licenseKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .disabled(appState.licenseActivationState == .validating)

                    Button {
                        appState.activateLicense(licenseKeyInput)
                    } label: {
                        if appState.licenseActivationState == .validating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 60)
                        } else {
                            Text("Activate")
                                .frame(width: 60)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || appState.licenseActivationState == .validating)
                }

                switch appState.licenseActivationState {
                case .success:
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Activated!").foregroundColor(.green)
                    }
                    .font(.caption)
                case .failure(let message):
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        Text(message).foregroundColor(.red)
                    }
                    .font(.caption)
                default:
                    Button {
                        if let url = URL(string: "https://buy.polar.sh/polar_cl_YS3DZpcmFoh7GDvDvRxWezZLUmPKgwf9Mb6T618NFdC") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Text("Get a license — $5/month →")
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Bring Your Own Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Use Your Own Anthropic API Key")
                .font(.headline)

            if appState.usingOwnAPIKey {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundColor(.green)
                    Text("Using your API key — requests go straight from your Mac to Anthropic. No subscription needed.")
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Remove") {
                        appState.clearUserAPIKey()
                        apiKeyInput = ""
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                }
                .font(.caption)
                .padding(.vertical, 4)
            } else {
                Text("SuperPaste is free forever with your own key: screenshots go directly to Anthropic, never through SuperPaste's servers. You pay Anthropic for what you use (typically well under a cent per paste).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    SecureField("sk-ant-…", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    Button("Save") {
                        appState.setUserAPIKey(apiKeyInput)
                        apiKeyInput = ""
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Link("Get an API key from Anthropic →",
                     destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - About You Section

    private var aboutYouSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About You")
                .font(.headline)

            Text("Help SuperPaste write in your voice.")
                .font(.caption)
                .foregroundColor(.secondary)

            ZStack(alignment: .topLeading) {
                // Placeholder
                if personalContext.isEmpty {
                    Text("I'm a product manager at a tech company. I prefer direct, concise communication. For emails I lean professional but warm. When I'm writing code it's usually Swift or Python.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(nsColor: .placeholderTextColor))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $personalContext)
                    .font(.system(size: 13))
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            Text("The more context you give, the better SuperPaste matches your style and intent.")
                .font(.caption)
                .foregroundColor(.secondary)
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

            Picker("Hotkey", selection: $hotkeyPreset) {
                ForEach(HotkeyPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text("Press \(hotkeyPreset.displayName) from any app while SuperPaste is running to instantly fill the focused field. Pick a different combination if the default collides with another shortcut or your keyboard layout (\u{2325}V is a dead key on some European layouts).")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
                .onChange(of: launchAtLogin) { _, newValue in
                    appState.setLaunchAtLogin(newValue)
                }

            Text("Keep this on so the hotkey is available after login without opening SuperPaste manually.")
                .font(.caption)
                .foregroundColor(.secondary)
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
