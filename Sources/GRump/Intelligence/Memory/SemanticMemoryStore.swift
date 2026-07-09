import Foundation
import NaturalLanguage

// MARK: - Semantic Memory Store (On-Device RAG)
//
// Replaces the plain-text MemoryStore with real vector embeddings using Apple's
// NaturalLanguage framework. Fully on-device, zero API calls, works offline.
// Retrieves the most semantically relevant past memories via cosine similarity.

struct SemanticMemoryStore: ProjectMemoryStore {
    let baseDirectory: String

    private static let memoryDirName = "memory"
    private static let semanticFileName = "semantic.json"
    private static let maxEntries = 500
    private static let defaultTopK = 5
    private static let maxContentLength = 600

    init(baseDirectory: String) {
        self.baseDirectory = (baseDirectory as NSString).standardizingPath
    }

    // MARK: - Public API

    /// Embed and store a new memory entry after a conversation turn.
    func addEntry(conversationId: String, userMessage: String, assistantContent: String, toolCallSummary: String = "") {
        guard !baseDirectory.isEmpty else { return }
        let actionPart: String
        if !toolCallSummary.isEmpty {
            actionPart = "Actions: \(String(toolCallSummary.prefix(Self.maxContentLength)))"
        } else {
            actionPart = "Assistant: \(String(assistantContent.prefix(Self.maxContentLength)))"
        }
        let text = "User: \(String(userMessage.prefix(200)))\n\(actionPart)"
        guard let vector = embed(text) else { return }
        let entry = SemanticMemoryEntry(
            id: UUID(),
            conversationId: conversationId,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            text: text,
            vector: vector
        )
        var entries = loadEntries()
        entries.append(entry)
        // Prune oldest if over cap
        if entries.count > Self.maxEntries {
            entries = Array(entries.suffix(Self.maxEntries))
        }
        saveEntries(entries)
    }

    /// Retrieve the top-K most semantically relevant entries for a given query.
    func relevantEntries(for query: String, topK: Int = defaultTopK) -> [SemanticMemoryEntry] {
        guard !baseDirectory.isEmpty else { return [] }
        let entries = loadEntries()
        guard !entries.isEmpty else { return [] }
        guard let queryVector = embed(query) else {
            // Fallback: return most recent entries
            return Array(entries.suffix(topK).reversed())
        }
        let scored = entries.map { entry -> (SemanticMemoryEntry, Float) in
            let score = cosineSimilarity(queryVector, entry.vector)
            return (entry, score)
        }
        return scored
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { $0.0 }
    }

    /// Build a formatted block for injection into the system prompt.
    func relevantMemoryBlock(for query: String, topK: Int = defaultTopK) -> String? {
        let entries = relevantEntries(for: query, topK: topK)
        guard !entries.isEmpty else { return nil }
        var block = "\n\n## Relevant Past Context\nSemanticaly retrieved from previous conversations:\n"
        for e in entries {
            block += "\n---\n[\(e.timestamp)]\n\(e.text)"
        }
        return block
    }

    func retrieveEntries(query: String, limit: Int) -> [UnifiedMemoryEntry] {
        relevantEntries(for: query, topK: limit).map {
            UnifiedMemoryEntry(id: $0.id, conversationId: $0.conversationId, timestamp: $0.timestamp, content: $0.text)
        }
    }

    // MARK: - Cognitive recall + consolidation (Track 1: MemoryAgent)

    /// Recall the most valuable memories within a fixed token budget — ranked by
    /// relevance × recency × salience, not a flat top-K. This is the answer to
    /// "recall critical memories within a limited context window".
    func budgetedMemoryBlock(for query: String, tokenBudget: Int = CognitiveMemory.defaultTokenBudget) -> String? {
        guard !baseDirectory.isEmpty else { return nil }
        let entries = loadEntries()
        guard !entries.isEmpty, let queryVector = embed(query) else { return nil }
        let records = entries.map { $0.toRecord() }
        let recalled = CognitiveMemory.budgetedRecall(records, queryVector: queryVector, now: Date(), tokenBudget: tokenBudget)
        return CognitiveMemory.promptBlock(recalled)
    }

