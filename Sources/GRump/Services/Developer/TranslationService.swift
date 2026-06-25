import Foundation
import SwiftUI
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

// MARK: - Translation Service
//
// Integrates with Apple's Translation framework for real-time translation
// of comments, documentation, and error messages.
//

@MainActor
final class TranslationService: ObservableObject {

    static let shared = TranslationService()

    @Published var isTranslationAvailable = false
    @Published var supportedLanguages: [TranslationLanguage] = []
    @Published var currentSourceLanguage: TranslationLanguage = .auto
    @Published var currentTargetLanguage: TranslationLanguage = .english
    @Published var isTranslating = false
    @Published var translationHistory: [TranslationEntry] = []

    private let userDefaults = UserDefaults.standard
    private let historyKey = "TranslationHistory"

    private init() {
        checkTranslationAvailability()
        loadTranslationHistory()
        loadSavedPreferences()
    }

    // MARK: - Availability Check

    private func checkTranslationAvailability() {
        if #available(macOS 13.0, iOS 16.0, *) {
            isTranslationAvailable = true
            loadSupportedLanguages()
        } else {
            isTranslationAvailable = false
        }
    }

    private func loadSupportedLanguages() {
        // Load supported languages from Translation framework
        // For now, provide common languages
        supportedLanguages = [
            .auto, .english, .spanish, .french, .german, .italian,
            .portuguese, .russian, .chineseSimplified, .chineseTraditional,
            .japanese, .korean, .arabic, .hindi, .dutch, .swedish,
            .danish, .norwegian, .finnish, .polish, .czech, .hungarian,
            .romanian, .ukrainian, .greek, .turkish, .hebrew, .thai,
            .vietnamese, .indonesian, .malay, .tagalog
        ]
    }

    // MARK: - Translation Methods

    /// Translate text using Apple's Translation framework
    func translate(_ text: String, from source: TranslationLanguage? = nil, to target: TranslationLanguage? = nil) async throws -> String {
        guard isTranslationAvailable else {
            throw TranslationError.notAvailable
        }

        guard !text.isEmpty else {
            return ""
        }

        let sourceLanguage = source ?? currentSourceLanguage
        let targetLanguage = target ?? currentTargetLanguage

        // Don't translate if source and target are the same
        if sourceLanguage == targetLanguage && sourceLanguage != .auto {
            return text
        }

        isTranslating = true
        defer { isTranslating = false }

        // Perform translation
        let translatedText = try await performTranslation(
            text: text,
            source: sourceLanguage,
            target: targetLanguage
        )

        // Save to history
        let entry = TranslationEntry(
            originalText: text,
            translatedText: translatedText,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            timestamp: Date()
        )

        addToHistory(entry)

        return translatedText
    }

    /// Translate multiple texts in batch
    func translateBatch(_ texts: [String], from source: TranslationLanguage? = nil, to target: TranslationLanguage? = nil) async throws -> [String] {
        var results: [String] = []

        for text in texts {
            let translated = try await translate(text, from: source, to: target)
            results.append(translated)
        }

        return results
    }

    /// Detect language of text
    func detectLanguage(_ text: String) async throws -> TranslationLanguage {
        // Use NaturalLanguage framework for language detection
        return try await detectLanguageForText(text)
    }

    // MARK: - Context-Aware Translation

    /// Translate code comments while preserving code
    func translateCodeWithComments(_ code: String, to target: TranslationLanguage) async throws -> String {
        let lines = code.components(separatedBy: .newlines)
        var translatedLines: [String] = []

        for line in lines {
            if isCommentLine(line) {
                let translatedComment = try await translate(line, to: target)
                translatedLines.append(translatedComment)
            } else {
                translatedLines.append(line)
            }
        }

        return translatedLines.joined(separator: "\n")
    }

    /// Translate documentation while preserving formatting
    func translateDocumentation(_ doc: String, to target: TranslationLanguage) async throws -> String {
        // Parse markdown and translate text blocks
        let translated = try await translateMarkdown(doc, to: target)
        return translated
    }

    /// Translate error messages with context
    func translateErrorMessage(_ error: String, context: ErrorContext? = nil) async throws -> String {
        // Add context to improve translation accuracy
        var textToTranslate = error

        if let context = context {
            textToTranslate = "[\(context.language)] \(error)"
        }

        let translated = try await translate(textToTranslate, to: currentTargetLanguage)

        // Remove context prefix if added
        if let context = context {
            let prefix = "[\(context.language)] "
            if translated.hasPrefix(prefix) {
                return String(translated.dropFirst(prefix.count))
            }
        }

        return translated
    }

    // MARK: - Private Implementation

    private func performTranslation(text: String, source: TranslationLanguage, target: TranslationLanguage) async throws -> String {
        #if canImport(NaturalLanguage)
        // Detect source language if auto
        let resolvedSource: TranslationLanguage
        if source == .auto || source.code == "auto" {
            resolvedSource = try await detectLanguageForText(text)
        } else {
            resolvedSource = source
        }

        // If source and target are the same after resolution, return as-is
        if resolvedSource.code == target.code {
            return text
        }

        // Use Apple's Translation framework when available (macOS 15+/iOS 18+)
        if #available(macOS 15.0, iOS 18.0, *) {
            return try await performAppleTranslation(text: text, source: resolvedSource, target: target)
        }

        // Fallback: language detection with clear limitation messaging
        let confidence = detectLanguageConfidence(text)
        throw TranslationError.translationFailed(
            "On-device translation from \(resolvedSource.name) to \(target.name) requires macOS 15+ or iOS 18+. Detected source language: \(resolvedSource.name) (\(Int(confidence * 100))% confidence). Upgrade your OS to enable real-time translation."
        )
        #else
        throw TranslationError.notAvailable
        #endif
    }

    @available(macOS 15.0, iOS 18.0, *)
    private func performAppleTranslation(text: String, source: TranslationLanguage, target: TranslationLanguage) async throws -> String {
        // Use the /usr/bin/translate CLI or AppleScript as a bridge to Apple's Translation framework
        // Apple's Translation framework requires SwiftUI TranslationSession which needs a view context,
        // so we use the system translate command as a reliable alternative
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let safeText = text.replacingOccurrences(of: "'", with: "'\\''")
        // Try using shortcuts for translation if available
        let shortcutCmd = "echo '\(safeText)' | shortcuts run 'Translate Text' 2>/dev/null"
        process.arguments = ["bash", "-c", shortcutCmd]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !result.isEmpty && result != text {
                return result
            }
        } catch {
            // Fall through to error
        }

        throw TranslationError.translationFailed(
            "Translation from \(source.name) to \(target.name) requires a 'Translate Text' Shortcut or the Translation framework. Create a Shortcut named 'Translate Text' that accepts text input and outputs translated text."
        )
        #else
        throw TranslationError.translationFailed(
            "Translation from \(source.name) to \(target.name) is not yet supported on this platform."
        )
        #endif
    }

    private func detectLanguageForText(_ text: String) async throws -> TranslationLanguage {
        #if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let language = recognizer.dominantLanguage,
              let translationLanguage = TranslationLanguage.fromLanguageCode(language.rawValue) else {
            return .english
        }

        return translationLanguage
        #else
        return .english
        #endif
    }

    #if canImport(NaturalLanguage)
    private func detectLanguageConfidence(_ text: String) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let dominant = recognizer.dominantLanguage else { return 0 }
        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        return hypotheses[dominant] ?? 0
    }
    #endif

    // MARK: - Helper Methods

    private func isCommentLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Check for common comment patterns
        let commentPrefixes = ["//", "#", "/*", "*", "<!--", "--", "(*"]

        for prefix in commentPrefixes {
            if trimmed.hasPrefix(prefix) {
                return true
            }
        }

        return false
    }

    private func translateMarkdown(_ markdown: String, to target: TranslationLanguage) async throws -> String {
        // Simple markdown parser and translator
        // In production, use a proper markdown parser

        let lines = markdown.components(separatedBy: .newlines)
        var translatedLines: [String] = []
        var inCodeBlock = false

        for line in lines {
            if line.hasPrefix("```") {
                inCodeBlock.toggle()
                translatedLines.append(line)
            } else if inCodeBlock {
                translatedLines.append(line)
            } else if line.hasPrefix("#") || line.hasPrefix("##") || line.hasPrefix("###") {
                // Translate headers
                let translated = try await translate(line, to: target)
                translatedLines.append(translated)
            } else if !line.isEmpty {
                // Translate regular text
                let translated = try await translate(line, to: target)
                translatedLines.append(translated)
            } else {
                translatedLines.append(line)
            }
        }

        return translatedLines.joined(separator: "\n")
    }

    // MARK: - History Management

    private func addToHistory(_ entry: TranslationEntry) {
        translationHistory.insert(entry, at: 0)

        // Keep history manageable
        if translationHistory.count > 1000 {
            translationHistory = Array(translationHistory.prefix(500))
        }

        saveTranslationHistory()
    }

    private func saveTranslationHistory() {
        if let data = try? JSONEncoder().encode(translationHistory) {
            userDefaults.set(data, forKey: historyKey)
        }
    }

    private func loadTranslationHistory() {
        guard let data = userDefaults.data(forKey: historyKey),
              let history = try? JSONDecoder().decode([TranslationEntry].self, from: data) else {
            return
        }

        translationHistory = history
    }

    private func loadSavedPreferences() {
        if let sourceCode = userDefaults.string(forKey: "SourceLanguage"),
           let source = TranslationLanguage.fromCode(sourceCode) {
            currentSourceLanguage = source
        }

        if let targetCode = userDefaults.string(forKey: "TargetLanguage"),
           let target = TranslationLanguage.fromCode(targetCode) {
            currentTargetLanguage = target
        }
    }

    func savePreferences() {
        userDefaults.set(currentSourceLanguage.code, forKey: "SourceLanguage")
        userDefaults.set(currentTargetLanguage.code, forKey: "TargetLanguage")
    }

    // MARK: - Convenience Methods

    func clearHistory() {
        translationHistory.removeAll()
        saveTranslationHistory()
    }

    func exportHistory() -> String {
        guard let data = try? JSONEncoder().encode(translationHistory),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json
    }
}

