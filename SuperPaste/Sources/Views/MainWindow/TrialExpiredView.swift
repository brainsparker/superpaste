import SwiftUI

/// View displayed when the 7-day free trial has ended.
struct TrialExpiredView: View {
    @EnvironmentObject var appState: AppState
    @State private var licenseKeyInput = ""

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            upgradeCard
                .padding(24)

            Divider()

            licenseSection
                .padding(24)
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

            Text("Press Option V. Text appears.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Upgrade Card

    private var upgradeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "hourglass")
                    .font(.title2)
                    .foregroundColor(.orange)

                Text("Your free trial has ended")
                    .font(.headline)
            }

            Text("Get full access for $5/month — no annual commitment, cancel anytime.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if let url = URL(string: "https://buy.polar.sh/polar_cl_YS3DZpcmFoh7GDvDvRxWezZLUmPKgwf9Mb6T618NFdC") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.up.right.square")
                    Text("Get SuperPaste — $5/month")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    // MARK: - License Entry

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Already have a license key?")
                .font(.subheadline)
                .fontWeight(.medium)

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

            activationStatusView
        }
    }

    @ViewBuilder
    private var activationStatusView: some View {
        switch appState.licenseActivationState {
        case .idle:
            EmptyView()
        case .validating:
            EmptyView()
        case .success:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("License activated. Welcome back!")
                    .foregroundColor(.green)
            }
            .font(.caption)
        case .failure(let message):
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .foregroundColor(.red)
            }
            .font(.caption)
        }
    }
}
