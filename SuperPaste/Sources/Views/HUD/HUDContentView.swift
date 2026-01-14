import SwiftUI

/// The content view displayed inside the HUD window
struct HUDContentView: View {
    @ObservedObject var hudState: HUDState

    var body: some View {
        VStack(spacing: 12) {
            // Phrase text
            Text(hudState.currentPhrase)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.3), value: hudState.currentPhrase)

            // Progress bar
            ProgressBar(progress: hudState.progress, stage: hudState.stage)

            // "Press Cmd+V to paste" instruction (only in ready stage)
            if hudState.stage == .ready {
                Text("Press ⌘V to paste")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Error message
            if case .error(let message) = hudState.stage {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
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
    }
}
