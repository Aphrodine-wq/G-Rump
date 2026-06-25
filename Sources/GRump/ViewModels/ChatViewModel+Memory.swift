import Foundation

// MARK: - ChatViewModel Memory Integration
//
// Extension that hooks the AdvancedMemoryStore and MemoryGraph into the
// conversation lifecycle:
//   1. Before each agent loop — retrieve relevant memories for prompt injection
//   2. After each assistant turn — extract and store key facts
//   3. On conversation switch — clear session tier
//   4. On project change — re-open DB connections

extension ChatViewModel {

    // MARK: - Memory Store Access

    /// Shared advanced memory store instance. Lazily initialized on first access.
    var advancedMemory: AdvancedMemoryStore {
        if _advancedMemory == nil {
            let store = AdvancedMemoryStore(projectDirectory: workingDirectory)
            Task { await store.open() }
            _advancedMemory = store
        }
        return _advancedMemory!
    }

    /// Shared memory graph instance. Lazily initialized alongside the memory store.
    var memoryGraph: MemoryGraph {
        if _memoryGraph == nil {
            let graph = MemoryGraph(projectDirectory: workingDirectory)
            Task { await graph.open() }
            _memoryGraph = graph
        }
        return _memoryGraph!
    }

    // MARK: - Prompt Injection

    /// Retrieve relevant memories and build a context block for system prompt injection.
    /// Called before `runAgentLoop()` to augment the prompt with recalled knowledge.
    func buildMemoryContextBlock() async -> String? {
        let enabled = UserDefaults.standard.object(forKey: "ProjectMemoryEnabled") as? Bool ?? true
        guard enabled, !workingDirectory.isEmpty else { return nil }

        let queryText = currentConversation?.messages.last(where: { $0.role == .user })?.content ?? ""
        guard !queryText.isEmpty else { return nil }

        let store = advancedMemory

        // Determine how many memories to inject based on model context window
        let topK = resolveMemoryTopK()

        // Hybrid search across all tiers
        let results = await store.search(query: queryText, topK: topK)
        guard !results.isEmpty else {
            // Fallback to legacy stores
            return legacyMemoryBlock(query: queryText)
        }

        // Deduplicate against current conversation history
        let conversationContent = (currentConversation?.messages ?? []).map(\.content).joined(separator: " ")
        let filtered = results.filter { result in
            // Skip if the memory content is already substantially present in the conversation
            !isSubstantialOverlap(memory: result.entry.content, conversation: conversationContent)
        }

        guard !filtered.isEmpty else { return nil }

        var block = "\n\n## Memory Context\nRetrieved from persistent memory (hybrid vector + keyword search):\n"
        for r in filtered {
            let tierLabel = r.entry.tier.rawValue.capitalized
            block += "\n---\n[\(tierLabel)] [relevance: \(String(format: "%.0f%%", r.score * 100))]\n\(r.entry.content)"
        }
        return block
    }

    // MARK: - Post-Turn Memory Storage

    /// Extract key facts from the latest assistant turn and store them.
    /// Called after each assistant response completes.
    func saveToAdvancedMemory() async {
        let enabled = UserDefaults.standard.object(forKey: "ProjectMemoryEnabled") as? Bool ?? true
        guard enabled, !workingDirectory.isEmpty else { return }

        let msgs = currentConversation?.messages ?? []
        guard let lastAssistant = msgs.last(where: { $0.role == .assistant }),
              let lastUser = msgs.last(where: { $0.role == .user }) else { return }

        let toolSummary = buildToolCallSummary(from: msgs)
        let convId = currentConversation?.id.uuidString ?? ""

        let store = advancedMemory
        let graph = memoryGraph

        // Store in advanced memory
        await store.addFromConversation(
            conversationId: convId,
            userMessage: lastUser.content,
            assistantContent: lastAssistant.content,
            toolCallSummary: toolSummary
        )

        // Extract entities and store graph relationships
        let combinedContent = "User: \(lastUser.content)\nAssistant: \(lastAssistant.content)"
        await graph.extractAndStore(from: combinedContent)

        // Also store in session tier for current conversation context
        let sessionContent = "Q: \(String(lastUser.content.prefix(150)))\nA: \(String(lastAssistant.content.prefix(300)))"
        await store.addEntry(
            tier: .session,
            content: sessionContent,
            conversationId: convId
        )

        // Periodic consolidation check
        await store.consolidateIfNeeded(tier: .project)

        // Vault brain write-back: human-readable daily notes + decision notes + backlinks.
        if BrainConfigStore.shared.load().vaultEnabled {
            await VaultWriteBack.shared.record(
                userMessage: lastUser.content,
                assistantContent: lastAssistant.content,
                workingDirectory: workingDirectory,
                graph: graph
            )
        }
    }

