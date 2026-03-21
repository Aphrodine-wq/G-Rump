import Foundation

// MARK: - Complexity Analyzer

/// Analyzes code complexity using multiple established metrics:
/// cyclomatic complexity, cognitive complexity, Halstead metrics, and maintainability index.
struct ComplexityAnalyzer: Sendable {

    // MARK: - Cyclomatic Complexity

    /// Calculate cyclomatic complexity by counting decision points.
    /// M = number of decision points + 1
    func analyzeCyclomaticComplexity(_ source: String, language: Language) -> Int {
        let lines = source.components(separatedBy: .newlines)
        var complexity = 1  // Base complexity

        let decisionKeywords = decisionKeywordsForLanguage(language)
        let logicalOperators = ["&&", "||"]

        var inBlockComment = false
        let blockDelimiters = language.blockCommentDelimiters

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            if trimmed.isEmpty { continue }

            // Handle block comments
            if let delimiters = blockDelimiters {
                if inBlockComment {
                    if trimmed.contains(delimiters.end) { inBlockComment = false }
                    continue
                }
                if trimmed.hasPrefix(delimiters.start) {
                    if !trimmed.contains(delimiters.end) { inBlockComment = true }
                    continue
                }
            }

            // Skip line comments
            if trimmed.hasPrefix(language.lineCommentPrefix) { continue }

            // Strip strings to avoid false positives
            let stripped = stripStrings(trimmed)

            // Count decision keywords
            for keyword in decisionKeywords {
                let pattern = "\\b\(keyword)\\b"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   regex.numberOfMatches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) > 0 {
                    complexity += 1
                }
            }

            // Count logical operators (each adds a path)
            for op in logicalOperators {
                var searchRange = stripped.startIndex..<stripped.endIndex
                while let range = stripped.range(of: op, range: searchRange) {
                    complexity += 1
                    searchRange = range.upperBound..<stripped.endIndex
                }
            }

