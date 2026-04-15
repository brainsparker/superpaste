import SwiftUI

/// About page showing app info, version, and credits
struct AboutPage: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // App icon
            Image(systemName: "wand.and.stars")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            // App name and version
            VStack(spacing: 4) {
                Text("SuperPaste")
                    .font(.title.bold())

                Text("Version \(appVersion)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Tagline
            Text("Sees your screen. Writes what you need.")
                .font(.body.weight(.medium))
                .foregroundColor(.secondary)

            Divider()
                .frame(width: 200)

            // Description

            Text("Press \u{2325}V anywhere \u{2014} SuperPaste reads your screen, understands the context, and types the right response. No copying, no prompting, no second step.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            // Claude AI badge
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.caption)
                Text("Powered by Claude AI")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            Spacer()

            // Copyright
            Text("\u{00A9} 2025 All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
