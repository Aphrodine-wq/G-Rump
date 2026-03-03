import Foundation
import SwiftUI
import UniformTypeIdentifiers
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
#if os(macOS)
import AppKit
#endif

// MARK: - Writing Tools Integration
//
// Integrates with Apple's Writing Tools for enhanced text generation
// including commit messages, documentation, and code comments.
//

@MainActor
final class WritingToolsService: ObservableObject {
    
    static let shared = WritingToolsService()
    
    @Published var isWritingToolsAvailable = false
    @Published var isProcessing = false
    @Published var suggestions: [WritingSuggestion] = []
    @Published var currentContext: WritingContext?
    
    private let nlpService = AppleIntelligenceService.shared
    
    private init() {
        checkWritingToolsAvailability()
    }
    
    // MARK: - Availability Check
    
    private func checkWritingToolsAvailability() {
        // Writing Tools uses OpenRouter for AI generation — available on all supported platforms.
        // NaturalLanguage framework used for suggestions is available on macOS 14+ / iOS 17+.
        let hasAPIKey = !(UserDefaults.standard.string(forKey: "openRouterAPIKey") ?? "").isEmpty
        let hasModel = !(UserDefaults.standard.string(forKey: "SelectedModel") ?? "").isEmpty
        isWritingToolsAvailable = hasAPIKey && hasModel
    }

    /// Re-check availability when API settings change (call from Settings).
    func refreshAvailability() {
        checkWritingToolsAvailability()
    }
    
    // MARK: - Text Generation
    
