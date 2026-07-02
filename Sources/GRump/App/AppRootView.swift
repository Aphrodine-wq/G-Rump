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
    }
}
