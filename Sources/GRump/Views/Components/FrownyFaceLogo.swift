import SwiftUI

// MARK: - Logo Mood

enum LogoMood: Equatable {
    case neutral
    case thinking
    case happy
    case error
    case success
}

// MARK: - Mouth Shapes

/// The frown arc shape — supports trim-based animation
struct FrownArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY + rect.height * 0.18
        let radius = rect.width * 0.22
        path.addArc(
            center: CGPoint(x: cx, y: cy + radius * 0.6),
            radius: radius,
            startAngle: .degrees(-160),
            endAngle: .degrees(-20),
            clockwise: false
        )
        return path
    }
}

/// A smile arc (inverted frown) for happy/success states
struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY + rect.height * 0.14
        let radius = rect.width * 0.22
        path.addArc(
            center: CGPoint(x: cx, y: cy - radius * 0.1),
            radius: radius,
            startAngle: .degrees(20),
            endAngle: .degrees(160),
            clockwise: false
        )
        return path
    }
}

/// A flat line mouth for thinking/neutral-processing state
struct FlatMouth: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cx = rect.midX
        let cy = rect.midY + rect.height * 0.2
        let halfWidth = rect.width * 0.15
        path.move(to: CGPoint(x: cx - halfWidth, y: cy))
        path.addLine(to: CGPoint(x: cx + halfWidth, y: cy))
        return path
    }
}

/// An X shape for error eyes
struct XEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset: CGFloat = rect.width * 0.2
        path.move(to: CGPoint(x: inset, y: inset))
        path.addLine(to: CGPoint(x: rect.width - inset, y: rect.height - inset))
        path.move(to: CGPoint(x: rect.width - inset, y: inset))
        path.addLine(to: CGPoint(x: inset, y: rect.height - inset))
        return path
    }
}

// MARK: - Floating Animation (reusable)

struct FloatingAnimation: ViewModifier {
    @State private var offset: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .onAppear {
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    offset = -4
                }
            }
    }
}

// MARK: - Pulsing Border Modifier (for thinking state)

struct PulsingBorder: ViewModifier {
    let color: Color
    let size: CGFloat
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.6), color.opacity(0.1), color.opacity(0.6)],
                            center: .center,
                            startAngle: .degrees(phase),
                            endAngle: .degrees(phase + 360)
                        ),
                        lineWidth: size * 0.05
                    )
            )
            .onAppear {
                withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) {
                    phase = 360
                }
            }
    }
}

// MARK: - FrownyFaceLogo

/// Full frowny face logo with contextual mood variants
struct FrownyFaceLogo: View {
    @EnvironmentObject var themeManager: ThemeManager
    var size: CGFloat = 40
    var eyeColor: Color?
    var frownColor: Color?
    var showFrown: Bool = true
    var frownProgress: CGFloat = 1.0
    var mood: LogoMood = .neutral
    var isActive: Bool = false

    private var resolvedEyeColor: Color {
        switch mood {
        case .error: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .success, .happy: return themeManager.palette.effectiveAccent
        default: return eyeColor ?? themeManager.palette.effectiveAccent
        }
    }
    private var resolvedMouthColor: Color {
        switch mood {
        case .error: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .success: return Color.accentGreen
        case .happy: return themeManager.palette.effectiveAccent
        default: return frownColor ?? themeManager.palette.effectiveAccent
        }
    }

    var body: some View {
        ZStack {
            faceCircle
            eyesView
            mouthView
        }
        .frame(width: size, height: size)
        .modifier(ActivePulseModifier(isActive: isActive && mood == .thinking, color: themeManager.palette.effectiveAccent, size: size))
    }

    // MARK: - Face Circle

