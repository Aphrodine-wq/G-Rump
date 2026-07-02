import SwiftUI

// MARK: - Agent Timeline / Waterfall View
//
// Unique-in-market visualization of agent tool execution as a horizontal
// waterfall chart. Each tool call is a colored bar: width = duration,
// color = tool category. Bars stack vertically for parallel operations.
// Clicking a bar can scroll to the corresponding message in chat.

struct AgentTimelineView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let toolCalls: [ToolCallStatus]
    let messages: [Message]
    var onSelectMessage: ((UUID) -> Void)?

    @State private var hoveredToolId: String?
    @State private var timelineScale: CGFloat = 1.0

    private var timelineStart: Date {
        toolCalls.compactMap(\.startTime).min() ?? Date()
    }

    private var timelineEnd: Date {
        let ends = toolCalls.compactMap(\.endTime)
        let running = toolCalls.filter { $0.status == .running }.map { _ in Date() }
        return (ends + running).max() ?? Date()
    }

    private var totalDuration: TimeInterval {
        max(timelineEnd.timeIntervalSince(timelineStart), 0.1)
    }

    // Group tool calls into "lanes" for parallel execution display
    private var lanes: [[ToolCallStatus]] {
        var result: [[ToolCallStatus]] = []
        let sorted = toolCalls.sorted { ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture) }

        for tool in sorted {
            guard let start = tool.startTime else { continue }
            var placed = false
            for i in result.indices {
                let laneEnd = result[i].compactMap(\.endTime).max() ?? .distantPast
                if start >= laneEnd {
                    result[i].append(tool)
                    placed = true
                    break
                }
            }
            if !placed {
                result.append([tool])
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Summary statistics bar
            summaryBar

            Divider()
                .background(themeManager.palette.borderSubtle)

            // Timeline header with time markers
            timelineHeader

            // Waterfall lanes
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lanes.enumerated()), id: \.offset) { laneIndex, lane in
                        laneView(lane: lane, laneIndex: laneIndex)
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.md)
                .frame(minWidth: max(600 * timelineScale, 400))
            }
            .background(themeManager.palette.bgDark)

            // Tooltip overlay
            if let hovered = hoveredToolId, let tool = toolCalls.first(where: { $0.id == hovered }) {
                toolTooltip(tool)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        let completed = toolCalls.filter { $0.status == .completed }.count
        let running = toolCalls.filter { $0.status == .running }.count
        let failed = toolCalls.filter { $0.status == .failed }.count
        let totalTime = totalDuration

        return HStack(spacing: Spacing.huge) {
            statPill(icon: "wrench", label: "\(toolCalls.count)", subtitle: "tools")
            statPill(icon: "checkmark.circle.fill", label: "\(completed)", subtitle: "done", color: .accentGreen)
            if running > 0 {
                statPill(icon: "arrow.triangle.2.circlepath", label: "\(running)", subtitle: "running", color: .orange)
            }
            if failed > 0 {
                statPill(icon: "xmark.circle.fill", label: "\(failed)", subtitle: "failed", color: .red)
            }
            statPill(icon: "clock", label: formatDuration(totalTime), subtitle: "elapsed")

            Spacer()

            // Zoom controls
            HStack(spacing: Spacing.sm) {
                Button(action: { withAnimation { timelineScale = max(0.5, timelineScale - 0.25) } }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)

                Text("\(Int(timelineScale * 100))%")
                    .font(Typography.micro)
                    .fontDesign(.monospaced)
                    .foregroundColor(themeManager.palette.textMuted)
                    .frame(width: 36)

                Button(action: { withAnimation { timelineScale = min(3.0, timelineScale + 0.25) } }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.xl)
        .background(themeManager.palette.bgCard)
    }

    private func statPill(icon: String, label: String, subtitle: String, color: Color? = nil) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color ?? themeManager.palette.effectiveAccent)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(Typography.captionSmallSemibold)
                    .fontDesign(.monospaced)
                    .foregroundColor(themeManager.palette.textPrimary)
                Text(subtitle)
                    .font(Typography.micro)
                    .foregroundColor(themeManager.palette.textMuted)
            }
        }
    }

    // MARK: - Timeline Header

    private var timelineHeader: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 400) * timelineScale
            ZStack(alignment: .leading) {
                // Time markers
                let markerCount = max(5, Int(width / 80))
                ForEach(0..<markerCount, id: \.self) { i in
                    let fraction = CGFloat(i) / CGFloat(markerCount - 1)
                    let time = totalDuration * Double(fraction)
                    VStack(spacing: 2) {
                        Text(formatDuration(time))
                            .font(Typography.micro)
                            .fontDesign(.monospaced)
                            .foregroundColor(themeManager.palette.textMuted)
                        Rectangle()
                            .fill(themeManager.palette.borderSubtle)
                            .frame(width: Border.thin, height: 6)
                    }
                    .position(x: fraction * width, y: 12)
                }
            }
        }
        .frame(height: 28)
        .padding(.horizontal, Spacing.xl)
        .background(themeManager.palette.bgElevated.opacity(0.5))
    }

    // MARK: - Lane View

    private func laneView(lane: [ToolCallStatus], laneIndex: Int) -> some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 400) * timelineScale
            ZStack(alignment: .leading) {
                ForEach(lane) { tool in
                    toolBar(tool: tool, totalWidth: width)
                }
            }
        }
        .frame(height: 28)
    }

    // MARK: - Tool Bar

    private func toolBar(tool: ToolCallStatus, totalWidth: CGFloat) -> some View {
        let start = tool.startTime ?? timelineStart
        let end = tool.endTime ?? (tool.status == .running ? Date() : start.addingTimeInterval(0.1))
        let startFraction = CGFloat(start.timeIntervalSince(timelineStart) / totalDuration)
        let durationFraction = CGFloat(end.timeIntervalSince(start) / totalDuration)
        let barWidth = max(durationFraction * totalWidth, 4)
        let xOffset = startFraction * totalWidth

        let isHovered = hoveredToolId == tool.id
        let category = toolCategory(tool.name)

        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [category.color, category.color.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: barWidth, height: isHovered ? 24 : 20)
                .overlay(
                    // Tool name label (only if bar is wide enough)
                    Group {
                        if barWidth > 60 {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 8, weight: .bold))
                                Text(tool.name.replacingOccurrences(of: "_", with: " "))
                                    .font(Typography.micro)
                                    .fontDesign(.monospaced)
                                    .lineLimit(1)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, Spacing.sm)
                        }
                    }
                )
                .overlay(
                    // Pulsing leading edge for running tools
                    Group {
                        if tool.status == .running {
                            HStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.6))
                                    .frame(width: 3, height: 16)
                                    .modifier(PulseAnimation())
                            }
                        }
                    }
                )
                .overlay(
                    // Failed indicator
                    Group {
                        if tool.status == .failed {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.red, lineWidth: 2)
                        }
                    }
                )
                .shadow(color: isHovered ? category.color.opacity(0.4) : .clear, radius: 6, y: 2)
                .scaleEffect(isHovered ? 1.05 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovered)
                .onHover { hovered in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        hoveredToolId = hovered ? tool.id : nil
                    }
                }
                .onTapGesture {
                    // Find corresponding message and scroll to it
                    if let msg = messages.first(where: { message in
                        message.role == .assistant &&
                        message.toolCalls?.contains(where: { $0.id == tool.id }) == true
                    }) {
                        onSelectMessage?(msg.id)
                    }
                }
        }
        .offset(x: xOffset)
    }

    // MARK: - Tooltip

    private func toolTooltip(_ tool: ToolCallStatus) -> some View {
        let duration = (tool.endTime ?? Date()).timeIntervalSince(tool.startTime ?? Date())
        let category = toolCategory(tool.name)

        return HStack(spacing: Spacing.xl) {
            Image(systemName: category.icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(category.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(tool.name.replacingOccurrences(of: "_", with: " "))
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)

                HStack(spacing: Spacing.md) {
                    Label(formatDuration(duration), systemImage: "clock")
                        .font(Typography.micro)
                        .foregroundColor(themeManager.palette.textMuted)

                    statusBadge(tool.status)
                }

                if !tool.arguments.isEmpty, let summary = toolArgPreview(tool.arguments) {
                    Text(summary)
                        .font(Typography.micro)
                        .fontDesign(.monospaced)
                        .foregroundColor(themeManager.palette.textMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
                .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.sm)
    }

    private func statusBadge(_ status: ToolCallStatus.ToolRunStatus) -> some View {
        let (icon, color, text): (String, Color, String) = {
            switch status {
            case .pending: return ("circle", .gray, "Pending")
            case .running: return ("arrow.triangle.2.circlepath", .orange, "Running")
            case .completed: return ("checkmark.circle.fill", .accentGreen, "Done")
            case .failed: return ("xmark.circle.fill", .red, "Failed")
            case .cancelled: return ("slash.circle", .gray, "Cancelled")
            }
        }()

        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(Typography.micro)
        }
        .foregroundColor(color)
    }

    // MARK: - Tool Categories

    private struct ToolCategory {
        let name: String
        let color: Color
        let icon: String
    }

    private func toolCategory(_ name: String) -> ToolCategory {
        let n = name.lowercased()
        if n.contains("read") || n.contains("write") || n.contains("edit") ||
           n.contains("create") || n.contains("delete") || n.contains("file") ||
           n.contains("append") || n.contains("list_directory") || n.contains("tree") {
            return ToolCategory(name: "File", color: Color(red: 0.24, green: 0.53, blue: 0.98), icon: "doc.text")
        }
        if n.contains("command") || n.contains("run") || n.contains("shell") ||
           n.contains("kill") || n.contains("system_run") {
            return ToolCategory(name: "Shell", color: Color(red: 0.22, green: 0.78, blue: 0.49), icon: "terminal")
        }
        if n.contains("git") {
            return ToolCategory(name: "Git", color: Color(red: 1.0, green: 0.58, blue: 0.20), icon: "arrow.triangle.branch")
        }
        if n.contains("search") || n.contains("grep") || n.contains("find") {
            return ToolCategory(name: "Search", color: Color(red: 0.22, green: 0.71, blue: 0.71), icon: "magnifyingglass")
        }
        if n.contains("web") || n.contains("url") || n.contains("fetch") || n.contains("download") {
            return ToolCategory(name: "Network", color: Color(red: 0.56, green: 0.34, blue: 1.0), icon: "globe")
        }
        if n.contains("screen") || n.contains("window") || n.contains("camera") {
            return ToolCategory(name: "UI", color: Color(red: 0.94, green: 0.33, blue: 0.54), icon: "macwindow")
        }
        if n.contains("test") {
            return ToolCategory(name: "Test", color: Color(red: 0.22, green: 0.88, blue: 0.60), icon: "checkmark.circle")
        }
        return ToolCategory(name: "Tool", color: Color(red: 0.55, green: 0.55, blue: 0.65), icon: "wrench")
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "\(Int(seconds * 1000))ms" }
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let min = Int(seconds) / 60
        let sec = Int(seconds) % 60
        return "\(min)m \(sec)s"
    }

    private func toolArgPreview(_ arguments: String) -> String? {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let path = args["path"] as? String { return (path as NSString).lastPathComponent }
        if let command = args["command"] as? String { return String(command.prefix(40)) }
        if let query = args["query"] as? String { return String(query.prefix(40)) }
        return nil
    }
}

// MARK: - Pulse Animation Modifier

private struct PulseAnimation: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
