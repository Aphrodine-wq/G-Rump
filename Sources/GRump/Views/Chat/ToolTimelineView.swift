import SwiftUI

/// Vertical timeline view for tool execution — shows connected dots/lines,
/// tool names, compact args previews, duration bars, and status indicators.
/// Optimized for speed: lazy rendering, minimal state updates.
struct ToolTimelineView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let toolCalls: [ToolCallStatus]
    let agentStep: Int?
    let agentStepMax: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Step indicator header
            if let step = agentStep, let max = agentStepMax {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    Text("Step \(step) of \(max)")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                }
                .padding(.bottom, Spacing.lg)
            }

            // Timeline
            ForEach(Array(toolCalls.enumerated()), id: \.element.id) { index, call in
                ToolTimelineEntry(
                    call: call,
                    isLast: index == toolCalls.count - 1,
                    themeManager: themeManager
                )
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.xl)
    }
}

/// A single entry in the tool execution timeline.
struct ToolTimelineEntry: View {
    let call: ToolCallStatus
    let isLast: Bool
    let themeManager: ThemeManager

    @State private var isExpanded: Bool = false
    @State private var showFullArgs: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xxl) {
            // Timeline dot + connecting line
            VStack(spacing: 0) {
                statusDot
                    .frame(width: 12, height: 12)

                if !isLast {
                    Rectangle()
                        .fill(lineColor)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            // Content
            VStack(alignment: .leading, spacing: Spacing.xs) {
                // Tool name + status
                HStack(spacing: Spacing.md) {
                    Image(systemName: toolIcon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(statusColor)

                    Text(displayName)
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Duration badge
                    if let duration = formattedDuration {
                        Text(duration)
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 2)
                            .background(themeManager.palette.bgElevated)
                            .clipShape(Capsule())
                    }

                    // Status indicator
                    statusBadge
                }

                // Args preview (compact, tap to expand full JSON)
                if !argsSummary.isEmpty {
                    Button(action: {
                        if hasFullArgs {
                            withAnimation(Anim.spring) { showFullArgs.toggle() }
                        }
                    }) {
                        HStack(spacing: Spacing.xs) {
                            Text(showFullArgs ? prettyArgs : argsSummary)
                                .font(Typography.codeMicro)
                                .foregroundColor(themeManager.palette.textMuted)
                                .lineLimit(showFullArgs ? nil : 1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if hasFullArgs {
                                Image(systemName: showFullArgs ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(themeManager.palette.textMuted.opacity(0.5))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                // Duration bar (visual progress)
                if call.status == .running {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(themeManager.palette.effectiveAccent)
                        .scaleEffect(y: 0.5)
                }

                // Expandable result preview
                if let result = call.result, !result.isEmpty {
                    Button(action: {
                        withAnimation(Anim.spring) { isExpanded.toggle() }
                    }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(isExpanded ? "Hide result" : "Show result")
                                .font(Typography.micro)
                        }
                        .foregroundColor(themeManager.palette.textMuted)
                    }
                    .buttonStyle(.plain)

                    if isExpanded {
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(result.prefix(2000).description)
                                .font(Typography.codeMicro)
                                .foregroundColor(themeManager.palette.textSecondary)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 200)
                        .padding(Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(themeManager.palette.bgElevated.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm)
                                .stroke(themeManager.palette.borderSubtle, lineWidth: Border.thin)
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : Spacing.xl)
        }
    }

    // MARK: - Status Dot

    @ViewBuilder
    private var statusDot: some View {
        switch call.status {
        case .pending:
            Circle()
                .fill(themeManager.palette.textMuted.opacity(0.3))
                .overlay(Circle().stroke(themeManager.palette.textMuted.opacity(0.5), lineWidth: 1))
        case .running:
            Circle()
                .fill(themeManager.palette.effectiveAccent)
                .modifier(PulseModifier())
        case .completed:
            Circle()
                .fill(Color.accentGreen)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.white)
                )
        case .failed:
            Circle()
                .fill(Color.red)
                .overlay(
                    Image(systemName: "xmark")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.white)
                )
        case .cancelled:
            Circle()
                .fill(Color.orange)
                .overlay(
                    Image(systemName: "minus")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(.white)
                )
        }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        switch call.status {
        case .pending:
            Text("Queued")
                .font(Typography.micro)
                .foregroundColor(themeManager.palette.textMuted)
        case .running:
            HStack(spacing: Spacing.xs) {
                ProgressView()
                    .controlSize(.mini)
                Text(call.currentStep ?? "Running")
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.effectiveAccent)
            }
        case .completed:
            Text("Done")
                .font(Typography.micro)
                .foregroundColor(.accentGreen)
        case .failed:
            Text("Failed")
                .font(Typography.micro)
                .foregroundColor(.red)
        case .cancelled:
            Text("Cancelled")
                .font(Typography.micro)
                .foregroundColor(.orange)
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        switch call.status {
        case .pending: return themeManager.palette.textMuted
        case .running: return themeManager.palette.effectiveAccent
        case .completed: return .accentGreen
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    private var lineColor: Color {
        switch call.status {
        case .completed: return Color.accentGreen.opacity(0.3)
        case .failed: return Color.red.opacity(0.3)
        default: return themeManager.palette.borderCrisp.opacity(0.3)
        }
    }

    private var displayName: String {
        call.name
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private var argsSummary: String {
        guard !call.arguments.isEmpty else { return "" }
        // Try to extract key info from JSON arguments
        if let data = call.arguments.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Show path for file ops, command for shell ops
            if let path = json["path"] as? String {
                return path
            }
            if let command = json["command"] as? String {
                return command.prefix(80).description
            }
            if let query = json["query"] as? String {
                return query.prefix(80).description
            }
        }
        // Fallback: truncated raw args
        if call.arguments.count > 60 {
            return String(call.arguments.prefix(57)) + "..."
        }
        return call.arguments
    }

    private var toolIcon: String {
        let name = call.name.lowercased()
        if name.contains("read") || name.contains("file") { return "doc.text" }
        if name.contains("write") || name.contains("edit") { return "pencil" }
        if name.contains("run") || name.contains("shell") || name.contains("command") { return "terminal" }
        if name.contains("search") || name.contains("grep") || name.contains("find") { return "magnifyingglass" }
        if name.contains("git") { return "arrow.triangle.branch" }
        if name.contains("web") || name.contains("browser") { return "globe" }
        if name.contains("docker") { return "shippingbox" }
        if name.contains("test") { return "checkmark.diamond" }
        if name.contains("build") || name.contains("xcode") { return "hammer" }
        if name.contains("delete") || name.contains("remove") { return "trash" }
        if name.contains("create") || name.contains("mkdir") { return "folder.badge.plus" }
        return "gearshape"
    }

    private var hasFullArgs: Bool {
        call.arguments.count > 60
    }

    private var prettyArgs: String {
        guard let data = call.arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: pretty, encoding: .utf8) else {
            return call.arguments
        }
        return str
    }

    private var formattedDuration: String? {
        guard let start = call.startTime else { return nil }
        let end = call.endTime ?? Date()
        let duration = end.timeIntervalSince(start)
        if duration < 0.1 { return nil }
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        }
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }
        return String(format: "%.0fm %.0fs", floor(duration / 60), duration.truncatingRemainder(dividingBy: 60))
    }
}
