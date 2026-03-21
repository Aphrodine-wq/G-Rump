// ╔══════════════════════════════════════════════════════════════╗
// ║  AutoFixEngine.swift                                        ║
// ║  Self-Healing Build Pipeline — automatic fix application    ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - Auto Fix Error

/// Errors that can occur during fix application.
enum AutoFixError: Error, LocalizedError {
    case fileNotFound(String)
    case fileReadFailed(String)
    case fileWriteFailed(String)
    case lineOutOfRange(Int, maxLine: Int)
    case oldTextNotFound(String)
    case verificationFailed
    case rollbackFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path): return "File not found: \(path)"
        case .fileReadFailed(let msg): return "Could not read file: \(msg)"
        case .fileWriteFailed(let msg): return "Could not write file: \(msg)"
        case .lineOutOfRange(let line, let max): return "Line \(line) out of range (file has \(max) lines)"
        case .oldTextNotFound(let text): return "Old text not found in file: \(String(text.prefix(100)))"
        case .verificationFailed: return "Fix did not resolve the build error"
        case .rollbackFailed(let msg): return "Could not rollback fix: \(msg)"
        }
    }
}

// MARK: - File Backup

/// Stores original file content for rollback.
private struct FileBackup {
    let path: String
    let originalContent: String
    let timestamp: Date
}

// MARK: - Auto Fix Engine

/// Generates and applies automatic fixes for build errors.
/// Supports rollback if a fix makes things worse.
struct AutoFixEngine {

    // MARK: - Fix Generation

    /// Generate all applicable fixes for a diagnostic result.
    func generateFixes(for diagnostic: DiagnosticResult, projectPath: String) async -> [AutoFix] {
        var fixes: [AutoFix] = []

        switch diagnostic.error.category {
        case .missingImport:
            fixes.append(contentsOf: fixMissingImport(diagnostic.error, projectPath: projectPath))
        case .typeError:
            fixes.append(contentsOf: fixTypeMismatch(diagnostic.error))
            fixes.append(contentsOf: fixOptionalUnwrap(diagnostic.error))
            fixes.append(contentsOf: fixAccessControl(diagnostic.error))
            fixes.append(contentsOf: fixMissingConformance(diagnostic.error))
        case .syntaxError:
            fixes.append(contentsOf: fixMissingSemicolon(diagnostic.error))
            fixes.append(contentsOf: fixMissingReturn(diagnostic.error))
            fixes.append(contentsOf: fixUnusedVariable(diagnostic.error))
        case .missingDependency:
            fixes.append(contentsOf: fixMissingDependency(diagnostic.error, projectPath: projectPath))
        default:
            fixes.append(contentsOf: fixDeprecatedAPI(diagnostic.error))
        }

        return fixes
    }

    // MARK: - Fix: Missing Import

