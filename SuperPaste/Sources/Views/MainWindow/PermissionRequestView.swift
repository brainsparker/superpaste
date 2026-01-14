import SwiftUI

/// View displayed when Screen Recording permission is required.
struct PermissionRequestView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            // Permission request card
            permissionCard
                .padding(24)

            // Footer instructions
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

    // MARK: - Permission Card

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Icon and title
            HStack(spacing: 12) {
                Image(systemName: "rectangle.inset.filled.and.cursorarrow")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("Screen Recording Required")
                    .font(.headline)
            }

            // Description
            Text("SuperPaste needs to see your screen to understand what you're looking at and generate helpful responses.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Privacy note
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundColor(.green)
                    .font(.caption)

                Text("Screenshots are sent to Claude AI for processing and are not stored.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            // Enable button
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
            Text("After clicking, find SuperPaste in System Settings and toggle it ON. Then return here.")
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
