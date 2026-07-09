import SwiftUI

/// App-level gate: shows onboarding (full-screen) until completed, then the main chat UI.
/// Receives ChatViewModel from GRumpApp so all scenes (WindowGroup + MenuBarExtra) share the same instance.
struct AppRootView: View {
    @EnvironmentObject var viewModel: ChatViewModel
    @AppStorage("HasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("LastSeenVersion") private var lastSeenVersion: String = ""
    @EnvironmentObject var frameLoop: FrameLoopService
    @Environment(\.scenePhase) private var scenePhase
    @State private var showWhatsNew = false
    #if os(macOS)
    @AppStorage("ShowWelcomeWindowOnLaunch") private var showWelcomeWindowOnLaunch = true
    @Environment(\.openWindow) private var openWindow
    #endif

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
        .environmentObject(viewModel)
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("GRumpWhatsNew"))) { _ in
            showWhatsNew = true
        }
        .onAppear {
            // Existing users should not be blocked by onboarding after upgrade.
            if !hasCompletedOnboarding && (viewModel.isAIProviderConfigured || !viewModel.conversations.isEmpty) {
                hasCompletedOnboarding = true
            }
            #if os(macOS)
            // No project open → offer the welcome window (unless opted out).
            if hasCompletedOnboarding && viewModel.workingDirectory.isEmpty && showWelcomeWindowOnLaunch {
                openWindow(id: "welcome")
            }
            #endif
            // FrameLoop is NOT started here — it auto-starts via markActive() when streaming begins.
            // Initialize PerformanceAdvisor early so thermal/memory monitoring is active
            _ = PerformanceAdvisor.shared
            // Defer heavy work off main thread to keep startup responsive
            Task.detached(priority: .background) {
                SkillsStorage.seedBundledSkillsIfNeeded()
                SoulStorage.seedDefaultSoulIfNeeded()
                // Brain subsystem: seed generic config + vault folder scaffold.
                BrainConfigStore.shared.seedIfNeeded()
                BrainPaths.ensureVaultScaffold()
                MindStorage.seedDefaultMindIfNeeded()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                frameLoop.stop()
            }
        }
        #if os(macOS)
        .onChange(of: hasCompletedOnboarding) { _, completed in
            // Fresh onboarding just finished with no project picked → welcome window.
            if completed && viewModel.workingDirectory.isEmpty {
                openWindow(id: "welcome")
            }
        }
        #endif
    }
}
