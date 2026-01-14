import SwiftUI

/// View displayed when API key configuration is required.
struct APIKeyEntryView: View {
    @EnvironmentObject var appState: AppState

    @State private var apiKey = ""
    @State private var isTestingKey = false
    @State private var testError: String?
    @State private var testSuccess = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // Status section
            statusSection
                .padding(.vertical, 12)

            Divider()

            // API Key entry
            apiKeySection
                .padding(24)
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SuperPaste")
                .font(.title.bold())

            Text("See your screen. Write your response.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Screen Recording")
                .foregroundColor(.secondary)

            Spacer()

            Text("Enabled")
                .foregroundColor(.green)
                .font(.subheadline.weight(.medium))
        }
        .font(.subheadline)
        .padding(.horizontal, 24)
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("API Key")
                .font(.headline)

            // API Key input
            SecureField("sk-ant-api03-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .disabled(isTestingKey)

            // Test button and status
            HStack {
                Button {
                    testAPIKey()
                } label: {
                    if isTestingKey {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                    } else {
                        Text("Test Key")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty || isTestingKey)

                if let error = testError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                    }
                    .font(.caption)
                } else if testSuccess {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Valid key!")
                            .foregroundColor(.green)
                    }
                    .font(.caption)
                }

                Spacer()
            }

            // Help link
            HStack {
                Text("Don't have one?")
                    .foregroundColor(.secondary)

                Button {
                    NSWorkspace.shared.open(APIConfig.anthropicConsoleURL)
                } label: {
                    HStack(spacing: 4) {
                        Text("Get API Key from Anthropic")
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(.link)
            }
            .font(.caption)
        }
    }

    // MARK: - Actions

    private func testAPIKey() {
        guard !apiKey.isEmpty else { return }

        isTestingKey = true
        testError = nil
        testSuccess = false

        Task {
            do {
                _ = try await LLMService.shared.testAPIKey(apiKey)

                // Key is valid, save it
                try APIConfig.saveAPIKey(apiKey)

                await MainActor.run {
                    testSuccess = true
                    isTestingKey = false

                    // Refresh app state to transition to Ready view
                    appState.refreshAPIKeyStatus()
                }
            } catch let error as LLMService.LLMError {
                await MainActor.run {
                    testError = error.userFriendlyMessage
                    isTestingKey = false
                }
            } catch {
                await MainActor.run {
                    testError = "Failed to validate key"
                    isTestingKey = false
                }
            }
        }
    }
}
