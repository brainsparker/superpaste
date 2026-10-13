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
    @State private var selectedProvider: LLMProviderID = LLMService.currentConfig().provider
    @State private var customModelInput: String = LLMService.currentConfig().model
    @State private var customEndpointInput: String = LLMService.currentConfig().customEndpoint
    @State private var apiKeyInput: String = ""
    @State private var isAdvancedExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("General")
                    .font(.title2.bold())

                aboutYouSection

                responseBehaviorSection

                hotkeySection

                hudPositionSection

                Divider()

                otherSettingsSection

                Divider()

                licenseSection

                Divider()

                aiProviderSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: selectedProvider) { _, newProvider in
            saveProviderChange(provider: newProvider)
        }
    }

    // MARK: - AI Provider Section

    /// Result of the last `/v1/models` probe against an endpoint-configured provider.
    private enum ConnectionStatus: Equatable {
        case idle
        case checking
        case connected(modelCount: Int)
        case failed(String)
    }

    @State private var discoveredModels: [LocalModelServer.Model] = []
    @State private var connectionStatus: ConnectionStatus = .idle

    private var aiProviderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI Provider")
                .font(.headline)

            Text("Choose which AI service powers your pastes: the hosted SuperPaste backend, your own API key from Anthropic, OpenAI, or OpenRouter, a model running on this Mac through Ollama or LM Studio, or any custom OpenAI-compatible endpoint.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Provider picker
            Picker("Provider", selection: $selectedProvider) {
                ForEach(LLMProviderID.allCases) { provider in
                    HStack {
                        Text(provider.displayName)
                    }.tag(provider)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            // Provider description
            Text(selectedProvider.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Endpoint (local servers and custom)
            if selectedProvider.supportsCustomEndpoint {
                endpointField
            }

            // Model field (hidden for superpaste)
            if selectedProvider.supportsCustomModel {
                modelField
            }

            // API key section per provider
            apiKeyField(for: selectedProvider)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .task(id: discoveryKey) {
            await refreshModels(debounce: true)
        }
    }

    /// Changes to either value re-run model discovery.
    private var discoveryKey: String {
        "\(selectedProvider.rawValue)|\(customEndpointInput)"
    }

    private var endpointField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedProvider.isLocal ? "Server address" : "API Endpoint")
                .font(.subheadline.weight(.medium))
            TextField(selectedProvider.endpointPlaceholder, text: $customEndpointInput)
                .textFieldStyle(.roundedBorder)
                .onChange(of: customEndpointInput) { _, _ in
                    saveProviderChange(provider: selectedProvider)
                }
            Text(endpointHelpText)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var endpointHelpText: String {
        guard selectedProvider.isLocal else {
            return "Paste the base URL (ending in /v1) or the full chat-completions URL. Both work."
        }
        let typed = customEndpointInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            return "Leave empty for the default (\(LocalEndpoint.displayHost(selectedProvider.endpointURL))). Change it only if you moved the server to another port or machine."
        }
        if LocalEndpoint.isLoopback(typed) {
            return "Reaches \(LocalEndpoint.displayHost(typed)) on this Mac. Screenshots stay local."
        }
        return "Reaches \(LocalEndpoint.displayHost(typed)) over the network. Screenshots leave this Mac."
    }

    private var modelField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Model")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if selectedProvider.supportsModelDiscovery {
                    connectionStatusLabel
                    Button {
                        Task { await refreshModels(debounce: false) }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .help("Ask the server which models are installed")
                    .disabled(connectionStatus == .checking)
                }
            }

            if selectedProvider.supportsModelDiscovery && !discoveredModels.isEmpty {
                Picker("Installed models", selection: $customModelInput) {
                    Text(selectedProvider.isLocal ? "Auto (first vision model on the server)" : "Auto (first model on the server)")
                        .tag("")
                    ForEach(ModelCapabilityHint.sortedForPicker(discoveredModels.map(\.id)), id: \.self) { id in
                        Text(ModelCapabilityHint.likelySupportsVision(id) ? "\(id)  (vision)" : id)
                            .tag(id)
                    }
                    if !customModelInput.isEmpty && !discoveredModels.contains(where: { $0.id == customModelInput }) {
                        Text("\(customModelInput)  (not installed)").tag(customModelInput)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .onChange(of: customModelInput) { _, _ in
                    saveProviderChange(provider: selectedProvider)
                }
            } else {
                TextField(selectedProvider.supportsModelDiscovery ? "Leave empty to use the first installed model" : "Model identifier", text: $customModelInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: customModelInput) { _, _ in
                        saveProviderChange(provider: selectedProvider)
                    }
            }

            Text(selectedProvider.modelHint)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if selectedProvider.supportsModelDiscovery,
               !customModelInput.isEmpty,
               !discoveredModels.isEmpty,
               !ModelCapabilityHint.likelySupportsVision(customModelInput) {
                Label("This model may not read screenshots. Vision models are marked in the list.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var connectionStatusLabel: some View {
        switch connectionStatus {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 14, height: 14)
        case .connected(let count):
            Label(count == 1 ? "Connected, 1 model" : "Connected, \(count) models", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundColor(.orange)
                .lineLimit(1)
                .help(message)
        }
    }

    /// Probes `/v1/models` on the configured endpoint. Runs automatically when
    /// the provider or endpoint changes (debounced so typing doesn't hammer the
    /// server) and on demand from the refresh button.
    @MainActor
    private func refreshModels(debounce: Bool) async {
        guard selectedProvider.supportsModelDiscovery else {
            connectionStatus = .idle
            discoveredModels = []
            return
        }
        if debounce {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
        }
        let config = LLMProviderConfig(
            provider: selectedProvider,
            model: customModelInput,
            customEndpoint: customEndpointInput
        )
        guard let endpoint = config.resolvedEndpoint else {
            connectionStatus = .idle
            discoveredModels = []
            return
        }
        connectionStatus = .checking
        do {
            let models = try await LocalModelServer.listModels(
                chatCompletionsURL: endpoint,
                apiKey: UserCredentialStore.apiKey(for: selectedProvider)
            )
            if Task.isCancelled { return }
            discoveredModels = models
            connectionStatus = models.isEmpty
                ? .failed(selectedProvider == .ollama ? "Connected, no models yet. Run: ollama pull qwen3-vl" : "Connected, no models loaded")
                : .connected(modelCount: models.count)
        } catch let error as LocalModelServer.ListError {
            if Task.isCancelled { return }
            discoveredModels = []
            switch error {
            case .unreachable:
                connectionStatus = .failed(selectedProvider.isLocal
                    ? "\(selectedProvider == .ollama ? "Ollama" : "LM Studio") isn't running at \(LocalEndpoint.displayHost(endpoint))"
                    : "Nothing answering at \(LocalEndpoint.displayHost(endpoint))")
            default:
                connectionStatus = .failed(error.errorDescription ?? "Couldn't reach the server")
            }
        } catch {
            if Task.isCancelled { return }
            discoveredModels = []
            connectionStatus = .failed("Couldn't reach the server")
        }
    }

    @ViewBuilder
    private func apiKeyField(for provider: LLMProviderID) -> some View {
        if provider.isBringYourOwnKey {
            let hasKey = UserCredentialStore.apiKey(for: provider) != nil
            VStack(alignment: .leading, spacing: 8) {
                if hasKey {
                    HStack(spacing: 8) {
                        Image(systemName: "key.fill")
                            .foregroundColor(.green)
                        Text(provider.requiresAPIKey
                             ? "Using your \(provider.displayName) API key: requests go directly to \(provider.displayName), not through SuperPaste's servers."
                             : "Sending your saved key to this server with every request.")
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Remove") {
                            appState.clearAPIKey(for: provider)
                            apiKeyInput = ""
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                } else if provider.requiresAPIKey {
                    Text("SuperPaste is free forever with your own key: screenshots go directly to \(provider.displayName). You pay them for what you use (typically well under a cent per paste).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        SecureField("Paste your \(provider.displayName) API key", text: $apiKeyInput)
                            .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            appState.setAPIKey(apiKeyInput, for: provider)
                            apiKeyInput = ""
                        }
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } else {
                    DisclosureGroup("API key (optional)") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(provider.isLocal
                                 ? "\(provider.displayName) doesn't need a key. Add one only if you turned on authentication in the server's settings."
                                 : "Leave this empty for servers that don't check credentials. Saved keys stay in the macOS Keychain.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                SecureField("API key", text: $apiKeyInput)
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") {
                                    appState.setAPIKey(apiKeyInput, for: provider)
                                    apiKeyInput = ""
                                    Task { await refreshModels(debounce: false) }
                                }
                                .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.caption)
                }

                if let url = provider.signupURL, !hasKey || provider.isLocal {
                    Link("\(provider.signupLabel) \u{2192}", destination: url)
                        .font(.caption)
                }
            }
        }
    }

    private func saveProviderChange(provider: LLMProviderID) {
        let config = LLMProviderConfig(
            provider: provider,
            model: provider.supportsCustomModel ? customModelInput : provider.defaultModel,
            customEndpoint: provider.supportsCustomEndpoint ? customEndpointInput : ""
        )
        appState.setProviderConfig(config)
    }

    // MARK: - License Section

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plan & License")
                .font(.headline)

            if appState.isLicensed {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Licensed \u{2014} thank you!")
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
                Text("Enter your license key to unlock the hosted SuperPaste plan.")
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
                        Text("Get a license \u{2014} $5/month \u{2192}")
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

    // MARK: - About You Section

    private var aboutYouSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Style")
                .font(.headline)

            Text("Help SuperPaste write in your voice.")
                .font(.caption)
                .foregroundColor(.secondary)

            ZStack(alignment: .topLeading) {
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
            Text("Keyboard Shortcut")
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
            Text("Writing Style")
                .font(.headline)

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
            Text("Status Bubble")
                .font(.headline)

            HStack {
                Text("Where the SuperPaste status bubble appears")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Preview") {
                    appState.previewHUD()
                }
                .controlSize(.small)
                .disabled(appState.isProcessing)
            }

            HStack(spacing: 4) {
                CornerButton(position: .topLeft, selected: hudPosition == .topLeft) { hudPosition = .topLeft }
                CornerButton(position: .topRight, selected: hudPosition == .topRight) { hudPosition = .topRight }
            }
            HStack(spacing: 4) {
                CornerButton(position: .bottomLeft, selected: hudPosition == .bottomLeft) { hudPosition = .bottomLeft }
                CornerButton(position: .bottomRight, selected: hudPosition == .bottomRight) { hudPosition = .bottomRight }
            }
        }
    }

    // MARK: - Other Settings Section

    private var otherSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Behavior")
                .font(.headline)
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