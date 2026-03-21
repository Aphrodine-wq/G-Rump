import Foundation

// MARK: - Workflow State Machine

/// Top-level state of an autonomous workflow.
enum WorkflowState: String, Codable, Sendable, Equatable {
    case idle
    case planning
    case executing
    case paused
    case checkpointed
    case rollingBack
    case completed
    case failed

    var isTerminal: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .planning, .executing, .checkpointed: return true
        default: return false
        }
    }

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .planning: return "Planning"
        case .executing: return "Executing"
        case .paused: return "Paused"
        case .checkpointed: return "Checkpointed"
        case .rollingBack: return "Rolling Back"
        case .completed: return "Completed"
        case .failed: return "Failed"
        }
    }
}

// MARK: - Step State

/// State of an individual workflow step.
enum StepState: String, Codable, Sendable, Equatable {
    case pending
    case blocked
    case ready
    case running
    case succeeded
    case failed
    case skipped
    case rolledBack

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .skipped, .rolledBack: return true
        default: return false
        }
    }

    var canRetry: Bool {
        self == .failed
    }
}

// MARK: - Tool Invocation

/// A single tool call within a workflow step.
struct ToolInvocation: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let toolName: String
    let arguments: [String: String]
    let expectedOutput: String?

    init(toolName: String, arguments: [String: String], expectedOutput: String? = nil) {
        self.id = UUID()
        self.toolName = toolName
        self.arguments = arguments
        self.expectedOutput = expectedOutput
    }

    /// Validate that the tool name is known and arguments are well-formed.
    func validate(knownTools: Set<String>) -> [String] {
        var errors: [String] = []
        if !knownTools.contains(toolName) {
            errors.append("Unknown tool: \(toolName)")
        }
        if arguments.isEmpty {
            errors.append("Tool \(toolName) has no arguments specified")
        }
        return errors
    }
}

// MARK: - File Snapshot

/// Snapshot of a single file for checkpoint/rollback.
struct FileSnapshot: Codable, Sendable, Equatable {
    let path: String
    let contentHash: String
    let originalContent: Data
    let modifiedContent: Data?
    let fileSize: Int
    let modificationDate: Date

    init(path: String, contentHash: String, originalContent: Data, modifiedContent: Data? = nil) {
        self.path = path
        self.contentHash = contentHash
        self.originalContent = originalContent
        self.modifiedContent = modifiedContent
        self.fileSize = originalContent.count
        self.modificationDate = Date()
    }

    /// Whether this snapshot shows a file that was modified.
    var wasModified: Bool {
        guard let modified = modifiedContent else { return false }
        return modified != originalContent
    }
}

// MARK: - Checkpoint Data

/// Full checkpoint capturing project state at a point in time.
struct CheckpointData: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let stepId: UUID
    let timestamp: Date
    let projectStateHash: String
    let modifiedFiles: [FileSnapshot]
    let gitRef: String?
    let description: String
    let metadata: [String: String]

    init(stepId: UUID, projectStateHash: String, modifiedFiles: [FileSnapshot],
         gitRef: String? = nil, description: String = "", metadata: [String: String] = [:]) {
        self.id = UUID()
        self.stepId = stepId
        self.timestamp = Date()
        self.projectStateHash = projectStateHash
        self.modifiedFiles = modifiedFiles
        self.gitRef = gitRef
        self.description = description
        self.metadata = metadata
    }

    /// Total bytes stored in this checkpoint.
    var totalSnapshotSize: Int {
        modifiedFiles.reduce(0) { $0 + $1.fileSize + ($1.modifiedContent?.count ?? 0) }
    }
}

// MARK: - Workflow Step

