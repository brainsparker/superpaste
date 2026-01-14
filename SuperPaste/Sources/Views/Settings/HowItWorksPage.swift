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
                    StepRow(number: 1, title: "Look at what you want to respond to", description: "Email, Slack message, document, etc.")
                    StepRow(number: 2, title: "Press \u{2325}S anywhere", description: "SuperPaste captures your screen")
                    StepRow(number: 3, title: "Wait for the magic", description: "AI analyzes what you're looking at")
                    StepRow(number: 4, title: "Press \u{2318}V to paste", description: "Your response is ready!")
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
