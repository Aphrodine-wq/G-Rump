import Foundation
import OSLog

// MARK: - Speculative Branching Engine
//
// For ambiguous or high-stakes tasks, forks the solution into 2-3 parallel
// approaches using TaskGroup. Each branch gets a different strategy prompt,
// generates its solution independently, and results are compared.
//
// This is CPU branch prediction applied to code generation. No tool
// speculatively runs multiple solution paths and picks the winner.

// MARK: - Branch Strategy

struct BranchStrategy: Identifiable, Sendable {
    let id: String
    let name: String
    let approach: String
    let systemPromptOverride: String
    let branchIndex: Int

    /// Build a strategy prompt that frames the approach.
    var fullPrompt: String {
        """
        You are exploring APPROACH \(branchIndex + 1): "\(name)".

        Strategy: \(approach)

        \(systemPromptOverride)

        Implement this approach fully. Be concrete and complete.
        Do NOT mention other approaches or alternatives — commit fully to this strategy.
        """
    }
}

// MARK: - Branch Result

struct BranchResult: Identifiable, Sendable {
    let id: String
    let strategyName: String
    let branchIndex: Int
    let content: String
    let durationSeconds: Double
    let modelUsed: String
    var evaluationScore: Double = 0.0
    var evaluationReason: String = ""
    var isWinner: Bool = false
}

// MARK: - Branch State (for UI)

struct SpeculativeBranchState: Identifiable {
    let id: String
    var strategyName: String
    var branchIndex: Int
    var status: Status
    var streamingText: String = ""
    var result: String?
    var evaluationScore: Double?
    var isWinner: Bool = false
    var modelName: String = ""

    enum Status: String {
        case pending
        case running
        case completed
        case failed
        case evaluating
    }
}

// MARK: - Speculative Branching Events

enum SpeculativeBranchEvent {
    case strategiesReady([BranchStrategy])
    case branchStarted(branchId: String, branchIndex: Int, model: String)
    case branchChunk(branchId: String, text: String)
    case branchCompleted(branchId: String, result: String)
    case branchFailed(branchId: String, error: String)
    case evaluationStarted
    case evaluationComplete(winner: BranchResult, allResults: [BranchResult])
    case error(String)
}

// MARK: - Strategy Generator

enum StrategyGenerator {

