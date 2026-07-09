// MARK: - Settings Scene Root
//
// Content of the macOS `Settings{}` scene. Wires SettingsView to the shared
// ChatViewModel exactly like the old ModalManagerView sheet did; tab routing
// arrives through SettingsRouter instead of an initialTab parameter.

#if os(macOS)
import SwiftUI
import AppKit

struct SettingsSceneRoot: View {
    @EnvironmentObject var viewModel: ChatViewModel

    var body: some View {
        SettingsView(
            selectedModel: $viewModel.selectedModel,
            systemPrompt: $viewModel.systemPrompt,
            workingDirectory: $viewModel.workingDirectory,
            onSetWorkingDirectory: { viewModel.setWorkingDirectory($0) },
            initialTab: nil,
            onExportJSON: { viewModel.runExportJSONPanel() },
            onExportMarkdown: { viewModel.runExportMarkdownPanel(onlyCurrent: false) },
            onImport: { viewModel.runImportPanel() },
            onApplyPreset: { viewModel.applyPreset($0) },
            onClearPreset: { viewModel.clearAppliedPreset() },
            appliedPresetName: viewModel.appliedPresetName,
            systemRunHistory: viewModel.systemRunHistory,
            onRestartOnboarding: {
                UserDefaults.standard.set(false, forKey: "HasCompletedOnboarding")
                NSApplication.shared.keyWindow?.close()
            }
        )
    }
}
#endif
