import SwiftUI

/// View displayed when Accessibility permission is required for auto-paste.
struct AccessibilityRequestView: View {
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
                Image(systemName: "hand.tap")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text("One Step, Not Two")
                    .font(.headline)
            }

            Text("Without this, you'd press Option V and then manually paste with \u{2318}V. With it, the text appears in your field the instant it's ready — nothing else to do.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .foregroundColor(.green)
                    .font(.caption)

                Text("SuperPaste only sends a \u{2318}V keystroke. It cannot read text, passwords, or anything else from other apps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 4)

            Button {
                appState.openAccessibilitySettings()
            } label: {
                HStack {
                    Image(systemName: "gear")
                    Text("Enable Auto-Paste")
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
            Text("After clicking, find SuperPaste under System Settings \u{203A} Privacy & Security \u{203A} Accessibility and toggle it on.")
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
