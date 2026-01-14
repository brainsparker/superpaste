import SwiftUI

/// Settings page showing permission status and controls.
struct PermissionsView: View {
    @StateObject private var permissionManager = PermissionManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text("Permissions")
                    .font(.title2.bold())

                // Description
                Text("SuperPaste needs Screen Recording permission to see your screen and generate helpful responses.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Required permissions section
                requiredPermissionsSection

                // Optional permissions section
                optionalPermissionsSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            permissionManager.checkPermission()
        }
    }

    // MARK: - Required Permissions

    private var requiredPermissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Required Permissions")
                .font(.headline)

            // Screen Recording permission card
            VStack(alignment: .leading, spacing: 12) {
                // Header row
                HStack {
                    Image(systemName: "rectangle.inset.filled.and.cursorarrow")
                        .font(.title2)
                        .foregroundColor(.blue)

                    Text("Screen Recording")
                        .font(.headline)

                    Spacer()

                    // Status indicator
                    if permissionManager.screenRecordingEnabled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.title3)
                    }
                }

                // Description
                Text("SuperPaste needs screen recording to capture screenshots when you press \u{2325}S. Screenshots are only taken when you trigger the hotkey.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Status and actions
                if permissionManager.screenRecordingEnabled {
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
                                permissionManager.openScreenRecordingSettings()
                            } label: {
                                Text("Open System Settings")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                permissionManager.checkPermission()
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
                        permissionManager.screenRecordingEnabled
                            ? Color(nsColor: .separatorColor)
                            : Color.orange.opacity(0.5),
                        lineWidth: 1
                    )
            )
        }
    }

    // MARK: - Optional Permissions

    private var optionalPermissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optional Permissions")
                .font(.headline)

            // Notifications (placeholder for future)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "bell.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("Notifications")
                        .font(.headline)

                    Spacer()

                    Circle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(width: 20, height: 20)
                }

                Text("Get notified about tips and updates. This is optional.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button {
                    // TODO: Request notification permission
                } label: {
                    Text("Enable")
                }
                .buttonStyle(.bordered)
                .disabled(true)  // Not implemented in v1.0
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }
}
