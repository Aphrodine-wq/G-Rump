import SwiftUI

// MARK: - Widget-Ready Views
//
// These views are designed for WidgetKit integration. They render
// standalone widget content that can be used in a WidgetKit extension
// target. For now they live in the main target for compilation and
// preview; extract to a separate widget extension when packaging for
// App Store distribution.

// MARK: - Agent Status Widget View

struct AgentStatusWidgetView: View {
    let isRunning: Bool
    let isPaused: Bool
    let currentStep: String?
    let modelName: String
    let conversationTitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("G-Rump")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                statusIndicator
            }

            Spacer()

            // Status content
            if let title = conversationTitle {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(modelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isRunning, let step = currentStep {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(step)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
        }
        .padding()
    }

    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private var statusColor: Color {
        if isRunning { return .orange }
        if isPaused { return .yellow }
        return .green
    }

    private var statusText: String {
        if isRunning { return "Running" }
        if isPaused { return "Paused" }
        return "Idle"
    }
}

// MARK: - Recent Conversations Widget View

struct RecentConversationsWidgetView: View {
    let conversations: [(title: String, timeAgo: String, messageCount: Int)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("Recent Chats")
                    .font(.headline)
                Spacer()
            }

            if conversations.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                        Text("No conversations yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(Array(conversations.prefix(4).enumerated()), id: \.offset) { _, convo in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(.purple.opacity(0.5))
                            .frame(width: 3, height: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(convo.title)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(convo.timeAgo)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("·")
                                    .foregroundStyle(.secondary)
                                Text("\(convo.messageCount) msgs")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - Quick Actions Widget View

struct QuickActionsWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("G-Rump")
                    .font(.headline)
                Spacer()
            }

            Spacer()

            HStack(spacing: 12) {
                quickAction(icon: "plus.bubble", label: "New Chat", color: .purple)
                quickAction(icon: "terminal", label: "Agent", color: .green)
                quickAction(icon: "doc.text.magnifyingglass", label: "Search", color: .blue)
            }
        }
        .padding()
    }

    private func quickAction(icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Previews

#if DEBUG
struct WidgetViews_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AgentStatusWidgetView(
                isRunning: true,
                isPaused: false,
                currentStep: "Reading project files...",
                modelName: "Claude 4 Sonnet",
                conversationTitle: "Refactor authentication module"
            )
            .frame(width: 170, height: 170)
            .background(.background)
            .previewDisplayName("Agent Status (Small)")

            RecentConversationsWidgetView(
                conversations: [
                    (title: "Fix login bug", timeAgo: "2m", messageCount: 12),
                    (title: "Add dark mode", timeAgo: "1h", messageCount: 8),
                    (title: "API integration", timeAgo: "3h", messageCount: 24)
                ]
            )
            .frame(width: 340, height: 170)
            .background(.background)
            .previewDisplayName("Recent Chats (Medium)")

            QuickActionsWidgetView()
                .frame(width: 170, height: 170)
                .background(.background)
                .previewDisplayName("Quick Actions (Small)")
        }
    }
}
#endif