/// A single step in a workflow, containing one or more tool invocations.
struct WorkflowStep: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var toolCalls: [ToolInvocation]
    var dependencies: [UUID]
    var state: StepState
    var result: String?
    var retryCount: Int
    var maxRetries: Int
    var timeout: TimeInterval
    var checkpoint: CheckpointData?
    var startedAt: Date?
    var completedAt: Date?
    var errorMessage: String?
    var estimatedDuration: TimeInterval

    init(name: String, description: String, toolCalls: [ToolInvocation],
         dependencies: [UUID] = [], maxRetries: Int = 2,
         timeout: TimeInterval = 300, estimatedDuration: TimeInterval = 30) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.toolCalls = toolCalls
        self.dependencies = dependencies
        self.state = .pending
        self.result = nil
        self.retryCount = 0
        self.maxRetries = maxRetries
        self.timeout = timeout
        self.checkpoint = nil
        self.startedAt = nil
        self.completedAt = nil
        self.errorMessage = nil
        self.estimatedDuration = estimatedDuration
    }

    /// Duration this step actually took, if completed.
    var actualDuration: TimeInterval? {
        guard let start = startedAt, let end = completedAt else { return nil }
        return end.timeIntervalSince(start)
    }

    /// Whether this step can be retried.
    var canRetry: Bool {
        state.canRetry && retryCount < maxRetries
    }

    /// All dependency IDs that this step requires.
    var dependencySet: Set<UUID> {
        Set(dependencies)
    }
}

// MARK: - Workflow

/// A complete workflow containing ordered steps with dependencies.
struct Workflow: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var description: String
    var steps: [WorkflowStep]
    var state: WorkflowState
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var checkpoints: [CheckpointData]
    var metadata: [String: String]
    var projectPath: String
    var errorLog: [WorkflowError]

    init(name: String, description: String, steps: [WorkflowStep],
         projectPath: String, metadata: [String: String] = [:]) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.steps = steps
        self.state = .idle
        self.createdAt = Date()
        self.startedAt = nil
        self.completedAt = nil
        self.checkpoints = []
        self.metadata = metadata
        self.projectPath = projectPath
        self.errorLog = []
    }

    /// Progress as a fraction 0.0-1.0.
    var progress: Double {
        guard !steps.isEmpty else { return 0 }
        let completed = steps.filter { $0.state == .succeeded || $0.state == .skipped }.count
        return Double(completed) / Double(steps.count)
    }

    /// Steps that have no unresolved dependencies.
    var readySteps: [WorkflowStep] {
        let completedIds = Set(steps.filter { $0.state == .succeeded || $0.state == .skipped }.map(\.id))
        return steps.filter { step in
            step.state == .pending || step.state == .ready
        }.filter { step in
            step.dependencySet.isSubset(of: completedIds)
        }
    }

    /// Total estimated duration based on critical path.
    var estimatedTotalDuration: TimeInterval {
        steps.reduce(0) { $0 + $1.estimatedDuration }
    }

    /// Number of steps in each state.
    var stepStateCounts: [StepState: Int] {
        var counts: [StepState: Int] = [:]
        for step in steps {
            counts[step.state, default: 0] += 1
        }
        return counts
    }

    /// The latest checkpoint, if any.
    var latestCheckpoint: CheckpointData? {
        checkpoints.max(by: { $0.timestamp < $1.timestamp })
    }

    mutating func addError(_ error: WorkflowError) {
        errorLog.append(error)
    }
}

// MARK: - Workflow Error

struct WorkflowError: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let stepId: UUID?
    let timestamp: Date
    let message: String
    let isRecoverable: Bool

    init(stepId: UUID? = nil, message: String, isRecoverable: Bool = true) {
        self.id = UUID()
        self.stepId = stepId
        self.timestamp = Date()
        self.message = message
        self.isRecoverable = isRecoverable
    }
}

// MARK: - Workflow Category

/// Categories for workflow templates.
enum WorkflowCategory: String, Codable, Sendable, CaseIterable {
    case refactoring
    case featureAddition
    case bugFix
    case testing
    case deployment
    case migration
    case documentation
    case custom

    var displayName: String {
        switch self {
        case .refactoring: return "Refactoring"
        case .featureAddition: return "Feature Addition"
        case .bugFix: return "Bug Fix"
        case .testing: return "Testing"
        case .deployment: return "Deployment"
        case .migration: return "Migration"
        case .documentation: return "Documentation"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .refactoring: return "arrow.triangle.2.circlepath"
        case .featureAddition: return "plus.square"
        case .bugFix: return "ladybug"
        case .testing: return "checkmark.diamond"
        case .deployment: return "shippingbox"
        case .migration: return "arrow.right.arrow.left"
        case .documentation: return "doc.text"
        case .custom: return "gearshape"
        }
    }
}

// MARK: - Step Template

/// Template for creating a workflow step.
struct StepTemplate: Codable, Sendable, Equatable {
    let name: String
    let description: String
    let toolNames: [String]
    let parameterKeys: [String]
    let dependsOnIndices: [Int]
    let maxRetries: Int
    let timeout: TimeInterval
    let estimatedDuration: TimeInterval

