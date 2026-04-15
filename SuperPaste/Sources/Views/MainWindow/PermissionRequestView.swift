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