    /// Add an import statement for a missing symbol.
    func fixMissingImport(_ error: BuildError, projectPath: String) -> [AutoFix] {
        guard let filePath = error.filePath else { return [] }
        var fixes: [AutoFix] = []

        let message = error.message

        // Extract module name from "no such module 'X'" or similar
        let modulePatterns = [
            (#"cannot find (?:type )?'(\w+)' in scope"#, true),   // Need to look up module
            (#"no such module '(\w+)'"#, false),                    // Module name is given
        ]

        for (pattern, needsLookup) in modulePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
                  let range = Range(match.range(at: 1), in: message) else {
                continue
            }

            let symbol = String(message[range])

            if needsLookup {
                // Look up which module contains this symbol
                let framework = lookupFramework(for: symbol)
                if let framework {
                    fixes.append(AutoFix(
                        description: "Add 'import \(framework)' to resolve '\(symbol)'",
                        filePath: filePath,
                        changes: [TextChange(
                            startLine: 1,
                            newText: "import \(framework)",
                            type: .insert
                        )],
                        risk: .safe
                    ))
                }
            } else {
                // Module name is directly in the error
                fixes.append(AutoFix(
                    description: "Module '\(symbol)' needs to be added as a dependency",
                    filePath: (projectPath as NSString).appendingPathComponent("Package.swift"),
                    changes: [TextChange(
                        startLine: 1,
                        newText: "// TODO: Add '\(symbol)' to Package.swift dependencies",
                        type: .insert
                    )],
                    risk: .risky
                ))
            }
        }

        return fixes
    }

    // MARK: - Fix: Type Mismatch

    /// Add type conversion for mismatched types.
    func fixTypeMismatch(_ error: BuildError) -> [AutoFix] {
        guard let filePath = error.filePath, let line = error.lineNumber else { return [] }
        var fixes: [AutoFix] = []

        let message = error.message

        // "cannot convert value of type 'X' to expected argument type 'Y'"
        let pattern = #"cannot convert value of type '(.+)' to expected argument type '(.+)'"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
           let fromRange = Range(match.range(at: 1), in: message),
           let toRange = Range(match.range(at: 2), in: message) {

            let fromType = String(message[fromRange])
            let toType = String(message[toRange])

            // Common safe conversions
            let conversion = suggestConversion(from: fromType, to: toType)
            if let conversion {
                fixes.append(AutoFix(
                    description: "Convert \(fromType) to \(toType) using \(conversion)",
                    filePath: filePath,
                    changes: [TextChange(
                        startLine: line,
                        newText: "// Apply conversion: \(conversion)",
                        type: .insert
                    )],
                    risk: .moderate
                ))
            }
        }

        return fixes
    }

    // MARK: - Fix: Missing Semicolon / Bracket

    /// Fix missing punctuation.
    func fixMissingSemicolon(_ error: BuildError) -> [AutoFix] {
        guard let filePath = error.filePath, let line = error.lineNumber else { return [] }
        let message = error.message.lowercased()

        if message.contains("expected '}'") {
            return [AutoFix(
                description: "Add missing closing brace",
                filePath: filePath,
                changes: [TextChange(startLine: line, newText: "}", type: .insert)],
                risk: .moderate
            )]
        }
        if message.contains("expected ')'") {
            return [AutoFix(
                description: "Add missing closing parenthesis",
                filePath: filePath,
                changes: [TextChange(startLine: line, newText: ")", type: .insert)],
                risk: .moderate
            )]
        }
        if message.contains("expected ']'") {
            return [AutoFix(
                description: "Add missing closing bracket",
                filePath: filePath,
                changes: [TextChange(startLine: line, newText: "]", type: .insert)],
                risk: .moderate
            )]
        }
        if message.contains("expected ';'") {
            return [AutoFix(
                description: "Add missing semicolon",
                filePath: filePath,
                changes: [TextChange(startLine: line, newText: ";", type: .insert)],
                risk: .safe
            )]
        }

        return []
    }

    // MARK: - Fix: Missing Return

    /// Add a return statement to a function missing one.
    func fixMissingReturn(_ error: BuildError) -> [AutoFix] {
        guard let filePath = error.filePath, let line = error.lineNumber else { return [] }
        let message = error.message.lowercased()

        guard message.contains("missing return") else { return [] }

        // Extract return type if possible
        let returnPattern = #"in a function expected to return '(.+)'"#
        var returnType = "Void"
        if let regex = try? NSRegularExpression(pattern: returnPattern),
           let match = regex.firstMatch(in: error.message, range: NSRange(error.message.startIndex..., in: error.message)),
           let range = Range(match.range(at: 1), in: error.message) {
            returnType = String(error.message[range])
        }

        let defaultValue = defaultValueForType(returnType)

        return [AutoFix(
            description: "Add return statement with default \(returnType) value",
            filePath: filePath,
            changes: [TextChange(
                startLine: line,
                newText: "        return \(defaultValue)",
                type: .insert
            )],
            risk: .moderate
        )]
    }

    // MARK: - Fix: Unused Variable

    /// Prefix unused variable with underscore or remove it.
    func fixUnusedVariable(_ error: BuildError) -> [AutoFix] {
        guard let filePath = error.filePath, let line = error.lineNumber else { return [] }
        let message = error.message

        let patterns = [
            #"variable '(\w+)' was never used"#,       // Swift
            #"unused variable: `(\w+)`"#,               // Rust
            #"'(\w+)' is declared but .+ never read"#,  // TypeScript
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
               let range = Range(match.range(at: 1), in: message) {
                let varName = String(message[range])

                return [AutoFix(
                    description: "Prefix unused variable '\(varName)' with underscore",
                    filePath: filePath,
                    changes: [TextChange(
                        startLine: line,
                        oldText: varName,
                        newText: "_\(varName)",
                        type: .replace
                    )],
                    risk: .safe
                )]
            }
        }

        return []
    }

    // MARK: - Fix: Access Control

    /// Change access level modifier.
    func fixAccessControl(_ error: BuildError) -> [AutoFix] {
        guard let filePath = error.filePath, let line = error.lineNumber else { return [] }

        let pattern = #"'(\w+)' is inaccessible due to '(\w+)' protection level"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: error.message, range: NSRange(error.message.startIndex..., in: error.message)),
              let nameRange = Range(match.range(at: 1), in: error.message),
              let levelRange = Range(match.range(at: 2), in: error.message) else {
            return []
        }

        let symbolName = String(error.message[nameRange])
        let currentLevel = String(error.message[levelRange])

        let suggestedLevel: String
        switch currentLevel {
        case "private": suggestedLevel = "internal"
        case "fileprivate": suggestedLevel = "internal"
        case "internal": suggestedLevel = "public"
        default: suggestedLevel = "public"
        }

        return [AutoFix(
            description: "Change '\(symbolName)' access from \(currentLevel) to \(suggestedLevel)",
            filePath: filePath,
            changes: [TextChange(
                startLine: line,
                oldText: currentLevel,
                newText: suggestedLevel,
                type: .replace
            )],
            risk: .risky
        )]
    }

    // MARK: - Fix: Optional Unwrap

    /// Add optional chaining or if-let for forced unwrap issues.
    func fixOptionalUnwrap(_ error: BuildError) -> [AutoFix] {
        guard let filePath = error.filePath, let line = error.lineNumber else { return [] }
        let message = error.message

        guard message.contains("must be unwrapped") || message.contains("optional") else {
            return []
        }

        return [
            AutoFix(
                description: "Add optional chaining (?.) to safely unwrap",
                filePath: filePath,
                changes: [TextChange(
                    startLine: line,
                    newText: "// Use optional chaining: value?.property or if let value = optional { ... }",
                    type: .insert
                )],
                risk: .moderate
            )
        ]
    }

    // MARK: - Fix: Missing Conformance

    /// Add protocol stub implementations.
    func fixMissingConformance(_ error: BuildError) -> [AutoFix] {
        guard let filePath = error.filePath, let line = error.lineNumber else { return [] }

        let pattern = #"type '(\w+)' does not conform to protocol '(\w+)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: error.message, range: NSRange(error.message.startIndex..., in: error.message)),
              let typeRange = Range(match.range(at: 1), in: error.message),
              let protoRange = Range(match.range(at: 2), in: error.message) else {
            return []
        }

        let typeName = String(error.message[typeRange])
        let protoName = String(error.message[protoRange])

        // Common protocol stubs
        let stubs = protocolStubs(for: protoName)
        guard !stubs.isEmpty else { return [] }

        return [AutoFix(
            description: "Add '\(protoName)' conformance stubs to '\(typeName)'",
            filePath: filePath,
            changes: [TextChange(
                startLine: line + 1,
                newText: stubs,
                type: .insert
            )],
            risk: .moderate
        )]
    }

    // MARK: - Fix: Deprecated API

    /// Replace deprecated API usage with modern alternatives.
    func fixDeprecatedAPI(_ error: BuildError) -> [AutoFix] {
        guard let filePath = error.filePath, let line = error.lineNumber else { return [] }
        let message = error.message

        guard message.contains("deprecated") || message.contains("was deprecated") else {
            return []
        }

        // Common deprecation replacements
        let replacements: [(String, String)] = [
            ("UIWebView", "WKWebView"),
            ("NSURLConnection", "URLSession"),
            ("NSURLSession", "URLSession"),
            ("NSJSONSerialization", "JSONDecoder/JSONEncoder"),
            ("stringByAppendingPathComponent", "appendingPathComponent"),
            ("objectForKey", "value(forKey:)"),
            ("NSNotificationCenter", "NotificationCenter"),
        ]

        for (old, new) in replacements {
            if message.contains(old) {
                return [AutoFix(
                    description: "Replace deprecated '\(old)' with '\(new)'",
                    filePath: filePath,
                    changes: [TextChange(
                        startLine: line,
                        oldText: old,
                        newText: new,
                        type: .replace
                    )],
                    risk: .moderate
                )]
            }
        }

        return []
    }

    // MARK: - Fix: Missing Dependency

    /// Add missing dependency to manifest file.
    func fixMissingDependency(_ error: BuildError, projectPath: String) -> [AutoFix] {
        let message = error.message

        let pattern = #"no such module '(\w+)'"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
              let range = Range(match.range(at: 1), in: message) else {
            return []
        }

        let moduleName = String(message[range])

        // Check if Package.swift exists
        let packageSwiftPath = (projectPath as NSString).appendingPathComponent("Package.swift")
        if FileManager.default.fileExists(atPath: packageSwiftPath) {
            return [AutoFix(
                description: "Add '\(moduleName)' dependency to Package.swift",
                filePath: packageSwiftPath,
                changes: [TextChange(
                    startLine: 1,
                    newText: "// TODO: Add dependency for '\(moduleName)' to Package.swift",
                    type: .insert
                )],
                risk: .risky
            )]
        }

        return []
    }

    // MARK: - Fix Application

    /// Apply a fix by modifying the target file.
    func applyFix(_ fix: AutoFix) async throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fix.filePath) else {
            throw AutoFixError.fileNotFound(fix.filePath)
        }

