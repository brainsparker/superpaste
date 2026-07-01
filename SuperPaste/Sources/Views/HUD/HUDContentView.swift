import SwiftUI

/// The content view displayed inside the HUD window
struct HUDContentView: View {
    @ObservedObject var hudState: HUDState

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                // Phrase text
                Text(hudState.currentPhrase)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .animation(.easeInOut(duration: 0.3), value: hudState.currentPhrase)

                // Cancel affordance while a request is in flight
                if hudState.stage.isWorking {
                    Button {
                        hudState.onCancel?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel")
                    .help("Cancel (esc)")
                }
            }

            // Progress bar
            ProgressBar(progress: hudState.progress, stage: hudState.stage)

            // Error message
            if case .error(let message) = hudState.stage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                Text("Click to dismiss")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }

            if hudState.stage.isWorking {
                Text("esc to cancel")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(minWidth: 200, maxWidth: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: NSColor(white: 0.1, alpha: 0.95)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.2), value: hudState.stage)
        .contentShape(Rectangle())
        .onTapGesture {
            if hudState.stage.isError {
                hudState.dismiss()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SuperPaste status: \(hudState.currentPhrase)")
    }
}

/// Custom progress bar with stage-aware styling
struct ProgressBar: View {
    let progress: Double
    let stage: HUDStage

    private var barColor: Color {
        switch stage {
        case .gathering, .thinking:
            return Color.blue
        case .ready:
            return Color.green
        case .error:
            return Color.orange
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.2))

                // Progress fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(barColor)
                    .frame(width: geometry.size.width * progress)
                    .animation(.easeInOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
