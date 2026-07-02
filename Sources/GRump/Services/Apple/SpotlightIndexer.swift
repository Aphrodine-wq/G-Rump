import Foundation
#if os(macOS)
import CoreSpotlight
import UniformTypeIdentifiers
#endif

// MARK: - Spotlight Indexer + Handoff
//
// Deep macOS integration: indexes every G-Rump conversation into Spotlight
// so users can find past coding sessions from Spotlight search, Finder, or
// Siri. Also creates NSUserActivity for Handoff between devices.
//
// Activity types registered in Info.plist:
//   com.grump.conversation  — viewing/editing a conversation
//   com.grump.agentTask     — running an agent task

// MARK: - Constants

enum GRumpActivityType {
    static let conversation = "com.grump.conversation"
    static let agentTask = "com.grump.agentTask"
    static let spotlightDomain = "com.grump.conversations"
}

// MARK: - Spotlight Indexer

@MainActor
final class SpotlightIndexer {

    static let shared = SpotlightIndexer()

    private init() {}

    // MARK: - Index a Single Conversation

    /// Index or update a conversation in Spotlight.
    func indexConversation(_ conversation: Conversation) {
        #if os(macOS)
        // Check if Spotlight indexing is available (may fail in command-line builds)
        guard CSSearchableIndex.isIndexingAvailable() else {
            GRumpLogger.spotlight.info("Indexing not available")
            return
        }

        let id = conversation.id.uuidString
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = conversation.title
        attributeSet.contentDescription = conversationPreview(conversation)
        attributeSet.identifier = id
        attributeSet.relatedUniqueIdentifier = id
        attributeSet.contentCreationDate = conversation.createdAt
        attributeSet.contentModificationDate = conversation.updatedAt
        attributeSet.creator = "G-Rump"

        // Add keywords from message content for better search
        let keywords = extractKeywords(from: conversation)
        attributeSet.keywords = keywords

        // Message count as additional metadata
        let messageCount = conversation.messages.filter { $0.role != .system }.count
        attributeSet.comment = "\(messageCount) messages"

        let item = CSSearchableItem(
            uniqueIdentifier: id,
            domainIdentifier: GRumpActivityType.spotlightDomain,
            attributeSet: attributeSet
        )
        // Keep indexed for 90 days
        item.expirationDate = Calendar.current.date(byAdding: .day, value: 90, to: Date())

        Task.detached(priority: .utility) {
            do {
                try await CSSearchableIndex.default().indexSearchableItems([item])
            } catch {
                GRumpLogger.spotlight.error("Index error: \(error.localizedDescription)")
            }
        }
        #endif
    }

    // MARK: - Index All Conversations

