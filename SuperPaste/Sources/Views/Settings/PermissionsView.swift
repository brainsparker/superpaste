import SwiftUI

/// Settings page showing permission status and controls.
struct PermissionsView: View {
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Permissions")
                    .font(.title2.bold())

                Text("SuperPaste requires two permissions to work. Both are granted once during setup.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                permissionCard(
                    icon: "rectangle.inset.filled.and.cursorarrow",
                    title: "Screen Recording",
                    description: "SuperPaste captures your active window when you press \u{2325}V. Screenshots are only taken on-demand and never stored.",
                    isEnabled: permissionManager.screenRecordingEnabled,
                    onOpen: { permissionManager.openScreenRecordingSettings() },
                    onRecheck: { permissionManager.checkPermission() }
                )

                permissionCard(
                    icon: "figure.arms.open",
                    title: "Accessibility",
                    description: "SuperPaste types into your focused field automatically. It only sends a paste keystroke (\u{2318}V) — it does not read text from other apps.",
                    isEnabled: permissionManager.accessibilityEnabled,
                    onOpen: { permissionManager.openAccessibilitySettings() },
                    onRecheck: { permissionManager.checkAccessibilityPermission() }
                )
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            permissionManager.checkPermission()
            permissionManager.checkAccessibilityPermission()
        }
    }

    // MARK: - Permission Card

    @discardableResult
    private func permissionCard(
        icon: String,
        title: String,
        description: String,
        isEnabled: Bool,
        onOpen: @escaping () -> Void,
        onRecheck: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)

                Text(title)
                    .font(.headline)

                Spacer()

                if isEnabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                }
            }

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if isEnabled {
                HStack(spacing: 4) {
                    Text("Status:")
                        .foregroundColor(.secondary)
                    Text("Enabled")
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                }
                .font(.caption)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Text("Status:")
                            .foregroundColor(.secondary)
                        Text("Not enabled")
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                    .font(.caption)

                    HStack(spacing: 12) {
                        Button {
                            onOpen()
                        } label: {
                            Text("Open System Settings")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            onRecheck()
                        } label: {
                            Text("Check Again")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isEnabled ? Color(nsColor: .separatorColor) : Color.orange.opacity(0.5),
                    lineWidth: 1
                )
        )
    }
}
