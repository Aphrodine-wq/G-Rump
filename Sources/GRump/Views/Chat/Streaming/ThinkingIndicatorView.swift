import SwiftUI

// MARK: - Claude-Style Thinking Indicator
//
// A collapsible "Thinking..." section shown during the model's reasoning phase.
// Collapsed: animated shimmer label with elapsed timer.
// Expanded: muted monospace text showing the reasoning trace.
// Auto-collapses when visible streaming text begins.

struct ThinkingIndicatorView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let thinkingText: String
    let isActive: Bool

    @State private var isExpanded: Bool = false
    @State private var shimmerPhase: CGFloat = -200
    @State private var elapsed: TimeInterval = 0
    @State private var startTime: Date = Date()
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header: "Thinking..." with shimmer + elapsed timer
            Button(action: { withAnimation(.easeInOut(duration: Anim.quick)) { isExpanded.toggle() } }) {
                HStack(spacing: Spacing.md) {
                    // Animated thinking dots
                    ThinkingDotsView()
                        .frame(width: 28, height: 14)

                    Text("Thinking")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textMuted)

                    if isActive {
                        // Shimmer overlay on "..."
                        Text("...")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.textMuted)
                            .overlay(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        themeManager.palette.effectiveAccent.opacity(0.4),
                                        .clear
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 40)
                                .offset(x: shimmerPhase)
                                .mask(Text("...").font(Typography.captionSmallSemibold))
                            )
                    }

                    Spacer()

                    // Elapsed time
                    Text(formattedElapsed)
                        .font(Typography.captionSmall)
                        .fontDesign(.monospaced)
                        .foregroundColor(themeManager.palette.textMuted.opacity(0.6))

                    // Expand/collapse chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(themeManager.palette.textMuted.opacity(0.5))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded: show reasoning trace
            if isExpanded && !thinkingText.isEmpty {
                ScrollView {
                    Text(thinkingText)
                        .font(Typography.captionSmall)
                        .fontDesign(.monospaced)
                        .foregroundColor(themeManager.palette.textMuted.opacity(0.7))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(themeManager.palette.bgDark.opacity(0.5))
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(.leading, Spacing.lg)
        .padding(.trailing, Spacing.huge)
        .overlay(alignment: .leading) {
            // Claude-style left accent bar for thinking section
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(themeManager.palette.effectiveAccent.opacity(0.4))
                .frame(width: 2.5)
                .padding(.vertical, Spacing.sm)
                .padding(.leading, Spacing.md)
        }
        .padding(.vertical, Spacing.sm)
        .onAppear {
            startTime = Date()
            startTimer()
            if isActive {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    shimmerPhase = 200
                }
            }
        }
        .onDisappear {
            timerTask?.cancel()
        }
        .onChange(of: isActive) { _, active in
            if !active {
                // Auto-collapse when thinking ends
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    isExpanded = false
                }
                timerTask?.cancel()
            }
        }
    }

    private var formattedElapsed: String {
        let secs = Int(elapsed)
        if secs < 60 {
            return "\(secs)s"
        }
        return "\(secs / 60)m \(secs % 60)s"
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled && isActive {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                elapsed = Date().timeIntervalSince(startTime)
            }
        }
    }
}

// MARK: - Persisted Thinking Disclosure
//
// Static, collapsed-by-default reasoning trace for COMPLETED assistant messages.
// The live streaming path uses ThinkingIndicatorView above; this renders the
// thinking blocks that were captured with the message (Claude-style "Thought
// process" you can reopen later). No timer, no shimmer.

struct ThinkingDisclosureView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let thinkingText: String

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button(action: { withAnimation(.easeInOut(duration: Anim.quick)) { isExpanded.toggle() } }) {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "brain")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(themeManager.palette.textMuted.opacity(0.7))
                    Text("Thought process")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textMuted)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(themeManager.palette.textMuted.opacity(0.5))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Hide thought process" : "Show thought process")

            if isExpanded {
                ScrollView {
                    Text(thinkingText)
                        .font(Typography.captionSmall)
                        .fontDesign(.monospaced)
                        .foregroundColor(themeManager.palette.textMuted.opacity(0.7))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
                .padding(Spacing.lg)
                .background(
                    RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .fill(themeManager.palette.bgDark.opacity(0.5))
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(.leading, Spacing.lg)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(themeManager.palette.effectiveAccent.opacity(0.25))
                .frame(width: 2.5)
                .padding(.vertical, Spacing.sm)
        }
    }
}

// MARK: - Thinking Dots Animation

/// Three dots that animate in a smooth wave pattern like Claude's thinking indicator.
/// Each dot pulses with a staggered phase delay, creating a fluid wave rather than
/// a discrete spotlight that jumps between dots.
struct ThinkingDotsView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var isAnimating: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(themeManager.palette.effectiveAccent)
                    .frame(width: 5, height: 5)
                    .scaleEffect(isAnimating ? 1.2 : 0.7)
                    .opacity(isAnimating ? 1.0 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
