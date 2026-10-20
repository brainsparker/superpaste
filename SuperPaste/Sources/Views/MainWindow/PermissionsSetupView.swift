import SwiftUI

/// Combined setup view for the two macOS permissions SuperPaste needs.
/// Walks the user through Screen Recording first, then Accessibility.
/// Each permission has its own card with inline status, action button, and
/// — for Screen Recording — a relaunch hint when the toggle is on but the
/// capability probe still fails.
struct PermissionsSetupView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    screenRecordingCard
                    accessibilityCard
                }
                .padding(24)
            }

            Divider()

            privacyFooter
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(width: 400, height: 520)
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

            Text("Two one-time permissions make the magic paste work.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Screen Recording Card

    private var screenRecordingCard: some View {
        PermissionCard(
            icon: "rectangle.inset.filled.and.cursorarrow",
            iconColor: appState.screenRecordingEnabled ? .green : .blue,
            title: "Screen Recording",
            detail: "Captures one snapshot of the active window only when you press \(HotkeyPreset.current.shortName).",
            isEnabled: appState.screenRecordingEnabled,
            actionLabel: appState.screenRecordingEnabled ? nil : "Open System Settings",
            action: { appState.openScreenRecordingSettings() },
            recheckLabel: "Check Again",
            recheckAction: { appState.recheckPermission() },
            relaunchHint: appState.shouldOfferPermissionRelaunch && !appState.screenRecordingEnabled,
            relaunchAction: { appState.relaunchForPermissions() }
        )
    }

    // MARK: - Accessibility Card

    private var accessibilityCard: some View {
        PermissionCard(
            icon: "hand.tap",
            iconColor: appState.accessibilityEnabled ? .green : .blue,
            title: "Accessibility",
            detail: "Sends the paste keystroke after the reply is ready, so there is no preview or manual paste step.",
            isEnabled: appState.accessibilityEnabled,
            actionLabel: appState.accessibilityEnabled
                ? nil
                : (appState.screenRecordingEnabled ? "Open System Settings" : nil),
            action: { appState.openAccessibilitySettings() },
            recheckLabel: "Check Again",
            recheckAction: { appState.recheckPermission() },
            relaunchHint: false,
            relaunchAction: nil
        )
    }

    // MARK: - Footer

    private var privacyFooter: some View {
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
}

// MARK: - Permission Card

private struct PermissionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let detail: String
    let isEnabled: Bool
    let actionLabel: String?
    let action: () -> Void
    let recheckLabel: String
    let recheckAction: () -> Void
    let relaunchHint: Bool
    let relaunchAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Icon + title + status
            HStack(alignment: .center) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 24)

                Text(title)
                    .font(.headline)

                Spacer()

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isEnabled ? .green : .secondary)
                    .font(.subheadline)
                    .accessibilityLabel(isEnabled ? "\(title) enabled" : "\(title) not enabled")
            }

            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !isEnabled {
                // Action buttons
                VStack(spacing: 8) {
                    if let actionLabel {
                        Button {
                            action()
                        } label: {
                            HStack {
                                Image(systemName: "gear")
                                Text(actionLabel)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    HStack(spacing: 8) {
                        Button {
                            recheckAction()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(recheckLabel)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }

                // Relaunch hint — shown when Screen Recording was toggled on
                // but the capability probe still fails (macOS needs a relaunch).
                if relaunchHint, let relaunchAction {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("If System Settings already shows SuperPaste enabled, relaunch once to finish applying Screen Recording.")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "arrow.triangle.swap")
                                .foregroundColor(.orange)
                        }
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                        Button {
                            relaunchAction()
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Relaunch SuperPaste")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
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

            // Heads-up about the monthly reminder macOS shows for screen-recording apps
            if title == "Screen Recording" {
                Text("Heads up: macOS shows every screenshot app a monthly \u{201C}can record your screen\u{201D} reminder. That\u{2019}s the OS being cautious, not SuperPaste doing anything new \u{2014} it still captures one frame of one window, only when you press the hotkey.")
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