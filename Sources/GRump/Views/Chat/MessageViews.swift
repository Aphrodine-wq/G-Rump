import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Message Reaction (single source of truth)

enum MessageReaction {
    case thumbsUp
    case thumbsDown
}

// MARK: - Message Row

struct MessageRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    let message: Message
    var agentMode: AgentMode = .standard
    @State private var showCopyConfirm = false
    @State private var isHovered = false
    @State private var reaction: MessageReaction? = nil
    @State private var isEditing = false
    @State private var editText = ""
    @State private var showAllTools = false
    @State private var isCollapsed: Bool? = nil // nil = auto-detect on appear

    /// Threshold for auto-collapsing long messages (line count)
    private static let collapseThreshold = 150
    /// How many lines to show when collapsed
    private static let collapsedPreviewLines = 30

    private var shouldAutoCollapse: Bool {
        !isUser && message.content.components(separatedBy: "\n").count > Self.collapseThreshold
    }

    private var effectivelyCollapsed: Bool {
        isCollapsed ?? shouldAutoCollapse
    }

    var isUser: Bool { message.role == .user }

    // MARK: - Mode-Specific Styling

    private var modeMood: LogoMood { agentMode.logoMood }

    private var modeLineSpacing: CGFloat {
        switch agentMode {
        case .plan: return 2        // tighter for structured lists
        case .argue: return 5       // more spacious for readability
        case .fullStack: return 3   // standard
        case .spec: return 4        // slightly spacious for Q&A
        default: return 3
        }
    }

    private var modeBorderColor: Color? {
        switch agentMode {
        case .argue: return Color(red: 1.0, green: 0.45, blue: 0.3).opacity(0.3)
        case .plan: return Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.3)
        case .fullStack: return Color(red: 0.2, green: 0.85, blue: 0.5).opacity(0.3)
        case .spec: return Color(red: 0.8, green: 0.6, blue: 1.0).opacity(0.3)
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isUser {
                userBlock
            } else {
                assistantBlock
            }
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.xs)
        .onHover { isHovered = $0 }
    }

    // MARK: - User Message (right-aligned plain text, flat)

    private var userBlock: some View {
        VStack(alignment: .trailing, spacing: Spacing.sm) {
            if isEditing {
                VStack(alignment: .trailing, spacing: Spacing.md) {
                    TextEditor(text: $editText)
                        .font(Typography.body)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 44, maxHeight: 200)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Spacing.lg) {
                        Button("Cancel") {
                            isEditing = false
                        }
                        .buttonStyle(.plain)
                        .font(Typography.captionSmallMedium)
                        .foregroundColor(themeManager.palette.textMuted)

                        Button("Save & Resend") {
                            viewModel.editUserMessage(message.id, newContent: editText)
                            isEditing = false
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                        .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            } else {
                VStack(alignment: .trailing, spacing: Spacing.sm) {
                    Text(message.content)
                        .font(Typography.body)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .fill(themeManager.palette.bgCard)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                                .stroke(themeManager.palette.borderSubtle, lineWidth: Border.thin)
                        )

                    // Edit button on hover
                    if isHovered {
                        Button(action: {
                            editText = message.content
                            isEditing = true
                        }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "pencil")
                                    .font(Typography.micro)
                                Text("Edit")
                                    .font(Typography.micro)
                            }
                            .foregroundColor(themeManager.palette.textMuted)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .transition(.opacity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.easeInOut(duration: Anim.instant), value: isHovered)
        .animation(.easeInOut(duration: Anim.quick), value: isEditing)
    }

    // MARK: - Assistant Message (flat text, small inline icon)

    private var assistantBlock: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Inline label: tiny frowny icon + "G-Rump"
            HStack(spacing: Spacing.sm) {
                FrownyFaceLogo(size: 16, mood: modeMood)
                Text("G-Rump")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textMuted)
            }

            // Tool calls as compact one-liners
            if let toolCalls = message.toolCalls, !toolCalls.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    ForEach(Array((showAllTools ? toolCalls : Array(toolCalls.prefix(6))).enumerated()), id: \.offset) { _, call in
                        HStack(spacing: Spacing.md) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentGreen.opacity(0.15))
                                    .frame(width: 18, height: 18)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.accentGreen)
                            }
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: toolIconForName(call.name))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.accentGreen)
                                Text(call.name.replacingOccurrences(of: "_", with: " "))
                                    .font(Typography.captionSmallSemibold)
                                    .foregroundColor(themeManager.palette.textPrimary)
                            }
                            .padding(.horizontal, Spacing.md)
                            .padding(.vertical, 3)
                            .background(Color.accentGreen.opacity(0.08))
                            .clipShape(Capsule())

                            // Show key argument (path or command)
                            if let argPreview = toolArgPreview(call.arguments) {
                                Text(argPreview)
                                    .font(Typography.captionSmall)
                                    .fontDesign(.monospaced)
                                    .foregroundColor(themeManager.palette.textMuted)
                                    .lineLimit(1)
                            }
                        }
                    }
                    if toolCalls.count > 6 {
                        Button(action: { showAllTools.toggle() }) {
                            Text(showAllTools ? "Show less" : "+\(toolCalls.count - 6) more")
                                .font(Typography.captionSmall)
                                .foregroundColor(themeManager.palette.effectiveAccent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, Spacing.sm)
            }

            // Message content — flat, no bubble (with auto-collapse for long messages)
            if !message.content.isEmpty {
                if effectivelyCollapsed {
                    // Show truncated preview
                    let previewText = message.content
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .prefix(Self.collapsedPreviewLines)
                        .joined(separator: "\n")
                    MarkdownTextView(text: previewText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    // Fade-out gradient + expand button
                    VStack(spacing: Spacing.sm) {
                        LinearGradient(
                            colors: [themeManager.palette.bgDark.opacity(0), themeManager.palette.bgDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 40)

                        Button(action: { withAnimation(.easeInOut(duration: Anim.quick)) { isCollapsed = false } }) {
                            HStack(spacing: Spacing.md) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                let totalLines = message.content.components(separatedBy: "\n").count
                                Text("Show all \(totalLines) lines")
                                    .font(Typography.captionSmallSemibold)
                            }
                            .foregroundColor(themeManager.palette.effectiveAccent)
                            .padding(.horizontal, Spacing.xxl)
                            .padding(.vertical, Spacing.md)
                            .background(themeManager.palette.effectiveAccent.opacity(0.08))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, -40) // overlap gradient with content
                } else {
                    MarkdownTextView(text: message.content)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    // Collapse button for long messages that are expanded
                    if shouldAutoCollapse {
                        Button(action: { withAnimation(.easeInOut(duration: Anim.quick)) { isCollapsed = true } }) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Collapse")
                                    .font(Typography.captionSmallMedium)
                            }
                            .foregroundColor(themeManager.palette.textMuted)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, Spacing.sm)
                    }
                }
            }

            // Inline question option grid (only for ask_user tool calls)
            if message.toolCallId != nil,
               let parsed = QuestionParser.parse(from: message.content) {
                QuestionOptionGrid(question: parsed) { selected in
                    viewModel.userInput = selected.label
                    Task { await viewModel.sendMessage() }
                }
                .padding(.top, Spacing.sm)
            }

            // Action bar (hover-visible): reactions + regenerate + copy
            if isHovered {
                assistantActionBar
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if let borderColor = modeBorderColor {
                RoundedRectangle(cornerRadius: 2)
                    .fill(borderColor)
                    .frame(width: 3)
                    .padding(.vertical, Spacing.sm)
            }
        }
        .animation(.easeInOut(duration: Anim.instant), value: isHovered)
    }

    // MARK: - Assistant Action Bar (reactions, regenerate, copy)

    private var assistantActionBar: some View {
        HStack(spacing: Spacing.xl) {
            // Thumbs up
            Button(action: { reaction = (reaction == .thumbsUp) ? nil : .thumbsUp }) {
                Image(systemName: reaction == .thumbsUp ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(Typography.captionSmall)
                    .foregroundColor(reaction == .thumbsUp ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Thumbs up")

            // Thumbs down
            Button(action: { reaction = (reaction == .thumbsDown) ? nil : .thumbsDown }) {
                Image(systemName: reaction == .thumbsDown ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(Typography.captionSmall)
                    .foregroundColor(reaction == .thumbsDown ? Color(red: 1.0, green: 0.4, blue: 0.4) : themeManager.palette.textMuted)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Thumbs down")

            Divider().frame(height: 14)

            // Copy
            copyButton

            // Copy as Markdown
            copyMarkdownButton

            // Regenerate
            Button(action: {
                viewModel.retryLastMessage()
            }) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.micro)
                    Text("Regenerate")
                        .font(Typography.micro)
                }
                .foregroundColor(themeManager.palette.textMuted)
            }
            .buttonStyle(ScaleButtonStyle())
            .accessibilityLabel("Regenerate response")

            Spacer()

            // Word count (subtle)
            Text(wordCountLabel)
                .font(Typography.micro)
                .foregroundColor(themeManager.palette.textMuted.opacity(0.5))
        }
    }

    private var wordCountLabel: String {
        let words = message.content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        if words < 1000 {
            return "\(words) words"
        }
        return String(format: "%.1fk words", Double(words) / 1000.0)
    }

    // MARK: - Shared Components

    private var copyButton: some View {
        Button(action: {
            #if os(macOS)
            // Copy as both plain text and RTF for rich paste support
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.content, forType: .string)
            #else
            UIPasteboard.general.string = message.content
            #endif
            showCopyConfirm = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                showCopyConfirm = false
            }
        }) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: showCopyConfirm ? "checkmark" : "doc.on.doc")
                    .font(Typography.micro)
                Text(showCopyConfirm ? "Copied" : "Copy")
                    .font(Typography.micro)
            }
            .foregroundColor(showCopyConfirm ? .accentGreen : themeManager.palette.textMuted)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(showCopyConfirm ? "Copied to clipboard" : "Copy message")
    }

    // MARK: - Copy as Markdown

    private var copyMarkdownButton: some View {
        Button(action: {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.content, forType: .string)
            #else
            UIPasteboard.general.string = message.content
            #endif
            showCopyConfirm = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1500))
                showCopyConfirm = false
            }
        }) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "text.alignleft")
                    .font(Typography.micro)
                Text("Markdown")
                    .font(Typography.micro)
            }
            .foregroundColor(themeManager.palette.textMuted)
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("Copy as markdown")
    }

    private func toolIconForName(_ name: String) -> String {
        switch name {
        case "read_file", "batch_read_files": return "doc.text"
        case "write_file", "append_file": return "pencil"
        case "edit_file": return "square.and.pencil"
        case "create_file", "create_directory": return "doc.badge.plus"
        case "delete_file": return "trash"
        case "list_directory", "tree_view": return "folder"
        case "search_files", "grep_search": return "magnifyingglass"
        case "run_command", "run_background", "system_run": return "terminal"
        case "git_status", "git_add", "git_commit", "git_push", "git_pull": return "arrow.triangle.branch"
        case "web_search": return "globe"
        case "read_url", "fetch_json": return "link"
        case "run_tests": return "checkmark.circle"
        default: return "wrench"
        }
    }

    private func toolArgPreview(_ arguments: String) -> String? {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let path = json["path"] as? String {
            // Show just the filename for brevity
            return (path as NSString).lastPathComponent
        }
        if let command = json["command"] as? String {
            return String(command.prefix(60))
        }
        if let query = json["query"] as? String {
            return String(query.prefix(50))
        }
        return nil
    }
}
