import SwiftUI

/// Welcome screen shown on first launch — establishes value before asking for permissions.
struct WelcomeView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Hero
            heroSection
                .padding(.top, 28)
                .padding(.bottom, 20)

            Divider()

            // Scenario showcase
            scenarioSection
                .padding(24)

            Divider()

            // Privacy promise
            privacySection
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

            Divider()

            // CTA
            ctaSection
                .padding(20)
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("SuperPaste")
                .font(.title.bold())

            Text("Sees your screen. Writes what you need.")
                .font(.subheadline.weight(.medium))
                .foregroundColor(.secondary)

            Text("No copying. No prompting. Just press \u{2325}V.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Scenarios

    private var scenarioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What SuperPaste can do")
                .font(.headline)

            ScenarioRow(
                icon: "envelope.fill",
                title: "See an email?",
                detail: "Get a reply, instantly."
            )
            ScenarioRow(
                icon: "bubble.left.and.bubble.right.fill",
                title: "See a Slack message?",
                detail: "Get the right response."
            )
            ScenarioRow(
                icon: "chevron.left.forwardslash.chevron.right",
                title: "See code?",
                detail: "Get the next function."
            )
            ScenarioRow(
                icon: "doc.text.fill",
                title: "See a form?",
                detail: "Get it filled in."
            )
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.green)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text("Private by design")
                    .font(.caption.weight(.semibold))
                Text("One screenshot, on demand, sent to Claude AI and immediately discarded. No recording, no storage, no continuous monitoring.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - CTA

    private var ctaSection: some View {
        VStack(spacing: 8) {
            Button {
                appState.dismissWelcome()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Takes about 30 seconds to set up")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

/// A single scenario showcase row
struct ScenarioRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.blue)
                .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
