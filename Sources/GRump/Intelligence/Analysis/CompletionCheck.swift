import Foundation

/// The in-loop completion judge: a cheap outside check that the original
/// request is actually satisfied before the agent loop accepts "done".
///
/// Design rules (see docs/ai-agent): deterministic plan fast-path first
/// (open update_plan steps need no LLM), light-model judge over a distilled
/// snapshot for everything else, and FAIL-OPEN — judge noise must never
/// hold a finished run hostage.
enum CompletionCheck {

    struct Verdict: Sendable, Equatable {
        let complete: Bool
        let unfinished: [String]
        let reason: String
    }

    /// Pure predicate for whether a check is warranted at the would-be
    /// completion point. Kept static + argument-only for testability.
    static func shouldRun(
        gateEnabled: Bool,
        hasCodeChanges: Bool,
        openPlanSteps: Int,
        iterationCount: Int,
        maxIterations: Int,
        completionRetries: Int
    ) -> Bool {
        guard gateEnabled else { return false }
        guard hasCodeChanges || openPlanSteps > 0 else { return false }
        guard iterationCount > 1 else { return false }
        guard iterationCount < maxIterations - 1 else { return false }
        return completionRetries < 2
    }

    /// One-shot light-model judgment over a distilled run snapshot.
    /// Returns nil on any transport/parse failure (fail-open).
    static func judge(
        taskFraming: String,
        changedFiles: [String],
        lastAssistantMessage: String,
        verifyStatus: String,
        modelID: String
    ) async -> Verdict? {
        let systemPrompt = """
        You are a completion auditor for a coding agent. Given the user's \
        original request and a summary of what the agent did, decide whether \
        the request is FULLY satisfied. Be strict about explicitly requested \
        items (all sub-tasks, all named files) but do not invent new scope.

        Respond with ONLY valid JSON:
        {"complete": true/false, "unfinished": ["item", ...], "reason": "one sentence"}
        """
        let user = """
        Original request (verbatim):
        \(String(taskFraming.prefix(2_000)))

        Files the agent changed: \(changedFiles.isEmpty ? "none" : changedFiles.joined(separator: ", "))
        Build verification: \(verifyStatus)

        Agent's final message:
        \(String(lastAssistantMessage.prefix(1_500)))
        """
        let messages: [Message] = [
            Message(role: .system, content: systemPrompt),
            Message(role: .user, content: user)
        ]

        var response = ""
        do {
            let stream = MultiProviderAIService.stream(messages: messages, modelID: modelID)
            for try await event in stream {
                if case .text(let chunk) = event { response += chunk }
            }
        } catch {
            GRumpLogger.ai.error("CompletionCheck judge failed: \(error.localizedDescription)")
            return nil
        }
        return parseVerdict(response)
    }

    /// Defensive JSON parse (fence-strip + first-brace fallback). Testable.
    static func parseVerdict(_ raw: String) -> Verdict? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            let lines = cleaned.components(separatedBy: "\n")
            cleaned = lines.dropFirst().dropLast().joined(separator: "\n")
        }
        var dict = decodeObject(cleaned)
        if dict == nil,
           let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            dict = decodeObject(String(cleaned[start...end]))
        }
        guard let obj = dict, let complete = obj["complete"] as? Bool else { return nil }
        return Verdict(
            complete: complete,
            unfinished: (obj["unfinished"] as? [String]) ?? [],
            reason: (obj["reason"] as? String) ?? ""
        )
    }

    private static func decodeObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