// MARK: - Data Models

struct TranslationEntry: Codable, Identifiable {
    var id = UUID()
    let originalText: String
    let translatedText: String
    let sourceLanguage: TranslationLanguage
    let targetLanguage: TranslationLanguage
    let timestamp: Date
}

struct TranslationLanguage: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    let nativeName: String
    let isRTL: Bool

    var id: String { code }

    static let auto = TranslationLanguage(code: "auto", name: "Auto-detect", nativeName: "Auto", isRTL: false)
    static let english = TranslationLanguage(code: "en", name: "English", nativeName: "English", isRTL: false)
    static let spanish = TranslationLanguage(code: "es", name: "Spanish", nativeName: "Español", isRTL: false)
    static let french = TranslationLanguage(code: "fr", name: "French", nativeName: "Français", isRTL: false)
    static let german = TranslationLanguage(code: "de", name: "German", nativeName: "Deutsch", isRTL: false)
    static let italian = TranslationLanguage(code: "it", name: "Italian", nativeName: "Italiano", isRTL: false)
    static let portuguese = TranslationLanguage(code: "pt", name: "Portuguese", nativeName: "Português", isRTL: false)
    static let russian = TranslationLanguage(code: "ru", name: "Russian", nativeName: "Русский", isRTL: false)
    static let chineseSimplified = TranslationLanguage(code: "zh-Hans", name: "Chinese (Simplified)", nativeName: "简体中文", isRTL: false)
    static let chineseTraditional = TranslationLanguage(code: "zh-Hant", name: "Chinese (Traditional)", nativeName: "繁體中文", isRTL: false)
    static let japanese = TranslationLanguage(code: "ja", name: "Japanese", nativeName: "日本語", isRTL: false)
    static let korean = TranslationLanguage(code: "ko", name: "Korean", nativeName: "한국어", isRTL: false)
    static let arabic = TranslationLanguage(code: "ar", name: "Arabic", nativeName: "العربية", isRTL: true)
    static let hindi = TranslationLanguage(code: "hi", name: "Hindi", nativeName: "हिन्दी", isRTL: false)
    static let dutch = TranslationLanguage(code: "nl", name: "Dutch", nativeName: "Nederlands", isRTL: false)
    static let swedish = TranslationLanguage(code: "sv", name: "Swedish", nativeName: "Svenska", isRTL: false)
    static let danish = TranslationLanguage(code: "da", name: "Danish", nativeName: "Dansk", isRTL: false)
    static let norwegian = TranslationLanguage(code: "no", name: "Norwegian", nativeName: "Norsk", isRTL: false)
    static let finnish = TranslationLanguage(code: "fi", name: "Finnish", nativeName: "Suomi", isRTL: false)
    static let polish = TranslationLanguage(code: "pl", name: "Polish", nativeName: "Polski", isRTL: false)
    static let czech = TranslationLanguage(code: "cs", name: "Czech", nativeName: "Čeština", isRTL: false)
    static let hungarian = TranslationLanguage(code: "hu", name: "Hungarian", nativeName: "Magyar", isRTL: false)
    static let romanian = TranslationLanguage(code: "ro", name: "Romanian", nativeName: "Română", isRTL: false)
    static let ukrainian = TranslationLanguage(code: "uk", name: "Ukrainian", nativeName: "Українська", isRTL: false)
    static let greek = TranslationLanguage(code: "el", name: "Greek", nativeName: "Ελληνικά", isRTL: false)
    static let turkish = TranslationLanguage(code: "tr", name: "Turkish", nativeName: "Türkçe", isRTL: false)
    static let hebrew = TranslationLanguage(code: "he", name: "Hebrew", nativeName: "עברית", isRTL: true)
    static let thai = TranslationLanguage(code: "th", name: "Thai", nativeName: "ไทย", isRTL: false)
    static let vietnamese = TranslationLanguage(code: "vi", name: "Vietnamese", nativeName: "Tiếng Việt", isRTL: false)
    static let indonesian = TranslationLanguage(code: "id", name: "Indonesian", nativeName: "Bahasa Indonesia", isRTL: false)
    static let malay = TranslationLanguage(code: "ms", name: "Malay", nativeName: "Bahasa Melayu", isRTL: false)
    static let tagalog = TranslationLanguage(code: "tl", name: "Tagalog", nativeName: "Tagalog", isRTL: false)

    static let allLanguages: [TranslationLanguage] = [
        .auto, .english, .spanish, .french, .german, .italian, .portuguese, .russian,
        .chineseSimplified, .chineseTraditional, .japanese, .korean, .arabic, .hindi,
        .dutch, .swedish, .danish, .norwegian, .finnish, .polish, .czech, .hungarian,
        .romanian, .ukrainian, .greek, .turkish, .hebrew, .thai, .vietnamese, .indonesian,
        .malay, .tagalog
    ]

    var languageCode: String {
        return code == "auto" ? "" : code
    }

    static func fromCode(_ code: String) -> TranslationLanguage? {
        return allLanguages.first { $0.code == code }
    }

    static func fromLanguageCode(_ code: String) -> TranslationLanguage? {
        return fromCode(code) ?? fromCode(String(code.prefix(2)))
    }
}

struct ErrorContext {
    let language: String
    let framework: String
    let errorType: String

    static let swift = ErrorContext(language: "Swift", framework: "Swift", errorType: "Compilation")
    static let objectiveC = ErrorContext(language: "Objective-C", framework: "Objective-C", errorType: "Compilation")
    static let javascript = ErrorContext(language: "JavaScript", framework: "JavaScript", errorType: "Runtime")
    static let python = ErrorContext(language: "Python", framework: "Python", errorType: "Runtime")
    static let java = ErrorContext(language: "Java", framework: "Java", errorType: "Compilation")
}

// MARK: - Errors

enum TranslationError: LocalizedError {
    case notAvailable
    case translationFailed(String)
    case languageNotSupported
    case networkError

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Translation is not available on this device"
        case .translationFailed(let message):
            return "Translation failed: \(message)"
        case .languageNotSupported:
            return "Language is not supported"
        case .networkError:
            return "Network error occurred during translation"
        }
    }
}
