import SwiftUI

/// Combined setup view for the two macOS permissions SuperPaste needs.
struct PermissionsSetupView: View {
    @EnvironmentObject var appState: AppState

    private var nextPermissionTitle: String {
        if !appState.screenRecordingEnabled {
            return "Enable Screen Recording"
        }
        if !appState.accessibilityEnabled {
            return "Enable Auto-Paste"
        }
        return "Check Again"
    }

    private var nextPermissionIcon: String {
        if !appState.screenRecordingEnabled {
            return "rectangle.inset.filled.and.cursorarrow"
        }
        if !appState.accessibilityEnabled {
            return "hand.tap"
        }
        return "arrow.clockwise"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            permissionSection
                .padding(24)

            Divider()

            footerSection
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SuperPaste")
                .font(.title.bold())

            Text("Press Option V. Text appears.")

            Text("Two one-time permissions make the magic paste work.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            PermissionSetupRow(
                icon: "rectangle.inset.filled.and.cursorarrow",
                title: "Screen Recording",
                detail: "Captures one snapshot of the active window only when you press Option V.",
                isEnabled: appState.screenRecordingEnabled
            )

            PermissionSetupRow(
                icon: "hand.tap",
                title: "Accessibility",
                detail: "Sends the paste keystroke after the reply is ready, so there is no preview or manual paste step.",
                isEnabled: appState.accessibilityEnabled
            )

            Button {
                openNextPermission()
            } label: {
                HStack {
                    Image(systemName: nextPermissionIcon)
                    Text(nextPermissionTitle)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("After you enable a permission in System Settings, return here. SuperPaste keeps checking and moves on automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if appState.shouldOfferPermissionRelaunch && !appState.screenRecordingEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("If System Settings already shows SuperPaste enabled, relaunch once to finish applying Screen Recording.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        appState.relaunchForPermissions()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Relaunch SuperPaste")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
            }
        }
    }

    private var footerSection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.green)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Narrow by design")
                    .font(.caption.weight(.semibold))
                Text("No recording, no continuous monitoring, no app switching during use. One hotkey captures the active window, asks the backend, and pastes into the focused field.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private func openNextPermission() {
        if !appState.screenRecordingEnabled {
            appState.openScreenRecordingSettings()
        } else if !appState.accessibilityEnabled {
            appState.openAccessibilitySettings()
        } else {
            appState.recheckPermission()
        }
    }
}

private struct PermissionSetupRow: View {
    let icon: String
    let title: String
    let detail: String
    let isEnabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isEnabled ? .green : .blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)

                    Spacer()

                    Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isEnabled ? .green : .secondary)
                        .font(.subheadline)
                        .accessibilityLabel(isEnabled ? "Enabled" : "Not enabled")
                }

                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isEnabled ? Color.green.opacity(0.35) : Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
