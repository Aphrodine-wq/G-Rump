// ╔══════════════════════════════════════════════════════════════════╗
// ║  SwiftDataModels.swift                                          ║
// ║  Dual persistence: SwiftData (@Model) for Xcode builds,        ║
// ║  plain Codable classes for SPM builds. Legacy JSON migration.   ║
// ╚══════════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - SwiftData Models
//
// Apple-native persistence layer replacing manual JSON file I/O.
// These models mirror the existing Conversation/Message/ToolCall structs
// and are designed for CloudKit sync via SwiftData's built-in support.
//
// Migration strategy: existing JSON conversations are imported on first
// launch via SwiftDataMigrator. After migration, SwiftData is the single
// source of truth.
//
// NOTE: @Model macros require Xcode's build system for expansion.
// When building with `swift build` (dev), GRUMP_SPM_BUILD is defined
// and stub types are provided instead. For App Store / Xcode builds,
// the full SwiftData models activate.

#if !GRUMP_SPM_BUILD
import SwiftData

// MARK: - Persisted Conversation

@Model
final class SDConversation {
    @Attribute(.unique) var conversationId: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var projectLabel: String?
    var activeThreadId: UUID?
    var viewMode: String // "linear", "threaded", "branched"

    @Relationship(deleteRule: .cascade, inverse: \SDMessage.conversation)
    var messages: [SDMessage]

    @Relationship(deleteRule: .cascade, inverse: \SDChatThread.conversation)
    var threads: [SDChatThread]

    @Relationship(deleteRule: .cascade, inverse: \SDChatBranch.conversation)
    var branches: [SDChatBranch]

    init(
        conversationId: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        projectLabel: String? = nil,
        viewMode: String = "linear"
    ) {
        self.conversationId = conversationId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.projectLabel = projectLabel
        self.viewMode = viewMode
        self.messages = []
        self.threads = [] as [SDChatThread]
        self.branches = [] as [SDChatBranch]
    }
}

// MARK: - Persisted Message

@Model
final class SDMessage {
    @Attribute(.unique) var messageId: UUID
    var role: String // "user", "assistant", "system", "tool"
    var content: String
    var timestamp: Date
    var toolCallId: String?
    var toolCallsData: Data? // JSON-encoded [ToolCall]
    var thinkingBlocksData: Data? // JSON-encoded [ThinkingBlock]

    // Threading
    var parentMessageId: UUID?
    var branchId: UUID?
    var threadId: UUID?
    var isBranch: Bool
    var branchName: String?
    var childrenIds: Data? // JSON-encoded [UUID]

    // Reactions & editing
    var reaction: String? // "thumbsUp", "thumbsDown", nil
    var isEdited: Bool

    var conversation: SDConversation?

    init(
        messageId: UUID = UUID(),
        role: String = "user",
        content: String = "",
        timestamp: Date = Date(),
        toolCallId: String? = nil,
        toolCallsData: Data? = nil,
        thinkingBlocksData: Data? = nil,
        parentMessageId: UUID? = nil,
        branchId: UUID? = nil,
        threadId: UUID? = nil,
        isBranch: Bool = false,
        branchName: String? = nil,
        reaction: String? = nil,
        isEdited: Bool = false
    ) {
        self.messageId = messageId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCallId = toolCallId
        self.toolCallsData = toolCallsData
        self.thinkingBlocksData = thinkingBlocksData
        self.parentMessageId = parentMessageId
        self.branchId = branchId
        self.threadId = threadId
        self.isBranch = isBranch
        self.branchName = branchName
        self.reaction = reaction
        self.isEdited = isEdited
    }

    // MARK: - ToolCall Helpers

    var toolCalls: [ToolCall]? {
        get {
            guard let data = toolCallsData else { return nil }
            return try? JSONDecoder().decode([ToolCall].self, from: data)
        }
        set {
            toolCallsData = try? JSONEncoder().encode(newValue)
        }
    }

    var thinkingBlocks: [ThinkingBlock]? {
        get {
            guard let data = thinkingBlocksData else { return nil }
            return try? JSONDecoder().decode([ThinkingBlock].self, from: data)
        }
        set {
            thinkingBlocksData = try? JSONEncoder().encode(newValue)
        }
    }

