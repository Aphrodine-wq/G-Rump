import SwiftUI

// MARK: - ContentView+ChatDetail
//
// Chat detail views, input section, mode buttons, error banners,
// tool call bars, and helper functions.
// Extracted from ContentView.swift for maintainability.

extension ContentView {

    // MARK: - Chat Content Area

    @ViewBuilder
    var chatContentArea: some View {
        if !viewModel.canUseAI {
            onboardingEmptyState
        } else if viewModel.currentConversation == nil {
            noSelectionEmptyState
        } else if viewModel.messages.isEmpty && viewModel.streamingContent.isEmpty {
            emptyStateView
        } else if state.showTimeline {
            AgentTimelineView(
                toolCalls: viewModel.activeToolCalls,
                messages: viewModel.filteredMessages,
                onSelectMessage: { _ in
                    state.showTimeline = false
                }
            )
        } else {
            MessageListView()
        }
    }

    // MARK: - Mode Buttons

    var modeButtonsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.md) {
                ForEach(AgentMode.allCases) { mode in
                    let isSelected = viewModel.agentMode == mode
                    Button {
                        withAnimation(.easeInOut(duration: Anim.quick)) {
                            viewModel.agentMode = mode
                            state.showModeToast(mode)
                        }
                    } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(mode.displayName)
                                .font(Typography.captionSmallSemibold)
                        }
                        .fixedSize()
                        .foregroundColor(isSelected ? mode.modeAccentColor : themeManager.palette.textSecondary)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.sm)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(isSelected ? mode.modeAccentColor.opacity(0.12) : themeManager.palette.bgInput)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .stroke(isSelected ? mode.modeAccentColor.opacity(0.5) : Color.clear, lineWidth: isSelected ? 2 : 0)
                        )
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .help(mode.description)
                    .accessibilityLabel("\(mode.displayName) mode")
                    .accessibilityHint(mode.description)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Spacing.huge)
        }
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Chat Input Section

    var chatInputSection: some View {
        let onSend: () -> Void = {
            if viewModel.agentMode == .spec {
                withAnimation(.easeInOut(duration: 0.25)) {
                    state.showSpecQuestionsModal = true
                }
            } else {
                viewModel.sendMessage()
            }
        }
        return VStack(spacing: 0) {
            // Undo send toast
            if viewModel.undoSendAvailable {
                HStack(spacing: Spacing.lg) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(Typography.bodySmall)
                        .foregroundColor(themeManager.palette.effectiveAccent)
                    Text("Message sent")
                        .font(Typography.captionSmallMedium)
                        .foregroundColor(themeManager.palette.textSecondary)
                    Spacer()
                    Button(action: { viewModel.undoSend() }) {
                        Text("Undo")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Undo send")
                }
                .padding(.horizontal, Spacing.huge)
                .padding(.vertical, Spacing.lg)
                .background(themeManager.palette.bgCard)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewModel.undoSendAvailable)
            }

            // Mode description toast (above input)
            if let toast = state.modeToastText {
                Text(toast)
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textMuted)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(themeManager.palette.bgElevated.opacity(0.9))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Spacing.huge)
                    .padding(.bottom, Spacing.sm)
            }

            // Inline Spec Context bar (replaces old modal sheet)
            if state.showSpecQuestionsModal {
                SpecContextBar(
                    isExpanded: $state.showSpecQuestionsModal,
                    userMessage: viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines),
                    onContinue: { context in
                        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            viewModel.userInput = viewModel.userInput.trimmingCharacters(in: .whitespacesAndNewlines)
                                + "\n\n[Spec context]\n" + trimmed
                        }
                        viewModel.sendMessage()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.showSpecQuestionsModal = false
                        }
                    },
                    onSkip: {
                        viewModel.sendMessage()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.showSpecQuestionsModal = false
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.showSpecQuestionsModal = false
                        }
                    }
                )
            }

            ChatInputView(
                text: $viewModel.userInput,
                isLoading: viewModel.isLoading,
                onSend: onSend,
                focus: $messageFieldFocused,
                onStop: { viewModel.stopGeneration() }
            )
            // Mode buttons below chat bar
            if viewModel.canUseAI {
                modeButtonsRow
            }
        }
    }

    // MARK: - Chat Detail Stack

    @ViewBuilder
    var chatDetailStack: some View {
        VStack(spacing: 0) {
            if !state.isZenMode {
                #if os(macOS)
                BuildToolbarView()
                #endif

                ChatTopBarView(
                    viewModel: viewModel,
                    lspService: state.lspService,
                    showSettings: $state.showSettings,
                    settingsInitialTab: $state.settingsInitialTab,
                    showTimeline: $state.showTimeline
                )

                Rectangle()
                    .fill(themeManager.palette.borderCrisp.opacity(0.7))
                    .frame(height: Border.thin)
            }

            // Thread/branch view mode toggle
            if let conv = viewModel.currentConversation,
               !conv.threads.isEmpty || !conv.branches.isEmpty {
                HStack(spacing: Spacing.md) {
                    Picker("View", selection: Binding(
                        get: { viewModel.conversationViewMode },
                        set: { viewModel.setConversationViewMode($0) }
                    )) {
                        Text("Linear").tag(Conversation.ConversationViewMode.linear)
                        Text("Threaded").tag(Conversation.ConversationViewMode.threaded)
                        Text("Branched").tag(Conversation.ConversationViewMode.branched)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)

                    Spacer()

                    Button(action: { state.showThreadNavigation.toggle() }) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.effectiveAccent)
                    }
                    .buttonStyle(.plain)
                    .help("Threads & Branches")
                    .accessibilityLabel("Toggle thread navigation")
                }
                .padding(.horizontal, Spacing.huge)
                .padding(.vertical, Spacing.sm)
                .background(themeManager.palette.bgElevated.opacity(0.5))
            }

            chatContentArea

            if !viewModel.activeToolCalls.isEmpty {
                activeToolCallsBar
            }

            if let err = viewModel.errorMessage {
                errorBanner(err)
            }

            Rectangle()
                .fill(themeManager.palette.borderCrisp.opacity(0.7))
                .frame(height: Border.thin)

            // Chat input: centered, constrained width, lifted from bottom
            HStack {
                Spacer(minLength: 0)
                chatInputSection
                    .frame(maxWidth: 760)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Spacing.huge)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxl)

            // Status bar at the bottom
            if state.layoutOptions.statusBarVisible && !state.isZenMode {
                StatusBarView(viewModel: viewModel)
            }
        }
    }

    var chatDetailBase: some View {
        chatDetailStack
            .background(themeManager.palette.bgDark)
    }

    var chatDetailView: some View {
        chatDetailBase
            .onChange(of: viewModel.errorMessage) { _, newValue in
                if newValue != nil { HapticHelper.error() }
            }
            .onChange(of: viewModel.activeToolCalls) { old, new in
                let oldCompleted = Set(old.filter { $0.status == .completed }.map(\.id))
                let newlyCompleted = new.filter { $0.status == .completed && !oldCompleted.contains($0.id) }
                if !newlyCompleted.isEmpty { HapticHelper.success() }
            }
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GRumpOpenSettings"))) { _ in
                state.showSettings = true
            }
            #endif
    }

    // MARK: - Error Banner

    func errorBanner(_ message: String) -> some View {
        HStack(spacing: Spacing.xl) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.accentOrange)
                .font(Typography.bodySmall)
            Text(message)
                .font(Typography.bodySmall)
                .foregroundColor(.textPrimary)
                .lineLimit(2)
            Spacer()

            Button(action: { viewModel.retryLastMessage() }) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "arrow.clockwise")
                        .font(Typography.captionSmallSemibold)
                    Text("Retry")
                        .font(Typography.captionSmallSemibold)
                }
                .foregroundColor(themeManager.palette.effectiveAccent)
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(themeManager.palette.effectiveAccent.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retry last message")

            Button(action: { viewModel.errorMessage = nil }) {
                Image(systemName: "xmark")
                    .font(Typography.captionSmallSemibold)
                    .foregroundColor(.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, Spacing.huge)
        .padding(.vertical, Spacing.xl)
        .background(Color.accentOrange.opacity(0.08))
        .overlay(Rectangle()
            .frame(height: 1)
            .foregroundColor(.accentOrange.opacity(0.25)), alignment: .bottom)
    }

    // MARK: - Active Tool Calls Bar

    var activeToolCallsBar: some View {
        let tools = viewModel.activeToolCalls
        let runningCount = tools.filter { $0.status == .running }.count
        let completedCount = tools.filter { $0.status == .completed }.count
        let failedCount = tools.filter { $0.status == .failed }.count

        return VStack(spacing: 0) {
            if tools.count > 1 {
                Button(action: { withAnimation(.easeInOut(duration: Anim.quick)) { state.toolCallsBarExpanded.toggle() } }) {
                    HStack(spacing: Spacing.lg) {
                        // Overall progress indicator
                        ZStack {
                            Circle()
                                .stroke(themeManager.palette.borderCrisp.opacity(0.3), lineWidth: 2)
                                .frame(width: 24, height: 24)

                            Circle()
                                .trim(from: 0, to: CGFloat(completedCount + failedCount) / CGFloat(tools.count))
                                .stroke(
                                    failedCount > 0 ? Color.red : themeManager.palette.effectiveAccent,
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                                )
                                .frame(width: 24, height: 24)
                                .rotationEffect(.degrees(-90))
                                .animation(.easeInOut(duration: 0.3), value: completedCount + failedCount)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(tools.count) tool\(tools.count == 1 ? "" : "s")")
                                .font(Typography.captionSmallSemibold)
                                .foregroundColor(.textPrimary)

                            HStack(spacing: Spacing.xs) {
                                if runningCount > 0 {
                                    Label("\(runningCount) running", systemImage: "arrow.triangle.2.circlepath")
                                        .font(Typography.micro)
                                        .foregroundColor(.orange)
                                }
                                if completedCount > 0 {
                                    Label("\(completedCount) done", systemImage: "checkmark.circle.fill")
                                        .font(Typography.micro)
                                        .foregroundColor(.accentGreen)
                                }
                                if failedCount > 0 {
                                    Label("\(failedCount) failed", systemImage: "xmark.circle.fill")
                                        .font(Typography.micro)
                                        .foregroundColor(.red)
                                }
                            }
                        }

                        Spacer()
                        Image(systemName: state.toolCallsBarExpanded ? "chevron.down" : "chevron.right")
                            .font(Typography.captionSmall)
                            .foregroundColor(.textMuted)
                    }
                    .padding(.horizontal, Spacing.huge)
                    .padding(.vertical, Spacing.md)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Toggle tool calls detail, \(tools.count) tools, \(runningCount) running, \(completedCount) done")
            }

            if state.toolCallsBarExpanded || tools.count <= 1 {
                ForEach(tools) { tool in
                    EnhancedToolCallRow(tool: tool, themeManager: themeManager)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        ))
                }
                .animation(.easeOut(duration: Anim.smooth), value: tools.map(\.id))
            }
        }
        .background(themeManager.palette.effectiveAccent.opacity(0.06))
        .overlay(Rectangle().frame(height: Border.thin).foregroundColor(themeManager.palette.borderCrisp), alignment: .top)
    }

    // MARK: - Tool Helpers

    func toolIcon(_ name: String) -> String {
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
        case "run_format": return "paintbrush"
        case "get_package_deps", "npm_install", "pip_install", "cargo_add": return "shippingbox"
        case "git_status", "git_add", "git_commit", "git_stash", "git_checkout", "git_push", "git_pull": return "vault"
        case "run_tests": return "checkmark.circle"
        case "get_system_info", "list_network_interfaces": return "info.circle"
        default: return "wrench"
        }
    }

    func toolDisplayName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func toolArgSummary(_ arguments: String) -> String {
        guard let data = arguments.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ""
        }
        if let path = args["path"] as? String { return (path as NSString).lastPathComponent }
        if let command = args["command"] as? String { return String(command.prefix(50)) }
        if let query = args["query"] as? String { return String(query.prefix(40)) }
        if let url = args["url"] as? String { return String(url.prefix(50)) }
        if let dir = args["directory"] as? String { return (dir as NSString).lastPathComponent }
        if let name = args["name_or_bundle_id"] as? String { return String(name.prefix(30)) }
        if let text = args["text"] as? String { return String(text.prefix(30)) + (text.count > 30 ? "…" : "") }
        if let paths = args["paths"] as? [String], let first = paths.first { return "\(paths.count) file(s), e.g. \((first as NSString).lastPathComponent)" }
        if let cmd = args["command"] as? String, !cmd.isEmpty { return String(cmd.prefix(40)) }
        return ""
    }
}