    init(name: String, description: String, toolNames: [String],
         parameterKeys: [String] = [], dependsOnIndices: [Int] = [],
         maxRetries: Int = 2, timeout: TimeInterval = 300,
         estimatedDuration: TimeInterval = 30) {
        self.name = name
        self.description = description
        self.toolNames = toolNames
        self.parameterKeys = parameterKeys
        self.dependsOnIndices = dependsOnIndices
        self.maxRetries = maxRetries
        self.timeout = timeout
        self.estimatedDuration = estimatedDuration
    }

    /// Create a concrete step from this template with supplied parameters.
    func instantiate(parameters: [String: String], stepIdMap: [Int: UUID]) -> WorkflowStep {
        let invocations = toolNames.map { name in
            let args = parameterKeys.reduce(into: [String: String]()) { dict, key in
                if let value = parameters[key] {
                    dict[key] = value
                }
            }
            return ToolInvocation(toolName: name, arguments: args)
        }

        let deps = dependsOnIndices.compactMap { stepIdMap[$0] }

        return WorkflowStep(
            name: name,
            description: description,
            toolCalls: invocations,
            dependencies: deps,
            maxRetries: maxRetries,
            timeout: timeout,
            estimatedDuration: estimatedDuration
        )
    }
}

// MARK: - Workflow Template

/// A reusable workflow template that can be instantiated with parameters.
struct WorkflowTemplate: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let description: String
    let category: WorkflowCategory
    let stepTemplates: [StepTemplate]
    let requiredParameters: [String]
    let optionalParameters: [String]

    init(name: String, description: String, category: WorkflowCategory,
         stepTemplates: [StepTemplate], requiredParameters: [String] = [],
         optionalParameters: [String] = []) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.category = category
        self.stepTemplates = stepTemplates
        self.requiredParameters = requiredParameters
        self.optionalParameters = optionalParameters
    }

    /// Instantiate this template into a concrete workflow.
    func instantiate(parameters: [String: String], projectPath: String) -> Workflow {
        // Validate required parameters
        for key in requiredParameters {
            assert(parameters[key] != nil, "Missing required parameter: \(key)")
        }

        // Build step ID map for dependency resolution
        var stepIdMap: [Int: UUID] = [:]
        var steps: [WorkflowStep] = []

        for (index, template) in stepTemplates.enumerated() {
            var step = template.instantiate(parameters: parameters, stepIdMap: stepIdMap)
            stepIdMap[index] = step.id
            // Re-resolve dependencies now that we have the ID
            let deps = template.dependsOnIndices.compactMap { stepIdMap[$0] }
            step = WorkflowStep(
                name: step.name,
                description: step.description,
                toolCalls: step.toolCalls,
                dependencies: deps,
                maxRetries: step.maxRetries,
                timeout: step.timeout,
                estimatedDuration: step.estimatedDuration
            )
            stepIdMap[index] = step.id
            steps.append(step)
        }

        return Workflow(
            name: "\(name) - \(parameters["target"] ?? "project")",
            description: description,
            steps: steps,
            projectPath: projectPath,
            metadata: parameters
        )
    }
}

// MARK: - Workflow Event

/// Events emitted during workflow execution for monitoring.
enum WorkflowEvent: Sendable {
    case started(workflowId: UUID, name: String)
    case stepBegan(workflowId: UUID, stepId: UUID, name: String)
    case stepCompleted(workflowId: UUID, stepId: UUID, name: String, result: String?)
    case stepFailed(workflowId: UUID, stepId: UUID, name: String, error: String)
    case stepRetrying(workflowId: UUID, stepId: UUID, attempt: Int, maxRetries: Int)
    case checkpointCreated(workflowId: UUID, checkpointId: UUID)
    case rollbackInitiated(workflowId: UUID, toCheckpointId: UUID)
    case rollbackCompleted(workflowId: UUID)
    case paused(workflowId: UUID)
    case resumed(workflowId: UUID)
    case completed(workflowId: UUID, duration: TimeInterval)
    case failed(workflowId: UUID, error: String)
    case progressUpdate(workflowId: UUID, progress: Double, currentStep: String)

