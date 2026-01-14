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
                Text("SuperPaste generates contextual responses based on what you're doing. No permissions required.")
                    .foregroundColor(.secondary)

                // Steps
                VStack(alignment: .leading, spacing: 16) {
                    StepRow(number: 1, title: "Copy some text for context", description: "Optional - gives SuperPaste more to work with")
                    StepRow(number: 2, title: "Press ⌥S anywhere", description: "Works in any app, anytime")
                    StepRow(number: 3, title: "Wait for the magic", description: "SuperPaste analyzes your context")
                    StepRow(number: 4, title: "Press ⌘V to paste", description: "The response is on your clipboard")
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

                    BulletPoint(text: "Your clipboard contents")
                    BulletPoint(text: "The active window title")
                    BulletPoint(text: "The app you're using")

                    Text("That's it! No screen recording, no keylogging.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
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
