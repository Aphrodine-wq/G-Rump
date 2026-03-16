import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Tool Result Row (collapsible)

struct ToolResultRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let message: Message
    var toolName: String? = nil
    var argSummary: String? = nil
    @State private var isExpanded = false
    @State private var copiedResult = false

    private var headerTitle: String {
        if let name = toolName, !name.isEmpty {
            return name
        }
        return "Tool result"
    }

    private var toolIcon: String {
        guard let name = toolName?.lowercased() else { return "wrench" }
        if name.contains("read") || name.contains("file") { return "doc.text" }
        if name.contains("write") || name.contains("edit") || name.contains("create") { return "square.and.pencil" }
        if name.contains("delete") { return "trash" }
        if name.contains("search") || name.contains("grep") || name.contains("find") { return "magnifyingglass" }
        if name.contains("command") || name.contains("run") || name.contains("shell") { return "terminal" }
        if name.contains("git") { return "arrow.triangle.branch" }
        if name.contains("list") || name.contains("tree") || name.contains("directory") { return "folder" }
        if name.contains("web") || name.contains("url") || name.contains("fetch") { return "globe" }
        if name.contains("test") { return "checkmark.circle" }
        if name.contains("clipboard") { return "doc.on.clipboard" }
        if name.contains("screen") || name.contains("window") { return "macwindow" }
        return "wrench"
    }

    private var statusColor: Color {
        let content = message.content.lowercased()
        if content.contains("error") || content.contains("failed") || content.contains("not found") {
            return .red
        }
        return .accentGreen
    }

    private var isBuildTool: Bool {
        guard let name = toolName?.lowercased() else { return false }
        return name.contains("command") || name.contains("run") || name.contains("shell") || name.contains("build")
    }

    private var parsedBuildErrors: [BuildError] {
        guard isBuildTool else { return [] }
        let errors = BuildErrorParserEngine.parse(message.content)
        return errors.isEmpty ? [] : errors
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Compact one-liner: icon + Tool Name · arg summary — click to expand
            Button(action: { withAnimation(.easeInOut(duration: Anim.quick)) { isExpanded.toggle() } }) {
                HStack(spacing: Spacing.md) {
                    // Status icon in a tinted circle
                    ZStack {
                        Circle()
                            .fill(statusColor.opacity(0.15))
                            .frame(width: 20, height: 20)
                        Image(systemName: statusColor == .red ? "xmark" : "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(statusColor)
                    }

                    // Tool name pill
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: toolIcon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(statusColor)
                        Text(headerTitle.replacingOccurrences(of: "_", with: " "))
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.08))
                    .clipShape(Capsule())

                    if let arg = argSummary, !arg.isEmpty {
                        Text(arg)
                            .font(Typography.captionSmall)
                            .fontDesign(.monospaced)
                            .foregroundColor(themeManager.palette.textMuted)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Line count hint
                    let lineCount = message.content.components(separatedBy: "\n").count
                    if lineCount > 1 {
                        Text("\(lineCount) lines")
                            .font(Typography.micro)
                            .foregroundColor(themeManager.palette.textMuted.opacity(0.4))
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted.opacity(0.5))
                }
                .padding(.vertical, Spacing.sm)
            }
            .buttonStyle(.plain)

            if isExpanded {
                // Rich rendering for build errors
                if isBuildTool, !parsedBuildErrors.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(parsedBuildErrors.prefix(10)) { error in
                            HStack(alignment: .top, spacing: Spacing.md) {
                                Image(systemName: error.severity.icon)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(error.severity.color)
                                    .frame(width: 14)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(error.message)
                                        .font(Typography.captionSmallMedium)
                                        .foregroundColor(themeManager.palette.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)

                                    HStack(spacing: Spacing.sm) {
                                        Text(error.fileName)
                                            .font(Typography.codeMicro)
                                            .foregroundColor(themeManager.palette.effectiveAccent)
                                        Text(":\(error.line)")
                                            .font(Typography.codeMicro)
                                            .foregroundColor(themeManager.palette.textMuted)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.xxs)
                        }

                        if parsedBuildErrors.count > 10 {
                            Text("… and \(parsedBuildErrors.count - 10) more")
                                .font(Typography.micro)
                                .foregroundColor(themeManager.palette.textMuted)
                                .padding(.horizontal, Spacing.lg)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        // Copy button for result
                        Button(action: {
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.content, forType: .string)
                            #else
                            UIPasteboard.general.string = message.content
                            #endif
                            copiedResult = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(1500))
                                copiedResult = false
                            }
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: copiedResult ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9))
                                Text(copiedResult ? "Copied" : "Copy")
                                    .font(Typography.micro)
                            }
                            .foregroundColor(copiedResult ? .accentGreen : themeManager.palette.textMuted)
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, Spacing.xxs)
                        }
                        .buttonStyle(.plain)

                        ScrollView {
                            Text(message.content)
                                .font(Typography.codeSmallScaled(scale: themeManager.contentSize.scaleFactor))
                                .foregroundColor(themeManager.palette.textSecondary)
                                .textSelection(.enabled)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.sm)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.xxs)
    }
}
