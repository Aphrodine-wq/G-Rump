// ╔══════════════════════════════════════════════════════════════╗
// ║  ProjectConfig.swift                                        ║
// ║  Per-project .grump/config.json loader and merger           ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

// MARK: - Project Config (from .grump/config.json or grump.json)

struct ProjectConfig: Codable, Equatable {
    var model: String?
    var systemPrompt: String?
    var toolAllowlist: [String]?
    var projectFacts: [String]?
    var maxAgentSteps: Int?
    /// Path relative to project root for persistent context (e.g. ".grump/context.md"). If nil, falls back to .grump/context.md when present.
    var contextFile: String?

    static func load(from directory: String) -> ProjectConfig? {
        guard !directory.isEmpty else { return nil }
        let dir = (directory as NSString).standardizingPath
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir), fm.isReadableFile(atPath: dir) else { return nil }

        // Try .grump/config.json first, then grump.json
        let candidates: [String] = [
            (dir as NSString).appendingPathComponent(".grump/config.json"),
            (dir as NSString).appendingPathComponent("grump.json")
        ]
        for path in candidates {
            guard fm.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let decoded = try? JSONDecoder().decode(ProjectConfig.self, from: data) else {
                continue
            }
            return decoded
        }
        return nil
    }

    /// Merge project config into effective values. Returns (model, systemPrompt, toolAllowlist, maxSteps).
    /// Pass current user values; project config overrides when present.
    func merged(
        currentModel: EnhancedAIModel,
        currentPrompt: String,
        currentMaxSteps: Int
    ) -> (model: EnhancedAIModel, prompt: String, tools: [String]?, maxSteps: Int) {
        let model = model.flatMap { AIModelRegistry.shared.getModel(by: $0) } ?? currentModel
        let prompt: String
        if let projPrompt = systemPrompt, !projPrompt.isEmpty {
            prompt = projPrompt
        } else {
            prompt = currentPrompt
        }
        let maxSteps = maxAgentSteps ?? currentMaxSteps
        return (model, prompt, toolAllowlist, maxSteps)
    }

    /// Appends project facts to the system prompt when present.
    func appendFacts(to prompt: inout String) {
        guard let facts = projectFacts, !facts.isEmpty else { return }
        let block = facts.joined(separator: "\n")
        prompt += "\n\n## Project Facts\n\(block)"
    }

    /// Loads context from contextFile or, if nil, from .grump/context.md when present.
    func loadContext(from baseDir: String) -> String? {
        guard !baseDir.isEmpty else { return nil }
        let dir = (baseDir as NSString).standardizingPath
        let candidates: [String]
        if let path = contextFile, !path.isEmpty {
            candidates = [(dir as NSString).appendingPathComponent(path)]
        } else {
            candidates = [(dir as NSString).appendingPathComponent(".grump/context.md")]
        }
        let fm = FileManager.default
        for path in candidates {
            guard fm.fileExists(atPath: path),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let contents = String(data: data, encoding: .utf8),
                  !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            return contents
        }
        return nil
    }

    /// Appends project context from file to the system prompt when present.
    func appendContext(to prompt: inout String, baseDir: String) {
        guard let contents = loadContext(from: baseDir) else { return }
        prompt += "\n\n## Project Context\n\(contents)"
    }
}
