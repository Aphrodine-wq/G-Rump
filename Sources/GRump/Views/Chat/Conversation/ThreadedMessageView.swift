import SwiftUI

// MARK: - Threaded Message View

struct ThreadedMessageView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject var themeManager: ThemeManager
    let message: Message
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onCreateThread: (UUID) -> Void
    let onCreateBranch: (UUID, String) -> Void
    let onSelectThread: (UUID?) -> Void

    @State private var showThreadOptions = false
    @State private var showBranchDialog = false
    @State private var branchName = ""

    private var hasChildren: Bool {
        !message.children.isEmpty
    }

    private var isThreaded: Bool {
        message.threadId != nil
    }

    private var threadColor: Color {
        guard let threadId = message.threadId,
              let thread = viewModel.currentConversation?.threads.first(where: { $0.id == threadId }),
              let colorString = thread.color else {
            return themeManager.palette.effectiveAccent
        }

        return Color(hex: colorString) ?? themeManager.palette.effectiveAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Thread indicator and controls
            if hasChildren || isThreaded {
                threadIndicator
            }

            // Message content
            MessageContentView(
                message: message,
                themeManager: themeManager,
                viewModel: viewModel
            )

            // Child messages (if expanded)
            if isExpanded && hasChildren {
                childMessagesView
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isThreaded ? threadColor.opacity(0.05) : Color.clear)
        )
        .overlay(
            // Thread line indicator
            isThreaded ? threadLineIndicator : nil
        )
        .contextMenu {
            threadContextMenu
        }
        .sheet(isPresented: $showBranchDialog) {
            branchCreationDialog
        }
    }

    private var threadIndicator: some View {
        HStack(spacing: Spacing.sm) {
            if hasChildren {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                }
                .buttonStyle(.plain)
            }

            if isThreaded {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(threadColor)
                        .frame(width: 8, height: 8)

                    if let threadId = message.threadId,
                       let thread = viewModel.currentConversation?.threads.first(where: { $0.id == threadId }) {
                        Text(thread.name ?? "Thread")
                            .font(Typography.micro)
                            .foregroundColor(threadColor)
                    }
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xs)
                .background(threadColor.opacity(0.1))
                .cornerRadius(Radius.xs)
            }

            Spacer()

            Button(action: { showThreadOptions = true }) {
                Image(systemName: "ellipsis")
                    .font(Typography.captionSmall)
                    .foregroundColor(.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md)
    }

    private var childMessagesView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(childMessages, id: \.id) { childMessage in
                HStack(alignment: .top, spacing: Spacing.md) {
                    // Thread line
                    Rectangle()
                        .fill(threadColor.opacity(0.3))
                        .frame(width: 2)
                        .padding(.leading, Spacing.md)

                    // Child message
                    ThreadedMessageView(
                        viewModel: viewModel,
                        message: childMessage,
                        isExpanded: false, // Child messages start collapsed
                        onToggleExpand: { /* Handle child expansion */ },
                        onCreateThread: onCreateThread,
                        onCreateBranch: onCreateBranch,
                        onSelectThread: onSelectThread
                    )
                    .padding(.leading, Spacing.lg)
                }
            }
        }
        .padding(.leading, Spacing.md)
    }

    private var threadLineIndicator: some View {
        Rectangle()
            .fill(threadColor.opacity(0.3))
            .frame(width: 3)
            .padding(.leading, Spacing.xs)
    }

    private var threadContextMenu: some View {
        Group {
            Button(action: { onCreateThread(message.id) }) {
                Label("Create Thread", systemImage: "bubble.left.and.bubble.right")
            }

            Button(action: { showBranchDialog = true }) {
                Label("Create Branch", systemImage: "arrow.branch")
            }

            if isThreaded {
                Button(action: { onSelectThread(nil) }) {
                    Label("Show All Messages", systemImage: "list.bullet")
                }
            }
        }
    }

    private var branchCreationDialog: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Create Branch")
                        .font(Typography.heading2)
                        .foregroundColor(.textPrimary)

                    Text("Create a new conversation branch from this message")
                        .font(Typography.body)
                        .foregroundColor(.textMuted)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Branch Name")
                        .font(Typography.captionSemibold)
                        .foregroundColor(.textPrimary)

                    TextField("e.g., Alternative approach", text: $branchName)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(Typography.body)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("New Branch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showBranchDialog = false
                        branchName = ""
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if !branchName.isEmpty {
                            onCreateBranch(message.id, branchName)
                            showBranchDialog = false
                            branchName = ""
                        }
                    }
                    .disabled(branchName.isEmpty)
                }
            }
        }
    }

    private var childMessages: [Message] {
        guard let conversation = viewModel.currentConversation else { return [] }

        return conversation.messages.filter { message.children.contains($0.id) }
            .sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Thread Navigation View

struct ThreadNavigationView: View {
    @ObservedObject var viewModel: ChatViewModel
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Threads & Branches")
                .font(Typography.heading2)
                .foregroundColor(.textPrimary)
                .padding(.horizontal)

            if let conversation = viewModel.currentConversation {
                // Threads section
                if !conversation.threads.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Threads")
                            .font(Typography.captionSemibold)
                            .foregroundColor(.textMuted)
                            .padding(.horizontal)

                        ForEach(conversation.threads) { thread in
                            ThreadRow(
                                thread: thread,
                                isActive: conversation.activeThreadId == thread.id,
                                onSelect: { viewModel.setActiveThread(thread.id) }
                            )
                        }
                    }
                }

                // Branches section
                if !conversation.branches.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Branches")
                            .font(Typography.captionSemibold)
                            .foregroundColor(.textMuted)
                            .padding(.horizontal)

                        ForEach(conversation.branches) { branch in
                            BranchRow(branch: branch)
                        }
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Thread Row

struct ThreadRow: View {
    let thread: MessageThread
    let isActive: Bool
    let onSelect: () -> Void
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.sm) {
                Circle()
                    .fill(Color(hex: thread.color ?? "#007AFF") ?? themeManager.palette.effectiveAccent)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.name ?? "Thread")
                        .font(Typography.captionSemibold)
                        .foregroundColor(.textPrimary)
                        .lineLimit(1)

                    Text("Created \(thread.createdAt, style: .relative) ago")
                        .font(Typography.micro)
                        .foregroundColor(.textMuted)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Typography.captionSmall)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isActive ? themeManager.palette.effectiveAccent.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Branch Row

struct BranchRow: View {
    let branch: MessageBranch
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "arrow.branch")
                .font(Typography.captionSmall)
                .foregroundColor(.textMuted)

            VStack(alignment: .leading, spacing: 2) {
                Text(branch.name)
                    .font(Typography.captionSemibold)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Text("Created \(branch.createdAt, style: .relative) ago")
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }
}

// MARK: - Message Content View

struct MessageContentView: View {
    let message: Message
    let themeManager: ThemeManager
    let viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Message header
            HStack {
                Text(message.role == .user ? "You" : "Assistant")
                    .font(Typography.captionSemibold)
                    .foregroundColor(message.role == .user ? .textPrimary : themeManager.palette.effectiveAccent)

                Spacer()

                Text(message.timestamp, style: .time)
                    .font(Typography.micro)
                    .foregroundColor(.textMuted)
            }

            // Message content
            MarkdownTextView(
                text: message.content,
                themeManager: themeManager,
                onCodeBlockTap: { _ in
                    // Handle code block tap
                }
            )
            .padding(.vertical, Spacing.xs)
        }
        .padding(Spacing.md)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
