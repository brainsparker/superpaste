import SwiftUI

/// A gentle, non-modal update reminder used by the main window.
struct UpdateBanner: View {
    @ObservedObject private var updateController = UpdateController.shared

    var body: some View {
        if let update = updateController.availableUpdate {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.43, green: 0.36, blue: 1.0),
                                    Color(red: 0.17, green: 0.72, blue: 1.0),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "arrow.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 36, height: 36)
                .shadow(color: .blue.opacity(0.22), radius: 7, y: 3)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("A fresh SuperPaste is ready")
                        .font(.subheadline.weight(.semibold))

                    Text("Version \(update.version) installs in one click.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Button("What’s New") {
                    updateController.openReleaseNotes()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

                Button("Install Update") {
                    updateController.installAvailableUpdate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.blue.opacity(0.20), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
        }
    }
}