    /// Generate 2-3 competing strategies for a given task.
    static func generateStrategies(for task: String) -> [BranchStrategy] {
        let lower = task.lowercased()

        // Architecture/design tasks
        if containsAny(lower, ["design", "architect", "structure", "organize", "pattern"]) {
            return [
                BranchStrategy(id: "s1", name: "Protocol-Oriented", approach: "Use protocols and protocol extensions for maximum flexibility and testability. Favor composition over inheritance.", systemPromptOverride: "Design using Swift protocol-oriented programming patterns.", branchIndex: 0),
                BranchStrategy(id: "s2", name: "Value-Type Driven", approach: "Use structs and enums as the primary building blocks. Minimize classes. Leverage value semantics for thread safety.", systemPromptOverride: "Design using value types (structs/enums) as the foundation.", branchIndex: 1),
                BranchStrategy(id: "s3", name: "Actor-Based", approach: "Use Swift actors and structured concurrency as the core architecture. Isolate state with actor boundaries.", systemPromptOverride: "Design using Swift actors and structured concurrency.", branchIndex: 2)
            ]
        }

        // Data handling tasks
        if containsAny(lower, ["data", "store", "persist", "database", "cache", "model"]) {
            return [
                BranchStrategy(id: "s1", name: "SwiftData", approach: "Use SwiftData with @Model macros for persistence. Leverage automatic CloudKit sync.", systemPromptOverride: "Implement using SwiftData framework.", branchIndex: 0),
                BranchStrategy(id: "s2", name: "SQLite Direct", approach: "Use SQLite directly for maximum control and performance. Write raw SQL with type-safe wrappers.", systemPromptOverride: "Implement using direct SQLite with type-safe Swift wrappers.", branchIndex: 1)
            ]
        }

        // UI tasks
        if containsAny(lower, ["ui", "view", "screen", "interface", "layout", "component"]) {
            return [
                BranchStrategy(id: "s1", name: "Declarative Composition", approach: "Build from small, reusable view components. Each view does one thing. Compose larger views from these atoms.", systemPromptOverride: "Build using atomic, composable SwiftUI views.", branchIndex: 0),
                BranchStrategy(id: "s2", name: "State-Machine Driven", approach: "Model the UI as a state machine. Each screen state is an enum case. Transitions are explicit and testable.", systemPromptOverride: "Build the UI around an explicit state machine with enum-based states.", branchIndex: 1)
            ]
        }

        // Performance/optimization tasks
        if containsAny(lower, ["performance", "optimize", "fast", "slow", "speed", "efficient"]) {
            return [
                BranchStrategy(id: "s1", name: "Algorithmic", approach: "Focus on algorithmic improvements: better data structures, reduced complexity, smarter caching.", systemPromptOverride: "Optimize through algorithmic improvements and better data structures.", branchIndex: 0),
                BranchStrategy(id: "s2", name: "Concurrency", approach: "Focus on parallelism: use TaskGroup, async sequences, and concurrent processing to utilize all cores.", systemPromptOverride: "Optimize through concurrency and parallel processing.", branchIndex: 1),
                BranchStrategy(id: "s3", name: "Memory/IO", approach: "Focus on memory and I/O: reduce allocations, use memory-mapped files, batch operations, lazy loading.", systemPromptOverride: "Optimize through memory efficiency and I/O optimization.", branchIndex: 2)
            ]
        }

        // Default: two general approaches
        return [
            BranchStrategy(id: "s1", name: "Direct Implementation", approach: "Take the most straightforward path. Minimal abstraction. Get it working correctly first, then refine.", systemPromptOverride: "Implement directly and pragmatically. Prioritize correctness over elegance.", branchIndex: 0),
            BranchStrategy(id: "s2", name: "Extensible Design", approach: "Build with extensibility in mind. Use dependency injection, protocols, and clean separation of concerns.", systemPromptOverride: "Implement with extensibility and clean architecture. Use protocols and dependency injection.", branchIndex: 1)
        ]
    }

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }
}

// MARK: - Speculative Branching Engine

@MainActor
final class SpeculativeBranchingEngine: ObservableObject {

    @Published var branches: [SpeculativeBranchState] = []
    @Published var isRunning = false
    @Published var winnerIndex: Int?

    private let openRouterService = OpenRouterService()
    private let maxConcurrentBranches = 3
    private let logger = GRumpLogger.general

    // MARK: - Run

