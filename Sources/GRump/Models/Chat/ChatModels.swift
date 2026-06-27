import Foundation

// MARK: - Shared Defaults (nonisolated for use in presets, etc.)
// NOTE: This is the canonical source for all default constants.
// Do not duplicate default values elsewhere - reference them from here.

enum GRumpDefaults {
    static let defaultSystemPrompt = """
    You are G-Rump, an elite AI coding agent with direct access to the user's file system, shell, browser, Docker, cloud deployments, and the web. You operate autonomously to complete complex software engineering tasks end-to-end.

    ## Core Principles
    1. **Inspect before modifying.** Always read files/directories before editing. Never guess at file contents.
    2. **Minimal, surgical changes.** Prefer edit_file over write_file when modifying existing code. Only change what's necessary.
    3. **Verify your work.** After making changes, run tests, linters, or build commands to confirm correctness.
    4. **Recover from errors.** If a tool call fails, diagnose the issue and retry with a corrected approach. Never give up after one failure.
    5. **Think step by step.** For complex tasks, break them down. State your plan, execute it, and verify each step.

    ## Tool Usage Strategy
    - Use `tree_view` or `list_directory` first to understand project structure before diving in.
    - Use `grep_search` to find relevant code across a codebase quickly.
    - Use `read_file` with line ranges for large files instead of reading the entire file.
    - Use `batch_read_files` when you need to read multiple files at once.
    - Use `edit_file` for targeted changes; use `write_file` only for new files or complete rewrites.
    - Use `run_command` to execute builds, tests, linters, git operations, and any CLI tool.
    - Use `web_search` when you need current documentation, API references, or solutions to errors.
    - Use `find_and_replace` for project-wide refactoring (renaming symbols, updating imports, etc.).

    ## Code Quality Standards
    - Write clean, idiomatic code that follows the project's existing conventions.
    - Include error handling. Never write code that silently swallows errors.
    - Prefer explicit types and clear naming over clever abstractions.
    - When adding dependencies, use the project's package manager and pin versions.
    - If creating new files, include necessary imports and follow the project's file organization.

    ## Communication Style
    - Be direct and concise. Lead with the solution, not the explanation.
    - When showing code changes, use diffs or describe exactly what changed and why.
    - If a task is ambiguous, make a reasonable decision and explain your choice briefly.
    - For multi-step tasks, give a brief plan upfront, then execute.
    - When you encounter an error or unexpected state, explain what happened and what you're doing to fix it.

    ## Working Directory
    The user may set a working directory. When set, prefer relative paths from that directory. Use absolute paths when the working directory is not set or when referencing files outside it.
    """
}

// MARK: - App Models

struct Message: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    let role: Role
    var content: String
    var timestamp: Date = Date()
    var toolCallId: String?         // for role == .tool
    var toolCalls: [ToolCall]?      // for role == .assistant with tool use

    // Threading support
    var parentMessageId: UUID?      // ID of the message this is a reply to
    var branchId: UUID?             // ID for branching conversations
    var threadId: UUID?             // ID for the main thread
    var isBranch: Bool = false      // Whether this message starts a new branch
    var branchName: String?         // Optional name for the branch
    var children: [UUID] = []       // IDs of child messages

    enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
        case tool
    }
}

struct ToolCall: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let arguments: String
}

struct ToolCallStatus: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let arguments: String
    var status: ToolRunStatus
    var result: String?
    var progress: Double = 0.0
    var startTime: Date?
    var endTime: Date?
    var currentStep: String?
    var totalSteps: Int = 1
    var currentStepNumber: Int = 0

    enum ToolRunStatus: Equatable, Sendable {
        case pending
        case running
        case completed
        case failed
        case cancelled
    }
}

struct SystemRunHistoryEntry: Identifiable, Sendable {
    let id: UUID
    let command: String
    let resolvedPath: String
    let allowed: Bool
    let timestamp: Date

    init(id: UUID = UUID(), command: String, resolvedPath: String, allowed: Bool, timestamp: Date = Date()) {
        self.id = id
        self.command = command
        self.resolvedPath = resolvedPath
        self.allowed = allowed
        self.timestamp = timestamp
    }
}

// MARK: - Thread Models

struct MessageThread: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String?
    let rootMessageId: UUID
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isActive: Bool = true
    var color: String? // Optional color for thread visualization

    init(id: UUID = UUID(), name: String? = nil, rootMessageId: UUID) {
        self.id = id
        self.name = name
        self.rootMessageId = rootMessageId
    }
}

struct MessageBranch: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    let parentMessageId: UUID
    let branchPointMessageId: UUID
    var createdAt: Date = Date()
    var isActive: Bool = true

    init(id: UUID = UUID(), name: String, parentMessageId: UUID, branchPointMessageId: UUID) {
        self.id = id
        self.name = name
        self.parentMessageId = parentMessageId
        self.branchPointMessageId = branchPointMessageId
    }
}

