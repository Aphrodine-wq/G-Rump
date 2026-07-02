import Foundation

// MARK: - Agent Orchestrator
//
// Parallel multi-agent execution engine. Decomposes a complex user task into a
// dependency graph of subtasks, assigns each an optimal model via ModelRouter,
// and executes independent subtasks concurrently using Swift TaskGroup.

// MARK: - Task Graph Models

struct SubAgentTask: Identifiable, Codable, Sendable {
    let id: String
    let description: String
    let taskType: TaskType
    let assignedModel: String          // AIModel.rawValue
    var dependsOn: [String]            // IDs of tasks that must complete first
    var status: SubAgentStatus = .pending
    var result: String?
    var startedAt: Date?
    var completedAt: Date?
    var agentIndex: Int = 0            // Display index (1-based in UI)

    enum SubAgentStatus: String, Codable, Sendable {
        case pending
        case running
        case completed
        case failed
    }
}

struct TaskGraph: Codable, Sendable {
    var tasks: [SubAgentTask]
    var synthesisInstruction: String   // How to combine results into a final answer
}

// MARK: - Orchestrator Events (streamed back to ChatViewModel)

enum OrchestratorEvent {
    case planReady(TaskGraph)
    case taskStarted(taskId: String, agentIndex: Int, model: String, taskType: TaskType)
    case taskChunk(taskId: String, text: String)
    case taskCompleted(taskId: String, result: String)
    case taskFailed(taskId: String, error: String)
    case synthesisChunk(text: String)
    case finished(finalResponse: String)
    case error(String)
}

// MARK: - Agent Orchestrator

@MainActor
final class AgentOrchestrator {

    private let openRouterService = OpenRouterService()
    private let maxConcurrentAgents: Int

    init(maxConcurrentAgents: Int = 4) {
        self.maxConcurrentAgents = maxConcurrentAgents
    }

    // MARK: - Main Entry Point