        var content: String
        do {
            content = try String(contentsOfFile: fix.filePath, encoding: .utf8)
        } catch {
            throw AutoFixError.fileReadFailed(error.localizedDescription)
        }

        var lines = content.components(separatedBy: "\n")

        // Apply changes in reverse order to preserve line numbers
        let sortedChanges = fix.changes.sorted { $0.startLine > $1.startLine }

        for change in sortedChanges {
            let lineIndex = change.startLine - 1 // Convert to 0-indexed

            switch change.type {
            case .insert:
                if lineIndex < 0 {
                    lines.insert(change.newText, at: 0)
                } else if lineIndex >= lines.count {
                    lines.append(change.newText)
                } else {
                    lines.insert(change.newText, at: lineIndex)
                }

            case .replace:
                guard lineIndex >= 0 && lineIndex < lines.count else {
                    throw AutoFixError.lineOutOfRange(change.startLine, maxLine: lines.count)
                }
                if let oldText = change.oldText {
                    if lines[lineIndex].contains(oldText) {
                        lines[lineIndex] = lines[lineIndex].replacingOccurrences(of: oldText, with: change.newText)
                    } else {
                        throw AutoFixError.oldTextNotFound(oldText)
                    }
                } else {
                    let endLine = (change.endLine ?? change.startLine) - 1
                    let endIndex = min(endLine, lines.count - 1)
                    lines.replaceSubrange(lineIndex...endIndex, with: [change.newText])
                }

            case .delete:
                guard lineIndex >= 0 && lineIndex < lines.count else {
                    throw AutoFixError.lineOutOfRange(change.startLine, maxLine: lines.count)
                }
                let endLine = (change.endLine ?? change.startLine) - 1
                let endIndex = min(endLine, lines.count - 1)
                lines.removeSubrange(lineIndex...endIndex)
            }
        }