    var children: [UUID] {
        get {
            guard let data = childrenIds else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set {
            childrenIds = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - Persisted Thread

@Model
final class SDChatThread {
    @Attribute(.unique) var threadId: UUID
    var name: String?
    var rootMessageId: UUID
    var createdAt: Date
    var updatedAt: Date
    var isActive: Bool
    var color: String?

    var conversation: SDConversation?

    init(
        threadId: UUID = UUID(),
        name: String? = nil,
        rootMessageId: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isActive: Bool = true,
        color: String? = nil
    ) {
        self.threadId = threadId
        self.name = name
        self.rootMessageId = rootMessageId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
        self.color = color
    }
}

// MARK: - Persisted Branch

@Model
final class SDChatBranch {
    @Attribute(.unique) var branchId: UUID
    var name: String
    var parentMessageId: UUID
    var branchPointMessageId: UUID
    var createdAt: Date
    var isActive: Bool

    var conversation: SDConversation?

    init(
        branchId: UUID = UUID(),
        name: String,
        parentMessageId: UUID,
        branchPointMessageId: UUID,
        createdAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.branchId = branchId
        self.name = name
        self.parentMessageId = parentMessageId
        self.branchPointMessageId = branchPointMessageId
        self.createdAt = createdAt
        self.isActive = isActive
    }
}

// MARK: - Persisted Project

@Model
final class SDProject {
    @Attribute(.unique) var projectId: UUID
    var name: String
    var path: String
    var lastOpened: Date
    var skillIds: Data? // JSON-encoded [String]
    var soulScope: String? // "global" or "project"

    init(
        projectId: UUID = UUID(),
        name: String,
        path: String,
        lastOpened: Date = Date()
    ) {
        self.projectId = projectId
        self.name = name
        self.path = path
        self.lastOpened = lastOpened
    }
}

// MARK: - Persisted Memory Entry (for Semantic RAG)

@Model
final class SDMemoryEntry {
    @Attribute(.unique) var entryId: UUID
    var conversationId: String
    var timestamp: String
    var text: String
    var vectorData: Data? // JSON-encoded [Double]

    init(
        entryId: UUID = UUID(),
        conversationId: String,
        timestamp: String,
        text: String,
        vectorData: Data? = nil
    ) {
        self.entryId = entryId
        self.conversationId = conversationId
        self.timestamp = timestamp
        self.text = text
        self.vectorData = vectorData
    }

    var vector: [Double]? {
        get {
            guard let data = vectorData else { return nil }
            return try? JSONDecoder().decode([Double].self, from: data)
        }
        set {
            vectorData = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - Conversion: Legacy ↔ SwiftData

extension SDConversation {
    /// Convert from legacy Conversation struct to SwiftData model.
    convenience init(from legacy: Conversation) {
        self.init(
            conversationId: legacy.id,
            title: legacy.title,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt,
            isPinned: false,
            viewMode: legacy.viewMode.rawValue
        )
        self.activeThreadId = legacy.activeThreadId
    }

    /// Convert back to legacy Conversation struct for compatibility.
    func toLegacy() -> Conversation {
        let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
        var conv = Conversation(
            id: conversationId,
            title: title,
            messages: sortedMessages.map { $0.toLegacy() },
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        conv.threads = threads.map { (t: SDChatThread) in t.toLegacy() }
        conv.branches = branches.map { (b: SDChatBranch) in b.toLegacy() }
        conv.activeThreadId = activeThreadId
        conv.viewMode = Conversation.ConversationViewMode(rawValue: viewMode) ?? .linear
        return conv
    }
}

extension SDMessage {
    convenience init(from legacy: Message) {
        self.init(
            messageId: legacy.id,
            role: legacy.role.rawValue,
            content: legacy.content,
            timestamp: legacy.timestamp,
            toolCallId: legacy.toolCallId,
            toolCallsData: {
                guard let tc = legacy.toolCalls else { return nil }
                return try? JSONEncoder().encode(tc)
            }(),
            thinkingBlocksData: {
                guard let tb = legacy.thinkingBlocks else { return nil }
                return try? JSONEncoder().encode(tb)
            }(),
            parentMessageId: legacy.parentMessageId,
            branchId: legacy.branchId,
            threadId: legacy.threadId,
            isBranch: legacy.isBranch,
            branchName: legacy.branchName
        )
    }

    func toLegacy() -> Message {
        var msg = Message(
            id: messageId,
            role: Message.Role(rawValue: role) ?? .user,
            content: content,
            timestamp: timestamp,
            toolCallId: toolCallId,
            toolCalls: toolCalls,
            thinkingBlocks: thinkingBlocks
        )
        msg.parentMessageId = parentMessageId
        msg.branchId = branchId
        msg.threadId = threadId
        msg.isBranch = isBranch
        msg.branchName = branchName
        msg.children = children
        return msg
    }
}

extension SDChatThread {
    convenience init(from legacy: MessageThread) {
        self.init(
            threadId: legacy.id,
            name: legacy.name,
            rootMessageId: legacy.rootMessageId,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt,
            isActive: legacy.isActive,
            color: legacy.color
        )
    }

    func toLegacy() -> MessageThread {
        var thread = MessageThread(id: threadId, name: name, rootMessageId: rootMessageId)
        thread.createdAt = createdAt
        thread.updatedAt = updatedAt
        thread.isActive = isActive
        thread.color = color
        return thread
    }
}

extension SDChatBranch {
    convenience init(from legacy: MessageBranch) {
        self.init(
            branchId: legacy.id,
            name: legacy.name,
            parentMessageId: legacy.parentMessageId,
            branchPointMessageId: legacy.branchPointMessageId,
            createdAt: legacy.createdAt,
            isActive: legacy.isActive
        )
    }

    func toLegacy() -> MessageBranch {
        var branch = MessageBranch(
            id: branchId,
            name: name,
            parentMessageId: parentMessageId,
            branchPointMessageId: branchPointMessageId
        )
        branch.createdAt = createdAt
        branch.isActive = isActive
        return branch
    }
}

// MARK: - SwiftData Migrator

/// Handles one-time migration from legacy conversations.json to SwiftData.
enum SwiftDataMigrator {

    private static let migrationKey = "SwiftDataMigrationComplete_v1"

    static var hasMigrated: Bool {
        UserDefaults.standard.bool(forKey: migrationKey)
    }

    /// Load and decode legacy conversations.json on a background thread to avoid blocking the main thread.
    private static nonisolated func loadLegacyConversations(from jsonURL: URL) -> [Conversation]? {
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: jsonURL)
            return try JSONDecoder().decode([Conversation].self, from: data)
        } catch {
            GRumpLogger.migration.error("SwiftData migration failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Import legacy conversations.json into SwiftData. Idempotent.
    /// File I/O and JSON decode run off the main thread to keep the splash screen responsive.
    @MainActor
    static func migrateIfNeeded(context: ModelContext) async {
        guard !hasMigrated else { return }

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        let jsonURL = appSupport
            .appendingPathComponent("GRump", isDirectory: true)
            .appendingPathComponent("conversations.json")

        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // Load and decode on background thread — this is the heaviest work
        let loadTask = Task.detached(priority: .userInitiated) {
            loadLegacyConversations(from: jsonURL)
        }
        guard let legacyConversations = await loadTask.value else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        do {
            for legacy in legacyConversations {
                let sdConv = SDConversation(from: legacy)
                context.insert(sdConv)

                for msg in legacy.messages {
                    let sdMsg = SDMessage(from: msg)
                    sdMsg.conversation = sdConv
                    context.insert(sdMsg)
                }

                for thread in legacy.threads {
                    let sdThread = SDChatThread(from: thread)
                    sdThread.conversation = sdConv
                    context.insert(sdThread)
                }

                for branch in legacy.branches {
                    let sdBranch = SDChatBranch(from: branch)
                    sdBranch.conversation = sdConv
                    context.insert(sdBranch)
                }
            }

            try context.save()
            UserDefaults.standard.set(true, forKey: migrationKey)
            GRumpLogger.migration.info("Migrated \(legacyConversations.count) conversations from JSON (SwiftData)")
        } catch {
            GRumpLogger.migration.error("SwiftData migration failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - SwiftData Container Configuration

enum SwiftDataConfiguration {
    /// The shared model container for the app.
    /// Uses CloudKit-backed container for iCloud sync when available.
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            SDConversation.self,
            SDMessage.self,
            SDChatThread.self,
            SDChatBranch.self,
            SDProject.self,
            SDMemoryEntry.self
        ] as [any PersistentModel.Type])

        let config = ModelConfiguration(
            "GRump",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .automatic
        )

        return try ModelContainer(for: schema, configurations: [config])
    }
}

#else
// MARK: - SPM Build — Manual Codable Persistence Layer
//
// SwiftData @Model macros require Xcode's SwiftDataMacros plugin.
// This provides equivalent persistence using plain Codable classes
// with file-based storage. Same API surface as the SwiftData version
// so GRumpApp.swift and ChatViewModel can use them interchangeably.

import SwiftUI

// MARK: - Persisted Conversation (SPM)

final class SDConversation: Codable, Identifiable, ObservableObject {
    var conversationId: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var projectLabel: String?
    var activeThreadId: UUID?
    var viewMode: String
    var messages: [SDMessage]
    var threads: [SDChatThread]
    var branches: [SDChatBranch]

    var id: UUID { conversationId }

    init(
        conversationId: UUID = UUID(),
        title: String = "New Chat",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        projectLabel: String? = nil,
        viewMode: String = "linear"
    ) {
        self.conversationId = conversationId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.projectLabel = projectLabel
        self.viewMode = viewMode
        self.messages = []
        self.threads = []
        self.branches = []
    }
}

// MARK: - Persisted Message (SPM)

final class SDMessage: Codable, Identifiable {
    var messageId: UUID
    var role: String
    var content: String
    var timestamp: Date
    var toolCallId: String?
    var toolCallsData: Data?
    var thinkingBlocksData: Data?
    var parentMessageId: UUID?
    var branchId: UUID?
    var threadId: UUID?
    var isBranch: Bool
    var branchName: String?
    var childrenIds: Data?
    var reaction: String?
    var isEdited: Bool

    var id: UUID { messageId }

    init(
        messageId: UUID = UUID(),
        role: String = "user",
        content: String = "",
        timestamp: Date = Date(),
        toolCallId: String? = nil,
        toolCallsData: Data? = nil,
        thinkingBlocksData: Data? = nil,
        parentMessageId: UUID? = nil,
        branchId: UUID? = nil,
        threadId: UUID? = nil,
        isBranch: Bool = false,
        branchName: String? = nil,
        reaction: String? = nil,
        isEdited: Bool = false
    ) {
        self.messageId = messageId
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolCallId = toolCallId
        self.toolCallsData = toolCallsData
        self.thinkingBlocksData = thinkingBlocksData
        self.parentMessageId = parentMessageId
        self.branchId = branchId
        self.threadId = threadId
        self.isBranch = isBranch
        self.branchName = branchName
        self.reaction = reaction
        self.isEdited = isEdited
    }

    var toolCalls: [ToolCall]? {
        get {
            guard let data = toolCallsData else { return nil }
            return try? JSONDecoder().decode([ToolCall].self, from: data)
        }
        set {
            toolCallsData = try? JSONEncoder().encode(newValue)
        }
    }

    var thinkingBlocks: [ThinkingBlock]? {
        get {
            guard let data = thinkingBlocksData else { return nil }
            return try? JSONDecoder().decode([ThinkingBlock].self, from: data)
        }
        set {
            thinkingBlocksData = try? JSONEncoder().encode(newValue)
        }
    }

    var children: [UUID] {
        get {
            guard let data = childrenIds else { return [] }
            return (try? JSONDecoder().decode([UUID].self, from: data)) ?? []
        }
        set {
            childrenIds = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - Persisted Thread (SPM)

final class SDChatThread: Codable, Identifiable {
    var threadId: UUID
    var name: String?
    var rootMessageId: UUID
    var createdAt: Date
    var updatedAt: Date
    var isActive: Bool
    var color: String?

    var id: UUID { threadId }

    init(
        threadId: UUID = UUID(),
        name: String? = nil,
        rootMessageId: UUID,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isActive: Bool = true,
        color: String? = nil
    ) {
        self.threadId = threadId
        self.name = name
        self.rootMessageId = rootMessageId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
        self.color = color
    }
}

// MARK: - Persisted Branch (SPM)

final class SDChatBranch: Codable, Identifiable {
    var branchId: UUID
    var name: String
    var parentMessageId: UUID
    var branchPointMessageId: UUID
    var createdAt: Date
    var isActive: Bool

    var id: UUID { branchId }

    init(
        branchId: UUID = UUID(),
        name: String,
        parentMessageId: UUID,
        branchPointMessageId: UUID,
        createdAt: Date = Date(),
        isActive: Bool = true
    ) {
        self.branchId = branchId
        self.name = name
        self.parentMessageId = parentMessageId
        self.branchPointMessageId = branchPointMessageId
        self.createdAt = createdAt
        self.isActive = isActive
    }
}

// MARK: - Persisted Project (SPM)

final class SDProject: Codable, Identifiable {
    var projectId: UUID
    var name: String
    var path: String
    var lastOpened: Date
    var skillIds: Data?
    var soulScope: String?

    var id: UUID { projectId }

    init(
        projectId: UUID = UUID(),
        name: String,
        path: String,
        lastOpened: Date = Date()
    ) {
        self.projectId = projectId
        self.name = name
        self.path = path
        self.lastOpened = lastOpened
    }
}

// MARK: - Persisted Memory Entry (SPM)

final class SDMemoryEntry: Codable, Identifiable {
    var entryId: UUID
    var conversationId: String
    var timestamp: String
    var text: String
    var vectorData: Data?

    var id: UUID { entryId }

    init(
        entryId: UUID = UUID(),
        conversationId: String,
        timestamp: String,
        text: String,
        vectorData: Data? = nil
    ) {
        self.entryId = entryId
        self.conversationId = conversationId
        self.timestamp = timestamp
        self.text = text
        self.vectorData = vectorData
    }

    var vector: [Double]? {
        get {
            guard let data = vectorData else { return nil }
            return try? JSONDecoder().decode([Double].self, from: data)
        }
        set {
            vectorData = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - Conversion: Legacy ↔ SPM Models

extension SDConversation {
    convenience init(from legacy: Conversation) {
        self.init(
            conversationId: legacy.id,
            title: legacy.title,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt,
            isPinned: false,
            viewMode: legacy.viewMode.rawValue
        )
        self.activeThreadId = legacy.activeThreadId
    }

    func toLegacy() -> Conversation {
        let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
        var conv = Conversation(
            id: conversationId,
            title: title,
            messages: sortedMessages.map { $0.toLegacy() },
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        conv.threads = threads.map { $0.toLegacy() }
        conv.branches = branches.map { $0.toLegacy() }
        conv.activeThreadId = activeThreadId
        conv.viewMode = Conversation.ConversationViewMode(rawValue: viewMode) ?? .linear
        return conv
    }
}

extension SDMessage {
    convenience init(from legacy: Message) {
        self.init(
            messageId: legacy.id,
            role: legacy.role.rawValue,
            content: legacy.content,
            timestamp: legacy.timestamp,
            toolCallId: legacy.toolCallId,
            toolCallsData: {
                guard let tc = legacy.toolCalls else { return nil }
                return try? JSONEncoder().encode(tc)
            }(),
            thinkingBlocksData: {
                guard let tb = legacy.thinkingBlocks else { return nil }
                return try? JSONEncoder().encode(tb)
            }(),
            parentMessageId: legacy.parentMessageId,
            branchId: legacy.branchId,
            threadId: legacy.threadId,
            isBranch: legacy.isBranch,
            branchName: legacy.branchName
        )
    }

    func toLegacy() -> Message {
        var msg = Message(
            id: messageId,
            role: Message.Role(rawValue: role) ?? .user,
            content: content,
            timestamp: timestamp,
            toolCallId: toolCallId,
            toolCalls: toolCalls,
            thinkingBlocks: thinkingBlocks
        )
        msg.parentMessageId = parentMessageId
        msg.branchId = branchId
        msg.threadId = threadId
        msg.isBranch = isBranch
        msg.branchName = branchName
        msg.children = children
        return msg
    }
}

extension SDChatThread {
    convenience init(from legacy: MessageThread) {
        self.init(
            threadId: legacy.id,
            name: legacy.name,
            rootMessageId: legacy.rootMessageId,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt,
            isActive: legacy.isActive,
            color: legacy.color
        )
    }

    func toLegacy() -> MessageThread {
        var thread = MessageThread(id: threadId, name: name, rootMessageId: rootMessageId)
        thread.createdAt = createdAt
        thread.updatedAt = updatedAt
        thread.isActive = isActive
        thread.color = color
        return thread
    }
}

extension SDChatBranch {
    convenience init(from legacy: MessageBranch) {
        self.init(
            branchId: legacy.id,
            name: legacy.name,
            parentMessageId: legacy.parentMessageId,
            branchPointMessageId: legacy.branchPointMessageId,
            createdAt: legacy.createdAt,
            isActive: legacy.isActive
        )
    }

    func toLegacy() -> MessageBranch {
        var branch = MessageBranch(
            id: branchId,
            name: name,
            parentMessageId: parentMessageId,
            branchPointMessageId: branchPointMessageId
        )
        branch.createdAt = createdAt
        branch.isActive = isActive
        return branch
    }
}

// MARK: - File-Based Persistence Store (SPM)

@MainActor
final class GRumpPersistenceStore: ObservableObject {
    static let shared = GRumpPersistenceStore()

    @Published var conversations: [SDConversation] = []

    private let storeURL: URL

    private init() {
        // Application Support is guaranteed on macOS/iOS, but avoid force unwrap for safety.
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        let grumpDir = appSupport.appendingPathComponent("GRump", isDirectory: true)
        try? FileManager.default.createDirectory(at: grumpDir, withIntermediateDirectories: true)
        storeURL = grumpDir.appendingPathComponent("swiftdata_store.json")
        loadAll()
    }

    func save(_ conversation: SDConversation) {
        if let idx = conversations.firstIndex(where: { $0.conversationId == conversation.conversationId }) {
            conversations[idx] = conversation
        } else {
            conversations.append(conversation)
        }
        persistAll()
    }

    func delete(_ conversationId: UUID) {
        conversations.removeAll { $0.conversationId == conversationId }
        persistAll()
    }

    func fetch(id: UUID) -> SDConversation? {
        conversations.first { $0.conversationId == id }
    }

    private func persistAll() {
        do {
            let data = try JSONEncoder().encode(conversations)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            GRumpLogger.persistence.error("Save failed: \(error.localizedDescription)")
        }
    }

    private func loadAll() {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return }
        do {
            let data = try Data(contentsOf: storeURL)
            conversations = try JSONDecoder().decode([SDConversation].self, from: data)
        } catch {
            GRumpLogger.persistence.error("Load failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Migrator (SPM)

enum SwiftDataMigrator {
    private static let migrationKey = "SwiftDataMigrationComplete_v1"

    static var hasMigrated: Bool {
        UserDefaults.standard.bool(forKey: migrationKey)
    }

    @MainActor
    static func migrateIfNeeded(context: Any) {
        guard !hasMigrated else { return }

        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        let jsonURL = appSupport
            .appendingPathComponent("GRump", isDirectory: true)
            .appendingPathComponent("conversations.json")

        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        do {
            let data = try Data(contentsOf: jsonURL)
            let legacyConversations = try JSONDecoder().decode([Conversation].self, from: data)
            let store = GRumpPersistenceStore.shared

            for legacy in legacyConversations {
                let sdConv = SDConversation(from: legacy)
                for msg in legacy.messages {
                    sdConv.messages.append(SDMessage(from: msg))
                }
                for thread in legacy.threads {
                    sdConv.threads.append(SDChatThread(from: thread))
                }
                for branch in legacy.branches {
                    sdConv.branches.append(SDChatBranch(from: branch))
                }
                store.save(sdConv)
            }

            UserDefaults.standard.set(true, forKey: migrationKey)
            GRumpLogger.migration.info("Migrated \(legacyConversations.count) conversations from JSON")
        } catch {
            GRumpLogger.migration.error("Migration failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Configuration Stub (SPM)

enum SwiftDataConfiguration {
    // Under SPM, GRumpPersistenceStore handles persistence.
    // No ModelContainer needed.
}

#endif
