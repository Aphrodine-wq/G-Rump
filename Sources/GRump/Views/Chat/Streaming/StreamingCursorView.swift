import SwiftUI

/// Claude-style premium streaming cursor — a subtle pulsing vertical line
/// that appears at the end of streaming text. Fades in/out smoothly and
/// uses the theme's accent color with a gentle glow effect.
///
/// Tuned to match Claude's actual cursor: thinner (1.5px), faster pulse (0.5s),
/// and deeper opacity fade (0.9 → 0.15) for a more refined, less distracting feel.
struct StreamingCursorView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var opacity: Double = 0.9

    /// Height matches the current line height of body text.
    var lineHeight: CGFloat = 18
    /// Width of the cursor line — 1.5px is thinner than standard, matching Claude.
    var cursorWidth: CGFloat = 1.5

    var body: some View {
        RoundedRectangle(cornerRadius: cursorWidth / 2, style: .continuous)
            .fill(themeManager.palette.effectiveAccent)
            .frame(width: cursorWidth, height: lineHeight)
            .opacity(opacity)
            .shadow(color: themeManager.palette.effectiveAccent.opacity(0.4), radius: 3, x: 0, y: 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.5)
                    .repeatForever(autoreverses: true)
                ) {
                    opacity = 0.15
                }
            }
    }
}

/// A minimal "Generating..." status line shown below streaming content.
/// Claude-style: clean shimmer effect with subtle animation.
struct StreamingStatusLine: View {
    @EnvironmentObject var themeManager: ThemeManager
    @ObservedObject var metrics: StreamMetrics

    @State private var shimmerOffset: CGFloat = -120

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Pulsing dot
            Circle()
                .fill(themeManager.palette.effectiveAccent)
                .frame(width: 6, height: 6)
                .modifier(PulseModifier())

            // Status text with shimmer
            statusText
                .font(Typography.captionSmallMedium)
                .foregroundColor(themeManager.palette.textMuted)
                .overlay(shimmerOverlay)

            Spacer()
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.sm)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                shimmerOffset = 300
            }
        }
    }

    private var statusText: some View {
        Group {
            switch metrics.phase {
            case .idle:
                Text("")
            case .waiting:
                Text("Thinking...")
            case .streaming:
                HStack(spacing: Spacing.sm) {
                    Text("Generating")
                    if metrics.tokensPerSecond > 0 {
                        Text("·")
                            .foregroundColor(themeManager.palette.textMuted.opacity(0.4))
                        Text("\(Int(metrics.tokensPerSecond)) tok/s")
                            .fontDesign(.monospaced)
                    }
                    if metrics.elapsedTime > 0 {
                        Text("·")
                            .foregroundColor(themeManager.palette.textMuted.opacity(0.4))
                        Text(formatElapsed(metrics.elapsedTime))
                            .fontDesign(.monospaced)
                    }
                }
            case .toolUse:
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "wrench.and.screwdriver")
                        .font(.system(size: 9, weight: .medium))
                    Text("Running tools")
                    if metrics.elapsedTime > 0 {
                        Text("·")
                            .foregroundColor(themeManager.palette.textMuted.opacity(0.4))
                        Text(formatElapsed(metrics.elapsedTime))
                            .fontDesign(.monospaced)
                    }
                }
            case .complete:
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.green.opacity(0.7))
                    Text("Done")
                    if metrics.elapsedTime > 0 {
                        Text("in \(formatElapsed(metrics.elapsedTime))")
                            .fontDesign(.monospaced)
                    }
                }
                .transition(.opacity)
                .onAppear {
                    // Auto-fade the status line 3 seconds after completion
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                    }
                }
            case .error(let msg):
                Text("Error: \(msg)")
                    .foregroundColor(.red)
            }
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let secs = Int(seconds)
        if secs < 60 { return "\(secs)s" }
        return "\(secs / 60)m \(secs % 60)s"
    }

    private var shimmerOverlay: some View {
        LinearGradient(
            colors: [
                .clear,
                themeManager.palette.effectiveAccent.opacity(0.25),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 60)
        .offset(x: shimmerOffset)
        .mask(statusText.font(Typography.captionSmallMedium))
    }
}

/// Smooth pulse animation modifier for dots and indicators.
struct PulseModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = 1.3
                    opacity = 0.5
                }
            }
    }
}

/// Premium streaming message row that replaces GRumpStreamingBubble.
/// Shows the actual streamed content with progressive markdown rendering,
/// a Claude-style cursor, and a minimal status line.
/// Integrates ThinkingIndicatorView for Claude-like "Thinking..." phase.
struct PremiumStreamingRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    let content: String
    var agentMode: AgentMode = .standard
    @ObservedObject var metrics: StreamMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Inline label matching MessageRow style
            HStack(spacing: Spacing.sm) {
                FrownyFaceLogo(size: 16, mood: modeMood)
                Text("G-Rump")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textMuted)
            }

            // Claude-style thinking indicator (shown during reasoning phase)
            if viewModel.isThinking || !viewModel.thinkingContent.isEmpty {
                ThinkingIndicatorView(
                    thinkingText: viewModel.thinkingContent,
                    isActive: viewModel.isThinking
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity
                ))
            }

            // Progressive markdown rendering with cursor (shown when visible text exists)
            if !content.isEmpty {
                HStack(alignment: .bottom, spacing: 0) {
                    MarkdownTextView(
                        text: content,
                        onCodeBlockTap: nil
                    )
                    .textSelection(.enabled)

                    StreamingCursorView(lineHeight: 16, cursorWidth: 2)
                        .padding(.leading, 1)
                        .padding(.bottom, 2)
                }
                .transition(.opacity.animation(.easeIn(duration: 0.2)))
            }

            // Enhanced status line with word count
            StreamingStatusLine(metrics: metrics)
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.sm)
        .overlay(alignment: .leading) {
            // Thin mode-color accent bar on the left edge
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(agentMode.modeAccentColor)
                .frame(width: 3)
                .padding(.vertical, Spacing.md)
                .padding(.leading, Spacing.lg)
                .opacity(agentMode == .standard ? 0 : 0.7)
        }
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .bottom)),
            removal: .opacity
        ))
    }

    private var modeMood: LogoMood { agentMode.logoMood }
}