    /// "Sleep" pass: decay strengths, merge near-duplicates, and forget stale
    /// memories. Persists the surviving set. Returns what changed (for the
    /// daemon's consolidation log / demo). Safe to call periodically.
    @discardableResult
    func consolidate(now: Date = Date()) -> ConsolidationResult {
        let entries = loadEntries()
        let records = entries.map { $0.toRecord() }
        let result = CognitiveMemory.consolidate(records, now: now, maxEntries: Self.maxEntries)

        // Reconstruct surviving entries from the originals, carrying updated strength.
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        let iso = ISO8601DateFormatter()
        let survivors: [SemanticMemoryEntry] = result.kept.compactMap { rec in
            guard let original = byID[rec.id] else { return nil }
            return SemanticMemoryEntry(
                id: original.id, conversationId: original.conversationId,
                timestamp: original.timestamp, text: original.text, vector: original.vector,
                strength: rec.strength, lastAccess: iso.string(from: rec.lastAccess),
                accessCount: rec.accessCount
            )
        }
        saveEntries(survivors)
        return result
    }

    /// Total number of stored memory entries.
    func count() -> Int {
        loadEntries().count
    }

    /// Remove all stored entries.
    func clear() {
        saveEntries([])
    }

    // MARK: - Embedding

    /// Embed text using NLEmbedding (sentence-level via word vector averaging).
    /// Returns nil if the embedding model is unavailable.
    private func embed(_ text: String) -> [Float]? {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var vectors: [[Double]] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = String(text[range]).lowercased()
            if let vec = embedding.vector(for: word) {
                vectors.append(vec)
            }
            return true
        }
        guard !vectors.isEmpty else { return nil }
        let dim = vectors[0].count
        var avg = [Float](repeating: 0, count: dim)
        for vec in vectors {
            for i in 0..<dim {
                avg[i] += Float(vec[i])
            }
        }
        let count = Float(vectors.count)
        for i in 0..<dim { avg[i] /= count }
        return avg
    }

    // MARK: - Cosine Similarity

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    // MARK: - Persistence

    private var memoryDir: String {
        URL(fileURLWithPath: baseDirectory)
            .appendingPathComponent(".grump")
            .appendingPathComponent(Self.memoryDirName)
            .path
    }

    private var semanticURL: URL {
        URL(fileURLWithPath: memoryDir).appendingPathComponent(Self.semanticFileName)
    }

    private func loadEntries() -> [SemanticMemoryEntry] {
        guard FileManager.default.fileExists(atPath: semanticURL.path),
              let data = try? Data(contentsOf: semanticURL),
              let decoded = try? JSONDecoder().decode(SemanticMemoryFile.self, from: data) else {
            return []
        }
        return decoded.entries
    }

    private func saveEntries(_ entries: [SemanticMemoryEntry]) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: memoryDir) {
            try? fm.createDirectory(atPath: memoryDir, withIntermediateDirectories: true)
        }
        let file = SemanticMemoryFile(entries: entries)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: semanticURL)
        }
    }
}

// MARK: - Models

struct SemanticMemoryEntry: Codable {
    let id: UUID
    let conversationId: String
    let timestamp: String
    let text: String
    let vector: [Float]
    // Cognitive metadata (optional for backward-compatible decoding of old files).
    var strength: Double?
    var lastAccess: String?
    var accessCount: Int?

    init(id: UUID, conversationId: String, timestamp: String, text: String, vector: [Float],
         strength: Double? = 1.0, lastAccess: String? = nil, accessCount: Int? = 0) {
        self.id = id
        self.conversationId = conversationId
        self.timestamp = timestamp
        self.text = text
        self.vector = vector
        self.strength = strength
        self.lastAccess = lastAccess ?? timestamp
        self.accessCount = accessCount
    }

    /// Map to the storage-agnostic record used by CognitiveMemory.
    func toRecord() -> MemoryRecord {
        let iso = ISO8601DateFormatter()
        let created = iso.date(from: timestamp) ?? Date(timeIntervalSince1970: 0)
        let accessed = lastAccess.flatMap { iso.date(from: $0) } ?? created
        return MemoryRecord(
            id: id, conversationId: conversationId, timestamp: created, text: text,
            vector: vector, strength: strength ?? 1.0, lastAccess: accessed,
            accessCount: accessCount ?? 0
        )
    }
}

private struct SemanticMemoryFile: Codable {
    var entries: [SemanticMemoryEntry]
}