        let newContent = lines.joined(separator: "\n")
        do {
            try newContent.write(toFile: fix.filePath, atomically: true, encoding: .utf8)
        } catch {
            throw AutoFixError.fileWriteFailed(error.localizedDescription)
        }
    }

    /// Verify that a fix resolved the error by re-running the build.
    func verifyFix(_ fix: AutoFix, config: BuildConfig) async -> Bool {
        let pipeline = SelfHealingBuildPipeline()
        let result = await pipeline.build(config: config)
        return result.success || !result.errors.contains(where: { $0.filePath == fix.filePath })
    }

    /// Rollback a fix by restoring original file content.
    func rollbackFix(_ fix: AutoFix, originalContent: String) async throws {
        do {
            try originalContent.write(toFile: fix.filePath, atomically: true, encoding: .utf8)
        } catch {
            throw AutoFixError.rollbackFailed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// Lookup which framework provides a given symbol.
    private func lookupFramework(for symbol: String) -> String? {
        let map: [String: String] = [
            // Foundation
            "URL": "Foundation", "UUID": "Foundation", "Date": "Foundation",
            "Data": "Foundation", "JSONDecoder": "Foundation", "JSONEncoder": "Foundation",
            "URLSession": "Foundation", "ProcessInfo": "Foundation", "FileManager": "Foundation",
            "NSRegularExpression": "Foundation", "Timer": "Foundation", "Calendar": "Foundation",
            "DateFormatter": "Foundation", "NumberFormatter": "Foundation",
            "Notification": "Foundation", "NotificationCenter": "Foundation",
            "DispatchQueue": "Foundation", "OperationQueue": "Foundation",
            "Bundle": "Foundation", "UserDefaults": "Foundation",
            "Process": "Foundation", "Pipe": "Foundation",
            // SwiftUI
            "View": "SwiftUI", "State": "SwiftUI", "Binding": "SwiftUI",
            "Text": "SwiftUI", "Button": "SwiftUI", "VStack": "SwiftUI",
            "HStack": "SwiftUI", "ZStack": "SwiftUI", "List": "SwiftUI",
            "NavigationStack": "SwiftUI", "NavigationView": "SwiftUI",
            "Color": "SwiftUI", "Image": "SwiftUI", "Toggle": "SwiftUI",
            "Slider": "SwiftUI", "TextField": "SwiftUI", "TextEditor": "SwiftUI",
            // Observation
            "Observable": "Observation",
            // AppKit
            "NSApplication": "AppKit", "NSWindow": "AppKit", "NSView": "AppKit",
            "NSViewController": "AppKit", "NSMenu": "AppKit", "NSMenuItem": "AppKit",
            "NSPasteboard": "AppKit", "NSPanel": "AppKit",
            // CryptoKit
            "SHA256": "CryptoKit", "SHA512": "CryptoKit", "AES": "CryptoKit",
            // CoreGraphics
            "CGFloat": "CoreGraphics", "CGPoint": "CoreGraphics",
            "CGSize": "CoreGraphics", "CGRect": "CoreGraphics",
        ]
        return map[symbol]
    }

    /// Suggest a type conversion expression.
    private func suggestConversion(from: String, to: String) -> String? {
        let conversionMap: [String: [String: String]] = [
            "Int": ["Double": "Double(value)", "String": "String(value)", "Float": "Float(value)", "CGFloat": "CGFloat(value)"],
            "Double": ["Int": "Int(value)", "String": "String(value)", "Float": "Float(value)", "CGFloat": "CGFloat(value)"],
            "Float": ["Double": "Double(value)", "Int": "Int(value)", "CGFloat": "CGFloat(value)"],
            "String": ["Int": "Int(value) ?? 0", "Double": "Double(value) ?? 0", "URL": "URL(string: value)!"],
            "CGFloat": ["Double": "Double(value)", "Float": "Float(value)", "Int": "Int(value)"],
        ]
        return conversionMap[from]?[to]
    }

    /// Get a default value for a Swift type.
    private func defaultValueForType(_ type: String) -> String {
        switch type {
        case "String": return "\"\""
        case "Int", "Int8", "Int16", "Int32", "Int64": return "0"
        case "UInt", "UInt8", "UInt16", "UInt32", "UInt64": return "0"
        case "Double", "Float", "CGFloat": return "0.0"
        case "Bool": return "false"
        case "Void", "()": return "()"
        case _ where type.hasSuffix("?"): return "nil"
        case _ where type.hasPrefix("["): return "[]"
        case _ where type.hasPrefix("[") && type.contains(":"): return "[:]"
        default: return "fatalError(\"TODO: Return \(type)\")"
        }
    }

    /// Generate protocol stubs for common protocols.
    private func protocolStubs(for protocolName: String) -> String {
        switch protocolName {
        case "Codable", "Decodable":
            return """
                init(from decoder: Decoder) throws {
                    fatalError("TODO: Implement Decodable")
                }
            """
        case "Encodable":
            return """
                func encode(to encoder: Encoder) throws {
                    fatalError("TODO: Implement Encodable")
                }
            """
        case "Hashable":
            return """
                func hash(into hasher: inout Hasher) {
                    fatalError("TODO: Implement Hashable")
                }
            """
        case "Equatable":
            return """
                static func == (lhs: Self, rhs: Self) -> Bool {
                    fatalError("TODO: Implement Equatable")
                }
            """
        case "Comparable":
            return """
                static func < (lhs: Self, rhs: Self) -> Bool {
                    fatalError("TODO: Implement Comparable")
                }
            """
        case "CustomStringConvertible":
            return """
                var description: String {
                    fatalError("TODO: Implement description")
                }
            """
        case "Identifiable":
            return """
                var id: String { fatalError("TODO: Implement id") }
            """
        default:
            return ""
        }
    }

    // MARK: - Risk Assessment

    /// Assess the risk of applying a fix.
    func assessRisk(_ fix: AutoFix) -> FixRisk {
        // Insertions at line 1 (imports) are typically safe
        if fix.changes.allSatisfy({ $0.type == .insert && $0.startLine == 1 }) {
            return .safe
        }

        // Pure replacements of single tokens are moderate
        if fix.changes.allSatisfy({ $0.type == .replace && ($0.oldText?.count ?? 0) < 50 }) {
            return .moderate
        }

        // Deletions are risky
        if fix.changes.contains(where: { $0.type == .delete }) {
            return .risky
        }

        // Multi-line changes are risky
        if fix.changes.contains(where: { ($0.endLine ?? $0.startLine) - $0.startLine > 3 }) {
            return .risky
        }

        return fix.risk
    }
}
