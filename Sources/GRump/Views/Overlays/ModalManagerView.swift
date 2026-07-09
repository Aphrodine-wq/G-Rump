import SwiftUI

// MARK: - Modal Manager View
struct ModalManagerView<Content: View>: View {
    @Binding var showProfile: Bool
    @Binding var showThreadNavigation: Bool
    @Binding var showSettings: Bool
    @Binding var settingsInitialTab: SettingsTab?
    @Binding var messageFieldFocused: Bool
    @FocusState var focusState: Bool

    @ObservedObject var viewModel: ChatViewModel
    let content: Content

    var body: some View {
        content
            .sheet(isPresented: $showProfile, onDismiss: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { messageFieldFocused = true }
            }) {
                profileSheetContent
            }
            .sheet(isPresented: $showThreadNavigation, onDismiss: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { messageFieldFocused = true }
            }) {
                ThreadNavigationView(viewModel: viewModel)
                    .frame(minWidth: 320, minHeight: 400)
            }
            // macOS settings live in the Settings{} scene; ContentView bridges
            // showSettings → openSettings. Only iOS still presents a sheet.
            #if os(iOS)
            .sheet(isPresented: $showSettings, onDismiss: {
                settingsInitialTab = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { messageFieldFocused = true }
            }) {
                settingsSheetContent
            }
            #endif
    }

    // MARK: - Sheet Contents

    private var profileSheetContent: some View {
        ProfileView(
            modelName: viewModel.selectedModel.displayName,
            workingDirectory: viewModel.workingDirectory,
            appliedPresetName: viewModel.appliedPresetName,
            totalConversations: viewModel.conversations.count,
            totalMessages: viewModel.conversations.reduce(0) { $0 + $1.messages.count },
            onOpenSettings: {
                showProfile = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showSettings = true }
            }
        )
    }

    #if os(iOS)
    private var settingsSheetContent: some View {
        SettingsView(
            selectedModel: $viewModel.selectedModel,
            systemPrompt: $viewModel.systemPrompt,
            workingDirectory: $viewModel.workingDirectory,
            onSetWorkingDirectory: { viewModel.setWorkingDirectory($0) },
            initialTab: settingsInitialTab,
            onApplyPreset: { viewModel.applyPreset($0) },
            onClearPreset: { viewModel.clearAppliedPreset() },
            appliedPresetName: viewModel.appliedPresetName,
            systemRunHistory: viewModel.systemRunHistory,
            onRestartOnboarding: {
                showSettings = false
                UserDefaults.standard.set(false, forKey: "HasCompletedOnboarding")
            }
        )
    }
    #endif
}