    /// Execute speculative branching for a task.
    func run(
        userTask: String,
        conversationHistory: [Message],
        apiKey: String,
        authToken: String?,
        fallbackModel: AIModel,
        onEvent: @escaping (SpeculativeBranchEvent) -> Void
    ) async {
        isRunning = true
        defer { isRunning = false }

        // Step 1: Generate strategies
        let strategies = StrategyGenerator.generateStrategies(for: userTask)
        onEvent(.strategiesReady(strategies))

        branches = strategies.map { strategy in
            SpeculativeBranchState(
                id: strategy.id,
                strategyName: strategy.name,
                branchIndex: strategy.branchIndex,
                status: .pending
            )
        }

        // Step 2: Run all branches in parallel
        let results: [BranchResult] = await withTaskGroup(of: BranchResult?.self) { group in
            for strategy in strategies {
                let model = ModelRouter.route(taskType: .codeGen, fallback: fallbackModel)

                // Update UI
                if let idx = branches.firstIndex(where: { $0.id == strategy.id }) {
                    branches[idx].status = .running
                    branches[idx].modelName = model.displayName
                }
                onEvent(.branchStarted(branchId: strategy.id, branchIndex: strategy.branchIndex, model: model.displayName))

                group.addTask { [weak self] in
                    guard let self else { return nil }
                    let startTime = Date()

                    let messages: [Message] = [
                        Message(role: .system, content: strategy.fullPrompt),
                        Message(role: .user, content: userTask)
                    ]

                    var content = ""
                    do {
                        if let token = authToken, !token.isEmpty {
                            let stream = self.openRouterService.streamMessageViaBackend(
                                messages: messages,
                                model: model.rawValue,
                                backendBaseURL: PlatformService.baseURL,
                                authToken: token
                            )
                            for try await event in stream {
                                if case .text(let chunk) = event {
                                    content += chunk
                                    onEvent(.branchChunk(branchId: strategy.id, text: chunk))
                                }
                            }
                        } else {
                            let stream = self.openRouterService.streamMessage(
                                messages: messages,
                                apiKey: apiKey,
                                model: model.rawValue
                            )
                            for try await event in stream {
                                if case .text(let chunk) = event {
                                    content += chunk
                                    onEvent(.branchChunk(branchId: strategy.id, text: chunk))
                                }
                            }
                        }
                    } catch {
                        onEvent(.branchFailed(branchId: strategy.id, error: error.localizedDescription))
                        return BranchResult(
                            id: strategy.id,
                            strategyName: strategy.name,
                            branchIndex: strategy.branchIndex,
                            content: "Error: \(error.localizedDescription)",
                            durationSeconds: Date().timeIntervalSince(startTime),
                            modelUsed: model.displayName
                        )
                    }

                    let result = BranchResult(
                        id: strategy.id,
                        strategyName: strategy.name,
                        branchIndex: strategy.branchIndex,
                        content: content,
                        durationSeconds: Date().timeIntervalSince(startTime),
                        modelUsed: model.displayName
                    )

                    onEvent(.branchCompleted(branchId: strategy.id, result: content))
                    return result
                }
            }

            var results: [BranchResult] = []
            for await result in group {
                if let r = result {
                    results.append(r)
                    if let idx = branches.firstIndex(where: { $0.id == r.id }) {
                        branches[idx].status = .completed
                        branches[idx].result = r.content
                    }
                }
            }
            return results
        }

        // Step 3: Evaluate and pick winner
        guard !results.isEmpty else {
            onEvent(.error("All branches failed"))
            return
        }

        onEvent(.evaluationStarted)
        for idx in branches.indices { branches[idx].status = .evaluating }

        let evaluatedResults = await evaluate(
            results: results,
            userTask: userTask,
            apiKey: apiKey,
            authToken: authToken,
            fallbackModel: fallbackModel
        )

        // Mark winner
        if let winner = evaluatedResults.first {
            if let idx = branches.firstIndex(where: { $0.id == winner.id }) {
                branches[idx].isWinner = true
                branches[idx].evaluationScore = winner.evaluationScore
                winnerIndex = idx
            }
        }

        for result in evaluatedResults {
            if let idx = branches.firstIndex(where: { $0.id == result.id }) {
                branches[idx].evaluationScore = result.evaluationScore
                branches[idx].status = .completed
            }
        }

        let winner = evaluatedResults.first ?? results[0]
        onEvent(.evaluationComplete(winner: winner, allResults: evaluatedResults))
    }

    // MARK: - Evaluation

