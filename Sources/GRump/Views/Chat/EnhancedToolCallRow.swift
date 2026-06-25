import SwiftUI

// MARK: - Enhanced Tool Call Row

struct EnhancedToolCallRow: View {
    let tool: ToolCallStatus
    let themeManager: ThemeManager
    @State private var animatedProgress: Double = 0

    private var statusColor: Color {
        switch tool.status {
        case .pending: return .orange
        case .running: return .blue
        case .completed: return .accentGreen
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    private var statusIcon: String {
        switch tool.status {
        case .pending: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    private var elapsedTime: String {
        guard let startTime = tool.startTime else { return "" }
        let endTime = tool.endTime ?? Date()
        let duration = endTime.timeIntervalSince(startTime)
        if duration < 1 {
            return "< 1s"
        } else if duration < 60 {
            return "\(Int(duration))s"
        } else {
            return "\(Int(duration / 60))m \(Int(duration.truncatingRemainder(dividingBy: 60)))s"
        }
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            HStack(spacing: Spacing.lg) {
                // Status indicator with animation
                ZStack {
                    Circle()
                        .stroke(statusColor.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)

                    if tool.status == .running {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(statusColor)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(statusColor)
                    }
                }

                // Tool info
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Image(systemName: toolIcon(tool.name))
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.effectiveAccentLightVariant)

                        Text(toolDisplayName(tool.name))
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textPrimary)

                        Spacer()

                        Text(elapsedTime)
                            .font(Typography.micro)
                            .foregroundColor(.textMuted)
                    }

                    if let currentStep = tool.currentStep {
                        HStack {
                            Text(currentStep)
                                .font(Typography.micro)
                                .foregroundColor(statusColor)

                            if tool.totalSteps > 1 {
                                Text("(\(tool.currentStepNumber)/\(tool.totalSteps))")
                                    .font(Typography.micro)
                                    .foregroundColor(.textMuted)
                            }
                        }
                    }
                }
            }

            // Progress bar for running tools
            if tool.status == .running && tool.totalSteps > 1 {
                HStack(spacing: Spacing.sm) {
                    ProgressView(value: animatedProgress, total: 1.0)
                        .progressViewStyle(LinearProgressViewStyle(tint: statusColor))
                        .scaleEffect(y: 0.5)

                    Text("\(Int(animatedProgress * 100))%")
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                }
            }

            // Tool arguments (collapsible)
            if !tool.arguments.isEmpty {
                Text(toolArgSummary(tool.arguments))
                    .font(Typography.codeSmall)
                    .foregroundColor(.textMuted)
                    .lineLimit(2)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xs)
                    .background(themeManager.palette.bgDark.opacity(0.5))
                    .cornerRadius(Radius.xs)
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.md)
        .background(themeManager.palette.bgCard.opacity(0.5))
        .cornerRadius(Radius.sm)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.3)) {
                animatedProgress = tool.progress
            }
        }
        .onChange(of: tool.progress) { _, newProgress in
            withAnimation(.easeInOut(duration: 0.3)) {
                animatedProgress = newProgress
            }
        }
    }

    private func toolIcon(_ name: String) -> String {
        switch name {
        case "read_file", "batch_read_files": return "doc.text"
        case "write_file", "append_file": return "pencil"
        case "edit_file": return "square.and.pencil"
        case "create_file", "create_directory": return "doc.badge.plus"
        case "delete_file": return "trash"
        case "compress_files", "extract_archive": return "doc.zipper"
        case "list_directory", "tree_view": return "folder"
        case "search_files": return "magnifyingglass"
        case "grep_search": return "text.magnifyingglass"
        case "find_and_replace": return "arrow.left.arrow.right"
        case "run_command", "run_background": return "terminal"
        case "kill_process": return "stop.circle"
        case "which": return "magnifyingglass"
        case "system_run": return "terminal.fill"
        case "system_notify": return "bell.fill"
        case "clipboard_read", "clipboard_write": return "doc.on.clipboard"
        case "open_url": return "link"
        case "open_app": return "app.badge"
        case "screen_snapshot": return "rectangle.dashed.badge.record"
        case "screen_record": return "record.circle"
        case "camera_snap": return "camera.fill"
        case "window_list", "window_snapshot": return "macwindow"
        case "web_search": return "globe"
        case "read_url", "fetch_json", "download_file": return "link"
        case "view_code_outline": return "chevron.left.forwardslash.chevron.right"
        default: return "wrench.and.screwdriver"
        }
    }

    private func toolDisplayName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func toolArgSummary(_ args: String) -> String {
        guard let data = args.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return args
        }

        var parts: [String] = []
        if let path = json["path"] as? String {
            parts.append("path: \(URL(fileURLWithPath: path).lastPathComponent)")
        }
        if let command = json["command"] as? String {
            parts.append("cmd: \(command.components(separatedBy: " ").first ?? command)")
        }
        if let query = json["query"] as? String {
            parts.append("query: \(String(query.prefix(30)))")
        }

        return parts.isEmpty ? args : parts.joined(separator: " • ")
    }
}
