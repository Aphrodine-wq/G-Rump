import Foundation

// MARK: - Language

/// Supported programming languages for code analysis.
enum Language: String, Codable, Sendable, CaseIterable {
    case swift
    case rust
    case typescript
    case javascript
    case python
    case java
    case kotlin
    case go
    case cpp
    case unknown

    /// File extensions associated with this language.
    var extensions: Set<String> {
        switch self {
        case .swift: return ["swift"]
        case .rust: return ["rs"]
        case .typescript: return ["ts", "tsx"]
        case .javascript: return ["js", "jsx", "mjs", "cjs"]
        case .python: return ["py"]
        case .java: return ["java"]
        case .kotlin: return ["kt", "kts"]
        case .go: return ["go"]
        case .cpp: return ["cpp", "cc", "cxx", "c", "h", "hpp", "hxx"]
        case .unknown: return []
        }
    }

    /// Detect language from file extension.
    static func from(extension ext: String) -> Language {
        let lower = ext.lowercased()
        for lang in Language.allCases {
            if lang.extensions.contains(lower) {
                return lang
            }
        }
        return .unknown
    }

    /// Comment syntax for this language.
    var lineCommentPrefix: String {
        switch self {
        case .swift, .rust, .typescript, .javascript, .java, .kotlin, .go, .cpp:
            return "//"
        case .python:
            return "#"
        case .unknown:
            return "//"
        }
    }

    /// Block comment delimiters.
    var blockCommentDelimiters: (start: String, end: String)? {
        switch self {
        case .swift, .rust, .typescript, .javascript, .java, .kotlin, .go, .cpp:
            return ("/*", "*/")
        case .python:
            return ("\"\"\"", "\"\"\"")
        case .unknown:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .swift: return "Swift"
        case .rust: return "Rust"
        case .typescript: return "TypeScript"
        case .javascript: return "JavaScript"
        case .python: return "Python"
        case .java: return "Java"
        case .kotlin: return "Kotlin"
        case .go: return "Go"
        case .cpp: return "C/C++"
        case .unknown: return "Unknown"
        }
    }
}

// MARK: - Halstead Metrics

/// Halstead software science metrics for measuring code complexity.
struct HalsteadMetrics: Codable, Sendable, Equatable {
    let distinctOperators: Int    // n1
    let distinctOperands: Int     // n2
    let totalOperators: Int       // N1
    let totalOperands: Int        // N2

    /// Program vocabulary: n = n1 + n2
    var vocabulary: Int { distinctOperators + distinctOperands }

    /// Program length: N = N1 + N2
    var length: Int { totalOperators + totalOperands }

    /// Calculated program length: N_hat = n1 * log2(n1) + n2 * log2(n2)
    var calculatedLength: Double {
        guard distinctOperators > 0 && distinctOperands > 0 else { return 0 }
        return Double(distinctOperators) * log2(Double(distinctOperators))
             + Double(distinctOperands) * log2(Double(distinctOperands))
    }

    /// Program volume: V = N * log2(n)
    var volume: Double {
        guard vocabulary > 0 else { return 0 }
        return Double(length) * log2(Double(vocabulary))
    }

    /// Difficulty: D = (n1 / 2) * (N2 / n2)
    var difficulty: Double {
        guard distinctOperands > 0 else { return 0 }
        return (Double(distinctOperators) / 2.0) * (Double(totalOperands) / Double(distinctOperands))
    }

    /// Effort: E = D * V
    var effort: Double { difficulty * volume }

    /// Time to program (seconds): T = E / 18
    var timeToProgram: Double { effort / 18.0 }

    /// Estimated number of bugs: B = V / 3000
    var estimatedBugs: Double { volume / 3000.0 }

    static let zero = HalsteadMetrics(
        distinctOperators: 0, distinctOperands: 0,
        totalOperators: 0, totalOperands: 0
    )
}

// MARK: - Complexity Score

/// Aggregated complexity score for a code unit.
struct ComplexityScore: Codable, Sendable, Equatable {
    let cyclomatic: Int
    let cognitive: Int
    let maintainability: Double  // 0-100 scale
    let overall: String          // A-F grade