    /// Bulk-index all conversations. Call on launch or after import.
    func indexAllConversations(_ conversations: [Conversation]) {
        #if os(macOS)
        // Check if Spotlight indexing is available (may fail in command-line builds)
        guard CSSearchableIndex.isIndexingAvailable() else {
            GRumpLogger.spotlight.info("Indexing not available")
            return
        }

        let items: [CSSearchableItem] = conversations.map { conversation in
            let id = conversation.id.uuidString
            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            attributeSet.title = conversation.title
            attributeSet.contentDescription = conversationPreview(conversation)
            attributeSet.identifier = id
            attributeSet.relatedUniqueIdentifier = id
            attributeSet.contentCreationDate = conversation.createdAt
            attributeSet.contentModificationDate = conversation.updatedAt
            attributeSet.creator = "G-Rump"
            attributeSet.keywords = extractKeywords(from: conversation)

            let messageCount = conversation.messages.filter { $0.role != .system }.count
            attributeSet.comment = "\(messageCount) messages"

            let item = CSSearchableItem(
                uniqueIdentifier: id,
                domainIdentifier: GRumpActivityType.spotlightDomain,
                attributeSet: attributeSet
            )
            item.expirationDate = Calendar.current.date(byAdding: .day, value: 90, to: Date())
            return item
        }

        do {
            try CSSearchableIndex.default().indexSearchableItems(items)
            GRumpLogger.spotlight.info("Indexed \(items.count) conversations")
        } catch {
            GRumpLogger.spotlight.error("Bulk index error: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Remove from Index

    /// Remove a conversation from Spotlight when deleted.
    func deindexConversation(_ conversationId: UUID) {
        #if os(macOS)
        CSSearchableIndex.default().deleteSearchableItems(
            withIdentifiers: [conversationId.uuidString]
        ) { error in
            if let error {
                GRumpLogger.spotlight.error("Deindex error: \(error.localizedDescription)")
            }
        }
        #endif
    }

    /// Remove all G-Rump items from Spotlight index.
    func deindexAll() {
        #if os(macOS)
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [GRumpActivityType.spotlightDomain]
        ) { error in
            if let error {
                GRumpLogger.spotlight.error("Deindex all error: \(error.localizedDescription)")
            }
        }
        #endif
    }

    // MARK: - Handle Spotlight Selection

    /// Parse a Spotlight continuation activity and return the conversation UUID.
    static func conversationId(from userActivity: NSUserActivity) -> UUID? {
        // From Spotlight search result
        #if os(macOS)
        if userActivity.activityType == CSSearchableItemActionType,
           let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
            return UUID(uuidString: identifier)
        }
        #endif
        // From Handoff activity
        if userActivity.activityType == GRumpActivityType.conversation,
           let idString = userActivity.userInfo?["conversationId"] as? String {
            return UUID(uuidString: idString)
        }
        return nil
    }

    // MARK: - Private Helpers

    private func conversationPreview(_ conversation: Conversation) -> String {
        let userMessages = conversation.messages
            .filter { $0.role == .user }
            .prefix(3)
            .map { String($0.content.prefix(200)) }
        return userMessages.joined(separator: " · ")
    }

    private func extractKeywords(from conversation: Conversation) -> [String] {
        var keywords: [String] = ["G-Rump", "AI", "coding"]

        // Extract notable words from user messages
        let allUserText = conversation.messages
            .filter { $0.role == .user }
            .map { $0.content }
            .joined(separator: " ")

        // Pick out programming-related terms
        let codeTerms = [
            "swift", "swiftui", "xcode", "ios", "macos", "api", "bug", "fix",
            "test", "build", "deploy", "refactor", "error", "crash", "debug",
            "feature", "migration", "database", "server", "client", "auth",
            "ui", "ux", "design", "performance", "memory", "network", "security",
            "python", "javascript", "typescript", "react", "node", "docker",
            "git", "github", "ci", "cd", "kubernetes", "aws", "firebase"
        ]

        let lowered = allUserText.lowercased()
        for term in codeTerms {
            if lowered.contains(term) {
                keywords.append(term)
            }
        }

        // Add words from the title
        let titleWords = conversation.title
            .components(separatedBy: .alphanumerics.inverted)
            .filter { $0.count > 2 }
        keywords.append(contentsOf: titleWords.prefix(5))

        return Array(Set(keywords)).sorted()
    }
}

// MARK: - Handoff Activity Builder

enum HandoffActivityBuilder {

    /// Create an NSUserActivity for the current conversation (Handoff).
    static func makeConversationActivity(
        conversation: Conversation,
        workingDirectory: String? = nil
    ) -> NSUserActivity {
        let activity = NSUserActivity(activityType: GRumpActivityType.conversation)
        activity.title = "G-Rump: \(conversation.title)"
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        #if os(iOS)
        activity.isEligibleForPrediction = true
        #endif

        // Searchable attributes
        #if os(macOS)
        let attributes = CSSearchableItemAttributeSet(contentType: .text)
        attributes.title = conversation.title
        let preview = conversation.messages
            .filter { $0.role == .user }
            .prefix(2)
            .map { String($0.content.prefix(150)) }
            .joined(separator: " · ")
        attributes.contentDescription = preview
        attributes.creator = "G-Rump"
        activity.contentAttributeSet = attributes
        #endif

        // UserInfo for continuing on another device
        var userInfo: [String: Any] = [
            "conversationId": conversation.id.uuidString,
            "title": conversation.title
        ]
        if let wd = workingDirectory, !wd.isEmpty {
            userInfo["workingDirectory"] = wd
        }
        activity.userInfo = userInfo

        // Required keys for Handoff
        activity.requiredUserInfoKeys = ["conversationId"]

        return activity
    }

    /// Create an NSUserActivity for a running agent task.
    static func makeAgentTaskActivity(
        conversation: Conversation,
        taskDescription: String,
        currentStep: Int?,
        totalSteps: Int?
    ) -> NSUserActivity {
        let activity = NSUserActivity(activityType: GRumpActivityType.agentTask)
        activity.title = "G-Rump Agent: \(taskDescription)"
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = false

        var userInfo: [String: Any] = [
            "conversationId": conversation.id.uuidString,
            "taskDescription": taskDescription
        ]
        if let step = currentStep { userInfo["currentStep"] = step }
        if let total = totalSteps { userInfo["totalSteps"] = total }
        activity.userInfo = userInfo
        activity.requiredUserInfoKeys = ["conversationId"]

        return activity
    }
}