    /// Decompose the user task, run sub-agents in parallel, synthesize results.
    /// Yields OrchestratorEvents via the continuation for the UI to consume.
    func run(
        userTask: String,
        conversationHistory: [Message],
        apiKey: String,
        authToken: String?,
        fallbackModel: AIModel,
        onEvent: @escaping (OrchestratorEvent) -> Void
    ) async {
        // Step 1: Decompose task into a graph
        let graph: TaskGraph
        do {
            graph = try await decompose(
                userTask: userTask,
                conversationHistory: conversationHistory,
                apiKey: apiKey,
                authToken: authToken,
                fallbackModel: fallbackModel
            )
        } catch {
            onEvent(.error("Failed to decompose task: \(error.localizedDescription)"))
            return
        }

        onEvent(.planReady(graph))

        // Step 2: Execute tasks respecting dependency order
        var completedResults: [String: String] = [:]  // taskId -> result
        var tasks = graph.tasks

        // Topological execution: keep running waves of tasks whose deps are all done
        var maxWaves = tasks.count + 1
        while !tasks.allSatisfy({ $0.status == .completed || $0.status == .failed }) && maxWaves > 0 {
            maxWaves -= 1

            // Find tasks ready to run (pending + all deps completed)
            let ready = tasks.filter { task in
                task.status == .pending &&
                task.dependsOn.allSatisfy { depId in
                    completedResults[depId] != nil
                }
            }

            guard !ready.isEmpty else { break }

            // Run this wave in parallel (up to maxConcurrentAgents)
            let wave = Array(ready.prefix(maxConcurrentAgents))

            // Mark as running
            for task in wave {
                if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[idx].status = .running
                    tasks[idx].startedAt = Date()
                    onEvent(.taskStarted(
                        taskId: task.id,
                        agentIndex: task.agentIndex,
                        model: task.assignedModel,
                        taskType: task.taskType
                    ))
                }
            }

            // Build context for each task (include results of its dependencies)
            let results: [(String, String, Bool)] = await withTaskGroup(of: (String, String, Bool).self) { group in
                for task in wave {
                    let depContext = task.dependsOn.compactMap { depId -> String? in
                        guard let r = completedResults[depId],
                              let dep = graph.tasks.first(where: { $0.id == depId }) else { return nil }
                        return "Result from '\(dep.description)':\n\(r)"
                    }.joined(separator: "\n\n")

                    group.addTask { [weak self] in
                        guard let self else { return (task.id, "Error: orchestrator deallocated", false) }
                        let result = await self.runSubAgent(
                            task: task,
                            userTask: userTask,
                            depContext: depContext,
                            conversationHistory: conversationHistory,
                            apiKey: apiKey,
                            authToken: authToken,
                            onChunk: { chunk in
                                onEvent(.taskChunk(taskId: task.id, text: chunk))
                            }
                        )
                        return (task.id, result, !result.lowercased().hasPrefix("error"))
                    }
                }
                var out: [(String, String, Bool)] = []
                for await r in group { out.append(r) }
                return out
            }

            // Commit results
            for (taskId, result, success) in results {
                if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
                    tasks[idx].status = success ? .completed : .failed
                    tasks[idx].result = result
                    tasks[idx].completedAt = Date()
                }
                completedResults[taskId] = result
                if success {
                    onEvent(.taskCompleted(taskId: taskId, result: result))
                } else {
                    onEvent(.taskFailed(taskId: taskId, error: result))
                }
            }
        }

        // Step 3: Synthesize all results into a final coherent response
        let finalResponse = await synthesize(
            userTask: userTask,
            graph: graph,
            completedResults: completedResults,
            apiKey: apiKey,
            authToken: authToken,
            fallbackModel: fallbackModel,
            onChunk: { chunk in
                onEvent(.synthesisChunk(text: chunk))
            }
        )

        onEvent(.finished(finalResponse: finalResponse))
    }

    // MARK: - Task Decomposition

    private func decompose(
        userTask: String,
        conversationHistory: [Message],
        apiKey: String,
        authToken: String?,
        fallbackModel: AIModel
    ) async throws -> TaskGraph {
        let systemPrompt = """
        You are a task decomposition engine. Break the user's request into 2-5 parallel subtasks.
        Each subtask should be independently executable where possible.

        Respond with ONLY valid JSON in this exact format:
        {
          "tasks": [
            {
              "id": "t1",
              "description": "Clear description of what this subtask does",
              "taskType": "code_gen",
              "dependsOn": []
            },
            {
              "id": "t2",
              "description": "Another subtask that depends on t1",
              "taskType": "testing",
              "dependsOn": ["t1"]
            }
          ],
          "synthesisInstruction": "Combine the code from t1 with the tests from t2 into a complete solution."
        }

        Valid taskType values: reasoning, planning, file_ops, search, code_gen, synthesis, writing, web, research, testing, debugging, general

        Rules:
        - Keep tasks focused and atomic
        - Use dependsOn only when truly necessary (prefer parallel execution)
        - 2 tasks minimum, 5 tasks maximum
        - Each description should be a complete, self-contained instruction
        """

        let decompositionMessages: [Message] = [
            Message(role: .system, content: systemPrompt),
            Message(role: .user, content: "Decompose this task:\n\n\(userTask)")
        ]

        let modelToUse = fallbackModel.rawValue
        var fullResponse = ""

        if let token = authToken, !token.isEmpty {
            let stream = openRouterService.streamMessageViaBackend(
                messages: decompositionMessages,
                model: modelToUse,
                backendBaseURL: PlatformService.baseURL,
                authToken: token
            )
            for try await event in stream {
                if case .text(let chunk) = event { fullResponse += chunk }
            }
        } else {
            let stream = openRouterService.streamMessage(
                messages: decompositionMessages,
                apiKey: apiKey,
                model: modelToUse
            )
            for try await event in stream {
                if case .text(let chunk) = event { fullResponse += chunk }
            }
        }

        return try parseTaskGraph(from: fullResponse, fallbackModel: fallbackModel)
    }

    private func parseTaskGraph(from json: String, fallbackModel: AIModel) throws -> TaskGraph {
        // Extract JSON from potential markdown code fences
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        guard let data = cleaned.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tasksArr = obj["tasks"] as? [[String: Any]] else {
            // Fallback: single task with the original request
            let task = SubAgentTask(
                id: "t1",
                description: "Complete the requested task",
                taskType: .general,
                assignedModel: fallbackModel.rawValue,
                dependsOn: [],
                agentIndex: 1
            )
            return TaskGraph(tasks: [task], synthesisInstruction: "Return the result directly.")
        }

        let synthesis = obj["synthesisInstruction"] as? String ?? "Combine all results into a coherent final answer."

        var tasks: [SubAgentTask] = []
        for (i, taskDict) in tasksArr.enumerated() {
            let id = taskDict["id"] as? String ?? "t\(i+1)"
            let description = taskDict["description"] as? String ?? "Subtask \(i+1)"
            let typeStr = taskDict["taskType"] as? String ?? "general"
            let taskType = TaskType(rawValue: typeStr) ?? .general
            let dependsOn = taskDict["dependsOn"] as? [String] ?? []
            let assignedModel = ModelRouter.route(taskType: taskType, fallback: fallbackModel).rawValue
            tasks.append(SubAgentTask(
                id: id,
                description: description,
                taskType: taskType,
                assignedModel: assignedModel,
                dependsOn: dependsOn,
                agentIndex: i + 1
            ))
        }

        return TaskGraph(tasks: tasks, synthesisInstruction: synthesis)
    }

    // MARK: - Sub-Agent Execution

    private func runSubAgent(
        task: SubAgentTask,
        userTask: String,
        depContext: String,
        conversationHistory: [Message],
        apiKey: String,
        authToken: String?,
        onChunk: @escaping (String) -> Void
    ) async -> String {
        var systemContent = """
        You are a specialized sub-agent focused on: \(task.taskType.displayName).
        Complete ONLY the specific subtask assigned to you. Be thorough and precise.
        Original user request for context: \(userTask)
        """
        if !depContext.isEmpty {
            systemContent += "\n\nResults from prerequisite tasks:\n\(depContext)"
        }

        let messages: [Message] = [
            Message(role: .system, content: systemContent),
            Message(role: .user, content: task.description)
        ]

        var result = ""
        do {
            if let token = authToken, !token.isEmpty {
                let stream = openRouterService.streamMessageViaBackend(
                    messages: messages,
                    model: task.assignedModel,
                    backendBaseURL: PlatformService.baseURL,
                    authToken: token
                )
                for try await event in stream {
                    if case .text(let chunk) = event {
                        result += chunk
                        onChunk(chunk)
                    }
                }
            } else {
                let stream = openRouterService.streamMessage(
                    messages: messages,
                    apiKey: apiKey,
                    model: task.assignedModel
                )
                for try await event in stream {
                    if case .text(let chunk) = event {
                        result += chunk
                        onChunk(chunk)
                    }
                }
            }
        } catch {
            return "Error: \(error.localizedDescription)"
        }

        return result.isEmpty ? "Error: sub-agent returned no content" : result
    }

    // MARK: - Synthesis

    private func synthesize(
        userTask: String,
        graph: TaskGraph,
        completedResults: [String: String],
        apiKey: String,
        authToken: String?,
        fallbackModel: AIModel,
        onChunk: @escaping (String) -> Void
    ) async -> String {
        var resultsBlock = ""
        for task in graph.tasks {
            if let result = completedResults[task.id] {
                resultsBlock += "\n\n### Agent \(task.agentIndex): \(task.description)\n\(result)"
            }
        }

        let systemPrompt = """
        You are a synthesis agent. Multiple specialized sub-agents have worked on parts of a task.
        Your job: combine their results into a single, coherent, complete response to the user.

        Synthesis instruction: \(graph.synthesisInstruction)

        Be concise. Do not repeat what each agent said verbatim — synthesize and integrate.
        """

        let messages: [Message] = [
            Message(role: .system, content: systemPrompt),
            Message(role: .user, content: "Original request: \(userTask)\n\nSub-agent results:\(resultsBlock)\n\nProvide the final synthesized response:")
        ]

        // Use Claude for synthesis (best at coherent long-form integration)
        let synthesisModel = ModelRouter.route(taskType: .synthesis, fallback: fallbackModel).rawValue
        var finalResponse = ""

        do {
            if let token = authToken, !token.isEmpty {
                let stream = openRouterService.streamMessageViaBackend(
                    messages: messages,
                    model: synthesisModel,
                    backendBaseURL: PlatformService.baseURL,
                    authToken: token
                )
                for try await event in stream {
                    if case .text(let chunk) = event {
                        finalResponse += chunk
                        onChunk(chunk)
                    }
                }
            } else {
                let stream = openRouterService.streamMessage(
                    messages: messages,
                    apiKey: apiKey,
                    model: synthesisModel
                )
                for try await event in stream {
                    if case .text(let chunk) = event {
                        finalResponse += chunk
                        onChunk(chunk)
                    }
                }
            }
        } catch {
            // Fallback: concatenate results
            finalResponse = graph.tasks.compactMap { task -> String? in
                guard let r = completedResults[task.id] else { return nil }
                return "**\(task.description)**\n\(r)"
            }.joined(separator: "\n\n")
        }

        return finalResponse
    }
}