    static func grade(maintainability: Double) -> String {
        switch maintainability {
        case 80...: return "A"
        case 60..<80: return "B"
        case 40..<60: return "C"
        case 20..<40: return "D"
        default: return "F"
        }
    }

    static let zero = ComplexityScore(cyclomatic: 1, cognitive: 0, maintainability: 100, overall: "A")
}

// MARK: - Function Metrics

/// Metrics for a single function/method.
struct FunctionMetrics: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let startLine: Int
    let endLine: Int
    let lineCount: Int
    let parameterCount: Int
    let cyclomaticComplexity: Int
    let cognitiveComplexity: Int
    let nestingDepth: Int
    let returnCount: Int
    let halsteadMetrics: HalsteadMetrics

    init(name: String, startLine: Int, endLine: Int, parameterCount: Int,
         cyclomaticComplexity: Int, cognitiveComplexity: Int, nestingDepth: Int,
         returnCount: Int, halsteadMetrics: HalsteadMetrics = .zero) {
        self.id = UUID()
        self.name = name
        self.startLine = startLine
        self.endLine = endLine
        self.lineCount = endLine - startLine + 1
        self.parameterCount = parameterCount
        self.cyclomaticComplexity = cyclomaticComplexity
        self.cognitiveComplexity = cognitiveComplexity
        self.nestingDepth = nestingDepth
        self.returnCount = returnCount
        self.halsteadMetrics = halsteadMetrics
    }

    /// Whether this function is considered complex.
    var isComplex: Bool {
        cyclomaticComplexity > 10 || cognitiveComplexity > 15 || nestingDepth > 4
    }

    /// Whether this function is too long.
    var isTooLong: Bool {
        lineCount > 50
    }
}

// MARK: - Class Metrics

/// Metrics for a class or struct.
struct ClassMetrics: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let startLine: Int
    let endLine: Int
    let methodCount: Int
    let propertyCount: Int
    let protocolConformances: [String]
    let inheritanceDepth: Int
    let responsibilityCount: Int
    let couplingScore: Double
    let cohesionScore: Double  // LCOM4 metric (0-1, 1 = perfectly cohesive)

    init(name: String, startLine: Int, endLine: Int, methodCount: Int,
         propertyCount: Int, protocolConformances: [String] = [],
         inheritanceDepth: Int = 0, responsibilityCount: Int = 1,
         couplingScore: Double = 0, cohesionScore: Double = 1.0) {
        self.id = UUID()
        self.name = name
        self.startLine = startLine
        self.endLine = endLine
        self.methodCount = methodCount
        self.propertyCount = propertyCount
        self.protocolConformances = protocolConformances
        self.inheritanceDepth = inheritanceDepth
        self.responsibilityCount = responsibilityCount
        self.couplingScore = couplingScore
        self.cohesionScore = cohesionScore
    }

    var lineCount: Int { endLine - startLine + 1 }

    /// Whether this class shows God Class symptoms.
    var isGodClass: Bool {
        methodCount > 20 || lineCount > 500 || cohesionScore < 0.3
    }
}

// MARK: - File Analysis

/// Complete analysis of a single source file.
struct FileAnalysis: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let filePath: String
    let language: Language
    let lineCount: Int
    let blankLines: Int
    let commentLines: Int
    let codeLines: Int
    let functions: [FunctionMetrics]
    let classes: [ClassMetrics]
    let imports: [String]
    let complexity: ComplexityScore

    init(filePath: String, language: Language, lineCount: Int, blankLines: Int,
         commentLines: Int, codeLines: Int, functions: [FunctionMetrics],
         classes: [ClassMetrics], imports: [String], complexity: ComplexityScore) {
        self.id = UUID()
        self.filePath = filePath
        self.language = language
        self.lineCount = lineCount
        self.blankLines = blankLines
        self.commentLines = commentLines
        self.codeLines = codeLines
        self.functions = functions
        self.classes = classes
        self.imports = imports
        self.complexity = complexity
    }

    /// Comment density as a ratio.
    var commentDensity: Double {
        guard codeLines > 0 else { return 0 }
        return Double(commentLines) / Double(codeLines)
    }

    /// Average function complexity.
    var averageFunctionComplexity: Double {
        guard !functions.isEmpty else { return 0 }
        return Double(functions.reduce(0) { $0 + $1.cyclomaticComplexity }) / Double(functions.count)
    }
}

