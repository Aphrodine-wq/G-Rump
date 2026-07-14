import XCTest
@testable import GRump

final class AIModelCatalogTests: XCTestCase {

    private let registry = AIModelRegistry.shared

    // MARK: - Default model

    func testDefaultModelIsOpus48() {
        let model = registry.defaultModel()
        XCTAssertEqual(model.id, "claude-opus-4-8")
        XCTAssertEqual(model.provider, .anthropic)
    }

    func testPerProviderDefaults() {
        XCTAssertEqual(registry.defaultModel(for: .anthropic)?.id, "claude-opus-4-8")
        XCTAssertEqual(registry.defaultModel(for: .openAI)?.id, "gpt-5.2")
        XCTAssertEqual(registry.defaultModel(for: .google)?.id, "gemini-3-pro")
        XCTAssertEqual(registry.defaultModel(for: .openRouter)?.id, "anthropic/claude-sonnet-5")
    }

    func testDefaultIsNeverFable() {
        for provider in AIProvider.allCases {
            XCTAssertNotEqual(registry.defaultModel(for: provider)?.id, "claude-fable-5",
                              "Fable is premium and must never be a default")
        }
    }

    // MARK: - Expected catalog entries

    func testAnthropicLineup() {
        let ids = registry.getModels(for: .anthropic).map(\.id)
        XCTAssertEqual(Set(ids), ["claude-opus-4-8", "claude-fable-5", "claude-sonnet-5", "claude-haiku-4-5"])
    }

    func testOpenAILineup() {
        let ids = registry.getModels(for: .openAI).map(\.id)
        XCTAssertEqual(Set(ids), ["gpt-5.2", "gpt-5.3-codex"])
    }

    func testGoogleLineup() {
        let ids = registry.getModels(for: .google).map(\.id)
        XCTAssertEqual(Set(ids), ["gemini-3-pro", "gemini-2.5-flash"])
    }

    func testOpenRouterLineupIncludesLegacyQwenRoute() {
        let ids = registry.getModels(for: .openRouter).map(\.id)
        XCTAssertEqual(Set(ids), ["anthropic/claude-sonnet-5", "openai/gpt-5.3-codex",
                                  "google/gemini-3-pro", "qwen/qwen3-coder"])
    }

    func testEveryCloudProviderHasModels() {
        // Local providers (Ollama) have no static entries — their models are
        // discovered live from the local server.
        for provider in AIProvider.allCases where !provider.isLocal {
            XCTAssertFalse(registry.getModels(for: provider).isEmpty,
                           "\(provider.displayName) has no catalog entries")
        }
    }

    func testOllamaHasNoStaticCatalogEntries() {
        XCTAssertTrue(registry.defaultModelCatalog().allSatisfy { $0.provider != .ollama },
                      "Ollama models must come from live discovery, not the static catalog")
    }

    // MARK: - Model shape

    func testFableIsMarkedPremium() {
        XCTAssertTrue(registry.getModel(by: "claude-fable-5")?.requiresPaidTier ?? false)
    }

    func testAnthropicContextAndOutputCaps() {
        // 1M context / 128K output across the tier, except Haiku (200K / 64K).
        for id in ["claude-opus-4-8", "claude-fable-5", "claude-sonnet-5"] {
            let model = registry.getModel(by: id)
            XCTAssertEqual(model?.contextWindow, 1_000_000, "\(id) context window")
            XCTAssertEqual(model?.maxOutput, 128_000, "\(id) max output")
        }
        let haiku = registry.getModel(by: "claude-haiku-4-5")
        XCTAssertEqual(haiku?.contextWindow, 200_000)
        XCTAssertEqual(haiku?.maxOutput, 64_000)
    }

    func testAnthropicPricingPresent() {
        for id in ["claude-opus-4-8", "claude-fable-5", "claude-sonnet-5", "claude-haiku-4-5"] {
            XCTAssertNotNil(registry.getModel(by: id)?.pricing, "\(id) missing pricing")
        }
        // Opus 4.8: $5 in / $25 out per MTok → 0.005 / 0.025 per 1K.
        let opus = registry.getModel(by: "claude-opus-4-8")?.pricing
        XCTAssertEqual(opus?.inputPricePer1K, 0.005)
        XCTAssertEqual(opus?.outputPricePer1K, 0.025)
    }

    func testAllModelsHaveValidFields() {
        for model in registry.getAllModels() {
            XCTAssertFalse(model.id.isEmpty)
            XCTAssertEqual(model.id, model.modelID, "\(model.id): id must equal the wire id")
            XCTAssertFalse(model.displayName.isEmpty, "\(model.id) displayName empty")
            XCTAssertFalse(model.description.isEmpty, "\(model.id) description empty")
            XCTAssertGreaterThan(model.contextWindow, 0, "\(model.id) contextWindow")
            XCTAssertGreaterThan(model.maxOutput, 0, "\(model.id) maxOutput")
            XCTAssertTrue(model.capabilities.supportsTools, "\(model.id) must support tools — this is an agent app")
            XCTAssertTrue(model.capabilities.supportsStreaming, "\(model.id) must support streaming")
        }
    }

    func testNoQwenProviderModels() {
        // Qwen survives only as an OpenRouter passthrough route.
        let qwenIDs = registry.getAllModels().filter { $0.id.lowercased().contains("qwen") }
        XCTAssertEqual(qwenIDs.map(\.id), ["qwen/qwen3-coder"])
        XCTAssertEqual(qwenIDs.first?.provider, .openRouter)
    }

    // MARK: - Fresh boot (P2 gate)

    @MainActor
    func testFreshServiceLandsOnAnthropicWithoutKeys() {
        // A service constructed with no persisted selection (and no API keys)
        // must land on an Anthropic model without crashing.
        let service = MultiProviderAIService()
        XCTAssertNotNil(service.currentModel)
        XCTAssertEqual(service.currentModel?.provider, service.currentProvider)
        XCTAssertFalse(service.availableModels.isEmpty)
    }
}
