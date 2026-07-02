import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

// MARK: - Conversation Row

/// A single row in the conversation sidebar list.
/// Displays the conversation title with hover/selection styling,
/// a context menu for rename/duplicate/export/delete, and drag support.
struct ConversationRow: View {
    @EnvironmentObject var themeManager: ThemeManager
    let conversation: Conversation
    let isSelected: Bool
    var onSelect: (() -> Void)?
    let onDelete: () -> Void
    let onRename: () -> Void
    var onDuplicate: (() -> Void)?
    @State private var isHovered = false

    var messageCount: Int { conversation.messages.count }

    private var lastMessagePreview: String? {
        // Walk backwards to find last user/assistant message — avoids full array scan
        for msg in conversation.messages.reversed() {
            guard msg.role == .user || msg.role == .assistant else { continue }
            let content = msg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            return String(content.replacingOccurrences(of: "\n", with: " ").prefix(80))
        }
        return nil
    }

    var body: some View {
        Button(action: { onSelect?() }) {
            HStack(spacing: Spacing.md) {
                RoundedRectangle(cornerRadius: Radius.xs)
                    .fill(isSelected ? themeManager.palette.effectiveAccent : Color.clear)
                    .frame(width: 2, height: 18)

                Text(conversation.title)
                    .font(isSelected ? Typography.bodySmallSemibold : Typography.bodySmall)
                    .foregroundColor(isSelected ? themeManager.palette.textPrimary : themeManager.palette.textSecondary)
                    .lineLimit(1)

                Spacer()

                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(themeManager.palette.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Delete conversation")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.md)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(
                    isSelected
                        ? themeManager.palette.effectiveAccent.opacity(0.10)
                        : (isHovered ? themeManager.palette.bgInput.opacity(0.5) : Color.clear)
                )
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: Anim.instant), value: isHovered)
        .contextMenu {
            Button(action: onRename) {
                Label("Rename…", systemImage: "pencil")
            }
            if let duplicate = onDuplicate {
                Button(action: duplicate) {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
            }

            Divider()

            Button(action: { exportAsMarkdown(conversation) }) {
                Label("Export as Markdown", systemImage: "doc.text")
            }
            Button(action: { exportAsGrumpFile(conversation) }) {
                Label("Export as .grump", systemImage: "doc.zipper")
            }
            #if os(macOS)
            Button(action: { ShareSheetHelper.shareConversation(conversation) }) {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            #endif

            Divider()

            Button(role: .destructive, action: onDelete) {
                Label("Delete Conversation", systemImage: "trash")
            }
        }
        .onDrag { conversation.itemProvider }
    }

    // MARK: - Export Helpers

    private func exportAsMarkdown(_ conversation: Conversation) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(conversation.title).md"
        panel.allowedContentTypes = [.plainText]
        panel.begin { result in
            if result == .OK, let url = panel.url {
                let md = conversation.asMarkdown()
                try? md.write(to: url, atomically: true, encoding: .utf8)
            }
        }
        #endif
    }

    private func exportAsGrumpFile(_ conversation: Conversation) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(conversation.title).grump"
        panel.allowedContentTypes = [.grumpConversation]
        panel.begin { result in
            if result == .OK, let url = panel.url {
                if let data = try? JSONEncoder().encode(conversation) {
                    try? data.write(to: url)
                }
            }
        }
        #endif
    }
}

// MARK: - Rename Conversation Sheet

struct RenameConversationSheet: View {
    let conversation: Conversation
    @ObservedObject var viewModel: ChatViewModel
    var onDismiss: () -> Void
    @State private var title: String
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var themeManager: ThemeManager

    init(conversation: Conversation, viewModel: ChatViewModel, onDismiss: @escaping () -> Void) {
        self.conversation = conversation
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        _title = State(initialValue: conversation.title)
    }

    var body: some View {
        VStack(spacing: Spacing.huge) {
            Text("Rename conversation")
                .font(Typography.heading2)
                .foregroundColor(themeManager.palette.textPrimary)

            TextField("Title", text: $title)
                .font(Typography.body)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submitRename() }

            HStack(spacing: Spacing.lg) {
                Button("Cancel") {
                    onDismiss()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Rename") {
                    submitRename()
                    onDismiss()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(Spacing.colossal)
        .frame(minWidth: 320)
        .background(themeManager.palette.bgDark)
    }

    private func submitRename() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        viewModel.renameConversation(conversation, to: t)
    }
}