// MARK: - Hotspot

/// A file identified as a complexity hotspot requiring attention.
struct Hotspot: Codable, Sendable, Equatable {
    let filePath: String
    let score: Double
    let reasons: [String]

    var severity: String {
        switch score {
        case 80...: return "Critical"
        case 60..<80: return "High"
        case 40..<60: return "Medium"
        default: return "Low"
        }
    }
}

// MARK: - Project Metrics

/// Aggregated metrics across an entire project.
struct ProjectMetrics: Codable, Sendable, Equatable {
    let totalFiles: Int
    let totalLines: Int
    let totalCodeLines: Int
    let avgComplexity: Double
    let maxComplexity: Int
    let hotspots: [Hotspot]
    let languageBreakdown: [String: Int]

    /// Lines of code per file on average.
    var avgLinesPerFile: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(totalLines) / Double(totalFiles)
    }

    /// Percentage of code vs total lines.
    var codePercentage: Double {
        guard totalLines > 0 else { return 0 }
        return Double(totalCodeLines) / Double(totalLines) * 100
    }
}

// MARK: - Architectural Smell

/// Detected architectural anti-patterns with associated data.
enum ArchitecturalSmell: Codable, Sendable, Equatable, Identifiable {
    case godClass(className: String, methodCount: Int, lineCount: Int)
    case featureEnvy(method: String, accessedClass: String, accessCount: Int)
    case shotgunSurgery(concept: String, affectedFiles: [String])
    case divergentChange(file: String, changeReasons: [String])
    case dataClump(fields: [String], occurrences: Int)
    case longParameterList(function: String, paramCount: Int)
    case circularDependency(modules: [String])
    case inappropriateIntimacy(classA: String, classB: String, sharedAccess: Int)

    var id: String {
        switch self {
        case .godClass(let name, _, _): return "godClass_\(name)"
        case .featureEnvy(let method, let cls, _): return "featureEnvy_\(method)_\(cls)"
        case .shotgunSurgery(let concept, _): return "shotgunSurgery_\(concept)"
        case .divergentChange(let file, _): return "divergentChange_\(file)"
        case .dataClump(let fields, _): return "dataClump_\(fields.joined(separator: "_"))"
        case .longParameterList(let func_, _): return "longParamList_\(func_)"
        case .circularDependency(let modules): return "circDep_\(modules.joined(separator: "_"))"
        case .inappropriateIntimacy(let a, let b, _): return "intimacy_\(a)_\(b)"
        }
    }

    var name: String {
        switch self {
        case .godClass: return "God Class"
        case .featureEnvy: return "Feature Envy"
        case .shotgunSurgery: return "Shotgun Surgery"
        case .divergentChange: return "Divergent Change"
        case .dataClump: return "Data Clump"
        case .longParameterList: return "Long Parameter List"
        case .circularDependency: return "Circular Dependency"
        case .inappropriateIntimacy: return "Inappropriate Intimacy"
        }
    }

    var severity: SmellSeverity {
        switch self {
        case .godClass(_, let methods, let lines):
            if methods > 40 || lines > 1000 { return .critical }
            if methods > 30 || lines > 750 { return .high }
            return .medium
        case .featureEnvy(_, _, let count):
            return count > 10 ? .high : .medium
        case .shotgunSurgery(_, let files):
            return files.count > 10 ? .critical : (files.count > 5 ? .high : .medium)
        case .divergentChange(_, let reasons):
            return reasons.count > 5 ? .high : .medium
        case .dataClump(_, let occurrences):
            return occurrences > 5 ? .high : .medium
        case .longParameterList(_, let count):
            return count > 8 ? .high : (count > 5 ? .medium : .low)
        case .circularDependency(let modules):
            return modules.count > 3 ? .critical : .high
        case .inappropriateIntimacy(_, _, let access):
            return access > 10 ? .high : .medium
        }
    }

