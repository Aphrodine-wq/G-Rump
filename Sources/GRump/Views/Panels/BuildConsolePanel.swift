// MARK: - Build Console Panel
//
// Right-dock panel for BuildService output. Log tab: streamed console with
// follow-tail and filtering, stderr in red. Issues tab: parsed build errors
// with Fix-with-G-Rump / Reveal / Open-in-Xcode actions, plus live LSP
// diagnostics when available. Auto-opened by BuildService on failure.

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct BuildConsolePanel: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var viewModel: ChatViewModel
    @ObservedObject private var buildService = BuildService.shared
    var lspService: LSPService?

    @AppStorage("BuildConsoleTab") private var selectedTabRaw: String = ConsoleTab.log.rawValue
    @State private var followTail = true
    @State private var filterText = ""
    @State private var expandedIssueIds: Set<UUID> = []

    private enum ConsoleTab: String, CaseIterable {
        case log
        case issues

        var label: String {
            switch self {
            case .log: return "Log"
            case .issues: return "Issues"
            }
        }
    }

    private var selectedTab: ConsoleTab {
        ConsoleTab(rawValue: selectedTabRaw) ?? .log
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: Border.thin)

            switch selectedTab {
            case .log:
                logTab
            case .issues:
                issuesTab
            }
        }
        .background(themeManager.palette.bgDark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.lg) {
                Picker("", selection: Binding(
                    get: { selectedTab },
                    set: { selectedTabRaw = $0.rawValue }
                )) {
                    ForEach(ConsoleTab.allCases, id: \.self) { tab in
                        if tab == .issues && !buildService.issues.isEmpty {
                            Text("\(tab.label) (\(buildService.issues.count))").tag(tab)
                        } else {
                            Text(tab.label).tag(tab)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)

                Spacer()

                if selectedTab == .log {
                    Button {
                        followTail.toggle()
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(followTail ? themeManager.palette.effectiveAccent : themeManager.palette.textMuted)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .help(followTail ? "Following output" : "Follow output")
                }

                Button {
                    sendToChat()
                } label: {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(themeManager.palette.textMuted)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(ScaleButtonStyle())
                .help("Send to chat")
                .disabled(buildService.consoleLines.isEmpty && buildService.issues.isEmpty)
            }

            if selectedTab == .log {
                TextField("Filter output", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(Typography.captionSmall)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.md)
                    .background(themeManager.palette.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
    }

    // MARK: - Log Tab

    private var filteredLines: [BuildService.ConsoleLine] {
        guard !filterText.isEmpty else { return buildService.consoleLines }
        return buildService.consoleLines.filter {
            $0.text.localizedCaseInsensitiveContains(filterText)
        }
    }

    private var logTab: some View {
        Group {
            if buildService.consoleLines.isEmpty {
                emptyState(icon: "hammer.circle", text: "No build output yet.\nRun a build with ⌘R.")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(filteredLines) { line in
                                Text(line.text)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(line.isStderr ? .red : themeManager.palette.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                        .padding(Spacing.lg)
                        .textSelection(.enabled)
                    }
                    .onChange(of: buildService.consoleLines.count) { _, _ in
                        if followTail, let last = filteredLines.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Issues Tab

    private var issuesTab: some View {
        Group {
            if buildService.issues.isEmpty && (lspService?.allDiagnostics.isEmpty ?? true) {
                emptyState(icon: "checkmark.circle", text: "No issues.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(buildService.issues) { issue in
                            issueRow(issue)
                        }

                        if let lspService, !lspService.allDiagnostics.isEmpty {
                            Text("Live Diagnostics")
                                .font(Typography.captionSmallSemibold)
                                .foregroundColor(themeManager.palette.textMuted)
                                .textCase(.uppercase)
                                .tracking(0.4)
                                .padding(.top, Spacing.xl)

                            ForEach(lspService.allDiagnostics) { diagnostic in
                                diagnosticRow(diagnostic)
                            }
                        }
                    }
                    .padding(Spacing.lg)
                }
            }
        }
    }

    private func issueRow(_ issue: BuildError) -> some View {
        let isExpanded = expandedIssueIds.contains(issue.id)
        return VStack(alignment: .leading, spacing: Spacing.md) {
            Button {
                withAnimation(.easeInOut(duration: Anim.quick)) {
                    if isExpanded {
                        expandedIssueIds.remove(issue.id)
                    } else {
                        expandedIssueIds.insert(issue.id)
                    }
                }
            } label: {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: issue.severity.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(issue.severity.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.message)
                            .font(Typography.captionSmallMedium)
                            .foregroundColor(themeManager.palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                        Text("\(issue.shortPath):\(issue.line):\(issue.column)")
                            .font(Typography.codeMicro)
                            .foregroundColor(themeManager.palette.textMuted)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(themeManager.palette.textMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(spacing: Spacing.md) {
                    issueAction("Fix with G-Rump", icon: "wand.and.stars") {
                        fixWithGRump(issue)
                    }
                    issueAction("Reveal in Navigator", icon: "sidebar.left") {
                        NotificationCenter.default.post(
                            name: .init("GRumpRevealFile"), object: nil,
                            userInfo: ["path": issue.file]
                        )
                    }
                    #if os(macOS)
                    issueAction("Open in Xcode", icon: "arrow.up.forward.app") {
                        openInXcode(issue)
                    }
                    #endif
                }
                .padding(.leading, Spacing.xxl)
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(themeManager.palette.bgElevated.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(issue.severity == .error ? issue.severity.color.opacity(0.25) : themeManager.palette.borderSubtle,
                        lineWidth: Border.hairline)
        )
    }

    private func diagnosticRow(_ diagnostic: LSPDiagnostic) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: diagnostic.severity == .error ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(diagnostic.severity == .error ? .red : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(diagnostic.message)
                    .font(Typography.captionSmall)
                    .foregroundColor(themeManager.palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\((diagnostic.file as NSString).lastPathComponent):\(diagnostic.line)")
                    .font(Typography.codeMicro)
                    .foregroundColor(themeManager.palette.textMuted)
            }
            Spacer()
        }
        .padding(Spacing.md)
    }

    private func issueAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title)
                    .font(Typography.micro)
            }
            .foregroundColor(themeManager.palette.effectiveAccent)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(themeManager.palette.effectiveAccent.opacity(0.12))
            .clipShape(Capsule())
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Actions

    /// Same prompt shape as BuildErrorsView.fixError — the agent reads the file
    /// and applies the minimal fix.
    private func fixWithGRump(_ issue: BuildError) {
        let prompt = """
        Fix this build error in \(issue.file) at line \(issue.line):

        Error: \(issue.message)
        \(issue.fixitSuggestion.map { "Suggested fix: \($0)" } ?? "")

        Read the file, apply the minimal fix, and verify it compiles.
        """
        viewModel.userInput = prompt
        viewModel.sendMessage()
    }

    #if os(macOS)
    private func openInXcode(_ issue: BuildError) {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["xed", "--line", "\(issue.line)", issue.file]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            try? process.run()
        }
    }
    #endif

    private func sendToChat() {
        var message = ""
        let tail = buildService.consoleLines.suffix(100).map(\.text).joined(separator: "\n")
        if !tail.isEmpty {
            message += "Here's my latest build output (last \(min(buildService.consoleLines.count, 100)) lines):\n```\n\(tail)\n```\n"
        }
        if !buildService.issues.isEmpty {
            let issueList = buildService.issues
                .map { "- \($0.severity.rawValue): \($0.file):\($0.line) — \($0.message)" }
                .joined(separator: "\n")
            message += "\nParsed issues:\n\(issueList)\n"
        }
        message += "\nPlease diagnose and fix what's broken."
        viewModel.userInput = message
        viewModel.sendMessage()
    }

    // MARK: - Empty State

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(themeManager.palette.textMuted.opacity(0.6))
            Text(text)
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
