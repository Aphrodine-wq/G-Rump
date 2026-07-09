import Foundation
import NaturalLanguage
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

// MARK: - Apple Intelligence Service
//
// Leverages Apple's on-device ML frameworks to provide intelligence
// features that run entirely locally — zero cloud, zero telemetry.
//
// Capabilities:
//   - NLEmbedding: semantic similarity for smarter memory retrieval
//   - NLTagger: code comment analysis, sentiment detection
//   - NLLanguageRecognizer: detect natural language of text
//   - Translation framework (macOS 15+): translate error messages, docs, comments
//   - Vision: OCR, image classification (tools already exist)
//   - Speech: transcription (tool already exists)
//
// This service acts as the bridge between Apple's ML stack and G-Rump's
// agent system, making the agent smarter with on-device intelligence.

// MARK: - Semantic Similarity Engine

@MainActor
final class AppleIntelligenceService: ObservableObject {

    static let shared = AppleIntelligenceService()

    @Published private(set) var embeddingModelLoaded: Bool = false
    @Published private(set) var availableCapabilities: [AICapability] = []

    enum AICapability: String, CaseIterable, Identifiable {
        case semanticEmbedding = "Semantic Embedding"
        case languageDetection = "Language Detection"
        case sentimentAnalysis = "Sentiment Analysis"
        case namedEntityRecognition = "Named Entities"
        case lemmatization = "Lemmatization"
        case tokenization = "Tokenization"
        case partOfSpeech = "Part of Speech"
        case translation = "Translation"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .semanticEmbedding: return "brain"
            case .languageDetection: return "globe"
            case .sentimentAnalysis: return "face.smiling"
            case .namedEntityRecognition: return "person.text.rectangle"
            case .lemmatization: return "textformat.abc"
            case .tokenization: return "text.word.spacing"
            case .partOfSpeech: return "text.badge.checkmark"
            case .translation: return "character.bubble"
            }
        }

        var isAvailable: Bool {
            switch self {
            case .semanticEmbedding:
                return NLEmbedding.sentenceEmbedding(for: .english) != nil
            case .languageDetection, .tokenization, .lemmatization, .partOfSpeech:
                return true
            case .sentimentAnalysis:
                return true // NLTagger supports sentiment on macOS 14+
            case .namedEntityRecognition:
                return true
            case .translation:
                // Translation framework availability check
                if #available(macOS 15.0, iOS 18.0, *) {
                    return true
                }
                return false
            }
        }
    }

    private var sentenceEmbedding: NLEmbedding?

    private init() {
        detectCapabilities()
        loadEmbedding()
    }

    // MARK: - Capability Detection

    private func detectCapabilities() {
        availableCapabilities = AICapability.allCases.filter { $0.isAvailable }
    }

    private func loadEmbedding() {
        sentenceEmbedding = NLEmbedding.sentenceEmbedding(for: .english)
        embeddingModelLoaded = sentenceEmbedding != nil
    }

    // MARK: - Semantic Embedding

    /// Get the embedding vector for a text string using Apple's NLEmbedding.
    /// Returns nil if embedding is not available.
    nonisolated func embed(_ text: String) -> [Double]? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        return embedding.vector(for: text)
    }

    /// Compute cosine similarity between two texts.
    nonisolated func similarity(between text1: String, and text2: String) -> Double? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        let distance = embedding.distance(between: text1, and: text2)
        // NLEmbedding.distance returns cosine distance (0 = identical, 2 = opposite)
        // Convert to similarity (1 = identical, -1 = opposite)
        return 1.0 - distance
    }

    /// Find the N most similar strings to a query from a list of candidates.
    nonisolated func findMostSimilar(
        query: String,
        candidates: [String],
        topK: Int = 5
    ) -> [(text: String, similarity: Double)] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return [] }

        var scored: [(String, Double)] = candidates.compactMap { candidate in
            let dist = embedding.distance(between: query, and: candidate)
            let sim = 1.0 - dist
            return (candidate, sim)
        }

        scored.sort { $0.1 > $1.1 }
        return Array(scored.prefix(topK))
    }

    // MARK: - Language Detection

    /// Detect the natural language of a text string.
    nonisolated func detectLanguage(_ text: String) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    /// Get language probabilities for a text string.
    nonisolated func languageProbabilities(_ text: String, max: Int = 5) -> [(NLLanguage, Double)] {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: max)
        return hypotheses.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    // MARK: - Sentiment Analysis

    /// Analyze sentiment of text. Returns a score from -1.0 (negative) to 1.0 (positive).
    nonisolated func analyzeSentiment(_ text: String) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        let (tag, _) = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore)
        return Double(tag?.rawValue ?? "0") ?? 0.0
    }

    /// Detect if a user message expresses frustration (negative sentiment).
    nonisolated func isUserFrustrated(_ text: String) -> Bool {
        let sentiment = analyzeSentiment(text)
        return sentiment < -0.3
    }

    // MARK: - Named Entity Recognition

    /// Extract named entities (people, places, organizations) from text.
    nonisolated func extractEntities(_ text: String) -> [(String, NLTag)] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text

        var entities: [(String, NLTag)] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]

        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag = tag, tag != .otherWord {
                entities.append((String(text[range]), tag))
            }
            return true
        }
        return entities
    }

    // MARK: - Tokenization & Lemmatization

    /// Tokenize text into words.
    nonisolated func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).map {
            String(text[$0])
        }
    }

    /// Lemmatize text (reduce words to base form).
    nonisolated func lemmatize(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        var lemmas: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma, options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            lemmas.append(tag?.rawValue ?? String(text[range]))
            return true
        }
        return lemmas
    }

    // MARK: - Smart Code Analysis

    /// Analyze a code comment or error message to extract actionable keywords.
    nonisolated func extractCodeKeywords(_ text: String) -> [String] {
        let tokens = tokenize(text.lowercased())
        let codeTerms = Set([
            "error", "warning", "fix", "bug", "crash", "null", "nil", "undefined",
            "exception", "timeout", "overflow", "leak", "deprecated", "missing",
            "invalid", "failed", "broken", "slow", "race", "deadlock", "segfault",
            "compile", "build", "test", "import", "export", "async", "await",
            "thread", "memory", "network", "auth", "permission", "access"
        ])
        return tokens.filter { codeTerms.contains($0) }
    }

    /// Classify the type of user request to help the agent choose strategy.
    nonisolated func classifyUserIntent(_ text: String) -> UserIntent {
        let lowered = text.lowercased()

        if lowered.contains("fix") || lowered.contains("bug") || lowered.contains("error") ||
           lowered.contains("crash") || lowered.contains("broken") || lowered.contains("not working") {
            return .debug
        }
        if lowered.contains("explain") || lowered.contains("what is") || lowered.contains("how does") ||
           lowered.contains("why") || lowered.contains("understand") {
            return .explain
        }
        if lowered.contains("create") || lowered.contains("build") || lowered.contains("make") ||
           lowered.contains("add") || lowered.contains("implement") || lowered.contains("write") {
            return .create
        }
        if lowered.contains("refactor") || lowered.contains("improve") || lowered.contains("optimize") ||
           lowered.contains("clean up") || lowered.contains("restructure") {
            return .refactor
        }
        if lowered.contains("test") || lowered.contains("spec") || lowered.contains("verify") {
            return .test
        }
        if lowered.contains("deploy") || lowered.contains("ship") || lowered.contains("release") ||
           lowered.contains("publish") {
            return .deploy
        }
        return .general
    }

    enum UserIntent: String {
        case debug = "Debug"
        case explain = "Explain"
        case create = "Create"
        case refactor = "Refactor"
        case test = "Test"
        case deploy = "Deploy"
        case general = "General"

        var suggestedMode: AgentMode {
            switch self {
            case .debug: return .fullStack
            case .explain: return .plan
            case .create: return .fullStack
            case .refactor: return .plan
            case .test: return .fullStack
            case .deploy: return .fullStack
            case .general: return .plan
            }
        }
    }

    // MARK: - Translation (macOS 15+ / iOS 18+)

    /// Check if Apple Translation framework is available.
    var isTranslationAvailable: Bool {
        if #available(macOS 15.0, iOS 18.0, *) {
            return true
        }
        return false
    }

    // MARK: - System ML Info

    /// Get a summary of available on-device ML capabilities.
    func capabilitySummary() -> String {
        let caps = availableCapabilities.map { "• \($0.rawValue)" }.joined(separator: "\n")
        let embeddingStatus = embeddingModelLoaded ? "Loaded" : "Not available"
        return """
        Apple Intelligence Capabilities:
        \(caps)

        Sentence Embedding: \(embeddingStatus)
        Total capabilities: \(availableCapabilities.count)/\(AICapability.allCases.count)
        """
    }
}