    var description: String {
        switch self {
        case .godClass(let name, let methods, let lines):
            return "Class '\(name)' has \(methods) methods and \(lines) lines. Consider breaking it into smaller, focused classes."
        case .featureEnvy(let method, let cls, let count):
            return "Method '\(method)' accesses '\(cls)' \(count) times. Consider moving it to \(cls)."
        case .shotgunSurgery(let concept, let files):
            return "Changing '\(concept)' requires modifying \(files.count) files. Consider consolidating related logic."
        case .divergentChange(let file, let reasons):
            return "File '\(file)' changes for \(reasons.count) different reasons: \(reasons.joined(separator: ", ")). Consider splitting by responsibility."
        case .dataClump(let fields, let occurrences):
            return "Fields [\(fields.joined(separator: ", "))] appear together \(occurrences) times. Consider extracting into a dedicated type."
        case .longParameterList(let fn, let count):
            return "Function '\(fn)' takes \(count) parameters. Consider using a parameter object or builder."
        case .circularDependency(let modules):
            return "Circular dependency: \(modules.joined(separator: " -> ")). Break the cycle with dependency inversion."
        case .inappropriateIntimacy(let a, let b, let access):
            return "Classes '\(a)' and '\(b)' share \(access) internal accesses. Consider refactoring shared logic into a third class."
        }
    }

    var suggestedRefactoring: String {
        switch self {
        case .godClass: return "Extract Class / Extract Module"
        case .featureEnvy: return "Move Method"
        case .shotgunSurgery: return "Move Method / Inline Class"
        case .divergentChange: return "Extract Class by responsibility"
        case .dataClump: return "Introduce Parameter Object / Extract Class"
        case .longParameterList: return "Introduce Parameter Object / Builder Pattern"
        case .circularDependency: return "Dependency Inversion / Introduce Protocol"
        case .inappropriateIntimacy: return "Extract Shared Class / Encapsulate Field"
        }
    }
}

enum SmellSeverity: String, Codable, Sendable, Comparable {
    case low, medium, high, critical

    static func < (lhs: SmellSeverity, rhs: SmellSeverity) -> Bool {
        let order: [SmellSeverity] = [.low, .medium, .high, .critical]
        let lhsIdx = order.firstIndex(of: lhs) ?? 0
        let rhsIdx = order.firstIndex(of: rhs) ?? 0
        return lhsIdx < rhsIdx
    }
}

// MARK: - Duplication

/// A fragment of code involved in duplication.
struct CodeFragment: Codable, Sendable, Equatable {
    let filePath: String
    let startLine: Int
    let endLine: Int
    let content: String

    var lineCount: Int { endLine - startLine + 1 }
}

/// A cluster of duplicated code fragments sharing the same content.
struct DuplicationCluster: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let hash: String
    let fragments: [CodeFragment]
    let totalDuplicatedLines: Int

    init(hash: String, fragments: [CodeFragment]) {
        self.id = UUID()
        self.hash = hash
        self.fragments = fragments
        self.totalDuplicatedLines = fragments.reduce(0) { $0 + $1.lineCount }
    }

    var fragmentCount: Int { fragments.count }

    /// Files involved in this duplication cluster.
    var affectedFiles: Set<String> {
        Set(fragments.map(\.filePath))
    }
}

// MARK: - Dependency Graph

/// A node in the dependency graph.
struct DependencyNode: Codable, Sendable, Equatable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let type: NodeType
    let filePath: String?

    enum NodeType: String, Codable, Sendable {
        case module
        case file
        case classType = "class"
        case function
        case protocolType = "protocol"
    }

    init(name: String, type: NodeType, filePath: String? = nil) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.filePath = filePath
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(type)
    }

    static func == (lhs: DependencyNode, rhs: DependencyNode) -> Bool {
        lhs.name == rhs.name && lhs.type == rhs.type
    }
}