    /// Generate commit message based on changes
    func generateCommitMessage(for changes: [WritingGitChange], style: CommitMessageStyle = .conventional) async throws -> String {
        guard isWritingToolsAvailable else {
            throw WritingToolsError.notAvailable
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Analyze changes
        let changeSummary = analyzeChanges(changes)
        
        // Generate commit message
        let prompt = createCommitMessagePrompt(changes: changeSummary, style: style)
        let suggestion = try await generateText(prompt: prompt, context: .commitMessage)
        
        return suggestion.text
    }
    
    /// Generate documentation for code
    func generateDocumentation(for code: String, language: String, type: DocumentationType) async throws -> String {
        guard isWritingToolsAvailable else {
            throw WritingToolsError.notAvailable
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Analyze code structure
        let codeAnalysis = try await nlpService.analyzeCodeStructure(code, language: language)
        
        // Generate documentation
        let prompt = createDocumentationPrompt(code: code, analysis: codeAnalysis, type: type)
        let suggestion = try await generateText(prompt: prompt, context: .documentation)
        
        return suggestion.text
    }
    
    /// Generate or improve code comments
    func generateComments(for code: String, language: String, style: CommentStyle = .docString) async throws -> String {
        guard isWritingToolsAvailable else {
            throw WritingToolsError.notAvailable
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Analyze code
        let codeAnalysis = try await nlpService.analyzeCodeStructure(code, language: language)
        
        // Generate comments
        let prompt = createCommentsPrompt(code: code, analysis: codeAnalysis, style: style)
        let suggestion = try await generateText(prompt: prompt, context: .codeComments)
        
        return suggestion.text
    }
    
    /// Improve existing text
    func improveText(_ text: String, improvement: TextImprovement) async throws -> String {
        guard isWritingToolsAvailable else {
            throw WritingToolsError.notAvailable
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = createImprovementPrompt(text: text, improvement: improvement)
        let suggestion = try await generateText(prompt: prompt, context: .textImprovement)
        
        return suggestion.text
    }
    
    /// Generate release notes
    func generateReleaseNotes(for version: String, changes: [String]) async throws -> String {
        guard isWritingToolsAvailable else {
            throw WritingToolsError.notAvailable
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = createReleaseNotesPrompt(version: version, changes: changes)
        let suggestion = try await generateText(prompt: prompt, context: .releaseNotes)
        
        return suggestion.text
    }
    
    /// Generate API documentation
    func generateAPIDocumentation(for endpoint: APIEndpoint) async throws -> String {
        guard isWritingToolsAvailable else {
            throw WritingToolsError.notAvailable
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        let prompt = createAPIDocumentationPrompt(endpoint: endpoint)
        let suggestion = try await generateText(prompt: prompt, context: .apiDocumentation)
        
        return suggestion.text
    }
    
    // MARK: - Smart Suggestions
    
    /// Get real-time writing suggestions as user types
    func getSuggestions(for text: String, context: WritingContext) async -> [WritingSuggestion] {
        guard isWritingToolsAvailable else { return [] }
        
        // Analyze text and context
        _ = await analyzeTextContext(text, context: context)
        
        // Generate suggestions based on analysis
        var suggestions: [WritingSuggestion] = []
        
        // Grammar and style suggestions
        if let grammarSuggestions = await getGrammarSuggestions(text) {
            suggestions.append(contentsOf: grammarSuggestions)
        }
        
        // Completion suggestions
        if let completionSuggestions = await getCompletionSuggestions(text, context: context) {
            suggestions.append(contentsOf: completionSuggestions)
        }
        
        // Tone and style adjustments
        if let toneSuggestions = await getToneSuggestions(text, context: context) {
            suggestions.append(contentsOf: toneSuggestions)
        }
        
        return suggestions
    }
    
    // MARK: - Private Implementation
    
    private func generateText(prompt: String, context: WritingContext) async throws -> WritingSuggestion {
        // Read API key and model from the same AppStorage the chat system uses
        let apiKey = UserDefaults.standard.string(forKey: "openRouterAPIKey") ?? ""
        let modelId = UserDefaults.standard.string(forKey: "SelectedModel") ?? ""

        guard !apiKey.isEmpty else {
            throw WritingToolsError.processingFailed("No API key configured. Set an API key in Settings to use Writing Tools.")
        }
        guard !modelId.isEmpty else {
            throw WritingToolsError.processingFailed("No AI model selected. Choose a model in Settings.")
        }

        let systemMsg = Message(role: .system, content: "You are a precise writing assistant. Respond only with the requested text, no explanations or preamble.")
        let userMsg = Message(role: .user, content: prompt)
        let messages = [systemMsg, userMsg]
        let service = OpenRouterService()
        let stream = service.streamMessage(messages: messages, apiKey: apiKey, model: modelId)

        var accumulated = ""
        do {
            for try await event in stream {
                switch event {
                case .text(let text):
                    accumulated += text
                case .done:
                    break
                case .toolCallDelta:
                    break
                }
            }
        } catch {
            GRumpLogger.ai.error("WritingTools generation failed: \(error.localizedDescription)")
            throw WritingToolsError.processingFailed(error.localizedDescription)
        }

        let text = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        return WritingSuggestion(
            text: text.isEmpty ? "No suggestion generated." : text,
            confidence: 0.9,
            context: context,
            timestamp: Date()
        )
    }
    
    private func analyzeChanges(_ changes: [WritingGitChange]) -> String {
        var summary = ""
        
        for change in changes {
            summary += "File: \(change.filePath)\n"
            summary += "Type: \(change.type)\n"
            if !change.additions.isEmpty {
                summary += "Additions: \(change.additions.count) lines\n"
            }
            if !change.deletions.isEmpty {
                summary += "Deletions: \(change.deletions.count) lines\n"
            }
            summary += "\n"
        }
        
        return summary
    }
    
    private func createCommitMessagePrompt(changes: String, style: CommitMessageStyle) -> String {
        switch style {
        case .conventional:
            return """
            Generate a conventional commit message for these changes:
            
            \(changes)
            
            Format: <type>(<scope>): <description>
            
            Types: feat, fix, docs, style, refactor, test, chore
            """
        case .simple:
            return """
            Generate a simple, clear commit message for these changes:
            
            \(changes)
            
            Keep it under 50 characters for the first line.
            """
        case .detailed:
            return """
            Generate a detailed commit message for these changes:
            
            \(changes)
            
            Include:
            - Clear title
            - Detailed description
            - Issue references if applicable
            """
        }
    }
    
    private func createDocumentationPrompt(code: String, analysis: CodeAnalysis, type: DocumentationType) -> String {
        switch type {
        case .readme:
            return """
            Generate a README.md for this code:
            
            Language: \(analysis.language)
            Purpose: \(analysis.purpose ?? "Unknown")
            
            Code:
            \(code)
            
            Include installation, usage, and examples.
            """
        case .api:
            return """
            Generate API documentation for this code:
            
            \(code)
            
            Include parameters, return values, and examples.
            """
        case .inline:
            return """
            Generate inline documentation for this code:
            
            \(code)
            
            Add appropriate doc comments.
            """
        }
    }
    
    private func createCommentsPrompt(code: String, analysis: CodeAnalysis, style: CommentStyle) -> String {
        switch style {
        case .docString:
            return """
            Add docstring comments to this code:
            
            \(code)
            
            Use standard docstring format for the language.
            """
        case .inline:
            return """
            Add inline comments to explain this code:
            
            \(code)
            
            Focus on complex logic and business rules.
            """
        case .summary:
            return """
            Add summary comments to major sections:
            
            \(code)
            
            Keep comments concise and clear.
            """
        }
    }
    
    private func createImprovementPrompt(text: String, improvement: TextImprovement) -> String {
        switch improvement {
        case .grammar:
            return "Fix grammar and spelling in: \(text)"
        case .clarity:
            return "Improve clarity and readability: \(text)"
        case .conciseness:
            return "Make this more concise: \(text)"
        case .formality:
            return "Adjust formality level: \(text)"
        case .tone:
            return "Adjust tone to be more professional: \(text)"
        }
    }
    
    private func createReleaseNotesPrompt(version: String, changes: [String]) -> String {
        return """
        Generate release notes for version \(version) with these changes:
        
        \(changes.joined(separator: "\n"))
        
        Format with sections: New Features, Improvements, Bug Fixes.
        """
    }
    
    private func createAPIDocumentationPrompt(endpoint: APIEndpoint) -> String {
        return """
        Generate API documentation for:
        
        Method: \(endpoint.method)
        Path: \(endpoint.path)
        Parameters: \(endpoint.parameters.map { "\($0.name): \($0.type)" }.joined(separator: ", "))
        
        Response: \(endpoint.responseType ?? "Unknown")
        
        Include examples and error codes.
        """
    }
    
    // MARK: - Suggestion Helpers
    
    private func analyzeTextContext(_ text: String, context: WritingContext) async -> TextContextAnalysis {
        // Analyze text context for better suggestions
        return TextContextAnalysis(
            language: detectLanguage(text),
            tone: await detectTone(text),
            complexity: calculateComplexity(text),
            domain: context.domain
        )
    }
    
    private func getGrammarSuggestions(_ text: String) async -> [WritingSuggestion]? {
        #if os(macOS)
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var issues: [WritingSuggestion] = []
        let checker = NSSpellChecker.shared
        let range = NSRange(text.startIndex..., in: text)
        var offset = 0
        while offset < range.length {
            let misspelledRange = checker.checkSpelling(of: text, startingAt: offset)
            if misspelledRange.location == NSNotFound { break }
            if let swiftRange = Range(misspelledRange, in: text) {
                let word = String(text[swiftRange])
                let guesses = checker.guesses(forWordRange: misspelledRange, in: text, language: nil, inSpellDocumentWithTag: 0) ?? []
                let suggestion = guesses.first.map { "'\(word)' → '\($0)'" } ?? "Check spelling of '\(word)'"
                issues.append(WritingSuggestion(
                    text: suggestion,
                    confidence: 0.9,
                    context: .textImprovement,
                    timestamp: Date()
                ))
            }
            offset = misspelledRange.location + misspelledRange.length
        }
        return issues.isEmpty ? nil : issues
        #else
        return nil
        #endif
    }
    
    private func getCompletionSuggestions(_ text: String, context: WritingContext) async -> [WritingSuggestion]? {
        #if canImport(NaturalLanguage)
        guard !text.isEmpty else { return nil }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        var lastWords: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if tag != nil { lastWords.append(String(text[range])) }
            return true
        }
        guard let lastWord = lastWords.last, lastWord.count >= 2 else { return nil }
        if let embedding = NLEmbedding.wordEmbedding(for: .english) {
            let neighbors = embedding.neighbors(for: lastWord.lowercased(), maximumCount: 3)
            let suggestions = neighbors.map { word, distance in
                WritingSuggestion(
                    text: word,
                    confidence: max(0, 1.0 - distance),
                    context: context,
                    timestamp: Date()
                )
            }
            return suggestions.isEmpty ? nil : suggestions
        }
        return nil
        #else
        return nil
        #endif
    }
    
    private func getToneSuggestions(_ text: String, context: WritingContext) async -> [WritingSuggestion]? {
        #if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        var sentimentScore: Double = 0
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .paragraph, scheme: .sentimentScore) { tag, _ in
            if let tag = tag, let score = Double(tag.rawValue) { sentimentScore = score }
            return true
        }
        if sentimentScore < -0.3 {
            return [WritingSuggestion(
                text: "Text has a negative tone (sentiment: \(String(format: "%.2f", sentimentScore))). Consider softening language.",
                confidence: abs(sentimentScore),
                context: context,
                timestamp: Date()
            )]
        } else if sentimentScore > 0.3 && context.type == .commitMessage {
            return [WritingSuggestion(
                text: "Commit messages are typically neutral. Consider a more factual tone.",
                confidence: sentimentScore,
                context: context,
                timestamp: Date()
            )]
        }
        return nil
        #else
        return nil
        #endif
    }
    
    private func detectLanguage(_ text: String) -> String {
        #if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue ?? "en"
        #else
        return "en"
        #endif
    }
    
    private func detectTone(_ text: String) async -> String {
        #if canImport(NaturalLanguage)
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        var score: Double = 0
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .paragraph, scheme: .sentimentScore) { tag, _ in
            if let tag = tag, let s = Double(tag.rawValue) { score = s }
            return true
        }
        if score > 0.3 { return "positive" }
        if score < -0.3 { return "negative" }
        return "neutral"
        #else
        return "neutral"
        #endif
    }
    
    private func calculateComplexity(_ text: String) -> Double {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !words.isEmpty, !sentences.isEmpty else { return 0 }
        let avgWordsPerSentence = Double(words.count) / Double(sentences.count)
        let avgWordLength = Double(words.reduce(0) { $0 + $1.count }) / Double(words.count)
        // Flesch-Kincaid-inspired: higher = more complex
        let complexity = (avgWordsPerSentence / 20.0) * 0.5 + (avgWordLength / 8.0) * 0.5
        return min(1.0, max(0.0, complexity))
    }
}

// MARK: - Data Models

struct WritingSuggestion: Identifiable, Codable {
    var id = UUID()
    let text: String
    let confidence: Double
    let context: WritingContext
    let timestamp: Date
}

struct WritingContext: Codable {
    let type: WritingType
    let domain: String
    let language: String
    let audience: Audience
    
    static let commitMessage = WritingContext(type: .commitMessage, domain: "development", language: "en", audience: .developers)
    static let documentation = WritingContext(type: .documentation, domain: "technical", language: "en", audience: .users)
    static let codeComments = WritingContext(type: .codeComments, domain: "development", language: "en", audience: .developers)
    static let textImprovement = WritingContext(type: .general, domain: "general", language: "en", audience: .general)
    static let releaseNotes = WritingContext(type: .releaseNotes, domain: "development", language: "en", audience: .users)
    static let apiDocumentation = WritingContext(type: .apiDocumentation, domain: "technical", language: "en", audience: .developers)
}

struct WritingGitChange {
    let filePath: String
    let type: WritingChangeType
    let additions: [String]
    let deletions: [String]
}

enum WritingChangeType {
    case added
    case modified
    case deleted
    case renamed
}

enum CommitMessageStyle {
    case conventional
    case simple
    case detailed
}

enum DocumentationType {
    case readme
    case api
    case inline
}

enum CommentStyle {
    case docString
    case inline
    case summary
}

enum TextImprovement {
    case grammar
    case clarity
    case conciseness
    case formality
    case tone
}

enum WritingType: String, Codable {
    case commitMessage
    case documentation
    case codeComments
    case general
    case releaseNotes
    case apiDocumentation
}

enum Audience: String, Codable {
    case developers
    case users
    case general
}

struct CodeAnalysis {
    let language: String
    let purpose: String?
    let complexity: Double
    let functions: [FunctionInfo]
    let classes: [ClassInfo]
}

struct FunctionInfo {
    let name: String
    let parameters: [ParameterInfo]
    let returnType: String
    let purpose: String?
}

struct ClassInfo {
    let name: String
    let properties: [PropertyInfo]
    let methods: [FunctionInfo]
    let purpose: String?
}

struct ParameterInfo {
    let name: String
    let type: String
    let purpose: String?
}

struct PropertyInfo {
    let name: String
    let type: String
    let purpose: String?
}

struct APIEndpoint {
    let method: String
    let path: String
    let parameters: [ParameterInfo]
    let responseType: String?
}

struct TextContextAnalysis {
    let language: String
    let tone: String
    let complexity: Double
    let domain: String
}

// MARK: - Errors

enum WritingToolsError: LocalizedError {
    case notAvailable
    case processingFailed(String)
    case contextNotSupported
    
    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Writing Tools are not available on this device"
        case .processingFailed(let message):
            return "Processing failed: \(message)"
        case .contextNotSupported:
            return "This writing context is not supported"
        }
    }
}

// MARK: - Code Analysis Extension

extension AppleIntelligenceService {
    /// Analyze code structure using regex-based parsing for function/class extraction.
    func analyzeCodeStructure(_ code: String, language: String) async throws -> CodeAnalysis {
        let lines = code.components(separatedBy: .newlines)
        let totalLines = Double(lines.count)

        let funcPattern = try? NSRegularExpression(pattern: #"(?:func|def|function|fn)\s+(\w+)\s*\(([^)]*)\)(?:\s*->\s*(\w+))?"#)
        var functions: [FunctionInfo] = []
        if let funcPattern {
            let nsCode = code as NSString
            let matches = funcPattern.matches(in: code, range: NSRange(location: 0, length: nsCode.length))
            for match in matches {
                let name = match.range(at: 1).location != NSNotFound ? nsCode.substring(with: match.range(at: 1)) : "unknown"
                let params = match.range(at: 2).location != NSNotFound ? nsCode.substring(with: match.range(at: 2)) : ""
                let ret = match.range(at: 3).location != NSNotFound ? nsCode.substring(with: match.range(at: 3)) : "Void"
                let paramList: [ParameterInfo] = params.isEmpty ? [] : params.components(separatedBy: ",").map { p in
                    let trimmed = p.trimmingCharacters(in: .whitespaces)
                    let parts = trimmed.components(separatedBy: ":")
                    return ParameterInfo(name: parts.first?.trimmingCharacters(in: .whitespaces) ?? trimmed, type: parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : "Any", purpose: nil)
                }
                functions.append(FunctionInfo(name: name, parameters: paramList, returnType: ret, purpose: nil))
            }
        }

        let classPattern = try? NSRegularExpression(pattern: #"(?:class|struct|enum|protocol)\s+(\w+)"#)
        var classes: [ClassInfo] = []
        if let classPattern {
            let nsCode = code as NSString
            let matches = classPattern.matches(in: code, range: NSRange(location: 0, length: nsCode.length))
            for match in matches {
                let name = match.range(at: 1).location != NSNotFound ? nsCode.substring(with: match.range(at: 1)) : "unknown"
                classes.append(ClassInfo(name: name, properties: [], methods: [], purpose: nil))
            }
        }

        let controlFlow = Set(["if", "else", "for", "while", "switch", "case", "guard", "catch", "try"])
        let tokens = code.components(separatedBy: .whitespacesAndNewlines)
        let controlCount = Double(tokens.filter { controlFlow.contains($0) }.count)
        let complexity = min(1.0, controlCount / max(1.0, totalLines) * 5.0)

        return CodeAnalysis(
            language: language,
            purpose: functions.isEmpty && classes.isEmpty ? "Script" : classes.isEmpty ? "Functional code" : "Object-oriented code",
            complexity: complexity,
            functions: functions,
            classes: classes
        )
    }
}