    var workflowId: UUID {
        switch self {
        case .started(let id, _), .stepBegan(let id, _, _),
             .stepCompleted(let id, _, _, _), .stepFailed(let id, _, _, _),
             .stepRetrying(let id, _, _, _), .checkpointCreated(let id, _),
             .rollbackInitiated(let id, _), .rollbackCompleted(let id),
             .paused(let id), .resumed(let id),
             .completed(let id, _), .failed(let id, _),
             .progressUpdate(let id, _, _):
            return id
        }
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }
}

// MARK: - Project State Snapshot

/// Complete snapshot of project file state for comparison and rollback.
struct ProjectStateSnapshot: Codable, Sendable, Equatable {
    let timestamp: Date
    let directoryPath: String
    let fileHashes: [String: String]
    let totalFiles: Int
    let totalSize: Int64

    init(directoryPath: String, fileHashes: [String: String], totalSize: Int64) {
        self.timestamp = Date()
        self.directoryPath = directoryPath
        self.fileHashes = fileHashes
        self.totalFiles = fileHashes.count
        self.totalSize = totalSize
    }
}

// MARK: - File Change

/// Represents a change between two project state snapshots.
struct FileChange: Sendable, Equatable {
    let path: String
    let type: ChangeType

    enum ChangeType: String, Sendable, Equatable {
        case added
        case modified
        case deleted
        case renamed
    }
}

// MARK: - Directed Graph (for dependency resolution)

/// Generic directed graph supporting topological sort and cycle detection.
struct DirectedGraph<T: Hashable & Sendable>: Sendable {
    private var adjacencyList: [T: Set<T>]
    private var allNodes: Set<T>

    init() {
        adjacencyList = [:]
        allNodes = []
    }

    mutating func addNode(_ node: T) {
        allNodes.insert(node)
        if adjacencyList[node] == nil {
            adjacencyList[node] = []
        }
    }

    mutating func addEdge(from source: T, to destination: T) {
        addNode(source)
        addNode(destination)
        adjacencyList[source, default: []].insert(destination)
    }

    /// Topological sort using Kahn's algorithm. Returns nil if cycle detected.
    func topologicalSort() -> [T]? {
        var inDegree: [T: Int] = [:]
        for node in allNodes {
            inDegree[node] = 0
        }
        for (_, neighbors) in adjacencyList {
            for neighbor in neighbors {
                inDegree[neighbor, default: 0] += 1
            }
        }

        var queue: [T] = inDegree.filter { $0.value == 0 }.map(\.key)
        var result: [T] = []

        while !queue.isEmpty {
            let node = queue.removeFirst()
            result.append(node)

            for neighbor in adjacencyList[node] ?? [] {
                inDegree[neighbor, default: 0] -= 1
                if inDegree[neighbor] == 0 {
                    queue.append(neighbor)
                }
            }
        }

        return result.count == allNodes.count ? result : nil
    }

    /// Detect if the graph has cycles.
    var hasCycles: Bool {
        topologicalSort() == nil
    }

    /// Get all neighbors of a node.
    func neighbors(of node: T) -> Set<T> {
        adjacencyList[node] ?? []
    }

    /// Get all nodes.
    var nodes: Set<T> {
        allNodes
    }

    /// Find all strongly connected components using Tarjan's algorithm.
    func stronglyConnectedComponents() -> [[T]] {
        var index = 0
        var stack: [T] = []
        var onStack: Set<T> = []
        var indices: [T: Int] = [:]
        var lowlinks: [T: Int] = [:]
        var components: [[T]] = []

        func strongconnect(_ v: T) {
            indices[v] = index
            lowlinks[v] = index
            index += 1
            stack.append(v)
            onStack.insert(v)

            for w in adjacencyList[v] ?? [] {
                if indices[w] == nil {
                    strongconnect(w)
                    lowlinks[v] = min(lowlinks[v]!, lowlinks[w]!)
                } else if onStack.contains(w) {
                    lowlinks[v] = min(lowlinks[v]!, indices[w]!)
                }
            }

            if lowlinks[v] == indices[v] {
                var component: [T] = []
                while true {
                    let w = stack.removeLast()
                    onStack.remove(w)
                    component.append(w)
                    if w == v { break }
                }
                components.append(component)
            }
        }

        for node in allNodes {
            if indices[node] == nil {
                strongconnect(node)
            }
        }

        return components
    }
}