/// An edge in the dependency graph.
struct DependencyEdge: Codable, Sendable, Equatable {
    let from: UUID
    let to: UUID
    let type: EdgeType

    enum EdgeType: String, Codable, Sendable {
        case imports
        case calls
        case inherits
        case conforms
        case references
    }
}

/// Complete dependency graph for a project.
struct DependencyGraph: Codable, Sendable, Equatable {
    let nodes: [DependencyNode]
    let edges: [DependencyEdge]

    /// Nodes with no incoming edges (roots).
    var rootNodes: [DependencyNode] {
        let targetIds = Set(edges.map(\.to))
        return nodes.filter { !targetIds.contains($0.id) }
    }

    /// Nodes with no outgoing edges (leaves).
    var leafNodes: [DependencyNode] {
        let sourceIds = Set(edges.map(\.from))
        return nodes.filter { !sourceIds.contains($0.id) }
    }

    /// Number of connections for each node.
    var connectionCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for edge in edges {
            counts[edge.from, default: 0] += 1
            counts[edge.to, default: 0] += 1
        }
        return counts
    }

    /// Build adjacency list representation.
    var adjacencyList: [UUID: [UUID]] {
        var adj: [UUID: [UUID]] = [:]
        for node in nodes {
            adj[node.id] = []
        }
        for edge in edges {
            adj[edge.from, default: []].append(edge.to)
        }
        return adj
    }
}

// MARK: - Module Suggestion

struct ModuleSuggestion: Sendable, Equatable {
    let suggestedModuleName: String
    let files: [String]
    let reasoning: String
    let cohesionScore: Double
}

// MARK: - CodeDNA Report

/// Complete project analysis report.
struct CodeDNAReport: Codable, Sendable, Equatable {
    let projectPath: String
    let timestamp: Date
    let fileAnalyses: [FileAnalysis]
    let projectMetrics: ProjectMetrics
    let smells: [ArchitecturalSmell]
    let duplications: [DuplicationCluster]
    let dependencyGraph: DependencyGraph

    /// Overall project health grade.
    var grade: String {
        let avgMaintainability = fileAnalyses.isEmpty ? 100.0
            : fileAnalyses.reduce(0.0) { $0 + $1.complexity.maintainability } / Double(fileAnalyses.count)
        return ComplexityScore.grade(maintainability: avgMaintainability)
    }

    /// Total duplication percentage across the project.
    var duplicationPercentage: Double {
        guard projectMetrics.totalCodeLines > 0 else { return 0 }
        let duplicatedLines = duplications.reduce(0) { $0 + $1.totalDuplicatedLines }
        return Double(duplicatedLines) / Double(projectMetrics.totalCodeLines) * 100
    }

    /// Number of critical smells.
    var criticalSmellCount: Int {
        smells.filter { $0.severity == .critical }.count
    }
}

// MARK: - CodeDNA Diff

/// Comparison between two CodeDNA reports showing what changed.
struct CodeDNADiff: Sendable {
    let before: Date
    let after: Date
    let complexityChange: Double
    let maintainabilityChange: Double
    let newSmells: [ArchitecturalSmell]
    let resolvedSmells: [ArchitecturalSmell]
    let newDuplications: Int
    let resolvedDuplications: Int
    let newHotspots: [Hotspot]
    let resolvedHotspots: [Hotspot]

    var improved: Bool {
        maintainabilityChange > 0 && resolvedSmells.count >= newSmells.count
    }

    var summary: String {
        var parts: [String] = []
        if maintainabilityChange > 0 {
            parts.append("Maintainability improved by \(String(format: "%.1f", maintainabilityChange))")
        } else if maintainabilityChange < 0 {
            parts.append("Maintainability decreased by \(String(format: "%.1f", abs(maintainabilityChange)))")
        }
        if !newSmells.isEmpty { parts.append("\(newSmells.count) new smell(s)") }
        if !resolvedSmells.isEmpty { parts.append("\(resolvedSmells.count) smell(s) resolved") }
        return parts.isEmpty ? "No significant changes" : parts.joined(separator: ", ")
    }
}