            // Count ternary operators
            let ternaryCount = stripped.filter { $0 == "?" }.count
            // Subtract optional chaining for Swift/TypeScript
            if language == .swift || language == .typescript {
                let optionalChainPattern = #"\?\."#
                let optionalChains = (try? NSRegularExpression(pattern: optionalChainPattern))
                    .map { $0.numberOfMatches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) } ?? 0
                let nullCoalescingCount = stripped.components(separatedBy: "??").count - 1
                complexity += max(0, ternaryCount - optionalChains - nullCoalescingCount)
            } else {
                complexity += ternaryCount
            }
        }

        return max(1, complexity)
    }

    // MARK: - Cognitive Complexity

    /// Calculate cognitive complexity with nesting penalty.
    /// Increments for: breaks in linear flow, structural complexity, nesting.
    func analyzeCognitiveComplexity(_ source: String, language: Language) -> Int {
        let lines = source.components(separatedBy: .newlines)
        var complexity = 0
        var nestingLevel = 0
        var inBlockComment = false
        let blockDelimiters = language.blockCommentDelimiters

        let flowBreakers = flowBreakersForLanguage(language)
        let nestingIncrementers = nestingIncrementersForLanguage(language)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Handle block comments
            if let delimiters = blockDelimiters {
                if inBlockComment {
                    if trimmed.contains(delimiters.end) { inBlockComment = false }
                    continue
                }
                if trimmed.hasPrefix(delimiters.start) {
                    if !trimmed.contains(delimiters.end) { inBlockComment = true }
                    continue
                }
            }

            if trimmed.hasPrefix(language.lineCommentPrefix) { continue }

            let stripped = stripStrings(trimmed)

            // Track nesting via braces
            let opens = stripped.filter { $0 == "{" }.count
            let closes = stripped.filter { $0 == "}" }.count

            // Check for nesting incrementers (structural constructs that increase cognitive load)
            for keyword in nestingIncrementers {
                let pattern = "\\b\(keyword)\\b"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   regex.numberOfMatches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) > 0 {
                    // Increment by 1 + current nesting level (nesting penalty)
                    complexity += 1 + nestingLevel
                }
            }

            // Check for flow breakers (add 1, no nesting penalty)
            for keyword in flowBreakers {
                let pattern = "\\b\(keyword)\\b"
                if let regex = try? NSRegularExpression(pattern: pattern),
                   regex.numberOfMatches(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)) > 0 {
                    complexity += 1
                }
            }

            // Check for logical operator sequences
            let logicalOps = ["&&", "||"]
            for op in logicalOps {
                var searchRange = stripped.startIndex..<stripped.endIndex
                while let range = stripped.range(of: op, range: searchRange) {
                    complexity += 1
                    searchRange = range.upperBound..<stripped.endIndex
                }
            }

            // Check for recursion (function calling itself)
            // This is a heuristic - we'd need the function name for precision
            if stripped.contains("self.") && stripped.contains("(") && language == .swift {
                // Could be recursive if calling own method, but conservative detection
            }

            // Update nesting level
            nestingLevel += opens
            nestingLevel -= closes
            nestingLevel = max(0, nestingLevel)
        }

        return max(0, complexity)
    }

    // MARK: - Nesting Depth

    /// Calculate maximum brace nesting depth.
    func analyzeNestingDepth(_ source: String) -> Int {
        var maxDepth = 0
        var currentDepth = 0
        var inString = false
        var stringDelimiter: Character = "\""
        var prevChar: Character = " "

        for char in source {
            // Track string boundaries
            if (char == "\"" || char == "'") && prevChar != "\\" {
                if inString && char == stringDelimiter {
                    inString = false
                } else if !inString {
                    inString = true
                    stringDelimiter = char
                }
            }

            if !inString {
                if char == "{" {
                    currentDepth += 1
                    maxDepth = max(maxDepth, currentDepth)
                } else if char == "}" {
                    currentDepth = max(0, currentDepth - 1)
                }
            }

            prevChar = char
        }

        return maxDepth
    }

    // MARK: - Halstead Metrics

    /// Tokenize source code and calculate Halstead software science metrics.
    func analyzeHalstead(_ source: String, language: Language) -> HalsteadMetrics {
        let tokens = tokenize(source, language: language)

        var operators = Set<String>()
        var operands = Set<String>()
        var totalOperators = 0
        var totalOperands = 0

        let operatorSet = operatorSetForLanguage(language)
        let keywordSet = keywordSetForLanguage(language)

        for token in tokens {
            if operatorSet.contains(token) || keywordSet.contains(token) {
                operators.insert(token)
                totalOperators += 1
            } else {
                // It's an operand (identifier, literal, etc.)
                operands.insert(token)
                totalOperands += 1
            }
        }

        return HalsteadMetrics(
            distinctOperators: operators.count,
            distinctOperands: operands.count,
            totalOperators: totalOperators,
            totalOperands: totalOperands
        )
    }

    // MARK: - Maintainability Index

    /// Calculate Maintainability Index (MI) on a 0-100 scale.
    /// Uses the SEI formula: MI = 171 - 5.2 * ln(V) - 0.23 * CC - 16.2 * ln(LOC)
    /// Normalized to 0-100 range.
    func calculateMaintainabilityIndex(halstead: HalsteadMetrics, cyclomatic: Int, loc: Int) -> Double {
        let volume = max(1.0, halstead.volume)
        let cc = Double(max(1, cyclomatic))
        let lines = Double(max(1, loc))

        let rawMI = 171.0
            - 5.2 * log(volume)
            - 0.23 * cc
            - 16.2 * log(lines)

        // Normalize to 0-100
        let normalized = max(0, min(100, rawMI * 100.0 / 171.0))
        return (normalized * 10).rounded() / 10  // Round to 1 decimal
    }

    /// Grade complexity on A-F scale.
    func gradeComplexity(_ maintainability: Double) -> String {
        ComplexityScore.grade(maintainability: maintainability)
    }

    // MARK: - Tokenization

    /// Tokenize source code into operators and operands.
    private func tokenize(_ source: String, language: Language) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inString = false
        var stringDelimiter: Character = "\""
        var prevChar: Character = " "
        var inLineComment = false
        var inBlockComment = false

        let lineCommentPrefix = language.lineCommentPrefix
        let blockDelimiters = language.blockCommentDelimiters

        for (index, char) in source.enumerated() {
            // Handle newlines
            if char == "\n" {
                if !current.isEmpty { tokens.append(current); current = "" }
                inLineComment = false
                prevChar = char
                continue
            }

            // Skip comments
            if inLineComment { prevChar = char; continue }
            if inBlockComment {
                if let end = blockDelimiters?.end,
                   char == end.last && prevChar == end.first {
                    inBlockComment = false
                }
                prevChar = char
                continue
            }

            // Detect comment start
            if !inString {
                if lineCommentPrefix.count == 2 && String([prevChar, char]) == lineCommentPrefix {
                    if !current.isEmpty {
                        current.removeLast()
                        if !current.isEmpty { tokens.append(current) }
                        current = ""
                    }
                    inLineComment = true
                    prevChar = char
                    continue
                }
                if let start = blockDelimiters?.start,
                   start.count == 2 && String([prevChar, char]) == start {
                    if !current.isEmpty {
                        current.removeLast()
                        if !current.isEmpty { tokens.append(current) }
                        current = ""
                    }
                    inBlockComment = true
                    prevChar = char
                    continue
                }
            }

            // Handle strings
            if (char == "\"" || char == "'") && prevChar != "\\" {
                if inString && char == stringDelimiter {
                    inString = false
                    if !current.isEmpty { tokens.append(current); current = "" }
                    tokens.append("\"string_literal\"")
                } else if !inString {
                    if !current.isEmpty { tokens.append(current); current = "" }
                    inString = true
                    stringDelimiter = char
                }
                prevChar = char
                continue
            }

            if inString { prevChar = char; continue }

            // Handle operators and delimiters
            let multiCharOps: Set<String> = ["==", "!=", "<=", ">=", "&&", "||", "+=", "-=", "*=", "/=",
                                              "->", "=>", "::", "..", "??", "?.", "<<", ">>"]

            if char.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if "(){}[];,:".contains(char) {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(char))
            } else if "+-*/%=<>!&|^~?@#".contains(char) {
                // Check for multi-character operators
                let twoChar = String([prevChar, char])
                if multiCharOps.contains(twoChar) && !tokens.isEmpty {
                    // Replace last single-char op with multi-char
                    let lastToken = tokens.last ?? ""
                    if lastToken == String(prevChar) {
                        tokens[tokens.count - 1] = twoChar
                    } else {
                        if !current.isEmpty { tokens.append(current); current = "" }
                        tokens.append(String(char))
                    }
                } else {
                    if !current.isEmpty { tokens.append(current); current = "" }
                    tokens.append(String(char))
                }
            } else if char == "." {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(".")
            } else {
                current.append(char)
            }

            prevChar = char
        }

        if !current.isEmpty { tokens.append(current) }

        return tokens.filter { !$0.isEmpty }
    }

    // MARK: - Language-specific Keyword/Operator Sets

    private func decisionKeywordsForLanguage(_ language: Language) -> [String] {
        var keywords = ["if", "else", "while", "for", "case", "catch"]

        switch language {
        case .swift:
            keywords.append(contentsOf: ["guard", "where", "#if", "repeat"])
        case .rust:
            keywords.append(contentsOf: ["match", "loop", "if let", "while let"])
        case .typescript, .javascript:
            keywords.append(contentsOf: ["switch", "do", "try", "finally"])
        case .python:
            keywords.append(contentsOf: ["elif", "except", "with", "assert"])
        case .go:
            keywords.append(contentsOf: ["select", "switch", "defer"])
        case .java, .kotlin:
            keywords.append(contentsOf: ["switch", "do", "try", "finally", "instanceof", "when"])
        case .cpp:
            keywords.append(contentsOf: ["switch", "do", "try"])
        case .unknown:
            break
        }

        return keywords
    }

    private func flowBreakersForLanguage(_ language: Language) -> [String] {
        var breakers = ["else", "break", "continue", "return"]

        switch language {
        case .swift:
            breakers.append(contentsOf: ["throw", "fallthrough", "defer"])
        case .rust:
            breakers.append(contentsOf: ["panic", "unreachable", "todo"])
        case .typescript, .javascript:
            breakers.append(contentsOf: ["throw", "yield", "await"])
        case .python:
            breakers.append(contentsOf: ["raise", "yield", "pass"])
        case .go:
            breakers.append(contentsOf: ["goto", "fallthrough", "panic"])
        case .java, .kotlin:
            breakers.append(contentsOf: ["throw", "yield"])
        case .cpp:
            breakers.append(contentsOf: ["throw", "goto"])
        case .unknown:
            break
        }

        return breakers
    }

    private func nestingIncrementersForLanguage(_ language: Language) -> [String] {
        var incrementers = ["if", "for", "while", "switch"]

        switch language {
        case .swift:
            incrementers.append(contentsOf: ["guard", "do"])
        case .rust:
            incrementers.append(contentsOf: ["match", "loop"])
        case .typescript, .javascript:
            incrementers.append(contentsOf: ["do", "try"])
        case .python:
            incrementers.append(contentsOf: ["try", "with"])
        case .go:
            incrementers.append(contentsOf: ["select"])
        case .java, .kotlin:
            incrementers.append(contentsOf: ["do", "try", "when"])
        case .cpp:
            incrementers.append(contentsOf: ["do", "try"])
        case .unknown:
            break
        }

        return incrementers
    }

    private func operatorSetForLanguage(_ language: Language) -> Set<String> {
        var ops: Set<String> = [
            "+", "-", "*", "/", "%", "=", "==", "!=", "<", ">", "<=", ">=",
            "&&", "||", "!", "&", "|", "^", "~", "<<", ">>",
            "+=", "-=", "*=", "/=", "%=",
            "(", ")", "{", "}", "[", "]", ",", ";", ":", "."
        ]

        switch language {
        case .swift:
            ops.formUnion(["->", "??", "?.", "...", "..<", "#if", "#else", "#endif", "@"])
        case .rust:
            ops.formUnion(["->", "::", "..", "..=", "=>", "?", "&mut", "as"])
        case .typescript, .javascript:
            ops.formUnion(["=>", "===", "!==", "?.", "??", "...", "typeof", "instanceof", "in"])
        case .python:
            ops.formUnion(["**", "//", "**=", "//=", "not", "and", "or", "in", "is", "@"])
        case .go:
            ops.formUnion([":=", "<-", "..."])
        case .java, .kotlin:
            ops.formUnion(["->", "::", "instanceof", "?:"])
        case .cpp:
            ops.formUnion(["->", "::", "sizeof", "new", "delete", "typeid"])
        case .unknown:
            break
        }

        return ops
    }

    private func keywordSetForLanguage(_ language: Language) -> Set<String> {
        switch language {
        case .swift:
            return ["func", "var", "let", "if", "else", "guard", "switch", "case", "for", "while",
                    "repeat", "do", "try", "catch", "throw", "return", "break", "continue",
                    "class", "struct", "enum", "protocol", "extension", "import", "typealias",
                    "where", "in", "as", "is", "nil", "true", "false", "self", "super",
                    "init", "deinit", "subscript", "operator", "precedencegroup",
                    "public", "private", "internal", "fileprivate", "open", "static",
                    "override", "mutating", "nonmutating", "lazy", "weak", "unowned",
                    "async", "await", "actor", "nonisolated", "isolated", "consuming", "borrowing"]
        case .rust:
            return ["fn", "let", "mut", "if", "else", "match", "for", "while", "loop",
                    "return", "break", "continue", "struct", "enum", "trait", "impl",
                    "pub", "use", "mod", "crate", "super", "self", "where", "as",
                    "type", "const", "static", "ref", "move", "async", "await",
                    "unsafe", "extern", "dyn", "true", "false"]
        case .typescript, .javascript:
            return ["function", "var", "let", "const", "if", "else", "switch", "case",
                    "for", "while", "do", "try", "catch", "finally", "throw", "return",
                    "break", "continue", "class", "extends", "implements", "interface",
                    "import", "export", "from", "default", "new", "delete", "typeof",
                    "instanceof", "in", "of", "async", "await", "yield", "this",
                    "true", "false", "null", "undefined", "void", "type", "enum"]
        case .python:
            return ["def", "class", "if", "elif", "else", "for", "while", "try",
                    "except", "finally", "raise", "return", "break", "continue",
                    "import", "from", "as", "with", "assert", "yield", "pass",
                    "lambda", "global", "nonlocal", "del", "in", "not", "and", "or",
                    "is", "True", "False", "None", "async", "await"]
        case .java, .kotlin:
            return ["class", "interface", "enum", "extends", "implements", "if", "else",
                    "switch", "case", "for", "while", "do", "try", "catch", "finally",
                    "throw", "throws", "return", "break", "continue", "new", "this",
                    "super", "static", "final", "abstract", "public", "private",
                    "protected", "void", "import", "package", "instanceof",
                    "true", "false", "null", "synchronized", "volatile"]
        case .go:
            return ["func", "var", "const", "type", "struct", "interface", "map",
                    "chan", "if", "else", "switch", "case", "select", "for",
                    "range", "return", "break", "continue", "goto", "fallthrough",
                    "defer", "go", "package", "import", "true", "false", "nil"]
        case .cpp:
            return ["class", "struct", "enum", "union", "if", "else", "switch", "case",
                    "for", "while", "do", "try", "catch", "throw", "return", "break",
                    "continue", "goto", "new", "delete", "this", "virtual", "override",
                    "static", "const", "volatile", "extern", "inline", "namespace",
                    "using", "template", "typename", "public", "private", "protected",
                    "true", "false", "nullptr", "sizeof", "typedef", "auto"]
        case .unknown:
            return []
        }
    }

    // MARK: - String Stripping

    /// Remove string literals from source to prevent false keyword matches.
    private func stripStrings(_ source: String) -> String {
        var result = ""
        var inString = false
        var delimiter: Character = "\""
        var prevChar: Character = " "

        for char in source {
            if (char == "\"" || char == "'") && prevChar != "\\" {
                if inString && char == delimiter {
                    inString = false
                    result.append("_")  // placeholder
                } else if !inString {
                    inString = true
                    delimiter = char
                    result.append("_")  // placeholder
                }
            } else if !inString {
                result.append(char)
            }
            prevChar = char
        }

        return result
    }
}
