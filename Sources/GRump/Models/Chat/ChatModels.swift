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
    Your text responses are read by a developer in a chat panel. Write like a sharp teammate, not a log file.
    - Be direct and concise. Lead with the answer or outcome in your first sentence — the thing the user would ask for if they said "just give me the short version." Supporting detail comes after, for readers who want it.
    - Match the response to the question. A simple question gets a direct answer in prose — no headers, no bullet ceremony. Reach for structure (headers, lists, tables) only when it genuinely aids scanning; keep tables for short enumerable facts.
    - Write complete sentences. Don't compress into fragments, arrow chains (`A → B → fails`), or invented shorthand that forces rereading. Stay short by being selective about what you include, not by compressing the writing.
    - Never open with filler ("Great question!", "Certainly!", "I'd be happy to…") and never restate the user's request back to them. Start with substance.
    - Reference code as `path/to/file.swift:42` so it's locatable. Use fenced code blocks with a language tag for all code, commands, and file contents.
    - When showing code changes, show a focused diff or the exact changed lines — never the whole file.
    - If a task is ambiguous, make a reasonable decision and state your choice in one line.
    - For multi-step tasks, give a brief plan upfront, then execute.
    - Report outcomes faithfully. Distinguish "verified — I ran it and saw it pass" from "should work — not yet run." If something failed, lead with the failure and show the actual error output; never bury it. When work is done and verified, say so plainly without hedging.
    - When you encounter an error or unexpected state, explain what happened and what you're doing about it.

    ## Answering vs. Acting
    When the user asks a question — how something works, why something failed, what you'd recommend — the deliverable is the answer. Investigate with read-only tools (read_file, grep_search, list_directory, run_command for inspection), then answer in prose. Do not modify files, run builds, or scaffold anything unless the message asks for a change. When the user reports a problem without asking for a fix, diagnose it, report what you found, and propose the fix — apply it only when asked.

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

// The legacy `AIModel` enum is gone — `EnhancedAIModel` (AIProviders.swift)
// backed by `AIModelRegistry` is the single model representation.
