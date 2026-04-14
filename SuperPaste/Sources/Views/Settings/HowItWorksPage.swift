import SwiftUI

/// How It Works page explaining the app functionality
struct HowItWorksPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text("How It Works")
                    .font(.title2.bold())

                // Description
                Text("SuperPaste sees your screen and writes for you. No need to copy text or explain context.")
                    .foregroundColor(.secondary)

                // Steps
                VStack(alignment: .leading, spacing: 16) {
                    StepRow(number: 1, title: "Place your cursor where you want text", description: "Email, Slack, a form, a document — anywhere.")
                    StepRow(number: 2, title: "Press \u{2325}V", description: "SuperPaste reads your screen.")
                    StepRow(number: 3, title: "Text appears automatically", description: "No \u{2318}V needed. It just arrives.")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                // What SuperPaste sees
                VStack(alignment: .leading, spacing: 12) {
                    Text("What SuperPaste sees:")
                        .font(.headline)

                    BulletPoint(text: "A screenshot of your active window")
                    BulletPoint(text: "The app name and window title")
                }

                // What SuperPaste does NOT do
                VStack(alignment: .leading, spacing: 12) {
                    Text("What SuperPaste does NOT do:")
                        .font(.headline)

                    BulletPoint(text: "Record video or continuous screenshots")
                    BulletPoint(text: "Store screenshots after processing")
                    BulletPoint(text: "Access files, passwords, or other private data")
                }
                .padding(.top, 8)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A step row with number, title, and description
struct StepRow: View {
    let number: Int
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.blue))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// A bullet point item
struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 6, height: 6)

            Text(text)
                .font(.subheadline)
        }
    }
}
