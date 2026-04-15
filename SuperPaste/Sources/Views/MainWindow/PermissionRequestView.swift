import SwiftUI

/// View displayed when Screen Recording permission is required.
struct PermissionRequestView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            permissionCard
                .padding(24)

            privacySection
                .padding(.bottom, 16)

            footerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
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

            Text("Sees your screen. Writes what you need.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Permission Card

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.inset.filled.and.cursorarrow")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Screen Recording")
                    .font(.headline)
            }

            Text("SuperPaste takes a single snapshot of your active window the moment you press Option V — so it knows exactly what you're looking at without you having to copy text, switch apps, or explain anything.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundColor(.green)
                    .font(.caption)

                Text("No recording, no continuous monitoring. One screenshot, on demand, sent to Claude and immediately discarded.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            Button {
                appState.openScreenRecordingSettings()
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Enable Screen Recording")
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

    // MARK: - Privacy Reassurance

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What SuperPaste does NOT do:")
                .font(.caption.weight(.semibold))

            PrivacyPoint(text: "Record video or continuous screenshots")
            PrivacyPoint(text: "Store screenshots after processing")
            PrivacyPoint(text: "Access files, passwords, or other private data")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 24)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Text("After clicking, find SuperPaste in System Settings and toggle it on. Then come back here.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button {
                appState.recheckPermission()
            } label: {
                Text("I've enabled it")
            }
            .buttonStyle(.bordered)
        }
    }
}

/// A single privacy reassurance point with a checkmark
struct PrivacyPoint: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .foregroundColor(.red.opacity(0.6))
                .frame(width: 14)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
