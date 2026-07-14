// ╔══════════════════════════════════════════════════════════════╗
// ║  OllamaModelDiscovery.swift                                  ║
// ║  Lists locally installed Ollama models via the native API    ║
// ╚══════════════════════════════════════════════════════════════╝

import Foundation

/// Discovers the models installed on a local Ollama server. The registry's
/// catalog is static for the cloud providers; Ollama's model set is whatever
/// the user has pulled, so it is fetched live (`/api/tags`) and each model's
/// capabilities probed (`/api/show`) before being merged into the registry.
enum OllamaModelDiscovery {

    /// Local server — a slow answer means it's not there.
    static let timeout: TimeInterval = 5

    /// Fetch installed models. Returns nil when the server is unreachable
    /// (callers keep the last known set), an empty array when it is running
    /// with no models pulled.
    static func discoverModels(baseURL: String? = nil) async -> [EnhancedAIModel]? {
        let root = nativeAPIRoot(from: baseURL)
        guard let tagsURL = URL(string: root + "/api/tags") else { return nil }

        var request = URLRequest(url: tagsURL)
        request.timeoutInterval = timeout

        let names: [String]
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let modelList = json["models"] as? [[String: Any]] else { return nil }
            names = modelList.compactMap { $0["name"] as? String }
        } catch {
            GRumpLogger.ai.info("Ollama not reachable at \(root): \(error.localizedDescription)")
            return nil
        }

        var models: [EnhancedAIModel] = []
        for name in names {
            let info = await showInfo(root: root, model: name)
            models.append(makeModel(name: name, info: info))
        }
        return models
    }

    /// The Ollama native API root: the configured base URL minus the
    /// OpenAI-compat `/v1` suffix (config stores `http://localhost:11434/v1`).
    static func nativeAPIRoot(from baseURL: String?) -> String {
        var base = (baseURL?.isEmpty == false ? baseURL! : AIProvider.ollama.defaultBaseURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/v1") { base.removeLast(3) }
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    // MARK: - Per-model capability probe

    struct ModelInfo {
        var supportsTools = false
        var supportsVision = false
        var contextWindow = 8_192
    }

    private static func showInfo(root: String, model: String) async -> ModelInfo {
        var info = ModelInfo()
        guard let url = URL(string: root + "/api/show") else { return info }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model])

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return info // conservative defaults: no tools, 8K context
        }
        return parseShowResponse(json)
    }

    /// Pure parser, unit-testable. Ollama reports a `capabilities` string array
    /// and a `model_info` dict whose context-length key is family-prefixed
    /// (e.g. `llama.context_length`).
    static func parseShowResponse(_ json: [String: Any]) -> ModelInfo {
        var info = ModelInfo()
        if let capabilities = json["capabilities"] as? [String] {
            info.supportsTools = capabilities.contains("tools")
            info.supportsVision = capabilities.contains("vision")
        }
        if let modelInfo = json["model_info"] as? [String: Any] {
            for (key, value) in modelInfo where key.hasSuffix(".context_length") {
                if let length = value as? Int, length > 0 {
                    info.contextWindow = length
                    break
                }
            }
        }
        return info
    }

    static func makeModel(name: String, info: ModelInfo) -> EnhancedAIModel {
        EnhancedAIModel(
            id: name,
            provider: .ollama,
            modelID: name,
            displayName: name,
            description: "Local Ollama model",
            contextWindow: info.contextWindow,
            maxOutput: max(1_024, min(8_192, info.contextWindow / 2)),
            requiresPaidTier: false,
            capabilities: ModelCapabilities(
                supportsTools: info.supportsTools,
                supportsVision: info.supportsVision,
                supportsStreaming: true,
                supportsFunctionCalling: info.supportsTools,
                supportsJSONMode: false,
                maxTokens: nil,
                supportsSystemMessages: true,
                supportsParallelToolUse: false
            ),
            pricing: nil
        )
    }
}
