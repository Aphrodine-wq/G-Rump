import SwiftUI

/// Inline chat popover that appears in the file navigator.
/// Lets users ask quick questions about a specific file without
/// leaving the project navigator context.
struct InlineFileChatView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    let filePath: String
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var isSubmitting = false
    @FocusState private var isFocused: Bool

    private var fileName: String {
        (filePath as NSString).lastPathComponent
    }

    private var relativePath: String {
        if !viewModel.workingDirectory.isEmpty, filePath.hasPrefix(viewModel.workingDirectory) {
            let rel = String(filePath.dropFirst(viewModel.workingDirectory.count))
            return rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
        }
        return fileName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.md) {
                Image(systemName: FileNode.iconForExtension((fileName as NSString).pathExtension))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(themeManager.palette.effectiveAccent)

                Text(fileName)
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(1)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(themeManager.palette.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Quick actions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.md) {
                    ForEach(quickActions, id: \.label) { action in
                        Button(action: { submitQuery(action.prompt) }) {
                            Text(action.label)
                                .font(Typography.micro)
                                .foregroundColor(themeManager.palette.effectiveAccent)
                                .padding(.horizontal, Spacing.lg)
                                .padding(.vertical, Spacing.xs)
                                .background(
                                    Capsule()
                                        .fill(themeManager.palette.effectiveAccent.opacity(0.1))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, Spacing.lg)
            }

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            // Input field
            HStack(spacing: Spacing.md) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 10))
                    .foregroundColor(themeManager.palette.textMuted)

                TextField("Ask about \(fileName)…", text: $query)
                    .font(Typography.bodySmall)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .onSubmit {
                        if !query.isEmpty {
                            submitQuery(query)
                        }
                    }

                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                } else if !query.isEmpty {
                    Button(action: { submitQuery(query) }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.lg)
        }
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
                .stroke(themeManager.palette.borderCrisp.opacity(0.3), lineWidth: Border.thin)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal, Spacing.lg)
        .onAppear { isFocused = true }
    }

    // MARK: - Quick Actions

    private struct QuickAction {
        let label: String
        let prompt: String
    }

    private var quickActions: [QuickAction] {
        let ext = (fileName as NSString).pathExtension.lowercased()
        var actions = [
            QuickAction(label: "Summarize", prompt: "Read and summarize the file `\(relativePath)`. Explain its purpose and key components."),
            QuickAction(label: "Find bugs", prompt: "Read `\(relativePath)` and identify any potential bugs, issues, or improvements."),
            QuickAction(label: "Explain", prompt: "Read `\(relativePath)` and explain how it works step by step.")
        ]

        if ["swift", "py", "js", "ts", "tsx", "jsx", "rs", "go", "java", "kt", "rb"].contains(ext) {
            actions.append(QuickAction(label: "Add tests", prompt: "Read `\(relativePath)` and write comprehensive unit tests for it."))
            actions.append(QuickAction(label: "Refactor", prompt: "Read `\(relativePath)` and suggest refactoring improvements for better code quality."))
        }

        if ["json", "yaml", "yml", "toml", "plist"].contains(ext) {
            actions.append(QuickAction(label: "Validate", prompt: "Read `\(relativePath)` and validate its structure. Report any issues."))
        }

        return actions
    }

    // MARK: - Submit

    private func submitQuery(_ text: String) {
        let fullPrompt: String
        if text.contains(relativePath) || text.contains(fileName) {
            fullPrompt = text
        } else {
            fullPrompt = "Regarding the file `\(relativePath)`: \(text)"
        }

        isSubmitting = true
        viewModel.userInput = fullPrompt
        viewModel.sendMessage()

        // Brief delay then dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isSubmitting = false
            query = ""
            onDismiss()
        }
    }
}