    @ViewBuilder
    private var faceCircle: some View {
        let borderGradient = LinearGradient(
            colors: borderColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        Circle()
            .fill(themeManager.palette.bgCard)
            .overlay(
                Circle()
                    .stroke(borderGradient, lineWidth: size * 0.05)
            )
            .shadow(color: shadowColor.opacity(0.18), radius: size * 0.18, y: size * 0.06)
    }

    private var borderColors: [Color] {
        switch mood {
        case .error:
            return [Color(red: 1.0, green: 0.35, blue: 0.35), Color(red: 1.0, green: 0.55, blue: 0.55)]
        case .success:
            return [Color.accentGreen, Color.accentGreen.opacity(0.7)]
        default:
            return [themeManager.palette.effectiveAccent, themeManager.palette.effectiveAccentLightVariant]
        }
    }

    private var shadowColor: Color {
        switch mood {
        case .error: return Color(red: 1.0, green: 0.35, blue: 0.35)
        case .success: return Color.accentGreen
        default: return themeManager.palette.effectiveAccent
        }
    }

    // MARK: - Eyes

    @ViewBuilder
    private var eyesView: some View {
        switch mood {
        case .error:
            // X-shaped eyes
            XEye()
                .stroke(resolvedEyeColor, style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
                .frame(width: size * 0.15, height: size * 0.15)
                .offset(x: -size * 0.17, y: -size * 0.1)
            XEye()
                .stroke(resolvedEyeColor, style: StrokeStyle(lineWidth: size * 0.04, lineCap: .round))
                .frame(width: size * 0.15, height: size * 0.15)
                .offset(x: size * 0.17, y: -size * 0.1)
        case .happy, .success:
            // Happy squint eyes (horizontal arcs)
            Capsule()
                .fill(resolvedEyeColor)
                .frame(width: size * 0.16, height: size * 0.06)
                .offset(x: -size * 0.17, y: -size * 0.1)
            Capsule()
                .fill(resolvedEyeColor)
                .frame(width: size * 0.16, height: size * 0.06)
                .offset(x: size * 0.17, y: -size * 0.1)
        default:
            // Standard circle eyes
            Circle()
                .fill(resolvedEyeColor)
                .frame(width: size * 0.15, height: size * 0.15)
                .offset(x: -size * 0.17, y: -size * 0.1)
            Circle()
                .fill(resolvedEyeColor)
                .frame(width: size * 0.15, height: size * 0.15)
                .offset(x: size * 0.17, y: -size * 0.1)
        }
    }

    // MARK: - Mouth

    @ViewBuilder
    private var mouthView: some View {
        switch mood {
        case .happy, .success:
            SmileArc()
                .trim(from: 0, to: frownProgress)
                .stroke(resolvedMouthColor, style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
                .frame(width: size, height: size)
        case .thinking:
            FlatMouth()
                .stroke(resolvedMouthColor, style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
                .frame(width: size, height: size)
        case .error:
            if showFrown {
                FrownArc()
                    .trim(from: 0, to: frownProgress)
                    .stroke(resolvedMouthColor, style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
                    .frame(width: size, height: size)
            }
        case .neutral:
            if showFrown {
                FrownArc()
                    .trim(from: 0, to: frownProgress)
                    .stroke(resolvedMouthColor, style: StrokeStyle(lineWidth: size * 0.055, lineCap: .round))
                    .frame(width: size, height: size)
            }
        }
    }
}

// MARK: - Active Pulse Modifier (thinking animation only when isActive)

private struct ActivePulseModifier: ViewModifier {
    let isActive: Bool
    let color: Color
    let size: CGFloat
    @State private var pulseScale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .overlay(
                Circle()
                    .stroke(color.opacity(isActive ? 0.3 : 0), lineWidth: 2)
                    .frame(width: size * 1.3, height: size * 1.3)
                    .scaleEffect(pulseScale)
                    .opacity(isActive ? (2.0 - pulseScale) : 0)
            )
            .onChange(of: isActive) { _, active in
                if active {
                    withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        pulseScale = 1.6
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        pulseScale = 1.0
                    }
                }
            }
            .onAppear {
                if isActive {
                    withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                        pulseScale = 1.6
                    }
                }
            }
    }
}