    // MARK: - Conversation Lifecycle

    /// Clear session-tier memories when switching conversations.
    func clearSessionMemory() async {
        await advancedMemory.clearSession()
    }

    /// Re-open memory stores when the working directory changes.
    func reopenMemoryStores() {
        _advancedMemory = nil
        _memoryGraph = nil
        // They'll be lazily re-created with the new workingDirectory
    }

    // MARK: - Memory-Enhanced Prompt Building

    /// Replace the legacy `appendProjectMemory` with advanced memory retrieval.
    /// This is called from `effectiveAgentConfig()` in the main ChatViewModel.
    func appendAdvancedMemory(to prompt: inout String) {
        let enabled = UserDefaults.standard.object(forKey: "ProjectMemoryEnabled") as? Bool ?? true
        guard enabled, !workingDirectory.isEmpty else { return }

        // Use a synchronous fallback since effectiveAgentConfig is sync
        // The async buildMemoryContextBlock() is preferred when called from streaming
        let queryText = currentConversation?.messages.last(where: { $0.role == .user })?.content ?? ""
        guard !queryText.isEmpty else { return }

        // Fallback to legacy for sync context
        if let block = legacyMemoryBlock(query: queryText) {
            prompt += block
        }
    }

    // MARK: - Private Helpers

    /// Determine the number of memories to inject based on model context window.
    private func resolveMemoryTopK() -> Int {
        if let model = currentEnhancedModel {
            let contextWindow = model.contextWindow
            if contextWindow >= 200_000 { return 8 }
            if contextWindow >= 100_000 { return 6 }
            if contextWindow >= 32_000 { return 5 }
            return 3
        }
        return 5
    }

    /// Check if memory content substantially overlaps with conversation history.
    private func isSubstantialOverlap(memory: String, conversation: String) -> Bool {
        let memoryWords = Set(memory.lowercased().split(separator: " ").map(String.init))
        guard memoryWords.count >= 5 else { return false }

        let convWords = Set(conversation.lowercased().split(separator: " ").map(String.init))
        let overlap = memoryWords.intersection(convWords)
        let overlapRatio = Float(overlap.count) / Float(memoryWords.count)
        return overlapRatio > 0.8
    }

    /// Legacy memory block retrieval for backward compatibility.
    private func legacyMemoryBlock(query: String) -> String? {
        guard !workingDirectory.isEmpty else { return nil }

        let semanticEnabled = UserDefaults.standard.object(forKey: "SemanticMemoryEnabled") as? Bool ?? true
        if semanticEnabled {
            let semanticStore = SemanticMemoryStore(baseDirectory: workingDirectory)
            if let block = semanticStore.relevantMemoryBlock(for: query) {
                return block
            }
        }

        let plainStore = MemoryStore(baseDirectory: workingDirectory)
        let entries = plainStore.recentEntries(limit: 5)
        guard !entries.isEmpty else { return nil }
        var block = "\n\n## Project Memory\nRecent context from past conversations:\n"
        for e in entries {
            block += "\n---\n[\(e.timestamp)]\n\(e.content)"
        }
        return block
    }
}

// MARK: - Stored Properties via Associated Objects

// Swift extensions can't add stored properties directly.
// Use a lightweight wrapper to hold the actor references.

private var _advancedMemoryKey: UInt8 = 0
private var _memoryGraphKey: UInt8 = 0

extension ChatViewModel {
    fileprivate var _advancedMemory: AdvancedMemoryStore? {
        get { objc_getAssociatedObject(self, &_advancedMemoryKey) as? AdvancedMemoryStore }
        set { objc_setAssociatedObject(self, &_advancedMemoryKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    fileprivate var _memoryGraph: MemoryGraph? {
        get { objc_getAssociatedObject(self, &_memoryGraphKey) as? MemoryGraph }
        set { objc_setAssociatedObject(self, &_memoryGraphKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
