import Foundation

// MARK: - CodeDNA Analyzer

/// Analyzes entire projects to produce comprehensive code quality reports.
/// Walks directory trees, dispatches to language-specific analyzers in parallel,
/// and aggregates results into a unified CodeDNAReport.
final class CodeDNAAnalyzer: Sendable {

    // MARK: - Configuration

    private let maxFileSizeBytes: Int = 5 * 1024 * 1024  // 5 MB
    private let ignoredDirectories: Set<String> = [
        ".git", ".build", "node_modules", ".swiftpm", "DerivedData",
        "Pods", ".next", "dist", "build", "__pycache__", ".cache",
        "vendor", "target", ".grump", ".DS_Store"
    ]

    // MARK: - Cache

    private let cacheActor = AnalysisCacheActor()

    actor AnalysisCacheActor {
        var cache: [String: (analysis: FileAnalysis, modDate: Date)] = [:]

        func get(_ path: String, modDate: Date) -> FileAnalysis? {
            guard let cached = cache[path], cached.modDate == modDate else { return nil }
            return cached.analysis
        }

        func set(_ path: String, analysis: FileAnalysis, modDate: Date) {
            cache[path] = (analysis, modDate)
        }

        func clear() {
            cache.removeAll()
        }
    }

    // MARK: - Project Analysis

    /// Analyze an entire project at the given path.
    func analyzeProject(at path: String, languages: [Language] = Language.allCases) async -> CodeDNAReport {
        let allowedExtensions = Set(languages.flatMap(\.extensions))
        let sourceFiles = discoverSourceFiles(at: path, allowedExtensions: allowedExtensions)

        // Analyze files in parallel using TaskGroup
        let fileAnalyses = await analyzeFilesInParallel(sourceFiles, basePath: path)

        // Build dependency graph
        let graphBuilder = DependencyGraphBuilder()
        let dependencyGraph = await graphBuilder.buildGraph(for: sourceFiles, basePath: path)

        // Detect duplications
        let duplicationDetector = DuplicationDetector()
        let duplications = await duplicationDetector.detectDuplication(in: sourceFiles, basePath: path)

        // Detect architectural smells
        let smellDetector = ArchitecturalSmellDetector()
        let smells = smellDetector.detect(in: fileAnalyses, dependencyGraph: dependencyGraph)

        // Aggregate project metrics
        let projectMetrics = aggregateMetrics(fileAnalyses)

        return CodeDNAReport(
            projectPath: path,
            timestamp: Date(),
            fileAnalyses: fileAnalyses,
            projectMetrics: projectMetrics,
            smells: smells,
            duplications: duplications,
            dependencyGraph: dependencyGraph
        )
    }

    // MARK: - File Analysis

    /// Analyze files in parallel, batched for memory efficiency.
    private func analyzeFilesInParallel(_ files: [String], basePath: String) async -> [FileAnalysis] {
        let batchSize = 20

        var allAnalyses: [FileAnalysis] = []

        for batchStart in stride(from: 0, to: files.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, files.count)
            let batch = Array(files[batchStart..<batchEnd])

            let batchResults = await withTaskGroup(of: FileAnalysis?.self) { group in
                for filePath in batch {
                    group.addTask {
                        await self.analyzeFile(filePath, basePath: basePath)
                    }
                }

                var results: [FileAnalysis] = []
                for await result in group {
                    if let analysis = result {
                        results.append(analysis)
                    }
                }
                return results
            }

            allAnalyses.append(contentsOf: batchResults)
        }

