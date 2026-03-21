import Foundation

// MARK: - Autonomous Workflow Engine

/// Actor-based engine for creating, executing, and managing autonomous multi-step workflows.
/// Supports dependency resolution, checkpointing, rollback, and event streaming.
actor AutonomousWorkflowEngine {

    // MARK: - State

    private var activeWorkflows: [UUID: Workflow] = [:]
    private var completedWorkflows: [UUID: Workflow] = [:]
    private var executionQueue: [UUID] = []
    private var eventContinuations: [UUID: AsyncStream<WorkflowEvent>.Continuation] = [:]
    private var globalEventContinuation: AsyncStream<WorkflowEvent>.Continuation?
    private var globalEventStream: AsyncStream<WorkflowEvent>?

    private let checkpointer: WorkflowCheckpointer
    private let scheduler: WorkflowScheduler
    private let persistenceDirectory: String
    private let maxConcurrentWorkflows = 2
    private var isProcessingQueue = false

    private let builtInTemplates: [String: WorkflowTemplate]

    // MARK: - Initialization

    init(baseDirectory: String? = nil) {
        let base = baseDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
        self.persistenceDirectory = (base as NSString).appendingPathComponent(".grump/workflows")
        self.checkpointer = WorkflowCheckpointer()
        self.scheduler = WorkflowScheduler()
        self.builtInTemplates = Self.createBuiltInTemplates()

        let stream = AsyncStream<WorkflowEvent> { continuation in
            // We store the continuation after init
            Task { [weak self = Optional(self)] in
                // This is set in the setupGlobalStream call
                _ = self
            }
        }
        self.globalEventStream = stream

        ensureDirectoryExists(persistenceDirectory)
        Task { await loadPersistedWorkflows() }
    }

    // MARK: - Global Event Stream

    /// Subscribe to all workflow events across all active workflows.
    func eventStream() -> AsyncStream<WorkflowEvent> {
        let stream = AsyncStream<WorkflowEvent> { continuation in
            self.globalEventContinuation = continuation
        }
        return stream
    }

    /// Subscribe to events for a specific workflow.
    func eventStream(for workflowId: UUID) -> AsyncStream<WorkflowEvent> {
        let stream = AsyncStream<WorkflowEvent> { [weak self] continuation in
            Task {
                await self?.registerContinuation(continuation, for: workflowId)
            }
        }
        return stream
    }

    private func registerContinuation(_ continuation: AsyncStream<WorkflowEvent>.Continuation, for id: UUID) {
        eventContinuations[id] = continuation
    }

    private func emit(_ event: WorkflowEvent) {
        globalEventContinuation?.yield(event)
        eventContinuations[event.workflowId]?.yield(event)
    }

    // MARK: - Workflow Creation

    /// Create a workflow from a built-in template name.
    func createWorkflow(fromTemplate templateName: String, parameters: [String: String],
                        projectPath: String) -> Workflow? {
        guard let template = builtInTemplates[templateName] else { return nil }
        var workflow = template.instantiate(parameters: parameters, projectPath: projectPath)
        activeWorkflows[workflow.id] = workflow
        persistWorkflow(workflow)
        return workflow
    }

    /// Create a workflow from a custom template.
    func createWorkflow(from template: WorkflowTemplate, parameters: [String: String],
                        projectPath: String) -> Workflow {
        var workflow = template.instantiate(parameters: parameters, projectPath: projectPath)
        activeWorkflows[workflow.id] = workflow
        persistWorkflow(workflow)
        return workflow
    }

    /// Create a workflow from explicit steps.
    func createWorkflow(name: String, description: String, steps: [WorkflowStep],
                        projectPath: String) -> Workflow {
        let workflow = Workflow(
            name: name, description: description,
            steps: steps, projectPath: projectPath
        )
        activeWorkflows[workflow.id] = workflow
        persistWorkflow(workflow)
        return workflow
    }

    // MARK: - Workflow Execution

    /// Execute a workflow by ID. Returns the completed workflow.
    func executeWorkflow(_ id: UUID) async throws -> Workflow {
        guard var workflow = activeWorkflows[id] else {
            throw WorkflowEngineError.workflowNotFound(id)
        }

        guard !workflow.state.isTerminal else {
            throw WorkflowEngineError.workflowAlreadyComplete(id)
        }

        workflow.state = .planning
        workflow.startedAt = Date()
        activeWorkflows[id] = workflow

        emit(.started(workflowId: id, name: workflow.name))

        // Resolve execution order
        let executionOrder: [UUID]
        do {
            executionOrder = try resolveExecutionOrder(workflow.steps)
        } catch {
            workflow.state = .failed
            workflow.addError(WorkflowError(message: "Dependency resolution failed: \(error.localizedDescription)", isRecoverable: false))
            activeWorkflows[id] = workflow
            emit(.failed(workflowId: id, error: "Dependency cycle detected"))
            persistWorkflow(workflow)
            throw error
        }

        workflow.state = .executing
        activeWorkflows[id] = workflow

        // Execute steps in dependency order, parallelizing where possible
        var completedStepIds: Set<UUID> = []

        while completedStepIds.count < workflow.steps.count {
            guard workflow.state == .executing else { break }

            // Find all steps that are ready to execute
            let readySteps = workflow.steps.filter { step in
                !completedStepIds.contains(step.id)
                && step.state != .succeeded
                && step.state != .skipped
                && step.state != .rolledBack
                && step.dependencySet.isSubset(of: completedStepIds)
            }

            if readySteps.isEmpty {
                // Check for failed steps we can't retry
                let failedSteps = workflow.steps.filter { $0.state == .failed && !$0.canRetry }
                if !failedSteps.isEmpty {
                    workflow.state = .failed
                    let errorMsg = "Steps failed without recovery: \(failedSteps.map(\.name).joined(separator: ", "))"
                    workflow.addError(WorkflowError(message: errorMsg, isRecoverable: false))
                    activeWorkflows[id] = workflow
                    emit(.failed(workflowId: id, error: errorMsg))
                    break
                }
                // Should not happen with valid DAG
                break
            }

            // Execute ready steps in parallel (up to scheduler concurrency limit)
            let results = await executeWave(readySteps, in: &workflow)

            for (stepId, success) in results {
                if success {
                    completedStepIds.insert(stepId)
                }
            }

            // Update progress
            let progress = Double(completedStepIds.count) / Double(workflow.steps.count)
            let currentStepName = readySteps.first?.name ?? ""
            emit(.progressUpdate(workflowId: id, progress: progress, currentStep: currentStepName))

            activeWorkflows[id] = workflow
        }

        // Finalize
        if workflow.state == .executing {
            workflow.state = .completed
            workflow.completedAt = Date()
            let duration = workflow.completedAt!.timeIntervalSince(workflow.startedAt ?? workflow.createdAt)
            emit(.completed(workflowId: id, duration: duration))
        }

        activeWorkflows.removeValue(forKey: id)
        completedWorkflows[id] = workflow
        persistWorkflow(workflow)

        return workflow
    }

    // MARK: - Step Execution

    /// Execute a wave of independent steps in parallel.
    private func executeWave(_ steps: [WorkflowStep], in workflow: inout Workflow) async -> [(UUID, Bool)] {
        let maxParallel = 4
        let batch = Array(steps.prefix(maxParallel))

        return await withTaskGroup(of: (UUID, Bool).self) { group in
            for step in batch {
                let stepCopy = step
                let workflowId = workflow.id
                group.addTask {
                    let success = await self.executeStepSafe(stepCopy, workflowId: workflowId)
                    return (stepCopy.id, success)
                }
            }

            var results: [(UUID, Bool)] = []
            for await result in group {
                results.append(result)
                // Update step state in workflow
                if let idx = workflow.steps.firstIndex(where: { $0.id == result.0 }) {
                    if result.1 {
                        workflow.steps[idx].state = .succeeded
                        workflow.steps[idx].completedAt = Date()
                    } else {
                        workflow.steps[idx].state = .failed
                        workflow.steps[idx].completedAt = Date()
                    }
                }
            }
            return results
        }
    }

    /// Execute a single step with error handling and retry logic.
    private func executeStepSafe(_ step: WorkflowStep, workflowId: UUID) async -> Bool {
        emit(.stepBegan(workflowId: workflowId, stepId: step.id, name: step.name))

        var currentStep = step
        var attempt = 0

        while attempt <= currentStep.maxRetries {
            do {
                let result = try await executeStep(currentStep, workflowId: workflowId)

                // Create checkpoint after successful step
                if let workflow = activeWorkflows[workflowId] {
                    let checkpoint = await createCheckpoint(for: currentStep, in: workflow)
                    if let checkpoint = checkpoint {
                        emit(.checkpointCreated(workflowId: workflowId, checkpointId: checkpoint.id))
                    }
                }

                emit(.stepCompleted(workflowId: workflowId, stepId: step.id, name: step.name, result: result))
                return true
            } catch {
                attempt += 1
                if attempt <= currentStep.maxRetries {
                    emit(.stepRetrying(workflowId: workflowId, stepId: step.id,
                                       attempt: attempt, maxRetries: currentStep.maxRetries))
                    // Exponential backoff: 1s, 2s, 4s, ...
                    let backoffSeconds = UInt64(pow(2.0, Double(attempt - 1)))
                    try? await Task.sleep(nanoseconds: backoffSeconds * 1_000_000_000)
                    currentStep.retryCount = attempt
                } else {
                    emit(.stepFailed(workflowId: workflowId, stepId: step.id,
                                     name: step.name, error: error.localizedDescription))
                    return false
                }
            }
        }

        return false
    }

    /// Execute a single step's tool calls.
    private func executeStep(_ step: WorkflowStep, workflowId: UUID) async throws -> String {
        var results: [String] = []

        for invocation in step.toolCalls {
            // Simulate tool execution - in production this dispatches to ToolExec
            let result = try await executeToolInvocation(invocation, projectPath: activeWorkflows[workflowId]?.projectPath ?? "")

            // Validate against expected output if specified
            if let expected = invocation.expectedOutput, !result.contains(expected) {
                throw WorkflowEngineError.unexpectedToolOutput(
                    tool: invocation.toolName,
                    expected: expected,
                    actual: String(result.prefix(200))
                )
            }

            results.append(result)
        }

        return results.joined(separator: "\n---\n")
    }

    /// Execute a single tool invocation. In production, this delegates to ToolExec.
    private func executeToolInvocation(_ invocation: ToolInvocation, projectPath: String) async throws -> String {
        // Tool dispatch would go through ChatViewModel+ToolExecution in production.
        // For now, we simulate the execution interface.
        let toolName = invocation.toolName
        let args = invocation.arguments

        switch toolName {
        case "read_file":
            guard let path = args["path"] else {
                throw WorkflowEngineError.missingArgument(tool: toolName, argument: "path")
            }
            let fullPath = (projectPath as NSString).appendingPathComponent(path)
            return try String(contentsOfFile: fullPath, encoding: .utf8)

        case "write_file":
            guard let path = args["path"], let content = args["content"] else {
                throw WorkflowEngineError.missingArgument(tool: toolName, argument: "path or content")
            }
            let fullPath = (projectPath as NSString).appendingPathComponent(path)
            try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
            return "File written: \(path)"

        case "run_command":
            guard let command = args["command"] else {
                throw WorkflowEngineError.missingArgument(tool: toolName, argument: "command")
            }
            return try await runShellCommand(command, in: projectPath)

        case "list_files":
            let path = args["path"] ?? "."
            let fullPath = (projectPath as NSString).appendingPathComponent(path)
            let contents = try FileManager.default.contentsOfDirectory(atPath: fullPath)
            return contents.joined(separator: "\n")

        case "search_code":
            guard let query = args["query"] else {
                throw WorkflowEngineError.missingArgument(tool: toolName, argument: "query")
            }
            return try await runShellCommand("grep -r '\(query)' --include='*.swift' --include='*.ts' -l", in: projectPath)

        case "git_status":
            return try await runShellCommand("git status --porcelain", in: projectPath)

        case "git_commit":
            let message = args["message"] ?? "Workflow checkpoint"
            return try await runShellCommand("git add -A && git commit -m '\(message)'", in: projectPath)

        case "run_tests":
            let testCommand = args["command"] ?? "swift test 2>&1 || true"
            return try await runShellCommand(testCommand, in: projectPath)

        case "run_build":
            let buildCommand = args["command"] ?? "swift build 2>&1"
            return try await runShellCommand(buildCommand, in: projectPath)

        default:
            throw WorkflowEngineError.unknownTool(toolName)
        }
    }

    /// Run a shell command and return output.
    private func runShellCommand(_ command: String, in directory: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: directory)

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 && !errorOutput.isEmpty {
            throw WorkflowEngineError.toolExecutionFailed(tool: command, error: errorOutput)
        }

        return output.isEmpty ? errorOutput : output
    }

    // MARK: - Dependency Resolution

    /// Resolve execution order via topological sort. Throws on cycles.
    func resolveExecutionOrder(_ steps: [WorkflowStep]) throws -> [UUID] {
        var graph = DirectedGraph<UUID>()

        for step in steps {
            graph.addNode(step.id)
            for dep in step.dependencies {
                graph.addEdge(from: dep, to: step.id)
            }
        }

        guard let sorted = graph.topologicalSort() else {
            throw WorkflowEngineError.dependencyCycle
        }

        return sorted
    }

    // MARK: - Checkpointing

    /// Create a checkpoint after completing a step.
    func createCheckpoint(for step: WorkflowStep, in workflow: Workflow) async -> CheckpointData? {
        let snapshot = await checkpointer.captureProjectState(directory: workflow.projectPath)
        let gitRef = await checkpointer.currentGitRef(in: workflow.projectPath)

        var fileSnapshots: [FileSnapshot] = []
        for (path, hash) in snapshot.fileHashes {
            let fullPath = (workflow.projectPath as NSString).appendingPathComponent(path)
            guard let data = FileManager.default.contents(atPath: fullPath) else { continue }
            fileSnapshots.append(FileSnapshot(
                path: path, contentHash: hash, originalContent: data
            ))
        }

        let checkpoint = CheckpointData(
            stepId: step.id,
            projectStateHash: snapshot.fileHashes.values.joined().hashValue.description,
            modifiedFiles: Array(fileSnapshots.prefix(50)),
            gitRef: gitRef,
            description: "After step: \(step.name)"
        )

        return checkpoint
    }

    // MARK: - Rollback

    /// Rollback a workflow to a specific checkpoint.
    func rollback(_ workflowId: UUID, to checkpointId: UUID) async throws {
        guard var workflow = activeWorkflows[workflowId] else {
            throw WorkflowEngineError.workflowNotFound(workflowId)
        }

        guard let checkpoint = workflow.checkpoints.first(where: { $0.id == checkpointId }) else {
            throw WorkflowEngineError.checkpointNotFound(checkpointId)
        }

        workflow.state = .rollingBack
        activeWorkflows[workflowId] = workflow
        emit(.rollbackInitiated(workflowId: workflowId, toCheckpointId: checkpointId))

        // Restore files from checkpoint
        for snapshot in checkpoint.modifiedFiles {
            let fullPath = (workflow.projectPath as NSString).appendingPathComponent(snapshot.path)
            try snapshot.originalContent.write(to: URL(fileURLWithPath: fullPath))
        }

        // Git rollback if ref available
        if let gitRef = checkpoint.gitRef {
            await checkpointer.gitRollback(to: gitRef, in: workflow.projectPath)
        }

        // Mark steps after checkpoint as rolled back
        let checkpointStepIndex = workflow.steps.firstIndex(where: { $0.id == checkpoint.stepId })
        if let idx = checkpointStepIndex {
            for i in (idx + 1)..<workflow.steps.count {
                workflow.steps[i].state = .rolledBack
            }
        }

        workflow.state = .checkpointed
        activeWorkflows[workflowId] = workflow
        emit(.rollbackCompleted(workflowId: workflowId))
        persistWorkflow(workflow)
    }

    // MARK: - Pause / Resume

    func pauseWorkflow(_ id: UUID) {
        guard var workflow = activeWorkflows[id], workflow.state == .executing else { return }
        workflow.state = .paused
        activeWorkflows[id] = workflow
        emit(.paused(workflowId: id))
        persistWorkflow(workflow)
    }

    func resumeWorkflow(_ id: UUID) async throws -> Workflow {
        guard var workflow = activeWorkflows[id], workflow.state == .paused else {
            throw WorkflowEngineError.workflowNotFound(id)
        }
        workflow.state = .executing
        activeWorkflows[id] = workflow
        emit(.resumed(workflowId: id))
        return try await executeWorkflow(id)
    }

    // MARK: - Retry

    func retryStep(_ stepId: UUID, in workflowId: UUID) async throws {
        guard var workflow = activeWorkflows[workflowId] else {
            throw WorkflowEngineError.workflowNotFound(workflowId)
        }

        guard let idx = workflow.steps.firstIndex(where: { $0.id == stepId }) else {
            throw WorkflowEngineError.stepNotFound(stepId)
        }

        guard workflow.steps[idx].canRetry else {
            throw WorkflowEngineError.stepCannotRetry(stepId)
        }

        workflow.steps[idx].state = .ready
        workflow.steps[idx].retryCount += 1
        activeWorkflows[workflowId] = workflow

        // Re-execute workflow from this point
        _ = try await executeWorkflow(workflowId)
    }

    // MARK: - Queries

    func getWorkflow(_ id: UUID) -> Workflow? {
        activeWorkflows[id] ?? completedWorkflows[id]
    }

    func activeWorkflowList() -> [Workflow] {
        Array(activeWorkflows.values).sorted(by: { $0.createdAt > $1.createdAt })
    }

    func completedWorkflowList() -> [Workflow] {
        Array(completedWorkflows.values).sorted(by: { ($0.completedAt ?? $0.createdAt) > ($1.completedAt ?? $1.createdAt) })
    }

    func availableTemplates() -> [String: WorkflowTemplate] {
        builtInTemplates
    }

    // MARK: - Persistence

    private func persistWorkflow(_ workflow: Workflow) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(workflow) else { return }
        let filePath = (persistenceDirectory as NSString).appendingPathComponent("\(workflow.id.uuidString).json")
        try? data.write(to: URL(fileURLWithPath: filePath))
    }

    private func loadPersistedWorkflows() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: persistenceDirectory) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for file in files where file.hasSuffix(".json") {
            let path = (persistenceDirectory as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let workflow = try? decoder.decode(Workflow.self, from: data) else { continue }

            if workflow.state.isTerminal {
                completedWorkflows[workflow.id] = workflow
            } else {
                activeWorkflows[workflow.id] = workflow
            }
        }
    }

    private func ensureDirectoryExists(_ path: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            try? fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    // MARK: - Built-in Templates

    private static func createBuiltInTemplates() -> [String: WorkflowTemplate] {
        var templates: [String: WorkflowTemplate] = [:]

        // Add Feature Template
        templates["Add Feature"] = WorkflowTemplate(
            name: "Add Feature",
            description: "Scaffold and implement a new feature with tests",
            category: .featureAddition,
            stepTemplates: [
                StepTemplate(
                    name: "Analyze Requirements",
                    description: "Read relevant files and understand the codebase structure",
                    toolNames: ["list_files", "search_code"],
                    parameterKeys: ["target", "query"],
                    estimatedDuration: 15
                ),
                StepTemplate(
                    name: "Create Feature Files",
                    description: "Create the necessary source files for the feature",
                    toolNames: ["write_file"],
                    parameterKeys: ["path", "content"],
                    dependsOnIndices: [0],
                    estimatedDuration: 30
                ),
                StepTemplate(
                    name: "Write Tests",
                    description: "Create unit tests for the new feature",
                    toolNames: ["write_file"],
                    parameterKeys: ["path", "content"],
                    dependsOnIndices: [1],
                    estimatedDuration: 20
                ),
                StepTemplate(
                    name: "Build and Test",
                    description: "Compile and run tests to verify the feature",
                    toolNames: ["run_build", "run_tests"],
                    dependsOnIndices: [2],
                    estimatedDuration: 60
                ),
                StepTemplate(
                    name: "Commit Changes",
                    description: "Stage and commit all changes",
                    toolNames: ["git_commit"],
                    parameterKeys: ["message"],
                    dependsOnIndices: [3],
                    estimatedDuration: 5
                ),
            ],
            requiredParameters: ["target"],
            optionalParameters: ["query", "message"]
        )

        // Fix Bug Template
        templates["Fix Bug"] = WorkflowTemplate(
            name: "Fix Bug",
            description: "Diagnose, fix, and verify a bug fix",
            category: .bugFix,
            stepTemplates: [
                StepTemplate(
                    name: "Reproduce Issue",
                    description: "Understand the bug by searching for related code and error patterns",
                    toolNames: ["search_code", "read_file"],
                    parameterKeys: ["query", "path"],
                    estimatedDuration: 20
                ),
                StepTemplate(
                    name: "Apply Fix",
                    description: "Modify the relevant code to fix the bug",
                    toolNames: ["write_file"],
                    parameterKeys: ["path", "content"],
                    dependsOnIndices: [0],
                    estimatedDuration: 30
                ),
                StepTemplate(
                    name: "Verify Fix",
                    description: "Run tests to confirm the fix works",
                    toolNames: ["run_tests"],
                    dependsOnIndices: [1],
                    estimatedDuration: 45
                ),
                StepTemplate(
                    name: "Commit Fix",
                    description: "Commit the bug fix with descriptive message",
                    toolNames: ["git_commit"],
                    parameterKeys: ["message"],
                    dependsOnIndices: [2],
                    estimatedDuration: 5
                ),
            ],
            requiredParameters: ["query"],
            optionalParameters: ["path", "message"]
        )

        // Refactor Module Template
        templates["Refactor Module"] = WorkflowTemplate(
            name: "Refactor Module",
            description: "Refactor a module for improved structure and readability",
            category: .refactoring,
            stepTemplates: [
                StepTemplate(
                    name: "Analyze Module",
                    description: "Read all files in the module and identify refactoring opportunities",
                    toolNames: ["list_files", "read_file"],
                    parameterKeys: ["path"],
                    estimatedDuration: 20
                ),
                StepTemplate(
                    name: "Create Checkpoint",
                    description: "Commit current state as a safety checkpoint",
                    toolNames: ["git_commit"],
                    parameterKeys: ["message"],
                    dependsOnIndices: [0],
                    estimatedDuration: 5
                ),
                StepTemplate(
                    name: "Apply Refactoring",
                    description: "Restructure code, extract methods, rename, and clean up",
                    toolNames: ["write_file"],
                    parameterKeys: ["path", "content"],
                    dependsOnIndices: [1],
                    maxRetries: 3,
                    estimatedDuration: 60
                ),
                StepTemplate(
                    name: "Verify Refactoring",
                    description: "Build and test to verify refactoring correctness",
                    toolNames: ["run_build", "run_tests"],
                    dependsOnIndices: [2],
                    estimatedDuration: 60
                ),
                StepTemplate(
                    name: "Commit Refactoring",
                    description: "Commit the refactored code",
                    toolNames: ["git_commit"],
                    parameterKeys: ["message"],
                    dependsOnIndices: [3],
                    estimatedDuration: 5
                ),
            ],
            requiredParameters: ["path"],
            optionalParameters: ["message"]
        )

        // Add Tests Template
        templates["Add Tests"] = WorkflowTemplate(
            name: "Add Tests",
            description: "Generate comprehensive tests for existing code",
            category: .testing,
            stepTemplates: [
                StepTemplate(
                    name: "Identify Untested Code",
                    description: "Find source files without corresponding tests",
                    toolNames: ["list_files", "search_code"],
                    parameterKeys: ["path", "query"],
                    estimatedDuration: 15
                ),
                StepTemplate(
                    name: "Generate Tests",
                    description: "Create test files with comprehensive test cases",
                    toolNames: ["write_file"],
                    parameterKeys: ["path", "content"],
                    dependsOnIndices: [0],
                    estimatedDuration: 45
                ),
                StepTemplate(
                    name: "Run Tests",
                    description: "Execute the new tests to verify they pass",
                    toolNames: ["run_tests"],
                    dependsOnIndices: [1],
                    maxRetries: 3,
                    estimatedDuration: 60
                ),
                StepTemplate(
                    name: "Commit Tests",
                    description: "Commit the new test files",
                    toolNames: ["git_commit"],
                    parameterKeys: ["message"],
                    dependsOnIndices: [2],
                    estimatedDuration: 5
                ),
            ],
            requiredParameters: ["path"]
        )

        // Deploy Template
        templates["Deploy"] = WorkflowTemplate(
            name: "Deploy",
            description: "Build, test, and prepare for deployment",
            category: .deployment,
            stepTemplates: [
                StepTemplate(
                    name: "Pre-deploy Checks",
                    description: "Run full test suite and linting",
                    toolNames: ["run_tests", "run_build"],
                    estimatedDuration: 120
                ),
                StepTemplate(
                    name: "Check Git Status",
                    description: "Ensure working tree is clean",
                    toolNames: ["git_status"],
                    dependsOnIndices: [0],
                    estimatedDuration: 5
                ),
                StepTemplate(
                    name: "Build Release",
                    description: "Create optimized release build",
                    toolNames: ["run_command"],
                    parameterKeys: ["command"],
                    dependsOnIndices: [1],
                    estimatedDuration: 180,
                    timeout: 600
                ),
            ],
            requiredParameters: [],
            optionalParameters: ["command"]
        )

        // Migrate Dependency Template
        templates["Migrate Dependency"] = WorkflowTemplate(
            name: "Migrate Dependency",
            description: "Update or replace a project dependency",
            category: .migration,
            stepTemplates: [
                StepTemplate(
                    name: "Audit Usage",
                    description: "Find all files using the dependency",
                    toolNames: ["search_code"],
                    parameterKeys: ["query"],
                    estimatedDuration: 15
                ),
                StepTemplate(
                    name: "Create Safety Checkpoint",
                    description: "Commit current state before migration",
                    toolNames: ["git_commit"],
                    parameterKeys: ["message"],
                    dependsOnIndices: [0],
                    estimatedDuration: 5
                ),
                StepTemplate(
                    name: "Update Configuration",
                    description: "Update package manifest with new dependency version",
                    toolNames: ["write_file"],
                    parameterKeys: ["path", "content"],
                    dependsOnIndices: [1],
                    estimatedDuration: 10
                ),
                StepTemplate(
                    name: "Update Source Code",
                    description: "Modify source files to work with new dependency API",
                    toolNames: ["write_file"],
                    parameterKeys: ["path", "content"],
                    dependsOnIndices: [2],
                    maxRetries: 3,
                    estimatedDuration: 60
                ),
                StepTemplate(
                    name: "Verify Migration",
                    description: "Build and run tests after migration",
                    toolNames: ["run_build", "run_tests"],
                    dependsOnIndices: [3],
                    estimatedDuration: 90
                ),
                StepTemplate(
                    name: "Commit Migration",
                    description: "Commit the dependency migration",
                    toolNames: ["git_commit"],
                    parameterKeys: ["message"],
                    dependsOnIndices: [4],
                    estimatedDuration: 5
                ),
            ],
            requiredParameters: ["query"],
            optionalParameters: ["path", "message"]
        )

        return templates
    }
}