struct Conversation: Identifiable, Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var title: String
    var messages: [Message] = []
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    // Threading support
    var threads: [MessageThread] = []
    var branches: [MessageBranch] = []
    var activeThreadId: UUID?
    var viewMode: ConversationViewMode = .linear

    enum ConversationViewMode: String, Codable, CaseIterable, Sendable {
        case linear = "linear"
        case threaded = "threaded"
        case branched = "branched"
    }

    /// Generate a title from the first user message
    mutating func updateTitle() {
        if let firstUserMsg = messages.first(where: { $0.role == .user }) {
            let content = firstUserMsg.content
            let maxLen = 40
            if content.count > maxLen {
                title = String(content.prefix(maxLen)) + "…"
            } else {
                title = content
            }
        }
    }

    /// Get messages for the active thread
    func getActiveThreadMessages() -> [Message] {
        guard let activeThreadId = activeThreadId else { return messages }

        let threadMessages = messages.filter { msg in
            msg.threadId == activeThreadId || msg.threadId == nil
        }

        return threadMessages.sorted { $0.timestamp < $1.timestamp }
    }

    /// Create a new thread from a message
    mutating func createThread(from messageId: UUID, name: String? = nil) -> UUID? {
        guard messages.contains(where: { $0.id == messageId }) else { return nil }

        let thread = MessageThread(name: name, rootMessageId: messageId)
        threads.append(thread)

        // Update the message and its descendants
        updateMessageAndDescendants(messageId: messageId, threadId: thread.id)

        activeThreadId = thread.id
        return thread.id
    }

    /// Create a branch from a message
    mutating func createBranch(from messageId: UUID, name: String) -> UUID? {
        guard messages.contains(where: { $0.id == messageId }) else { return nil }

        let branch = MessageBranch(name: name, parentMessageId: messageId, branchPointMessageId: messageId)
        branches.append(branch)

        return branch.id
    }

    private mutating func updateMessageAndDescendants(messageId: UUID, threadId: UUID) {
        if let index = messages.firstIndex(where: { $0.id == messageId }) {
            messages[index].threadId = threadId
        }

        // Recursively update children
        let children = messages.filter { $0.parentMessageId == messageId }
        for child in children {
            updateMessageAndDescendants(messageId: child.id, threadId: threadId)
        }
    }
}

// MARK: - Parallel Agent UI State

/// Published state for a single sub-agent running in parallel mode.
struct ParallelAgentState: Identifiable, Sendable {
    enum SubAgentStatus: String, Sendable {
        case pending, running, completed, failed
    }
    let id: String                  // sub-agent task id
    let agentIndex: Int             // 1-based display index
    let taskDescription: String
    let taskType: TaskType
    let modelName: String
    var status: SubAgentStatus = .pending
    var streamingText: String = ""
    var result: String?
}

// MARK: - Available Models (Qwen Cloud / Alibaba DashScope)
// rawValue == the exact DashScope model id sent on the wire.

enum AIModel: String, CaseIterable, Identifiable {
    case qwenCoderPlus = "qwen-coder-plus"   // default — agentic coding
    case qwenMax       = "qwen-max"          // flagship reasoning / planning
    case qwenPlus      = "qwen-plus"         // balanced
    case qwenTurbo     = "qwen-turbo"        // fast / cheap

    var id: String { rawValue }

    // No billing tiers in the Qwen build — every model is available.
    var requiresPaidTier: Bool { false }

    var displayName: String {
        switch self {
        case .qwenCoderPlus: return "Qwen Coder Plus"
        case .qwenMax:       return "Qwen Max"
        case .qwenPlus:      return "Qwen Plus"
        case .qwenTurbo:     return "Qwen Turbo"
        }
    }

    var description: String {
        switch self {
        case .qwenCoderPlus: return "Agentic coding model — multi-file edits, strong tool use"
        case .qwenMax:       return "Flagship Qwen — deepest reasoning and planning"
        case .qwenPlus:      return "Balanced reasoning and speed for everyday tasks"
        case .qwenTurbo:     return "Fastest, cheapest — drafting and quick iteration"
        }
    }

    var contextWindow: Int {
        switch self {
        case .qwenCoderPlus: return 1_000_000
        case .qwenMax:       return 32_768
        case .qwenPlus:      return 131_072
        case .qwenTurbo:     return 1_000_000
        }
    }

    // Conservative max_tokens that stay within DashScope per-model output limits.
    var maxOutput: Int {
        switch self {
        case .qwenCoderPlus: return 65_536
        case .qwenMax:       return 8_192
        case .qwenPlus:      return 8_192
        case .qwenTurbo:     return 8_192
        }
    }

    // Single provider now; kept for UI labels that group by tier.
    var tier: String { "Qwen" }

    /// All Qwen models, regardless of platform tier (billing removed).
    static func modelsForTier(_ platformTier: String?) -> [AIModel] {
        AIModel.allCases
    }

    static func defaultForTier(_ platformTier: String?) -> AIModel {
        .qwenCoderPlus
    }

    /// Map any legacy (multi-provider) model id from saved conversations/presets
    /// onto a Qwen model so nothing crashes after the single-provider migration.
    static func migrateLegacyID(_ rawValue: String) -> AIModel? {
        if let exact = AIModel(rawValue: rawValue) { return exact }
        let lower = rawValue.lowercased()
        if lower.contains("coder") || lower.contains("codex") || lower.contains("deepseek") {
            return .qwenCoderPlus
        }
        if lower.contains("flash") || lower.contains("turbo") || lower.contains("mini") || lower.contains("air") {
            return .qwenTurbo
        }
        if lower.contains("opus") || lower.contains("max") || lower.contains("pro") || lower.contains("r1") {
            return .qwenMax
        }
        // Any other historical id → safe default.
        return .qwenCoderPlus
    }
}
