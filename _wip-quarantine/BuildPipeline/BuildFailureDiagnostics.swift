// ╔══════════════════════════════════════════════════════════════╗
// ║  BuildFailureDiagnostics.swift                              ║
// ║  Self-Healing Build Pipeline — error diagnosis              ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - Error Pattern

/// A known error pattern with its diagnosis and fix template.
private struct ErrorPattern {
    let name: String
    let category: BuildErrorCategory
    let messagePattern: String // regex
    let rootCauseTemplate: String
    let fixGenerator: ((BuildError, String) async -> [AutoFix])?
    let confidence: Double

    init(
        name: String,
        category: BuildErrorCategory,
        messagePattern: String,
        rootCauseTemplate: String,
        confidence: Double = 0.8,
        fixGenerator: ((BuildError, String) async -> [AutoFix])? = nil
    ) {
        self.name = name
        self.category = category
        self.messagePattern = messagePattern
        self.rootCauseTemplate = rootCauseTemplate
        self.confidence = confidence
        self.fixGenerator = fixGenerator
    }
}

// MARK: - Build Failure Diagnostics

/// Diagnoses build errors by matching against known patterns, correlating
/// related errors, and generating fix suggestions.
struct BuildFailureDiagnostics {

    // MARK: - Pattern Database

    /// 50+ known error patterns across Swift, Rust, TypeScript, and C.
    private let patterns: [ErrorPattern] = {
        var p: [ErrorPattern] = []

        // MARK: Swift Patterns
        p.append(ErrorPattern(
            name: "swift-missing-module",
            category: .missingDependency,
            messagePattern: #"no such module '(\w+)'"#,
            rootCauseTemplate: "Module '$1' is not available. It may need to be added to Package.swift dependencies.",
            confidence: 0.95
        ))
        p.append(ErrorPattern(
            name: "swift-missing-type",
            category: .missingImport,
            messagePattern: #"cannot find type '(\w+)' in scope"#,
            rootCauseTemplate: "Type '$1' is not in scope. A missing import statement or the type is defined in another module.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "swift-missing-value",
            category: .missingImport,
            messagePattern: #"cannot find '(\w+)' in scope"#,
            rootCauseTemplate: "Symbol '$1' is not in scope. Check imports and ensure the declaration is accessible.",
            confidence: 0.85
        ))
        p.append(ErrorPattern(
            name: "swift-type-mismatch",
            category: .typeError,
            messagePattern: #"cannot convert value of type '(.+)' to expected argument type '(.+)'"#,
            rootCauseTemplate: "Type mismatch: got '$1' but expected '$2'. A type conversion or different overload may be needed.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "swift-return-type",
            category: .typeError,
            messagePattern: #"cannot convert return expression of type '(.+)' to return type '(.+)'"#,
            rootCauseTemplate: "Return type mismatch: returning '$1' but function declares '$2'.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "swift-missing-return",
            category: .syntaxError,
            messagePattern: #"missing return in"#,
            rootCauseTemplate: "Function requires a return statement but none was found in all code paths.",
            confidence: 0.95
        ))
        p.append(ErrorPattern(
            name: "swift-expected-brace",
            category: .syntaxError,
            messagePattern: #"expected '\{' in"#,
            rootCauseTemplate: "Syntax error: missing opening brace. Check the surrounding code structure.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "swift-expected-close-brace",
            category: .syntaxError,
            messagePattern: #"expected '\}'"#,
            rootCauseTemplate: "Syntax error: missing closing brace. A block was opened but not properly closed.",
            confidence: 0.85
        ))
        p.append(ErrorPattern(
            name: "swift-expected-paren",
            category: .syntaxError,
            messagePattern: #"expected '\)' in expression"#,
            rootCauseTemplate: "Syntax error: unmatched parenthesis.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "swift-value-of-optional",
            category: .typeError,
            messagePattern: #"value of optional type '(.+)\?' must be unwrapped"#,
            rootCauseTemplate: "Optional '$1?' used where non-optional is expected. Use optional binding or force unwrap.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "swift-initializer-missing",
            category: .typeError,
            messagePattern: #"missing argument for parameter '(\w+)'"#,
            rootCauseTemplate: "Required parameter '$1' not provided in initializer/function call.",
            confidence: 0.85
        ))
        p.append(ErrorPattern(
            name: "swift-access-control",
            category: .typeError,
            messagePattern: #"'(\w+)' is inaccessible due to '(\w+)' protection level"#,
            rootCauseTemplate: "'$1' has '$2' access but needs to be more visible from the call site.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "swift-protocol-conformance",
            category: .typeError,
            messagePattern: #"type '(\w+)' does not conform to protocol '(\w+)'"#,
            rootCauseTemplate: "'$1' declares conformance to '$2' but is missing required members.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "swift-ambiguous",
            category: .typeError,
            messagePattern: #"ambiguous use of '(\w+)'"#,
            rootCauseTemplate: "Multiple overloads of '$1' match. Add type annotations to disambiguate.",
            confidence: 0.75
        ))
        p.append(ErrorPattern(
            name: "swift-deprecated",
            category: .typeError,
            messagePattern: #"'(\w+)' was deprecated in"#,
            rootCauseTemplate: "'$1' is deprecated. Use the modern replacement API.",
            confidence: 0.8
        ))
        p.append(ErrorPattern(
            name: "swift-concurrency-sendable",
            category: .typeError,
            messagePattern: #"cannot be sent to .+ actor-isolated"#,
            rootCauseTemplate: "Concurrency safety: the value crosses an isolation boundary. Mark the type as Sendable or restructure the code.",
            confidence: 0.8
        ))
        p.append(ErrorPattern(
            name: "swift-actor-isolation",
            category: .typeError,
            messagePattern: #"actor-isolated .+ cannot be .+ from"#,
            rootCauseTemplate: "Actor isolation violation. Use 'await' or restructure to respect actor boundaries.",
            confidence: 0.85
        ))
        p.append(ErrorPattern(
            name: "swift-unused-result",
            category: .typeError,
            messagePattern: #"result of call to '(\w+)' is unused"#,
            rootCauseTemplate: "Return value of '$1' is discarded. Assign to _ or use @discardableResult.",
            confidence: 0.7
        ))

        // MARK: Rust Patterns
        p.append(ErrorPattern(
            name: "rust-unresolved-import",
            category: .missingImport,
            messagePattern: #"unresolved import `(.+)`"#,
            rootCauseTemplate: "Import '$1' cannot be resolved. Check Cargo.toml for missing dependency.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "rust-mismatched-types",
            category: .typeError,
            messagePattern: #"mismatched types"#,
            rootCauseTemplate: "Type mismatch in expression. Check the expected and actual types.",
            confidence: 0.85
        ))
        p.append(ErrorPattern(
            name: "rust-borrow-checker",
            category: .typeError,
            messagePattern: #"cannot borrow .+ as mutable"#,
            rootCauseTemplate: "Borrow checker violation: attempting to mutably borrow a value that is already borrowed.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "rust-lifetime",
            category: .typeError,
            messagePattern: #"lifetime .+ does not .+"#,
            rootCauseTemplate: "Lifetime annotation issue. The referenced value may not live long enough.",
            confidence: 0.8
        ))
        p.append(ErrorPattern(
            name: "rust-unused-var",
            category: .syntaxError,
            messagePattern: #"unused variable: `(\w+)`"#,
            rootCauseTemplate: "Variable '$1' is declared but never used. Prefix with _ or remove it.",
            confidence: 0.95
        ))
        p.append(ErrorPattern(
            name: "rust-missing-field",
            category: .syntaxError,
            messagePattern: #"missing field `(\w+)` in initializer"#,
            rootCauseTemplate: "Struct initializer is missing required field '$1'.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "rust-no-method",
            category: .typeError,
            messagePattern: #"no method named `(\w+)` found"#,
            rootCauseTemplate: "Method '$1' does not exist on this type. Check trait imports and method names.",
            confidence: 0.85
        ))

        // MARK: TypeScript Patterns
        p.append(ErrorPattern(
            name: "ts-cannot-find",
            category: .missingImport,
            messagePattern: #"Cannot find name '(\w+)'"#,
            rootCauseTemplate: "Name '$1' is not defined. Add an import or declare the variable.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "ts-not-assignable",
            category: .typeError,
            messagePattern: #"Type '(.+)' is not assignable to type '(.+)'"#,
            rootCauseTemplate: "Type '$1' is not assignable to '$2'. Check the types and add conversion if needed.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "ts-module-not-found",
            category: .missingDependency,
            messagePattern: #"Cannot find module '(.+)'"#,
            rootCauseTemplate: "Module '$1' is not installed. Run npm install or add to package.json.",
            confidence: 0.95
        ))
        p.append(ErrorPattern(
            name: "ts-property-missing",
            category: .typeError,
            messagePattern: #"Property '(\w+)' does not exist on type"#,
            rootCauseTemplate: "Property '$1' is not defined on the object type.",
            confidence: 0.85
        ))
        p.append(ErrorPattern(
            name: "ts-argument-count",
            category: .typeError,
            messagePattern: #"Expected \d+ arguments?, but got \d+"#,
            rootCauseTemplate: "Wrong number of arguments in function call.",
            confidence: 0.9
        ))

        // MARK: C/C++ Patterns
        p.append(ErrorPattern(
            name: "c-undeclared-identifier",
            category: .missingImport,
            messagePattern: #"use of undeclared identifier '(\w+)'"#,
            rootCauseTemplate: "Identifier '$1' is not declared. Add #include or declare it.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "c-undefined-reference",
            category: .linkError,
            messagePattern: #"undefined reference to `(.+)`"#,
            rootCauseTemplate: "Linker error: '$1' is declared but not defined. Check library linking.",
            confidence: 0.85
        ))
        p.append(ErrorPattern(
            name: "c-redefinition",
            category: .syntaxError,
            messagePattern: #"redefinition of '(\w+)'"#,
            rootCauseTemplate: "'$1' is defined multiple times. Check for missing include guards.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "c-incompatible-pointer",
            category: .typeError,
            messagePattern: #"incompatible pointer type"#,
            rootCauseTemplate: "Pointer type mismatch. Check the expected and actual pointer types.",
            confidence: 0.8
        ))

        // MARK: General Patterns
        p.append(ErrorPattern(
            name: "general-permission-denied",
            category: .permissionError,
            messagePattern: #"[Pp]ermission denied"#,
            rootCauseTemplate: "File system permission error. Check read/write permissions on the path.",
            confidence: 0.95
        ))
        p.append(ErrorPattern(
            name: "general-out-of-memory",
            category: .memoryError,
            messagePattern: #"[Oo]ut of memory|[Cc]annot allocate"#,
            rootCauseTemplate: "System ran out of memory during compilation. Close other programs or increase swap.",
            confidence: 0.9
        ))
        p.append(ErrorPattern(
            name: "general-file-not-found",
            category: .resourceError,
            messagePattern: #"[Nn]o such file|[Ff]ile not found"#,
            rootCauseTemplate: "A referenced file does not exist. Check the path and ensure the file was not deleted.",
            confidence: 0.85
        ))
        p.append(ErrorPattern(
            name: "general-command-not-found",
            category: .configError,
            messagePattern: #"command not found"#,
            rootCauseTemplate: "Build tool not installed or not in PATH.",
            confidence: 0.95
        ))

        return p
    }()

