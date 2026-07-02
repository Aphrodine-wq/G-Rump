import SwiftUI

// MARK: - Thinking Dots (minimal bouncing)

struct ThinkingDots: View {
    var color: Color
    @State private var activeIndex = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color.opacity(activeIndex == i ? 1.0 : 0.3))
                    .frame(width: 5, height: 5)
                    .offset(y: activeIndex == i ? -2 : 0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: activeIndex)
            }
        }
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                DispatchQueue.main.async {
                    activeIndex = (activeIndex + 1) % 3
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Enhanced Typing Indicator (Claude-style clean)

struct EnhancedTypingIndicator: View {
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            FrownyFaceLogo(size: 26)
                .padding(.top, 1)

            HStack(spacing: Spacing.md) {
                ThinkingDots(color: themeManager.palette.effectiveAccent)
                Text("Thinking…")
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            .padding(.horizontal, Spacing.xxxl)
            .padding(.vertical, Spacing.xl)
            .background(themeManager.palette.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.bubble, style: .continuous)
                    .stroke(themeManager.palette.borderCrisp.opacity(0.4), lineWidth: Border.thin)
            )

            Spacer()
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Compact Typing Indicator

struct CompactTypingIndicator: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var animationPhase: Int = 0

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(shouldHighlight(for: index) ? themeManager.palette.effectiveAccent : Color.textMuted.opacity(0.3))
                    .frame(width: shouldHighlight(for: index) ? 8 : 6, height: 4)
                    .animation(.easeInOut(duration: 0.3).delay(Double(index) * 0.1), value: animationPhase)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                animationPhase = 1
            }
        }
    }

    private func shouldHighlight(for index: Int) -> Bool {
        let cyclePosition = animationPhase % 3
        return cyclePosition == index
    }
}

// MARK: - Status-Based Typing Indicator

struct StatusTypingIndicator: View {
    @EnvironmentObject var themeManager: ThemeManager
    let status: TypingStatus
    let message: String?
    @State private var animationPhase: Int = 0
    @State private var animationTimer: Timer?

    enum TypingStatus {
        case connecting
        case processing
        case generating
        case completing

        var icon: String {
            switch self {
            case .connecting: return "wifi"
            case .processing: return "gear.badge"
            case .generating: return "sparkles"
            case .completing: return "checkmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .connecting: return .orange
            case .processing: return .blue
            case .generating: return .purple
            case .completing: return .green
            }
        }
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Status icon
            ZStack {
                Circle()
                    .fill(status.color.opacity(0.1))
                    .frame(width: 32, height: 32)

                Image(systemName: status.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(status.color)
                    .scaleEffect(1.0)
            }

            // Status text
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(statusText)
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(.textPrimary)

                if let message = message {
                    Text(message)
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Activity indicator
            HStack(spacing: Spacing.xs) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(status.color)
                        .opacity(activityDotOpacity(for: index))
                        .frame(width: 4, height: 4)
                        .scaleEffect(activityDotScale(for: index))
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: index)
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(themeManager.palette.bgCard)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(status.color.opacity(0.3), lineWidth: 1)
                )
        )
        .onAppear {
            animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                DispatchQueue.main.async {
                    animationPhase += 1
                }
            }
        }
        .onDisappear {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private var statusText: String {
        switch status {
        case .connecting: return "Connecting to AI..."
        case .processing: return "Processing request..."
        case .generating: return "Generating response..."
        case .completing: return "Finalizing response..."
        }
    }

    private func activityDotOpacity(for index: Int) -> CGFloat {
        let baseOpacity: CGFloat = 0.3
        let activeOpacity: CGFloat = 0.8
        let cyclePosition = animationPhase % 3

        return cyclePosition == index ? activeOpacity : baseOpacity
    }

    private func activityDotScale(for index: Int) -> CGFloat {
        let cyclePosition = animationPhase % 3
        return cyclePosition == index ? 1.2 : 1.0
    }
}
