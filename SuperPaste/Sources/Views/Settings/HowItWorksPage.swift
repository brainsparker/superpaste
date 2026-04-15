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
                Text("SuperPaste sees your screen and writes what you need. No copying, no prompting, no app-switching.")
                    .foregroundColor(.secondary)

                // Steps
                VStack(alignment: .leading, spacing: 16) {
                    StepRow(number: 1, title: "Place your cursor where you want text", description: "Email, Slack, a form, a document \u{2014} anywhere.")
                    StepRow(number: 2, title: "Press \u{2325}V", description: "SuperPaste takes a snapshot and reads the room.")
                    StepRow(number: 3, title: "Text appears automatically", description: "No \u{2318}V needed. It just arrives.")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )

                // Scenarios
                VStack(alignment: .leading, spacing: 12) {
                    Text("What you can do with it")
                        .font(.headline)

                    ScenarioCard(
                        icon: "envelope.fill",
                        title: "Reply to emails",
                        detail: "See an email, get a thoughtful reply. Matches the tone of the conversation."
                    )
                    ScenarioCard(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Answer messages",
                        detail: "Slack, Teams, iMessage \u{2014} SuperPaste reads the thread and writes your response."
                    )
                    ScenarioCard(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "Write code",
                        detail: "Sees your editor, understands the context, writes the next logical block."
                    )
                    ScenarioCard(
                        icon: "doc.text.fill",
                        title: "Fill in forms",
                        detail: "Application fields, surveys, sign-up pages \u{2014} filled in contextually."
                    )
                    ScenarioCard(
                        icon: "exclamationmark.triangle.fill",
                        title: "Explain errors",
                        detail: "See an error message? Get a plain-English explanation and suggested fix."
                    )
                    ScenarioCard(
                        icon: "doc.richtext.fill",
                        title: "Continue writing",
                        detail: "Drafting a doc? SuperPaste picks up where you left off, in your voice."
                    )
                }

                Divider()

                // What SuperPaste sees
                VStack(alignment: .leading, spacing: 12) {
                    Text("What SuperPaste sees")
                        .font(.headline)

                    BulletPoint(text: "A screenshot of your active window")
                    BulletPoint(text: "The app name and window title")
                    BulletPoint(text: "Nothing else \u{2014} no files, no clipboard, no history")
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

/// A scenario card for the "What you can do" section
struct ScenarioCard: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.blue)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
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