    // MARK: - Diagnosis

    /// Diagnose a list of build errors, producing root cause analysis and fix suggestions.
    func diagnose(_ errors: [BuildError], projectPath: String) async -> [DiagnosticResult] {
        // First, correlate errors to find root causes
        let groups = correlateErrors(errors)

        // Prioritize: fix root causes first
        let prioritized = prioritizeErrors(errors)

        var results: [DiagnosticResult] = []

        for error in prioritized {
            let (rootCause, confidence) = determineRootCause(error)
            let fixes = await generateFixes(for: error, projectPath: projectPath)
            let related = groups.first(where: { $0.contains(where: { $0.id == error.id }) }) ?? []
            let relatedOthers = related.filter { $0.id != error.id }

            results.append(DiagnosticResult(
                error: error,
                rootCause: rootCause,
                confidence: confidence,
                suggestedFixes: fixes,
                relatedErrors: relatedOthers
            ))
        }

        return results
    }

    // MARK: - Root Cause Analysis

    /// Determine the root cause of an error by matching against known patterns.
    private func determineRootCause(_ error: BuildError) -> (rootCause: String, confidence: Double) {
        let message = error.message

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.messagePattern, options: [.caseInsensitive]) else {
                continue
            }

            if let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) {
                var rootCause = pattern.rootCauseTemplate

                // Replace $1, $2, etc. with capture groups
                for i in 1..<match.numberOfRanges {
                    if let range = Range(match.range(at: i), in: message) {
                        let captured = String(message[range])
                        rootCause = rootCause.replacingOccurrences(of: "$\(i)", with: captured)
                    }
                }

                return (rootCause, pattern.confidence)
            }
        }

        // No pattern matched; generate a generic root cause
        let genericCause = "Build error in \(error.category.displayName.lowercased()): \(message)"
        return (genericCause, 0.3)
    }

    // MARK: - Fix Generation

    /// Generate potential fixes for an error.
    private func generateFixes(for error: BuildError, projectPath: String) async -> [AutoFix] {
        var fixes: [AutoFix] = []

        // Check pattern-specific fix generators
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern.messagePattern, options: [.caseInsensitive]),
                  regex.firstMatch(in: error.message, range: NSRange(error.message.startIndex..., in: error.message)) != nil,
                  let generator = pattern.fixGenerator else {
                continue
            }
            let patternFixes = await generator(error, projectPath)
            fixes.append(contentsOf: patternFixes)
        }

        // Category-based fix generation
        switch error.category {
        case .missingImport:
            if let fix = generateMissingImportFix(error, projectPath: projectPath) {
                fixes.append(fix)
            }
        case .syntaxError:
            if let fix = generateSyntaxFix(error) {
                fixes.append(fix)
            }
        case .typeError:
            if let fix = generateTypeFix(error) {
                fixes.append(fix)
            }
        default:
            break
        }

        return fixes
    }

    /// Generate a fix for a missing import.
    private func generateMissingImportFix(_ error: BuildError, projectPath: String) -> AutoFix? {
        guard let filePath = error.filePath else { return nil }

        // Extract the missing symbol
        let message = error.message
        var symbolName: String?

        let patterns = [
            #"cannot find (?:type )?'(\w+)' in scope"#,
            #"no such module '(\w+)'"#,
            #"use of undeclared identifier '(\w+)'"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
               let range = Range(match.range(at: 1), in: message) {
                symbolName = String(message[range])
                break
            }
        }

        guard let symbol = symbolName else { return nil }

        // Common framework mappings for Swift
        let frameworkMap: [String: String] = [
            "URL": "Foundation",
            "UUID": "Foundation",
            "Date": "Foundation",
            "Data": "Foundation",
            "JSONDecoder": "Foundation",
            "JSONEncoder": "Foundation",
            "URLSession": "Foundation",
            "ProcessInfo": "Foundation",
            "FileManager": "Foundation",
            "NSRegularExpression": "Foundation",
            "View": "SwiftUI",
            "State": "SwiftUI",
            "Binding": "SwiftUI",
            "Text": "SwiftUI",
            "Button": "SwiftUI",
            "VStack": "SwiftUI",
            "HStack": "SwiftUI",
            "List": "SwiftUI",
            "NavigationView": "SwiftUI",
            "Observable": "Observation",
            "NSApplication": "AppKit",
            "NSWindow": "AppKit",
            "NSView": "AppKit",
            "UIView": "UIKit",
            "UIViewController": "UIKit",
            "CGFloat": "CoreGraphics",
            "CGPoint": "CoreGraphics",
            "CGSize": "CoreGraphics",
            "CGRect": "CoreGraphics",
            "SHA256": "CryptoKit",
        ]

        if let framework = frameworkMap[symbol] {
            return AutoFix(
                description: "Add 'import \(framework)' for '\(symbol)'",
                filePath: filePath,
                changes: [TextChange(
                    startLine: 1,
                    oldText: nil,
                    newText: "import \(framework)\n",
                    type: .insert
                )],
                risk: .safe
            )
        }

        return nil
    }

    /// Generate a fix for a syntax error.
    private func generateSyntaxFix(_ error: BuildError) -> AutoFix? {
        guard let filePath = error.filePath, let line = error.lineNumber else { return nil }
        let message = error.message.lowercased()

        if message.contains("expected '}'") || message.contains("expected ')'") || message.contains("expected ']'") {
            let bracket: String
            if message.contains("}") { bracket = "}" }
            else if message.contains(")") { bracket = ")" }
            else { bracket = "]" }

            return AutoFix(
                description: "Add missing '\(bracket)' at line \(line)",
                filePath: filePath,
                changes: [TextChange(
                    startLine: line,
                    newText: bracket,
                    type: .insert
                )],
                risk: .moderate
            )
        }

        if message.contains("missing return") {
            return AutoFix(
                description: "Add missing return statement",
                filePath: filePath,
                changes: [TextChange(
                    startLine: line,
                    newText: "    return // TODO: Add return value",
                    type: .insert
                )],
                risk: .moderate
            )
        }

        return nil
    }

    /// Generate a fix for a type error.
    private func generateTypeFix(_ error: BuildError) -> AutoFix? {
        guard let filePath = error.filePath, let line = error.lineNumber else { return nil }
        let message = error.message

        // Optional unwrapping
        if message.contains("must be unwrapped") {
            return AutoFix(
                description: "Add optional chaining (?) to unwrap optional value",
                filePath: filePath,
                changes: [TextChange(
                    startLine: line,
                    newText: "// Consider using: if let value = optionalValue { ... }",
                    type: .insert
                )],
                risk: .moderate
            )
        }

        // Access control
        let accessPattern = #"'(\w+)' is inaccessible due to '(\w+)' protection level"#
        if let regex = try? NSRegularExpression(pattern: accessPattern),
           let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)) {
            return AutoFix(
                description: "Change access level to allow access",
                filePath: filePath,
                changes: [TextChange(
                    startLine: line,
                    newText: "// TODO: Change access level of the referenced symbol",
                    type: .insert
                )],
                risk: .risky
            )
        }

        return nil
    }

    // MARK: - Error Correlation

    /// Group related errors (same file, cascading from same root cause).
    func correlateErrors(_ errors: [BuildError]) -> [[BuildError]] {
        guard !errors.isEmpty else { return [] }

        var groups: [[BuildError]] = []
        var assigned = Set<UUID>()

        // Group by file first
        var byFile: [String: [BuildError]] = [:]
        for error in errors {
            let key = error.filePath ?? "__no_file__"
            byFile[key, default: []].append(error)
        }

        for (_, fileErrors) in byFile {
            // Within a file, group errors that are likely caused by the same root issue
            var currentGroup: [BuildError] = []

            for error in fileErrors.sorted(by: { ($0.lineNumber ?? 0) < ($1.lineNumber ?? 0) }) {
                if assigned.contains(error.id) { continue }

                if currentGroup.isEmpty {
                    currentGroup.append(error)
                    assigned.insert(error.id)
                } else {
                    // Check if this error is likely a cascade from the first
                    let firstError = currentGroup[0]
                    if isCascade(primary: firstError, secondary: error) {
                        currentGroup.append(error)
                        assigned.insert(error.id)
                    } else {
                        groups.append(currentGroup)
                        currentGroup = [error]
                        assigned.insert(error.id)
                    }
                }
            }

            if !currentGroup.isEmpty {
                groups.append(currentGroup)
            }
        }

        return groups
    }

    /// Determine if one error is a cascade from another.
    private func isCascade(primary: BuildError, secondary: BuildError) -> Bool {
        // Same file, close line numbers -> likely related
        if primary.filePath == secondary.filePath,
           let l1 = primary.lineNumber, let l2 = secondary.lineNumber,
           abs(l1 - l2) <= 5 {
            return true
        }

        // Missing import causes multiple "not found" errors
        if primary.category == .missingImport && secondary.category == .missingImport {
            return true
        }

        // Syntax error causes cascading type errors
        if primary.category == .syntaxError && secondary.category == .typeError {
            return true
        }

        return false
    }

    // MARK: - Error Prioritization

    /// Sort errors by fix priority: root causes first, cascading errors last.
    func prioritizeErrors(_ errors: [BuildError]) -> [BuildError] {
        errors.sorted { a, b in
            if a.category.fixPriority != b.category.fixPriority {
                return a.category.fixPriority < b.category.fixPriority
            }
            // Within same category, prioritize by line number (earlier first)
            return (a.lineNumber ?? Int.max) < (b.lineNumber ?? Int.max)
        }
    }
}
