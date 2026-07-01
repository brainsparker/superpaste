import SwiftUI

/// View displayed when SuperPaste is fully configured and ready to use.
struct ReadyView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("hasTriedOnce") private var hasTriedOnce = false

    private let tips = [
        "Works in any app — email, Slack, code editors, forms, documents.",
        "SuperPaste matches the tone of the active window. Casual for chat, professional for email.",
        "Stuck on an error? Press Option V while looking at it for an instant explanation.",
        "Writing a doc? Place your cursor at the end and press Option V to continue your thought.",
        "SuperPaste only captures your active window when you press Option V.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.top, 24)
                .padding(.bottom, 16)

            Divider()

            if !hasTriedOnce {
                firstUseSection.padding(24)
            } else {
                returningUserSection.padding(24)
            }

            Divider()

            footerSection
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
        }
        .frame(width: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(appState.$isProcessing) { processing in
            if !processing && appState.useCount > 0 { hasTriedOnce = true }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("SuperPaste")
                .font(.title.bold())
            HStack(spacing: 6) {
                if appState.isProcessing {
                    ProgressView().scaleEffect(0.7)
                    Text("Working on it…").foregroundColor(.secondary)
                } else if let error = appState.lastError {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).foregroundColor(.secondary).lineLimit(2)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Ready").foregroundColor(.green).fontWeight(.medium)
                }
            }
            .font(.subheadline)
        }
    }

    // MARK: - First Use

    @State private var practiceReply = ""
    @FocusState private var practiceFieldFocused: Bool

    /// A supervised first success: the fake email below IS the captured
    /// context (this window is frontmost), and the reply lands visibly in the
    /// practice field. No other app, no way to fail unseen.
    private var firstUseSection: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "hand.point.up.left.fill").foregroundColor(.blue)
                    Text("Try it right here").font(.headline)
                }

                // Fake received email — the on-screen context SuperPaste reads.
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.fill").foregroundColor(.secondary)
                        Text("Alex").font(.caption.weight(.semibold))
                        Text("• Coffee next week?").font(.caption).foregroundColor(.secondary)
                    }
                    Text("Hey! Are we still on for coffee next Tuesday? Let me know what time works for you.")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

                TextField("Click here, then press \(HotkeyPreset.current.shortName)", text: $practiceReply, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                    .focused($practiceFieldFocused)
                    .accessibilityLabel("Practice reply field")

                if practiceReply.isEmpty {
                    Text("SuperPaste reads this window and writes the reply into the field — exactly what it does in your real apps.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("That's it. Now try it in any app.")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.2), lineWidth: 1))
            hotkeyVisual
            availabilityNote
        }
    }

    // MARK: - Returning User

    private var returningUserSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if appState.useCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "option").foregroundColor(.blue)
                    Text("Used \(appState.useCount) time\(appState.useCount == 1 ? "" : "s")")
                        .font(.subheadline).foregroundColor(.secondary)
                }
            }
            hotkeyVisual
            availabilityNote
            VStack(alignment: .leading, spacing: 6) {
                Text("Tip").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Text(tips[appState.useCount % tips.count])
                    .font(.subheadline).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            if let days = appState.trialDaysRemaining {
                HStack {
                    Image(systemName: "calendar").foregroundColor(days <= 3 ? .orange : .secondary)
                    Text(days == 0 ? "Trial expires today" : "\(days) day\(days == 1 ? "" : "s") left in trial")
                    Spacer()
                    Button {
                        if let url = URL(string: "https://buy.polar.sh/polar_cl_YS3DZpcmFoh7GDvDvRxWezZLUmPKgwf9Mb6T618NFdC") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: { Text("Upgrade") }
                    .font(.caption).buttonStyle(.plain).foregroundColor(.blue)
                }
                .font(.subheadline)
                .foregroundColor(days <= 3 ? .orange : .secondary)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(days <= 3 ? Color.orange.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
            }
        }
    }

    // MARK: - Hotkey Visual

    private var hotkeyVisual: some View {
        HStack(spacing: 6) {
            ForEach(hotkeyKeyCaps, id: \.self) { label in
                if label == "+" {
                    Text("+").font(.title3.weight(.light)).foregroundColor(.secondary)
                } else {
                    KeyCap(label: label)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var hotkeyKeyCaps: [String] {
        switch HotkeyPreset.current {
        case .optionV: return ["\u{2325} Option", "+", "V"]
        case .controlOptionV: return ["\u{2303} Control", "+", "\u{2325} Option", "+", "V"]
        case .commandShiftV: return ["\u{2318} Command", "+", "\u{21E7} Shift", "+", "V"]
        }
    }

    private var availabilityNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "power")
                .foregroundColor(.secondary)
            Text("Turn on \u{201C}Launch at login\u{201D} below so the hotkey is ready without opening this window. You can pause or quit SuperPaste any time from the \u{2325} menu bar icon.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .onChange(of: launchAtLogin) { _, newValue in
                        appState.setLaunchAtLogin(newValue)
                    }
                Spacer()
                Button {
                    // The legacy showSettingsWindow: selector is dead on
                    // macOS 14+; openSettings is the supported route.
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gear")
                    Text("Settings")
                }
            }
            .font(.subheadline)
            Text("Powered by Claude")
                .font(.caption).foregroundColor(.secondary)
        }
    }

}

// MARK: - Subviews

struct KeyCap: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(
                // Hard 2pt bottom edge gives the chunky keycap depth used
                // across the brand (site demo key, app icon).
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 2)
            )
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

struct FirstUseStep: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.white).frame(width: 22, height: 22)
                .background(Circle().fill(Color.blue))
            Text(text).font(.subheadline)
        }
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white).frame(width: 24, height: 24)
                .background(Circle().fill(Color.blue))
            Text(text).font(.subheadline)
        }
    }
}
