import SwiftUI

/// The compact status surface displayed above the active app.
struct HUDContentView: View {
    @ObservedObject var hudState: HUDState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var accentColors: [Color] {
        switch hudState.stage {
        case .gathering, .thinking:
            return [
                Color(red: 0.43, green: 0.36, blue: 1.0),
                Color(red: 0.17, green: 0.72, blue: 1.0),
            ]
        case .ready:
            return [
                Color(red: 0.16, green: 0.80, blue: 0.48),
                Color(red: 0.35, green: 0.92, blue: 0.68),
            ]
        case .error:
            return [
                Color(red: 1.0, green: 0.45, blue: 0.28),
                Color(red: 1.0, green: 0.67, blue: 0.30),
            ]
        }
    }

    private var surfaceOpacity: Double {
        if reduceTransparency || colorSchemeContrast == .increased {
            return 0.94
        }
        return 0.78
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if case .error(let message) = hudState.stage {
                errorContent(message)
            } else if hudState.stage.isWorking {
                workingFooter
            }
        }
        .padding(14)
        .frame(width: 292)
        .background(
            ZStack {
                shape.fill(.regularMaterial)
                shape.fill(Color.black.opacity(surfaceOpacity))
            }
        )
        .overlay(
            shape
                .stroke(
                    LinearGradient(
                        colors: accentColors.map { $0.opacity(0.72) },
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: accentColors[0].opacity(0.18), radius: 18)
        .shadow(color: .black.opacity(0.38), radius: 12, x: 0, y: 5)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SuperPaste status: \(hudState.currentPhrase)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: accentColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Image(systemName: stageSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 32, height: 32)
            .shadow(color: accentColors[0].opacity(0.35), radius: 7)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(hudState.currentPhrase)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                if hudState.stage.isWorking {
                    Text(hudState.secondaryPhrase ?? " ")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(hudState.secondaryPhrase == nil ? 0 : 0.56))
                        .lineLimit(1)
                        .animation(
                            reduceMotion ? nil : .easeOut(duration: 0.16),
                            value: hudState.secondaryPhrase
                        )
                } else if let secondaryPhrase = hudState.secondaryPhrase {
                    Text(secondaryPhrase)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.56))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 6)

            if hudState.stage.isWorking {
                Button {
                    hudState.onCancel?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.68))
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel SuperPaste")
                .help("Cancel (Esc)")
            }
        }
    }

    private var workingFooter: some View {
        HStack(spacing: 8) {
            MagicDots(colors: accentColors, reduceMotion: reduceMotion)

            Spacer()

            Text("Esc")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.5)
                )

            Text("cancels")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
        }
        .padding(.leading, 42)
    }

    @ViewBuilder
    private func errorContent(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let action = hudState.recoveryAction {
                    Button {
                        perform(action)
                    } label: {
                        Label(action.title, systemImage: action.icon)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(accentColors[0])
                }

                Button("Dismiss") {
                    hudState.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.leading, 42)
    }

    private var stageSymbol: String {
        switch hudState.stage {
        case .gathering:
            return "viewfinder"
        case .thinking:
            return "pencil.line"
        case .ready:
            return "checkmark"
        case .error:
            return "exclamationmark"
        }
    }

    private func perform(_ action: HUDRecoveryAction) {
        switch action {
        case .openSettings:
            hudState.dismiss()
            hudState.onOpenSettings?()
        case .retry:
            hudState.onRetry?()
        case .copyResponse:
            hudState.onCopyResponse?()
            hudState.dismiss()
        }
    }
}

private struct MagicDots: View {
    let colors: [Color]
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 60 : 0.28)) { context in
            let activeIndex = reduceMotion
                ? -1
                : Int(context.date.timeIntervalSinceReferenceDate / 0.28) % 3

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: colors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 5, height: 5)
                        .opacity(reduceMotion || activeIndex == index ? 1 : 0.28)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