// MARK: - Errors

enum WorkflowEngineError: Error, LocalizedError {
    case workflowNotFound(UUID)
    case workflowAlreadyComplete(UUID)
    case stepNotFound(UUID)
    case stepCannotRetry(UUID)
    case checkpointNotFound(UUID)
    case dependencyCycle
    case unknownTool(String)
    case missingArgument(tool: String, argument: String)
    case unexpectedToolOutput(tool: String, expected: String, actual: String)
    case toolExecutionFailed(tool: String, error: String)
    case persistenceFailed(String)

    var errorDescription: String? {
        switch self {
        case .workflowNotFound(let id):
            return "Workflow not found: \(id)"
        case .workflowAlreadyComplete(let id):
            return "Workflow already completed: \(id)"
        case .stepNotFound(let id):
            return "Step not found: \(id)"
        case .stepCannotRetry(let id):
            return "Step cannot be retried: \(id)"
        case .checkpointNotFound(let id):
            return "Checkpoint not found: \(id)"
        case .dependencyCycle:
            return "Dependency cycle detected in workflow steps"
        case .unknownTool(let name):
            return "Unknown tool: \(name)"
        case .missingArgument(let tool, let arg):
            return "Tool '\(tool)' missing required argument: \(arg)"
        case .unexpectedToolOutput(let tool, let expected, let actual):
            return "Tool '\(tool)' output mismatch. Expected: \(expected), Got: \(actual)"
        case .toolExecutionFailed(let tool, let error):
            return "Tool '\(tool)' failed: \(error)"
        case .persistenceFailed(let msg):
            return "Persistence failed: \(msg)"
        }
    }
}