        return allAnalyses.sorted(by: { $0.filePath < $1.filePath })
    }

    /// Analyze a single file, using cache when possible.
    func analyzeFile(_ path: String, basePath: String) async -> FileAnalysis? {
        let fm = FileManager.default

        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else {
            return nil
        }

        // Check cache
        if let cached = await cacheActor.get(path, modDate: modDate) {
            return cached
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return nil
        }

        let ext = (path as NSString).pathExtension
        let language = Language.from(extension: ext)
        guard language != .unknown else { return nil }

        let relativePath = makeRelativePath(path, from: basePath)
        let analysis = analyzeFileContent(content, filePath: relativePath, language: language)

        await cacheActor.set(path, analysis: analysis, modDate: modDate)
        return analysis
    }

    /// Perform the actual analysis on file content.
    func analyzeFileContent(_ content: String, filePath: String, language: Language) -> FileAnalysis {
        let lines = content.components(separatedBy: .newlines)
        let lineCount = lines.count

        // Count line types
        var blankLines = 0
        var commentLines = 0
        var codeLines = 0
        var inBlockComment = false

        let blockDelimiters = language.blockCommentDelimiters

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                blankLines += 1
                continue
            }

            // Handle block comments
            if let delimiters = blockDelimiters {
                if inBlockComment {
                    commentLines += 1
                    if trimmed.contains(delimiters.end) {
                        inBlockComment = false
                    }
                    continue
                }
                if trimmed.hasPrefix(delimiters.start) {
                    commentLines += 1
                    if !trimmed.contains(delimiters.end) || trimmed.hasSuffix(delimiters.start) {
                        inBlockComment = true
                    }
                    continue
                }
            }

            // Line comments
            if trimmed.hasPrefix(language.lineCommentPrefix) {
                commentLines += 1
                continue
            }

            codeLines += 1
        }

        // Extract imports
        let imports = extractImports(from: lines, language: language)

        // Extract and analyze functions
        let functions = extractFunctions(from: content, lines: lines, language: language)

        // Extract and analyze classes/structs
        let classes = extractClasses(from: content, lines: lines, language: language)

        // Calculate complexity
        let complexityAnalyzer = ComplexityAnalyzer()
        let cyclomatic = complexityAnalyzer.analyzeCyclomaticComplexity(content, language: language)
        let cognitive = complexityAnalyzer.analyzeCognitiveComplexity(content, language: language)
        let halstead = complexityAnalyzer.analyzeHalstead(content, language: language)
        let maintainability = complexityAnalyzer.calculateMaintainabilityIndex(
            halstead: halstead, cyclomatic: cyclomatic, loc: codeLines
        )

        let complexity = ComplexityScore(
            cyclomatic: cyclomatic,
            cognitive: cognitive,
            maintainability: maintainability,
            overall: ComplexityScore.grade(maintainability: maintainability)
        )

        return FileAnalysis(
            filePath: filePath,
            language: language,
            lineCount: lineCount,
            blankLines: blankLines,
            commentLines: commentLines,
            codeLines: codeLines,
            functions: functions,
            classes: classes,
            imports: imports,
            complexity: complexity
        )
    }

    // MARK: - Import Extraction

    private func extractImports(from lines: [String], language: Language) -> [String] {
        var imports: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            switch language {
            case .swift:
                if trimmed.hasPrefix("import ") {
                    let module = trimmed.replacingOccurrences(of: "import ", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    imports.append(module)
                }

            case .typescript, .javascript:
                // import X from 'Y' or import { X } from 'Y'
                if trimmed.hasPrefix("import "), let fromRange = trimmed.range(of: "from ") {
                    let modulePart = String(trimmed[fromRange.upperBound...])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "'\";"))
                    imports.append(modulePart)
                }
                // const X = require('Y')
                if trimmed.contains("require(") {
                    let parts = trimmed.components(separatedBy: "require(")
                    if parts.count > 1 {
                        let module = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "'\");"))
                        imports.append(module)
                    }
                }

            case .rust:
                if trimmed.hasPrefix("use ") {
                    let module = trimmed.replacingOccurrences(of: "use ", with: "")
                        .replacingOccurrences(of: ";", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    imports.append(module)
                }
                if trimmed.hasPrefix("extern crate ") {
                    let module = trimmed.replacingOccurrences(of: "extern crate ", with: "")
                        .replacingOccurrences(of: ";", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    imports.append(module)
                }

            case .python:
                if trimmed.hasPrefix("import ") {
                    let module = trimmed.replacingOccurrences(of: "import ", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    imports.append(module)
                }
                if trimmed.hasPrefix("from ") {
                    let parts = trimmed.components(separatedBy: " import ")
                    if let first = parts.first {
                        let module = first.replacingOccurrences(of: "from ", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        imports.append(module)
                    }
                }

            case .java, .kotlin:
                if trimmed.hasPrefix("import ") {
                    let module = trimmed.replacingOccurrences(of: "import ", with: "")
                        .replacingOccurrences(of: ";", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    imports.append(module)
                }

            case .go:
                if trimmed.hasPrefix("import ") || trimmed.hasPrefix("\"") {
                    let module = trimmed.replacingOccurrences(of: "import", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: " \"()"))
                    if !module.isEmpty {
                        imports.append(module)
                    }
                }

            case .cpp:
                if trimmed.hasPrefix("#include") {
                    let header = trimmed.replacingOccurrences(of: "#include", with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: " <>\"/"))
                    imports.append(header)
                }

            case .unknown:
                break
            }
        }

        return imports
    }

    // MARK: - Function Extraction

    private func extractFunctions(from content: String, lines: [String], language: Language) -> [FunctionMetrics] {
        var functions: [FunctionMetrics] = []
        let complexityAnalyzer = ComplexityAnalyzer()

        // Language-specific function detection patterns
        let funcPattern: String
        switch language {
        case .swift:
            funcPattern = #"(?:(?:public|private|internal|fileprivate|open|static|class|override|mutating|@\w+)\s+)*func\s+(\w+)"#
        case .rust:
            funcPattern = #"(?:pub\s+)?(?:async\s+)?fn\s+(\w+)"#
        case .typescript, .javascript:
            funcPattern = #"(?:(?:export\s+)?(?:async\s+)?function\s+(\w+)|(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?\()"#
        case .python:
            funcPattern = #"def\s+(\w+)\s*\("#
        case .java, .kotlin:
            funcPattern = #"(?:public|private|protected|static|final|abstract|synchronized)?\s*(?:\w+(?:<[^>]+>)?)\s+(\w+)\s*\("#
        case .go:
            funcPattern = #"func\s+(?:\(\w+\s+\*?\w+\)\s+)?(\w+)"#
        case .cpp:
            funcPattern = #"(?:\w+(?:::)?)+\s+(\w+)\s*\("#
        case .unknown:
            return []
        }

        guard let regex = try? NSRegularExpression(pattern: funcPattern, options: []) else {
            return []
        }

        for (lineIndex, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range) else { continue }

            // Get function name from first non-nil capture group
            var funcName = ""
            for groupIdx in 1..<match.numberOfRanges {
                let groupRange = match.range(at: groupIdx)
                if groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: line) {
                    funcName = String(line[swiftRange])
                    break
                }
            }
            guard !funcName.isEmpty else { continue }

            // Find the end of the function by brace matching
            let startLine = lineIndex
            let endLine = findClosingBrace(from: startLine, in: lines)

            // Extract function body
            let bodyLines = Array(lines[startLine...min(endLine, lines.count - 1)])
            let body = bodyLines.joined(separator: "\n")

            // Count parameters
            let paramCount = countParameters(in: line, language: language)

            // Analyze complexity of function body
            let cyclomatic = complexityAnalyzer.analyzeCyclomaticComplexity(body, language: language)
            let cognitive = complexityAnalyzer.analyzeCognitiveComplexity(body, language: language)
            let nesting = complexityAnalyzer.analyzeNestingDepth(body)
            let halstead = complexityAnalyzer.analyzeHalstead(body, language: language)
            let returnCount = body.components(separatedBy: "return ").count - 1

            functions.append(FunctionMetrics(
                name: funcName,
                startLine: startLine + 1,
                endLine: endLine + 1,
                parameterCount: paramCount,
                cyclomaticComplexity: cyclomatic,
                cognitiveComplexity: cognitive,
                nestingDepth: nesting,
                returnCount: max(1, returnCount),
                halsteadMetrics: halstead
            ))
        }

        return functions
    }

    // MARK: - Class Extraction

    private func extractClasses(from content: String, lines: [String], language: Language) -> [ClassMetrics] {
        var classes: [ClassMetrics] = []

        let classPattern: String
        switch language {
        case .swift:
            classPattern = #"(?:(?:public|private|internal|fileprivate|open|final)\s+)*(?:class|struct|actor|enum)\s+(\w+)"#
        case .rust:
            classPattern = #"(?:pub\s+)?(?:struct|enum|trait|impl)\s+(\w+)"#
        case .typescript, .javascript:
            classPattern = #"(?:export\s+)?class\s+(\w+)"#
        case .python:
            classPattern = #"class\s+(\w+)"#
        case .java, .kotlin:
            classPattern = #"(?:public|private|protected)?\s*(?:abstract\s+)?(?:final\s+)?class\s+(\w+)"#
        case .go:
            classPattern = #"type\s+(\w+)\s+struct"#
        case .cpp:
            classPattern = #"(?:class|struct)\s+(\w+)"#
        case .unknown:
            return []
        }

        guard let regex = try? NSRegularExpression(pattern: classPattern, options: []) else {
            return []
        }

        for (lineIndex, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges > 1,
                  let nameRange = Range(match.range(at: 1), in: line) else { continue }

            let className = String(line[nameRange])
            let startLine = lineIndex
            let endLine = findClosingBrace(from: startLine, in: lines)

            // Extract class body
            let bodyLines = Array(lines[startLine...min(endLine, lines.count - 1)])
            let body = bodyLines.joined(separator: "\n")

            // Count methods and properties
            let methodCount = countMethods(in: body, language: language)
            let propertyCount = countProperties(in: body, language: language)

            // Extract protocol conformances (Swift-specific, but generalized)
            let conformances = extractConformances(from: line, language: language)

            // Calculate cohesion (simplified LCOM4)
            let cohesion = calculateCohesion(body: body, methodCount: methodCount, propertyCount: propertyCount)

            classes.append(ClassMetrics(
                name: className,
                startLine: startLine + 1,
                endLine: endLine + 1,
                methodCount: methodCount,
                propertyCount: propertyCount,
                protocolConformances: conformances,
                inheritanceDepth: 0,  // would need full type graph to compute
                responsibilityCount: max(1, conformances.count),
                couplingScore: 0,  // computed later via dependency graph
                cohesionScore: cohesion
            ))
        }

        return classes
    }

    // MARK: - Report Generation

    /// Generate a formatted markdown report from a CodeDNA report.
    func generateReport(_ report: CodeDNAReport) -> String {
        var output = "# Code DNA Analysis Report\n\n"
        output += "**Project:** \(report.projectPath)\n"
        output += "**Analyzed:** \(ISO8601DateFormatter().string(from: report.timestamp))\n"
        output += "**Grade:** \(report.grade)\n\n"

        // Project overview
        output += "## Project Overview\n\n"
        output += "| Metric | Value |\n|--------|-------|\n"
        output += "| Total Files | \(report.projectMetrics.totalFiles) |\n"
        output += "| Total Lines | \(report.projectMetrics.totalLines) |\n"
        output += "| Code Lines | \(report.projectMetrics.totalCodeLines) |\n"
        output += "| Avg Complexity | \(String(format: "%.1f", report.projectMetrics.avgComplexity)) |\n"
        output += "| Max Complexity | \(report.projectMetrics.maxComplexity) |\n"
        output += "| Duplication | \(String(format: "%.1f%%", report.duplicationPercentage)) |\n\n"

        // Language breakdown
        if !report.projectMetrics.languageBreakdown.isEmpty {
            output += "## Language Breakdown\n\n"
            for (lang, lines) in report.projectMetrics.languageBreakdown.sorted(by: { $0.value > $1.value }) {
                output += "- **\(lang)**: \(lines) lines\n"
            }
            output += "\n"
        }

        // Hotspots
        if !report.projectMetrics.hotspots.isEmpty {
            output += "## Hotspots\n\n"
            for hotspot in report.projectMetrics.hotspots.prefix(10) {
                output += "### \(hotspot.filePath) (Score: \(String(format: "%.0f", hotspot.score)), \(hotspot.severity))\n"
                for reason in hotspot.reasons {
                    output += "- \(reason)\n"
                }
                output += "\n"
            }
        }

        // Architectural smells
        if !report.smells.isEmpty {
            output += "## Architectural Smells (\(report.smells.count))\n\n"
            for smell in report.smells.sorted(by: { $0.severity > $1.severity }) {
                output += "### \(smell.name) [\(smell.severity.rawValue.uppercased())]\n"
                output += "\(smell.description)\n"
                output += "**Suggested fix:** \(smell.suggestedRefactoring)\n\n"
            }
        }

        // Duplications
        if !report.duplications.isEmpty {
            output += "## Code Duplication (\(report.duplications.count) clusters)\n\n"
            for cluster in report.duplications.prefix(5) {
                output += "### Cluster (\(cluster.totalDuplicatedLines) duplicated lines)\n"
                for fragment in cluster.fragments {
                    output += "- \(fragment.filePath) lines \(fragment.startLine)-\(fragment.endLine)\n"
                }
                output += "\n"
            }
        }

        return output
    }

    /// Compare two reports and identify improvements and regressions.
    func compareReports(_ before: CodeDNAReport, _ after: CodeDNAReport) -> CodeDNADiff {
        let avgMaintBefore = before.fileAnalyses.isEmpty ? 100.0
            : before.fileAnalyses.reduce(0.0) { $0 + $1.complexity.maintainability } / Double(before.fileAnalyses.count)
        let avgMaintAfter = after.fileAnalyses.isEmpty ? 100.0
            : after.fileAnalyses.reduce(0.0) { $0 + $1.complexity.maintainability } / Double(after.fileAnalyses.count)

        let beforeSmellIds = Set(before.smells.map(\.id))
        let afterSmellIds = Set(after.smells.map(\.id))

        let newSmells = after.smells.filter { !beforeSmellIds.contains($0.id) }
        let resolvedSmells = before.smells.filter { !afterSmellIds.contains($0.id) }

        let beforeHotspotPaths = Set(before.projectMetrics.hotspots.map(\.filePath))
        let afterHotspotPaths = Set(after.projectMetrics.hotspots.map(\.filePath))

        let newHotspots = after.projectMetrics.hotspots.filter { !beforeHotspotPaths.contains($0.filePath) }
        let resolvedHotspots = before.projectMetrics.hotspots.filter { !afterHotspotPaths.contains($0.filePath) }

        return CodeDNADiff(
            before: before.timestamp,
            after: after.timestamp,
            complexityChange: after.projectMetrics.avgComplexity - before.projectMetrics.avgComplexity,
            maintainabilityChange: avgMaintAfter - avgMaintBefore,
            newSmells: newSmells,
            resolvedSmells: resolvedSmells,
            newDuplications: max(0, after.duplications.count - before.duplications.count),
            resolvedDuplications: max(0, before.duplications.count - after.duplications.count),
            newHotspots: newHotspots,
            resolvedHotspots: resolvedHotspots
        )
    }

    // MARK: - Helpers

    private func discoverSourceFiles(at path: String, allowedExtensions: Set<String>) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return [] }

        var files: [String] = []
        while let file = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(file)
            let lastComponent = (file as NSString).lastPathComponent

            // Skip ignored directories
            if ignoredDirectories.contains(lastComponent) {
                enumerator.skipDescendants()
                continue
            }

            // Check extension
            let ext = (file as NSString).pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }

            // Check size
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let size = attrs[.size] as? Int,
               size <= maxFileSizeBytes {
                files.append(fullPath)
            }
        }

        return files
    }

    private func findClosingBrace(from startLine: Int, in lines: [String]) -> Int {
        var braceCount = 0
        var foundOpen = false

        for i in startLine..<lines.count {
            for char in lines[i] {
                if char == "{" {
                    braceCount += 1
                    foundOpen = true
                } else if char == "}" {
                    braceCount -= 1
                    if foundOpen && braceCount == 0 {
                        return i
                    }
                }
            }
        }

        return min(startLine + 1, lines.count - 1)
    }

    private func countParameters(in line: String, language: Language) -> Int {
        guard let openParen = line.firstIndex(of: "("),
              let closeParen = line.firstIndex(of: ")") else { return 0 }

        let paramString = String(line[line.index(after: openParen)..<closeParen])
            .trimmingCharacters(in: .whitespaces)

        if paramString.isEmpty { return 0 }

        // Count commas + 1, accounting for generics and closures
        var depth = 0
        var count = 1
        for char in paramString {
            switch char {
            case "<", "(", "[": depth += 1
            case ">", ")", "]": depth -= 1
            case "," where depth == 0: count += 1
            default: break
            }
        }
        return count
    }

    private func countMethods(in body: String, language: Language) -> Int {
        let pattern: String
        switch language {
        case .swift: pattern = #"\bfunc\s+\w+"#
        case .rust: pattern = #"\bfn\s+\w+"#
        case .python: pattern = #"\bdef\s+\w+"#
        case .typescript, .javascript: pattern = #"(?:\bfunction\s+\w+|\b\w+\s*\([^)]*\)\s*\{)"#
        case .java, .kotlin: pattern = #"(?:public|private|protected|static|final|abstract).*\w+\s*\("#
        case .go: pattern = #"\bfunc\s+\w+"#
        case .cpp: pattern = #"\w+\s+\w+\s*\([^)]*\)\s*\{"#
        case .unknown: return 0
        }

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(body.startIndex..<body.endIndex, in: body)
        return regex.numberOfMatches(in: body, range: range)
    }

    private func countProperties(in body: String, language: Language) -> Int {
        let lines = body.components(separatedBy: .newlines)
        var count = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            switch language {
            case .swift:
                if trimmed.hasPrefix("var ") || trimmed.hasPrefix("let ") ||
                   trimmed.hasPrefix("@Published var ") || trimmed.hasPrefix("@State var ") ||
                   trimmed.hasPrefix("private var ") || trimmed.hasPrefix("private let ") ||
                   trimmed.hasPrefix("public var ") || trimmed.hasPrefix("public let ") {
                    count += 1
                }
            case .typescript, .javascript:
                if trimmed.hasPrefix("this.") && trimmed.contains("=") { count += 1 }
                if (trimmed.hasPrefix("private ") || trimmed.hasPrefix("public ") || trimmed.hasPrefix("readonly "))
                    && !trimmed.contains("(") { count += 1 }
            case .python:
                if trimmed.hasPrefix("self.") && trimmed.contains("=") { count += 1 }
            case .rust:
                if trimmed.contains(":") && !trimmed.contains("fn ") && !trimmed.hasPrefix("//") { count += 1 }
            default:
                if trimmed.contains(";") && !trimmed.contains("(") && !trimmed.hasPrefix("//") {
                    count += 1
                }
            }
        }

        return count
    }

    private func extractConformances(from line: String, language: Language) -> [String] {
        guard language == .swift else { return [] }

        // Look for ": Protocol1, Protocol2" or ": BaseClass, Protocol"
        guard let colonIdx = line.firstIndex(of: ":") else { return [] }
        let afterColon = String(line[line.index(after: colonIdx)...])

        // Stop at opening brace or where clause
        let stopChars: [Character] = ["{", "\n"]
        var conformanceStr = afterColon
        for char in stopChars {
            if let idx = conformanceStr.firstIndex(of: char) {
                conformanceStr = String(conformanceStr[..<idx])
            }
        }
        if let whereRange = conformanceStr.range(of: " where ") {
            conformanceStr = String(conformanceStr[..<whereRange.lowerBound])
        }

        return conformanceStr.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func calculateCohesion(body: String, methodCount: Int, propertyCount: Int) -> Double {
        // Simplified LCOM4: ratio of methods that share property access
        guard methodCount > 1 && propertyCount > 0 else { return 1.0 }

        // A more thorough implementation would build a graph of method-property access
        // and compute connected components. For now, use a heuristic.
        let linesPerMethod = Double(body.components(separatedBy: .newlines).count) / Double(max(1, methodCount))

        // Higher lines per method often correlates with higher cohesion (methods do more with the class state)
        // but extremely high means the class is doing too much
        if linesPerMethod > 50 { return 0.3 }
        if linesPerMethod > 30 { return 0.5 }
        if linesPerMethod > 15 { return 0.7 }
        return 0.85
    }

    private func makeRelativePath(_ path: String, from base: String) -> String {
        if path.hasPrefix(base) {
            var relative = String(path.dropFirst(base.count))
            if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
            return relative
        }
        return path
    }
}
