import SwiftUI

/// Apple Intelligence-style animated prismatic glow around the screen edges.
struct GlowBorderView: View {
    @ObservedObject var hudState: HUDState

    /// Continuously rotating angle for the gradient
    @State private var rotationAngle: Double = 0

    /// Opacity of the entire effect
    @State private var opacity: Double = 0

    /// Glow intensity multiplier
    @State private var intensity: Double = 1.0

    /// Border inset from screen edge
    private let inset: CGFloat = 2

    /// Thickness of the glow stroke
    private let strokeWidth: CGFloat = 4

    /// Blur radius for the glow halo
    private let glowRadius: CGFloat = 20

    private var gradientColors: [Color] {
        switch hudState.stage {
        case .gathering, .thinking:
            // Prismatic Apple Intelligence palette
            return [
                Color(red: 0.55, green: 0.35, blue: 0.95),  // purple
                Color(red: 0.35, green: 0.50, blue: 1.0),   // blue
                Color(red: 0.20, green: 0.75, blue: 0.95),   // cyan
                Color(red: 0.30, green: 0.85, blue: 0.65),   // teal
                Color(red: 0.95, green: 0.60, blue: 0.30),   // orange
                Color(red: 0.95, green: 0.40, blue: 0.55),   // pink
                Color(red: 0.55, green: 0.35, blue: 0.95),   // purple (wrap)
            ]
        case .ready:
            return [
                Color(red: 0.20, green: 0.85, blue: 0.50),
                Color(red: 0.30, green: 0.95, blue: 0.65),
                Color(red: 0.20, green: 0.85, blue: 0.50),
            ]
        case .error:
            return [
                Color(red: 0.95, green: 0.50, blue: 0.30),
                Color(red: 1.0, green: 0.65, blue: 0.40),
                Color(red: 0.95, green: 0.50, blue: 0.30),
            ]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let rect = CGRect(
                x: inset,
                y: inset,
                width: geometry.size.width - inset * 2,
                height: geometry.size.height - inset * 2
            )

            ZStack {
                // Layer 1: Wide soft glow (background halo)
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: gradientColors),
                            center: .center,
                            angle: .degrees(rotationAngle)
                        ),
                        lineWidth: strokeWidth * 2
                    )
                    .frame(width: rect.width, height: rect.height)
                    .blur(radius: glowRadius)
                    .opacity(0.6 * intensity)

                // Layer 2: Medium glow
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: gradientColors),
                            center: .center,
                            angle: .degrees(rotationAngle + 30)
                        ),
                        lineWidth: strokeWidth * 1.5
                    )
                    .frame(width: rect.width, height: rect.height)
                    .blur(radius: glowRadius * 0.5)
                    .opacity(0.7 * intensity)

                // Layer 3: Sharp core line
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: gradientColors),
                            center: .center,
                            angle: .degrees(rotationAngle + 60)
                        ),
                        lineWidth: strokeWidth
                    )
                    .frame(width: rect.width, height: rect.height)
                    .blur(radius: 2)
                    .opacity(0.9 * intensity)
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .opacity(opacity)
        .allowsHitTesting(false)
        .onChange(of: hudState.isVisible) { visible in
            if visible {
                startAnimation()
            } else {
                stopAnimation()
            }
        }
        .onChange(of: hudState.stage) { stage in
            switch stage {
            case .gathering:
                withAnimation(.easeInOut(duration: 0.4)) {
                    intensity = 0.8
                }
            case .thinking:
                withAnimation(.easeInOut(duration: 0.4)) {
                    intensity = 1.0
                }
            case .ready:
                // Brief bright flash then fade
                withAnimation(.easeIn(duration: 0.15)) {
                    intensity = 1.4
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeOut(duration: 1.0)) {
                        intensity = 0.0
                    }
                }
            case .error:
                withAnimation(.easeInOut(duration: 0.3)) {
                    intensity = 1.0
                }
            }
        }
    }

    // MARK: - Animation Control

    private func startAnimation() {
        withAnimation(.easeIn(duration: 0.3)) {
            opacity = 1.0
        }
        intensity = 0.8
        startRotation()
    }

    private func stopAnimation() {
        withAnimation(.easeOut(duration: 0.4)) {
            opacity = 0
        }
    }

    private func startRotation() {
        // Continuous smooth rotation
        withAnimation(
            .linear(duration: 4.0)
            .repeatForever(autoreverses: false)
        ) {
            rotationAngle = 360
        }
    }
}
