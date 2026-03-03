import SwiftUI
#if !GRUMP_SPM_BUILD
import SwiftData
#endif

@main
struct GRumpApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var showSplash = true
    @State private var appLoaded = false
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var frameLoop = FrameLoopService()
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var ambientService = AmbientCodeAwarenessService()
    @StateObject private var ambientMonitor = AmbientMonitor.shared
    @StateObject private var proactiveEngine = ProactiveEngine()
    #if os(macOS)
    @AppStorage("ShowMenuBarExtra") private var showMenuBarExtra = false
    @AppStorage("EnableMCPServer") private var enableMCPServer = false
    @StateObject private var sparkleService = SparkleUpdateService()
    @StateObject private var globalHotkey = GlobalHotkeyService.shared
    #endif

    #if !GRUMP_SPM_BUILD
    private let modelContainer: ModelContainer
    #endif

    @State private var swiftDataError: String?

    init() {
        #if !GRUMP_SPM_BUILD
        do {
            modelContainer = try SwiftDataConfiguration.makeContainer()
        } catch {
            // Graceful fallback — app still launches; persistence degrades to JSON.
            // The error is surfaced in-app rather than crashing.
            modelContainer = try! ModelContainer(for: Schema([]), configurations: [])
            _swiftDataError = State(initialValue: "[SwiftData] \(error.localizedDescription)")
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if appLoaded {
                    AppRootView()
                }

                if showSplash {
                    SplashScreenView {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSplash = false
                        }
                        appLoaded = true
                    }
                    .transition(.opacity)
                }
            }
            .task {
                // Request notification authorization (async, non-blocking)
                GRumpNotificationService.shared.requestAuthorization()
            }
            .task {
                // Failsafe: if splash is still showing after 4s, force-dismiss
                try? await Task.sleep(for: .seconds(4))
                if showSplash {
                    withAnimation(.easeOut(duration: 0.2)) { showSplash = false }
                    appLoaded = true
                }
            }
            .environmentObject(themeManager)
            .environmentObject(frameLoop)
            .environmentObject(viewModel)
            .environmentObject(ambientService)
            .environmentObject(ambientMonitor)
            .environmentObject(proactiveEngine)
            #if !GRUMP_SPM_BUILD
            .modelContainer(modelContainer)
            #endif
            .preferredColorScheme(themeManager.colorScheme)
            .onChange(of: showSplash) { _, newValue in
                if !newValue {
                    // Run blocking work only after splash is fully dismissed
                    #if !GRUMP_SPM_BUILD
                    Task { @MainActor in
                        await SwiftDataMigrator.migrateIfNeeded(context: modelContainer.mainContext)
                    }
                    #endif
                    // Start connection monitoring (cross-platform)
                    ConnectionMonitor.shared.start()

                    #if os(macOS)
                    Task.detached(priority: .utility) {
                        await MainActor.run {
                            GRumpServicesProvider.shared.register()
                        }
                    }
                    // Listen for update check requests from Settings
                    NotificationCenter.default.addObserver(forName: .init("GRumpCheckForUpdates"), object: nil, queue: .main) { [weak sparkleService] _ in
                        sparkleService?.checkForUpdates()
                    }
                    // Start ambient monitoring and global hotkey
                    ambientMonitor.startMonitoring()
                    globalHotkey.onActivate = { [weak viewModel] in
                        guard let vm = viewModel else { return }
                        QuickChatWindowController.shared.toggle(viewModel: vm, themeManager: themeManager)
                    }
                    globalHotkey.start()
                    // Bootstrap proactive engine with dependencies
                    proactiveEngine.bootstrap(
                        activityStore: viewModel.activityStore,
                        ambientMonitor: ambientMonitor
                    )
                    // Start MCP server if enabled
                    if enableMCPServer {
                        Task { try? await MCPServerHost.shared.start() }
                    }
                    #endif
                }
            }
        #if os(macOS)
        .frame(minWidth: 800, minHeight: 550)
        .onChange(of: enableMCPServer) { _, enabled in
            Task {
                if enabled {
                    try? await MCPServerHost.shared.start()
                } else {
                    await MCPServerHost.shared.stop()
                }
            }
        }
        #endif
            .onOpenURL { url in
                #if os(macOS)
                GRumpURLSchemeHandler.handle(url)
                #endif
            }
            #if os(macOS)
            .handlesExternalEvents(preferring: Set(["grump"]), allowing: Set(["grump"]))
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 700)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .windowResizability(.contentSize)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(name: .init("GRumpNewChat"), object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .init("GRumpToggleSidebar"), object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button("Toggle Activity Bar") {
                    NotificationCenter.default.post(name: .init("GRumpToggleActivityBar"), object: nil)
                }
                .keyboardShortcut("a", modifiers: [.command, .option])

                Button("Toggle Status Bar") {
                    NotificationCenter.default.post(name: .init("GRumpToggleStatusBar"), object: nil)
                }

                Divider()

                Button("Toggle Zen Mode") {
                    NotificationCenter.default.post(name: .init("GRumpToggleZenMode"), object: nil)
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Divider()

                Button("Customize Layout...") {
                    NotificationCenter.default.post(name: .init("GRumpShowLayoutCustomizer"), object: nil)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Reset Layout to Defaults") {
                    NotificationCenter.default.post(name: .init("GRumpResetLayout"), object: nil)
                }
            }
            #if os(macOS)
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(sparkle: sparkleService)
            }
            #endif
            CommandGroup(replacing: .help) {
                Button("What's New") {
                    NotificationCenter.default.post(name: .init("GRumpWhatsNew"), object: nil)
                }
                Divider()
                Menu("Keyboard Shortcuts") {
                    Text("New Chat — ⌘N")
                    Text("Settings — ⌘,")
                    Text("Stop Generation — ⌘.")
                    Text("Focus Input — ⌘L")
                    Text("Toggle Sidebar — ⌘\\")
                    Text("Toggle Activity Bar — ⌘⌥A")
                    Text("Zen Mode — ⌘⇧Z")
                    Text("Customize Layout — ⌘⇧L")
                    Text("Export Markdown — ⌘E")
                    Text("Exit Zen Mode — Escape")
                }
                Divider()
                Button("G-Rump Help") {
                    if let url = URL(string: "https://www.g-rump.com") {
                        #if os(macOS)
                        NSWorkspace.shared.open(url)
                        #else
                        UIApplication.shared.open(url)
                        #endif
                    }
                }
            }
        }
        #if os(macOS)
        MenuBarExtra("G-Rump", systemImage: "brain.head.profile", isInserted: $showMenuBarExtra) {
            MenuBarAgent()
                .environmentObject(viewModel)
                .environmentObject(themeManager)
        }
        #endif
    }
}
