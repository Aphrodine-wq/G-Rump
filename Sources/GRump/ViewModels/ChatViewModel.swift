// ╔══════════════════════════════════════════════════════════════╗
// ║  ChatViewModel.swift                                        ║
// ║  Core view model — properties, init, and provider bridge    ║
// ║                                                              ║
// ║  Extensions:  +AgentLoop, +Streaming, +ToolExecution,       ║
// ║  +Messages, +Memory, +Persistence, +PromptBuilding,         ║
// ║  +Helpers, +UIState, +ExportImport,                         ║
// ║  +AgentPostRun, +ThinkingParser                             ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation
import Combine
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import CoreGraphics
import ImageIO
import ApplicationServices
import ScreenCaptureKit
#else
import UIKit
#endif
import UserNotifications

@MainActor
class ChatViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var currentConversation: Conversation?
    @Published var userInput: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var streamingContent: String = ""
    @Published var importExportMessage: String?

    // MARK: - Claude-Style Thinking State
    /// Reasoning trace captured from `<thinking>` blocks during streaming.
    @Published var thinkingContent: String = ""
    /// True while the model is in its "thinking" phase (before visible output begins).
    @Published var isThinking: Bool = false
    @Published var activeToolCalls: [ToolCallStatus] = []
    /// True while the autonomous daemon is driving this view model. When set, every
    /// mutating tool additionally requires an explicit user approval (approve-every-write).
    var isDaemonRunActive: Bool = false
    @Published var workingDirectory: String = "" {
        didSet { activityStore.setPersistencePath(workingDirectory.isEmpty ? nil : "\(workingDirectory)/.grump/activity.json") }
    }
    /// When non-nil, the agent is in a multi-step run; UI can show "Step currentAgentStep of currentAgentStepMax".
    @Published var currentAgentStep: Int?
    @Published var currentAgentStepMax: Int?
    /// When true, the agent was paused (not stopped). User can resume.
    @Published var isPaused: Bool = false

    // MARK: - LSP Bridge (set by ContentView)
    var lspDiagnostics: [String: [LSPDiagnostic]] = [:]
    var lspStatusMessage: String = "Not started"

    /// Real-time streaming performance metrics (tokens/sec, elapsed, phase).
    let streamMetrics = StreamMetrics()

    /// Smart follow-up suggestions generated after each assistant response.
    @Published var followUpSuggestions: [FollowUpSuggestion] = []

    /// Multi-file context resolver for automatic file awareness.
    let contextResolver = ContextResolver()

    // MARK: - Next-Level Intelligence Subsystems

    /// Detects when the agent is stuck in a repeating failure pattern and forces a strategy pivot.
    let cognitiveLoopDetector = CognitiveLoopDetector()
    /// Calibrated confidence scoring — adapts agent autonomy based on certainty.
    let confidenceCalibration = ConfidenceCalibration()
    /// Adversarial self-review — red team critic for Build mode output.
    let adversarialReview = AdversarialReviewEngine()
    /// Causal regression tracking — traces build/test failures to the commit that caused them.
    let regressionTracker = CausalRegressionTracker()
    /// Intent continuity — persists high-level goals across sessions with progress tracking.
    let intentContinuity = IntentContinuityService()
    /// Tracks code changes made during the current agent run for adversarial review.
    var currentRunCodeChanges: [CodeChange] = []

    /// Preserved partial response content when a stream error occurs.
    @Published var streamErrorPartialContent: String?
    /// The error message from a failed stream, for inline retry UI.
    @Published var streamErrorMessage: String?

    #if os(macOS)
    /// When non-nil, the UI should show an approval dialog for system_run. Call respondToSystemRunApproval when the user chooses.
    @Published var pendingSystemRunApproval: (command: String, resolvedPath: String)?
    var systemRunApprovalContinuation: CheckedContinuation<SystemRunApprovalResponse, Never>?

    func respondToSystemRunApproval(_ response: SystemRunApprovalResponse) {
        guard let cont = systemRunApprovalContinuation else { return }
        systemRunApprovalContinuation = nil
        pendingSystemRunApproval = nil
        cont.resume(returning: response)
    }
    #endif

    // Legacy properties for backward compatibility
    @Published var apiKey: String {
        didSet {
            KeychainStorage.set(account: "QwenAPIKey", value: apiKey)
            // Update Qwen provider configuration
            if let config = aiService.modelRegistry.getProviderConfig(for: .qwen) {
                let updatedConfig = ProviderConfiguration(
                    provider: .qwen,
                    apiKey: apiKey,
                    baseURL: config.baseURL
                )
                aiService.modelRegistry.setProviderConfig(updatedConfig)
            }
        }
    }
    @Published var selectedModel: AIModel {
        didSet {
            guard oldValue != selectedModel else { return }
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "SelectedModel")
            // Update AI service to use equivalent enhanced model
            if let enhancedModel = aiService.availableModels.first(where: { $0.modelID == selectedModel.rawValue }) {
                aiService.selectModel(enhancedModel)
            }
        }
    }
    @Published var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "SystemPrompt") }
    }
    /// Agent mode for next message (Plan, Build, Spec). Per-message override.
    @Published var agentMode: AgentMode {
        didSet { UserDefaults.standard.set(agentMode.rawValue, forKey: "AgentMode") }
    }

    // New multi-provider system
    @Published var aiService = QwenAIService()

    let openAICompatibleService = OpenAICompatibleService()
    let activityStore = ActivityStore()
    internal var streamTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    var syncDebounceTask: Task<Void, Never>?
    var syncDirty = false

    var suggestions: [Suggestion] {
        SuggestionEngine.suggest(activityEntries: activityStore.entries, workingDirectory: workingDirectory)
    }
    static let appDirectoryName = "GRump"
    private static let draftsUserDefaultsKey = "GRumpConversationDrafts"

    var messages: [Message] {
        currentConversation?.messages ?? []
    }

    /// Model actually used for requests (project config can override selectedModel).
    /// Validated against tier; falls back to first allowed model if project config specifies a Pro model for free user.
    var effectiveModel: AIModel {
        // First try to get the enhanced model from AI service
        if let enhancedModel = aiService.currentModel {
            // Convert back to legacy AIModel for compatibility
            return AIModel(rawValue: enhancedModel.modelID) ?? selectedModel
        }

        // Fallback to legacy system
        let candidate = projectConfig?.model.flatMap { AIModel(rawValue: $0) } ?? selectedModel
        let allowed = AIModel.modelsForTier(nil)
        return allowed.contains(candidate) ? candidate : AIModel.defaultForTier(nil)
    }

    /// Enhanced model currently selected
    var currentEnhancedModel: EnhancedAIModel? {
        return aiService.currentModel
    }

    /// Current AI provider
    var currentAIProvider: AIProvider {
        return aiService.currentProvider
    }

    /// Whether the current AI provider is configured
    var isAIProviderConfigured: Bool {
        return aiService.isConfigured
    }

    /// All models for a given provider from the registry
    func modelsForProvider(_ provider: AIProvider) -> [EnhancedAIModel] {
        return aiService.modelRegistry.getModels(for: provider)
    }

    /// No local models in the Qwen build (all inference is cloud).
    var localModels: [EnhancedAIModel] { [] }

    /// Whether a provider has any models available
    func providerHasModels(_ provider: AIProvider) -> Bool {
        !modelsForProvider(provider).isEmpty
    }

    /// Select a provider and model from the picker
    func selectProviderAndModel(provider: AIProvider, model: EnhancedAIModel) {
        aiService.selectProvider(provider)
        aiService.selectModel(model)
    }

    /// Select just a provider (model auto-selected)
    func selectProvider(_ provider: AIProvider) {
        aiService.selectProvider(provider)
    }

    init() {
        // Initialize AI service
        self.aiService = QwenAIService()

        // Load the Qwen API key, migrating any key from the old provider account.
        if let key = KeychainStorage.get(account: "QwenAPIKey") {
            self.apiKey = key
        } else if let legacy = KeychainStorage.get(account: "OpenRouterAPIKey") {
            // One-time migration from the pre-Qwen build.
            self.apiKey = legacy
            KeychainStorage.set(account: "QwenAPIKey", value: legacy)
        } else {
            self.apiKey = ""
        }

        // Load legacy model selection
        let savedModel = UserDefaults.standard.string(forKey: "SelectedModel") ?? AIModel.qwenCoderPlus.rawValue
        let migratedModel = Self.migrateLegacyModelID(savedModel)
        self.selectedModel = AIModel(rawValue: migratedModel) ?? .qwenCoderPlus
        self.systemPrompt = UserDefaults.standard.string(forKey: "SystemPrompt") ?? GRumpDefaults.defaultSystemPrompt
        let savedMode = UserDefaults.standard.string(forKey: "AgentMode") ?? AgentMode.plan.rawValue
        self.agentMode = AgentMode(rawValue: savedMode) ?? .plan
        self.workingDirectory = UserDefaults.standard.string(forKey: "WorkingDirectory") ?? ""
        self.projectConfig = ProjectConfig.load(from: self.workingDirectory)
        if !self.workingDirectory.isEmpty {
            activityStore.setPersistencePath("\(self.workingDirectory)/.grump/activity.json")
        }

        // Show an empty conversation immediately so UI renders fast
        createNewConversation()

        // Load conversations on the next main-actor tick (fast, file I/O only).
        // Conversations are loaded for the sidebar, but currentConversation stays
        // as the fresh "New Chat" so the user always sees a clean screen on launch.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.loadConversations()
        }

        // Set up AI service observers
        aiService.$currentProvider
            .sink { [weak self] _ in
                // Update legacy selectedModel when provider changes
                if let enhancedModel = self?.aiService.currentModel {
                    // Try to find equivalent legacy model
                    if let legacyModel = AIModel(rawValue: enhancedModel.modelID) {
                        self?.selectedModel = legacyModel
                    }
                }
            }
            .store(in: &cancellables)

        aiService.$currentModel
            .sink { [weak self] enhancedModel in
                // Update legacy selectedModel when model changes
                if let enhancedModel = enhancedModel,
                   let legacyModel = AIModel(rawValue: enhancedModel.modelID) {
                    self?.selectedModel = legacyModel
                }
            }
            .store(in: &cancellables)

        aiService.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        activityStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func saveDraft(_ text: String, forConversationId id: UUID) {
        var dict = UserDefaults.standard.dictionary(forKey: Self.draftsUserDefaultsKey) as? [String: String] ?? [:]
        if text.isEmpty {
            dict.removeValue(forKey: id.uuidString)
        } else {
            dict[id.uuidString] = text
        }
        UserDefaults.standard.set(dict, forKey: Self.draftsUserDefaultsKey)
    }

    func loadDraft(forConversationId id: UUID) -> String {
        let dict = UserDefaults.standard.dictionary(forKey: Self.draftsUserDefaultsKey) as? [String: String] ?? [:]
        return dict[id.uuidString] ?? ""
    }

    /// Maps any legacy (multi-provider) model ID onto a current Qwen model so
    /// existing users keep a valid selection after the single-provider migration.
    private static func migrateLegacyModelID(_ id: String) -> String {
        (AIModel.migrateLegacyID(id) ?? .qwenCoderPlus).rawValue
    }

    /// Project-level config loaded from .grump/config.json or grump.json when working directory is set.
    @Published var projectConfig: ProjectConfig?

    /// Tool allowlist from applied workflow preset. When set, overrides project config tool list.
    @Published var appliedPresetToolAllowlist: [String]?
    /// Name of applied preset, for display. When non-nil, a preset is active.
    @Published var appliedPresetName: String?
    /// Max agent steps from applied preset. When set, overrides user default (project config still wins).
    @Published var appliedPresetMaxAgentSteps: Int?

    /// Commands run or denied via system_run this session (for Security history view).
    @Published var systemRunHistory: [SystemRunHistoryEntry] = []

    // MARK: - Conversation Threads & Branches

    var conversationThreads: [MessageThread] {
        currentConversation?.threads ?? []
    }

    /// Get all branches for the current conversation
    var conversationBranches: [MessageBranch] {
        currentConversation?.branches ?? []
    }

    // MARK: - Undo Send

    /// Stores the last sent message text so it can be undone within a short window.
    @Published var undoSendAvailable = false
    var lastSentText: String?
    var undoSendTask: Task<Void, Never>?

    // MARK: - Scroll & Search

    /// Incremented to trigger a scroll-to-bottom in MessageListView
    @Published var scrollToBottomTrigger: Int = 0

    /// Conversation search state
    @Published var conversationSearchText: String = ""
    @Published var conversationSearchVisible: Bool = false

    func scrollToLastMessage() {
        scrollToBottomTrigger += 1
    }

    // MARK: - Apple Intelligence Context

    enum UserSentiment { case neutral, frustrated }

    /// Last detected user sentiment (from AppleIntelligenceService).
    var lastUserSentiment: UserSentiment = .neutral
    /// Last classified user intent (from AppleIntelligenceService).
    var lastUserIntent: AppleIntelligenceService.UserIntent = .general

}
