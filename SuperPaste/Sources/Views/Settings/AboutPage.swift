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

            // Powered by
            Text("Powered by Claude AI")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()
                .frame(width: 200)

            // Description
            Text("Press Option V. SuperPaste reads your screen and types the response — no copying, no prompting, no second step.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Spacer()

            // Copyright
            Text("© 2025 All rights reserved.")
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
