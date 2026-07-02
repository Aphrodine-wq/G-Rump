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
    let id: String                  // SubAgentTask.id
    let agentIndex: Int             // 1-based display index
    let taskDescription: String
    let taskType: TaskType
    let modelName: String
    var status: SubAgentTask.SubAgentStatus = .pending
    var streamingText: String = ""
    var result: String?
}

// MARK: - Available Models (OpenRouter)

enum AIModel: String, CaseIterable, Identifiable {
    // Pro-only: Paying users (Pro/Team) see these
    case claudeOpus46      = "anthropic/claude-opus-4.6"
    case gemini31Pro       = "google/gemini-3.1-pro"
    case claudeSonnet46    = "anthropic/claude-sonnet-4.6"
    case codex53           = "openai/codex-5.3"
    case kimiK25           = "moonshotai/kimi-k2.5"

    // Fast + Smart (Free tier users)
    case claudeSonnet4     = "anthropic/claude-sonnet-4"
    case gemini31Flash     = "google/gemini-3.1-flash"
    case deepseekChat      = "deepseek/deepseek-chat-v3-0324:free"

    // Free — best open-source coding models (2026)
    case qwen3Coder        = "qwen/qwen3-coder:free"
    case deepseekR1        = "deepseek/deepseek-r1-0528:free"
    case gptOss120b        = "openai/gpt-oss-120b:free"
    case trinityLarge      = "arcee-ai/trinity-large-preview:free"
    case step35Flash       = "stepfun/step-3.5-flash:free"
    case llama33           = "meta-llama/llama-3.3-70b-instruct:free"
    case glm45Air          = "z-ai/glm-4.5-air:free"

    var id: String { rawValue }

    var requiresPaidTier: Bool {
        switch self {
        case .claudeOpus46, .gemini31Pro, .claudeSonnet46, .codex53, .kimiK25: return true
        case .claudeSonnet4: return false
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .claudeOpus46:     return "Claude Opus 4.6"
        case .gemini31Pro:      return "Gemini 3.1 Pro"
        case .claudeSonnet46:   return "Claude Sonnet 4.6"
        case .codex53:          return "Codex 5.3"
        case .kimiK25:          return "Kimi K2.5"
        case .claudeSonnet4:    return "Claude Sonnet 4"
        case .gemini31Flash:    return "Gemini 3.1 Flash"
        case .deepseekChat:     return "DeepSeek V3"
        case .qwen3Coder:       return "Qwen3 Coder 480B"
        case .deepseekR1:       return "DeepSeek R1"
        case .gptOss120b:       return "GPT-OSS 120B"
        case .trinityLarge:     return "Trinity Large 400B"
        case .step35Flash:      return "Step 3.5 Flash"
        case .llama33:          return "Llama 3.3 70B"
        case .glm45Air:         return "GLM 4.5 Air"
        }
    }

    var description: String {
        switch self {
        case .claudeOpus46:     return "Flagship frontier model — complex coding, agents, long context"
        case .gemini31Pro:      return "Flagship reasoning, complex coding, 1M context"
        case .claudeSonnet46:   return "Frontier Sonnet — coding, agents, professional work"
        case .codex53:          return "OpenAI's latest coding model — agentic, multi-file, deep reasoning"
        case .kimiK25:          return "Strong reasoning and visual coding, top tool use"
        case .claudeSonnet4:    return "Balanced coding and reasoning, excellent tool use"
        case .gemini31Flash:    return "Speed king — fast iteration, great for drafting"
        case .deepseekChat:     return "Strong coder, free DeepSeek V3"
        case .qwen3Coder:       return "Best free coding model, 480B MoE, agentic tool use"
        case .deepseekR1:       return "Open-source reasoning on par with o1, 164K context"
        case .gptOss120b:       return "OpenAI open-weight MoE, native tool use & reasoning"
        case .trinityLarge:     return "400B MoE, trained for agentic coding (Cline/OpenCode)"
        case .step35Flash:      return "196B MoE, blazing fast at 256K context"
        case .llama33:          return "Meta's best open-weight 70B, multilingual coding"
        case .glm45Air:         return "Agent-first model with thinking mode, tool use"
        }
    }

    var contextWindow: Int {
        switch self {
        case .claudeOpus46:     return 1_000_000
        case .gemini31Pro:      return 1_000_000
        case .claudeSonnet46:   return 1_000_000
        case .codex53:          return 200_000
        case .kimiK25:          return 262_144
        case .claudeSonnet4:    return 200_000
        case .gemini31Flash:    return 1_000_000
        case .deepseekChat:     return 128_000
        case .qwen3Coder:       return 262_000
        case .deepseekR1:       return 164_000
        case .gptOss120b:       return 131_000
        case .trinityLarge:     return 131_000
        case .step35Flash:      return 256_000
        case .llama33:          return 128_000
        case .glm45Air:         return 131_000
        }
    }

    var maxOutput: Int {
        switch self {
        case .claudeOpus46:     return 65_536
        case .gemini31Pro:      return 65_536
        case .claudeSonnet46:   return 65_536
        case .codex53:          return 65_536
        case .kimiK25:          return 65_536
        case .claudeSonnet4:    return 16_000
        case .gemini31Flash:    return 65_536
        case .deepseekChat:     return 16_384
        case .qwen3Coder:       return 32_768
        case .deepseekR1:       return 32_768
        case .gptOss120b:       return 16_384
        case .trinityLarge:     return 16_384
        case .step35Flash:      return 16_384
        case .llama33:          return 16_384
        case .glm45Air:         return 16_384
        }
    }

    var tier: String {
        switch self {
        case .claudeOpus46, .gemini31Pro, .claudeSonnet46, .codex53, .kimiK25:
            return "Pro"
        case .claudeSonnet4, .gemini31Flash, .deepseekChat:
            return "Fast"
        case .qwen3Coder, .deepseekR1, .gptOss120b, .trinityLarge, .step35Flash, .llama33, .glm45Air:
            return "Free"
        }
    }

    /// Models available for the given platform tier. Pro/Team -> all; Free -> Fast + Free tiers.
    static func modelsForTier(_ platformTier: String?) -> [AIModel] {
        let isPaid = platformTier == "pro" || platformTier == "team"
        if isPaid {
            return [.claudeOpus46, .gemini31Pro, .claudeSonnet46, .codex53, .kimiK25]
        }
        return [
            .claudeSonnet4, .gemini31Flash, .deepseekChat,
            .qwen3Coder, .deepseekR1, .gptOss120b, .trinityLarge, .step35Flash, .llama33, .glm45Air
        ]
    }

    static func defaultForTier(_ platformTier: String?) -> AIModel {
        modelsForTier(platformTier).first ?? .qwen3Coder
    }

    /// Migrate old model IDs to current ones (for saved conversations).
    static func migrateLegacyID(_ rawValue: String) -> AIModel? {
        // Handle renamed Gemini models
        switch rawValue {
        case "google/gemini-2.5-pro-preview": return .gemini31Pro
        case "google/gemini-2.5-flash-preview": return .gemini31Flash
        default: return AIModel(rawValue: rawValue)
        }
    }
}