    /// Have a judge model evaluate all branch results and pick the best one.
    private func evaluate(
        results: [BranchResult],
        userTask: String,
        apiKey: String,
        authToken: String?,
        fallbackModel: AIModel
    ) async -> [BranchResult] {
        let judgeModel = ModelRouter.route(taskType: .reasoning, fallback: fallbackModel)

        let approachSummaries = results.enumerated().map { (i, result) in
            """
            --- APPROACH \(i + 1): \(result.strategyName) ---
            \(String(result.content.prefix(3000)))
            --- END APPROACH \(i + 1) ---
            """
        }.joined(separator: "\n\n")

        let judgePrompt = """
        You are a code quality judge. Multiple approaches were generated for the same task.
        Evaluate each approach on these criteria:
        1. **Correctness**: Does it solve the problem correctly?
        2. **Completeness**: Does it handle edge cases and error conditions?
        3. **Maintainability**: Is the code clean, readable, and well-structured?
        4. **Performance**: Is it efficient and scalable?
        5. **Idiomatic**: Does it follow language/framework best practices?

        Respond with ONLY valid JSON:
        {
          "evaluations": [
            {"approach": 1, "score": 0.85, "reason": "Brief explanation"},
            {"approach": 2, "score": 0.72, "reason": "Brief explanation"}
          ],
          "winner": 1,
          "winner_reason": "Why this approach is best overall"
        }
        """

        let messages: [Message] = [
            Message(role: .system, content: judgePrompt),
            Message(role: .user, content: "Task: \(userTask)\n\n\(approachSummaries)")
        ]

        var fullResponse = ""
        do {
            if let token = authToken, !token.isEmpty {
                let stream = openRouterService.streamMessageViaBackend(
                    messages: messages,
                    model: judgeModel.rawValue,
                    backendBaseURL: PlatformService.baseURL,
                    authToken: token
                )
                for try await event in stream {
                    if case .text(let chunk) = event { fullResponse += chunk }
                }
            } else {
                let stream = openRouterService.streamMessage(
                    messages: messages,
                    apiKey: apiKey,
                    model: judgeModel.rawValue
                )
                for try await event in stream {
                    if case .text(let chunk) = event { fullResponse += chunk }
                }
            }
        } catch {
            // Fallback: pick the longest result (heuristic for completeness)
            logger.error("SpeculativeBranching: Evaluation failed: \(error.localizedDescription)")
            var mutResults = results
            if let maxIdx = mutResults.indices.max(by: { mutResults[$0].content.count < mutResults[$1].content.count }) {
                mutResults[maxIdx].isWinner = true
                mutResults[maxIdx].evaluationScore = 0.7
            }
            return mutResults.sorted { $0.evaluationScore > $1.evaluationScore }
        }

        return parseEvaluation(fullResponse, results: results)
    }

    private func parseEvaluation(_ json: String, results: [BranchResult]) -> [BranchResult] {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }

        // Try to extract JSON
        var jsonStr = cleaned
        if let start = cleaned.firstIndex(of: "{"), let end = cleaned.lastIndex(of: "}") {
            jsonStr = String(cleaned[start...end])
        }

        guard let data = jsonStr.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let evaluations = obj["evaluations"] as? [[String: Any]] else {
            // Fallback: assign equal scores
            return results.map { var r = $0; r.evaluationScore = 0.5; return r }
                .sorted { $0.content.count > $1.content.count }
        }

        let winnerIdx = (obj["winner"] as? Int ?? 1) - 1
        let winnerReason = obj["winner_reason"] as? String ?? ""

        var mutResults = results
        for eval in evaluations {
            let approachIdx = ((eval["approach"] as? Int) ?? 1) - 1
            let score = eval["score"] as? Double ?? 0.5
            let reason = eval["reason"] as? String ?? ""

            if approachIdx >= 0 && approachIdx < mutResults.count {
                mutResults[approachIdx].evaluationScore = score
                mutResults[approachIdx].evaluationReason = reason
                mutResults[approachIdx].isWinner = approachIdx == winnerIdx
            }
        }

        if winnerIdx >= 0 && winnerIdx < mutResults.count {
            mutResults[winnerIdx].isWinner = true
            if mutResults[winnerIdx].evaluationReason.isEmpty {
                mutResults[winnerIdx].evaluationReason = winnerReason
            }
        }

        return mutResults.sorted { $0.evaluationScore > $1.evaluationScore }
    }
}
