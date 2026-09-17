import SwiftUI

/// About page showing app identity, version, and update controls.
struct AboutPage: View {
    @ObservedObject private var updateController = UpdateController.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 78, height: 78)
                    .shadow(color: .black.opacity(0.18), radius: 9, y: 4)

                VStack(spacing: 4) {
                    Text("SuperPaste")
                        .font(.title.bold())

                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("Sees your active window. Writes what you need.")
                    .font(.body.weight(.medium))
                    .foregroundColor(.secondary)

                Text("Press \u{2325}V anywhere and the right words appear at your cursor. No copying, prompting, or app switching.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)

                updateSection

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    Text("Captures one window only when you press the shortcut")
                }
                .font(.caption.weight(.medium))
                .foregroundColor(.secondary)

                Text("AI by Anthropic")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Link("Created by sparker.ai", destination: URL(string: "https://sparker.ai")!)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text("\u{00A9} \(currentYear) All rights reserved.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                updateStatusIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(updateStatusTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(updateStatusDetail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let update = updateController.availableUpdate {
                    Button("Install \(update.version)") {
                        updateController.installAvailableUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Check Now") {
                        updateController.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        !updateController.canCheckForUpdates
                            || updateController.isChecking
                    )
                }
            }

            Divider()

            Toggle(
                "Automatically keep SuperPaste up to date",
                isOn: Binding(
                    get: { updateController.automaticallyKeepsUpToDate },
                    set: { updateController.setAutomaticallyKeepsUpToDate($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: 390)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    updateController.availableUpdate == nil
                        ? Color(nsColor: .separatorColor)
                        : Color.red.opacity(0.35),
                    lineWidth: 1
                )
        )
    }

    @ViewBuilder
    private var updateStatusIcon: some View {
        if updateController.isChecking {
            ProgressView()
                .controlSize(.small)
                .frame(width: 22)
        } else if updateController.availableUpdate != nil {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.red)
                .font(.title3)
                .frame(width: 22)
        } else if updateController.lastCheckError != nil {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
                .font(.title3)
                .frame(width: 22)
        } else if !updateController.hasCompletedCheck {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .foregroundColor(.secondary)
                .font(.title3)
                .frame(width: 22)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.title3)
                .frame(width: 22)
        }
    }

    private var updateStatusTitle: String {
        if updateController.isChecking {
            return "Checking for updates…"
        }
        if let update = updateController.availableUpdate {
            return "SuperPaste \(update.version) is ready"
        }
        if updateController.lastCheckError != nil {
            return "Couldn’t check for updates"
        }
        if !updateController.hasCompletedCheck {
            return "Updates are automatic"
        }
        return "You’re up to date"
    }

    private var updateStatusDetail: String {
        if updateController.availableUpdate != nil {
            return "See what’s new, then install and relaunch."
        }
        if updateController.lastCheckError != nil {
            return "Check your connection and try again."
        }
        if !updateController.hasCompletedCheck {
            return "SuperPaste checks quietly in the background."
        }
        return "You have the latest version."
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var currentYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }
}
