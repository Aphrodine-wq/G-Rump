import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Settings View
//
// SettingsTab enum & SettingsKeys are in SettingsTab.swift.
// Tab content sections are in extension files:
// - Settings+ProviderViews.swift   (providers, model rows, CoreML catalog)
// - Settings+TabViews.swift        (all other tab content sections)

struct SettingsView: View {
    @Binding var apiKey: String
    @Binding var selectedModel: EnhancedAIModel
    @Binding var systemPrompt: String
    @Binding var workingDirectory: String
    var onSetWorkingDirectory: (String) -> Void
    /// When set, the sheet will select this tab when it appears (e.g. open to Model from chat toolbar).
    var initialTab: SettingsTab?
    /// Export/import actions (macOS). When nil, Data section shows unavailable message.
    var onExportJSON: (() -> Void)?
    var onExportMarkdown: (() -> Void)?
    var onImport: (() -> Void)?
    /// Workflow presets: apply and clear.
    var onApplyPreset: ((WorkflowPreset) -> Void)?
    var onClearPreset: (() -> Void)?
    var appliedPresetName: String?
    /// Commands run/denied via system_run this session (Security tab).
    var systemRunHistory: [SystemRunHistoryEntry] = []
    /// When set, About section shows "Restart onboarding" button. Called when user taps it.
    var onRestartOnboarding: (() -> Void)?
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) var dismiss
    @State var selectedTab: SettingsTab = .account
    @AppStorage("BackendURL") var backendURL: String = ""
    @State var appAPIKeyInput: String = KeychainStorage.get(account: "AppAPIKey") ?? ""
    @State var appAPIKeyVisible = false
    @AppStorage(SettingsKeys.maxAgentSteps) var maxAgentStepsStorage: Int = 200
    @AppStorage(SettingsKeys.compactToolResults) var compactToolResults: Bool = false
    @AppStorage(SettingsKeys.allowSystemNotifications) var allowSystemNotifications: Bool = true
    @AppStorage(SettingsKeys.notificationSoundEnabled) var notificationSoundEnabled: Bool = true
    @AppStorage(SettingsKeys.checkUpdatesOnLaunch) var checkUpdatesOnLaunch: Bool = false
    @AppStorage(SettingsKeys.showTokenCount) var showTokenCount: Bool = false
    @AppStorage(SettingsKeys.projectMemoryEnabled) var projectMemoryEnabled: Bool = true
    @AppStorage(SettingsKeys.semanticMemoryEnabled) var semanticMemoryEnabled: Bool = true
    @AppStorage(SettingsKeys.returnToSend) var returnToSendSetting: Bool = false
    @AppStorage("LineSpacing") var lineSpacingSetting: String = "normal"
    @AppStorage("CodeFont") var codeFontSetting: String = "sf-mono"
    #if os(iOS)
    @AppStorage(SettingsKeys.hapticFeedbackEnabled) var hapticFeedbackEnabled: Bool = true
    #endif
    #if os(macOS)
    @AppStorage(SettingsKeys.showMenuBarExtra) var showMenuBarExtra: Bool = false
    @State var execConfig: ExecApprovalsConfig = .default
    #endif
    @State var expandedCategories: Set<String> = ["AI", "Workspace", "General"]

    // Provider state
    @State var selectedProvider: AIProvider = .anthropic
    @State var providerAPIKeys: [String: String] = [:]
    @State var providerBaseURLs: [String: String] = [:]
    @State var providerKeyValidation: [String: KeyValidationState] = [:]

    // Tools state
    @State var toolsDenylist: Set<String> = []
    @State var selectedToolCategory: ToolDefinitions.ToolCategory = .file

    // Memory state
    @State var memoryEntryCount: Int = 0
    @State var semanticMemoryCount: Int = 0
    @State var memoryCountLoading: Bool = false

    // MCP state
    @State var mcpServers: [MCPServerConfig] = []
    @State var mcpEditServer: MCPServerConfig?
    @State var mcpShowAddSheet = false
    @State var mcpTestingServerIDs: Set<String> = []
    @State var mcpServerTestMessages: [String: String] = [:]

    // Skills state
    @State var settingsSkills: [Skill] = []
    @State var settingsSkillEnabledIds: Set<String> = []
    @State var settingsShowAddSkillSheet = false
    @State var settingsSkillToEdit: Skill?

    // Presets state
    @State var workflowPresets: [WorkflowPreset] = []

    var body: some View {
        Group {
        #if os(macOS)
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(SettingsTab.categories, id: \.label) { category in
                    if category.tabs.count == 1 {
                        Label(category.label, systemImage: category.icon)
                            .tag(category.tabs[0])
                    } else {
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedCategories.contains(category.label) },
                                set: { newVal in
                                    if newVal { expandedCategories.insert(category.label) } else { expandedCategories.remove(category.label) }
                                }
                            )
                        ) {
                            ForEach(category.tabs, id: \.self) { tab in
                                Label(tab.label, systemImage: tab.icon)
                                    .tag(tab)
                            }
                        } label: {
                            Label(category.label, systemImage: category.icon)
                                .font(Typography.captionSemibold)
                                .foregroundColor(themeManager.palette.textSecondary)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(themeManager.palette.bgDark)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        } detail: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    tabContent(selectedTab)
                        .padding(Spacing.huge)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(themeManager.palette.bgDark)
            .navigationTitle(selectedTab.label)
        }
        #else
        NavigationStack {
            List {
                ForEach(SettingsTab.categories, id: \.label) { category in
                    if category.tabs.count == 1 {
                        NavigationLink {
                            ScrollView {
                                tabContent(category.tabs[0])
                                    .padding(Spacing.huge)
                            }
                            .navigationTitle(category.tabs[0].label)
                        } label: {
                            Label(category.label, systemImage: category.icon)
                        }
                    } else {
                        Section(category.label) {
                            ForEach(category.tabs, id: \.self) { tab in
                                NavigationLink {
                                    ScrollView {
                                        tabContent(tab)
                                            .padding(Spacing.huge)
                                    }
                                    .navigationTitle(tab.label)
                                } label: {
                                    Label(tab.label, systemImage: tab.icon)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
        #endif
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(themeManager.palette.textMuted)
                    .frame(width: 28, height: 28)
                    .background(themeManager.palette.bgElevated)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(themeManager.palette.borderCrisp.opacity(0.4), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Close")
            .padding(.top, 24)
            .padding(.trailing, 24)
        }
        #if os(macOS)
        .frame(minWidth: 860, minHeight: 720)
        #endif
        .onAppear {
            if let tab = initialTab {
                selectedTab = tab
            }
        }
    }

    @MainActor
    func testMCPServer(_ server: MCPServerConfig) async {
        mcpTestingServerIDs.insert(server.id)
        defer { mcpTestingServerIDs.remove(server.id) }

        let mgr = MCPConnectionManager.shared
        let tools = await mgr.fetchTools(config: server)
        if tools.isEmpty {
            mcpServerTestMessages[server.id] = "No tools detected. Check command path, env vars/API keys, then test again."
        } else {
            // Try to get resource and prompt counts too
            var parts = ["OK: \(tools.count) tool\(tools.count == 1 ? "" : "s")"]
            if let resources = try? await mgr.listResources(config: server), !resources.isEmpty {
                parts.append("\(resources.count) resource\(resources.count == 1 ? "" : "s")")
            }
            if let prompts = try? await mgr.listPrompts(config: server), !prompts.isEmpty {
                parts.append("\(prompts.count) prompt\(prompts.count == 1 ? "" : "s")")
            }
            mcpServerTestMessages[server.id] = parts.joined(separator: ", ") + "."
        }
    }

    func mcpCredentialHint(for serverID: String) -> String? {
        switch serverID {
        case "github":
            return "Requires a GitHub token in your environment (for example GITHUB_TOKEN)."
        case "brave-search":
            return "Requires a Brave Search API key in your environment."
        case "slack":
            return "Requires Slack app credentials and token in your environment."
        case "postgres":
            return "Requires Postgres connection info (host/database/user/password or URL)."
        case "gdrive":
            return "Requires Google OAuth credentials/service account setup."
        case "sentry":
            return "Requires Sentry auth token and org/project configuration."
        case "claude-code":
            return "Requires the Claude CLI installed (npm install -g @anthropic-ai/claude-code). Uses your Anthropic API key."
        case "manus":
            return "Requires Manus agent running locally on port 8765. Visit manus.im for setup."
        case "linear":
            return "Requires a Linear API key in your environment (LINEAR_API_KEY)."
        case "notion":
            return "Requires a Notion integration token (NOTION_API_KEY). Create one at notion.so/my-integrations."
        case "jira":
            return "Requires Jira credentials: JIRA_URL, JIRA_EMAIL, and JIRA_API_TOKEN."
        case "figma":
            return "Requires a Figma personal access token (FIGMA_ACCESS_TOKEN)."
        case "vercel":
            return "Requires a Vercel access token (VERCEL_TOKEN). Create one in Vercel dashboard > Settings > Tokens."
        case "supabase":
            return "Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY from your Supabase project settings."
        case "cloudflare":
            return "Requires a Cloudflare API token (CLOUDFLARE_API_TOKEN) with appropriate permissions."
        case "todoist":
            return "Requires a Todoist API token (TODOIST_API_TOKEN) from Settings > Integrations > Developer."
        case "turso":
            return "Requires TURSO_DATABASE_URL and TURSO_AUTH_TOKEN from your Turso dashboard."
        default:
            return nil
        }
    }

    @ViewBuilder
    func tabContent(_ tab: SettingsTab) -> some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            switch tab {
            case .account:
                accountSection
            case .appearance:
                appearanceSection
            case .providers:
                providersSection
            case .presets:
                presetsSection
            case .project:
                projectSection
            case .behavior:
                behaviorSection
            case .streaming:
                streamingSection
            case .advanced:
                advancedSection
            case .notifications:
                notificationsSection
            case .shortcuts:
                shortcutsSection
            case .updates:
                updatesSection
            case .tools:
                toolsSection
            case .mcp:
                mcpSection
            case .skills:
                skillsSettingsSection
            case .soul:
                SoulSettingsView(workingDirectory: workingDirectory)
            case .brain:
                BrainSettingsView(workingDirectory: workingDirectory)
            case .data:
                dataSection
            case .memory:
                memorySection
            case .privacy:
                PrivacyDashboardView()
            #if os(macOS)
            case .security:
                securitySection
            #endif
            case .about:
                aboutSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Account (backend proxy)
    // Per-provider API keys live in the Providers tab, not here.

    var accountSection: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Backend", icon: "server.rack", accent: themeManager.accentColor)
                    Text("Optional: route requests through a slim backend proxy. Leave blank to call your AI provider directly with your API key.")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    TextField("https://your-backend.example.com", text: $backendURL)
                        .font(Typography.bodySmall)
                        .fontDesign(.monospaced)
                        .textFieldStyle(.plain)
                        .padding(Spacing.xl)
                        .background(themeManager.palette.bgInput)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))

                    Text("Backend API key (APP_API_KEY)")
                        .font(Typography.captionSmall)
                        .foregroundColor(.textMuted)
                    HStack(spacing: Spacing.xl) {
                        if appAPIKeyVisible {
                            TextField("Optional — leave blank in local dev", text: $appAPIKeyInput)
                                .font(Typography.bodySmall)
                                .fontDesign(.monospaced)
                        } else {
                            SecureField("Optional — leave blank in local dev", text: $appAPIKeyInput)
                                .font(Typography.bodySmall)
                                .fontDesign(.monospaced)
                        }
                        Button(action: { appAPIKeyVisible.toggle() }) {
                            Image(systemName: appAPIKeyVisible ? "eye.slash" : "eye")
                                .foregroundColor(.textMuted)
                                .font(Typography.bodySmall)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Spacing.xl)
                    .background(themeManager.palette.bgInput)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                        .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
                    .onChange(of: appAPIKeyInput) { _, newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            KeychainStorage.delete(account: "AppAPIKey")
                        } else {
                            KeychainStorage.set(account: "AppAPIKey", value: trimmed)
                        }
                    }
                }
            }

        }
    }

    // MARK: - Appearance (Theme + Accent)

    var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Spacing.huge) {
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Theme", icon: "paintbrush.fill", accent: themeManager.accentColor)
                    VStack(spacing: Spacing.md) {
                        themeRow(.system)
                        Text("Light")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Spacing.sm)
                        ForEach(AppTheme.lightThemes, id: \.self) { appTheme in
                            themeRow(appTheme)
                        }
                        Text("Dark")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Spacing.lg)
                        ForEach(AppTheme.darkThemes, id: \.self) { appTheme in
                            themeRow(appTheme)
                        }
                        Text("Fun")
                            .font(Typography.captionSmallSemibold)
                            .foregroundColor(.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Spacing.lg)
                        ForEach(AppTheme.funThemes, id: \.self) { appTheme in
                            themeRow(appTheme)
                        }
                    }
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Accent color", icon: "paintpalette.fill", accent: themeManager.accentColor)
                    let columns = [GridItem(.adaptive(minimum: 100))]
                    LazyVGrid(columns: columns, spacing: Spacing.md) {
                        ForEach(AccentColorOption.allCases) { option in
                            accentChip(option)
                        }
                    }
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Display", icon: "rectangle.compress.vertical", accent: themeManager.accentColor)
                    Text("Compact uses slightly tighter spacing.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    Picker("Density", selection: $themeManager.density) {
                        ForEach(AppDensity.allCases) { density in
                            Text(density.displayName).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Text size", icon: "textformat.size", accent: themeManager.accentColor)
                    Text("Scale for message and code text. Medium is the default.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    Picker("Content size", selection: $themeManager.contentSize) {
                        ForEach(AppContentSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Line spacing", icon: "arrow.up.and.down.text.horizontal", accent: themeManager.accentColor)
                    Text("Adjust vertical spacing between lines in messages.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    Picker("Line spacing", selection: $lineSpacingSetting) {
                        Text("Tight").tag("tight")
                        Text("Normal").tag("normal")
                        Text("Relaxed").tag("relaxed")
                    }
                    .pickerStyle(.segmented)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    sectionTitle("Code font", icon: "chevron.left.forwardslash.chevron.right", accent: themeManager.accentColor)
                    Text("Font used for code blocks and inline code.")
                        .font(Typography.bodySmall)
                        .foregroundColor(.textMuted)
                    Picker("Code font", selection: $codeFontSetting) {
                        Text("SF Mono").tag("sf-mono")
                        Text("Menlo").tag("menlo")
                        Text("Fira Code").tag("fira-code")
                        Text("JetBrains Mono").tag("jetbrains-mono")
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(Spacing.huge)
        .background(themeManager.palette.bgCard)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)
            .stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
    }

    func sectionTitle(_ title: String, icon: String, accent: AccentColorOption? = nil) -> some View {
        let iconColor = accent != nil ? themeManager.palette.effectiveAccent : Color.brandPurple
        return HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(Typography.captionSemibold)
                .foregroundColor(iconColor)
            Text(title)
                .font(Typography.captionSemibold)
                .foregroundColor(.textSecondary)
                .textCase(.uppercase)
                .tracking(0.4)
        }
    }

    func themeRow(_ appTheme: AppTheme) -> some View {
        let accent = themeManager.palette.effectiveAccent
        return Button(action: { themeManager.theme = appTheme }) {
            HStack(spacing: Spacing.xxl) {
                Image(systemName: appTheme.icon)
                    .font(Typography.bodySmall)
                    .foregroundColor(themeManager.theme == appTheme ? accent : .textMuted)
                    .frame(width: 24, alignment: .center)
                Text(appTheme.displayName)
                    .font(Typography.bodySmallMedium)
                    .foregroundColor(.textPrimary)
                Spacer()
                if themeManager.theme == appTheme {
                    Image(systemName: "checkmark")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(.accentGreen)
                }
            }
            .padding(Spacing.xl)
            .background(themeManager.theme == appTheme ? accent.opacity(0.10) : themeManager.palette.bgInput)
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(themeManager.theme == appTheme ? accent.opacity(0.4) : themeManager.palette.borderCrisp, lineWidth: Border.thin))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: Anim.quick), value: themeManager.theme)
    }

    func accentChip(_ option: AccentColorOption) -> some View {
        Button(action: { themeManager.accentColor = option }) {
            ZStack {
                Circle()
                    .fill(option.color)
                    .frame(width: 32, height: 32)
                if themeManager.accentColor == option {
                    Image(systemName: "checkmark")
                        .font(Typography.bodySemibold)
                        .foregroundColor(.white)
                }
            }
            .overlay(
                Circle()
                    .stroke(themeManager.accentColor == option ? Color.primary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: Anim.quick), value: themeManager.accentColor)
    }

    func formatContextWindow(_ tokens: Int) -> String {
        if tokens >= 1_000_000 { return "1M ctx" }
        return "\(tokens / 1000)K ctx"
    }

    #if os(macOS)
    func runDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your project's root directory"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workingDirectory = url.path
        onSetWorkingDirectory(url.path)
    }
    #endif
}
