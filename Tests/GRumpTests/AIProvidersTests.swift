import XCTest
@testable import GRump

final class AIProvidersTests: XCTestCase {

    // MARK: - AIProvider Enum

    func testAllCases() {
        XCTAssertEqual(AIProvider.allCases, [.anthropic, .openAI, .google, .openRouter, .ollama],
                       "Anthropic leads; order drives UI sections")
    }

    func testRawValues() {
        XCTAssertEqual(AIProvider.anthropic.rawValue, "anthropic")
        XCTAssertEqual(AIProvider.openAI.rawValue, "openai")
        XCTAssertEqual(AIProvider.google.rawValue, "google")
        XCTAssertEqual(AIProvider.openRouter.rawValue, "openrouter")
        XCTAssertEqual(AIProvider.ollama.rawValue, "ollama")
    }

    func testDisplayNames() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.displayName.isEmpty, "\(provider.rawValue) missing displayName")
        }
        XCTAssertEqual(AIProvider.anthropic.displayName, "Anthropic")
    }

    func testDescriptions() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.description.isEmpty, "\(provider.rawValue) missing description")
        }
    }

    func testIdentifiable() {
        for provider in AIProvider.allCases {
            XCTAssertEqual(provider.id, provider.rawValue)
        }
    }

    func testCloudProvidersRequireAPIKeyAndOllamaDoesNot() {
        for provider in AIProvider.allCases where !provider.isLocal {
            XCTAssertTrue(provider.requiresAPIKey, "\(provider.rawValue) should require an API key")
        }
        XCTAssertFalse(AIProvider.ollama.requiresAPIKey, "Ollama is keyless")
    }

    func testOnlyOllamaIsLocal() {
        for provider in AIProvider.allCases {
            XCTAssertEqual(provider.isLocal, provider == .ollama,
                           "\(provider.rawValue) local flag wrong")
        }
    }

    func testDefaultBaseURLs() {
        XCTAssertEqual(AIProvider.anthropic.defaultBaseURL, "https://api.anthropic.com/v1")
        XCTAssertEqual(AIProvider.openAI.defaultBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(AIProvider.google.defaultBaseURL, "https://generativelanguage.googleapis.com/v1beta")
        XCTAssertEqual(AIProvider.openRouter.defaultBaseURL, "https://openrouter.ai/api/v1")
        XCTAssertEqual(AIProvider.ollama.defaultBaseURL, "http://localhost:11434/v1")
    }

    func testKeychainAccountMapping() {
        XCTAssertEqual(AIProvider.anthropic.keychainAccount, "AnthropicAPIKey")
        XCTAssertEqual(AIProvider.openAI.keychainAccount, "OpenAIAPIKey")
        XCTAssertEqual(AIProvider.google.keychainAccount, "GoogleAPIKey")
        XCTAssertEqual(AIProvider.openRouter.keychainAccount, "OpenRouterAPIKey")
    }

    func testKeychainAccountsUnique() {
        let accounts = AIProvider.allCases.map(\.keychainAccount)
        XCTAssertEqual(accounts.count, Set(accounts).count)
    }

    func testIconAndPlaceholderPresent() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.iconName.isEmpty, "\(provider.rawValue) missing icon")
            XCTAssertFalse(provider.keyPlaceholder.isEmpty, "\(provider.rawValue) missing key placeholder")
        }
    }

    func testCodableRoundtrip() throws {
        for provider in AIProvider.allCases {
            let data = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(AIProvider.self, from: data)
            XCTAssertEqual(decoded, provider)
        }
    }

    func testQwenNoLongerDecodes() {
        let data = Data("\"qwen\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(AIProvider.self, from: data),
                             "The qwen provider is gone; stale persisted values must fail typed decoding")
    }

    // MARK: - ModelCapabilities

    func testDefaultCapabilities() {
        let caps = ModelCapabilities.default
        XCTAssertTrue(caps.supportsTools)
        XCTAssertFalse(caps.supportsVision)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertTrue(caps.supportsFunctionCalling)
        XCTAssertFalse(caps.supportsJSONMode)
        XCTAssertNil(caps.maxTokens)
        XCTAssertTrue(caps.supportsSystemMessages)
        XCTAssertFalse(caps.supportsParallelToolUse)
    }

    func testCapabilitiesCodable() throws {
        let caps = ModelCapabilities(
            supportsTools: true, supportsVision: true, supportsStreaming: false,
            supportsFunctionCalling: true, supportsJSONMode: true,
            maxTokens: 100_000, supportsSystemMessages: true, supportsParallelToolUse: true
        )
        let data = try JSONEncoder().encode(caps)
        let decoded = try JSONDecoder().decode(ModelCapabilities.self, from: data)
        XCTAssertEqual(decoded, caps)
    }

    // MARK: - ModelPricing

    func testModelPricingFormatted() {
        let pricing = ModelPricing(inputPricePer1K: 0.015, outputPricePer1K: 0.075, currency: "USD")
        XCTAssertTrue(pricing.formattedInputPrice.contains("0.0150"))
        XCTAssertTrue(pricing.formattedOutputPrice.contains("0.0750"))
        XCTAssertTrue(pricing.formattedInputPrice.contains("USD"))
    }

    // MARK: - EnhancedAIModel

    func testEnhancedModelEquality() {
        let a = EnhancedAIModel(
            id: "test-1", provider: .anthropic, modelID: "claude-opus-4-8", displayName: "Claude Opus 4.8",
            description: "Test", contextWindow: 1_000_000, maxOutput: 128_000,
            requiresPaidTier: false, capabilities: .default, pricing: nil
        )
        let b = EnhancedAIModel(
            id: "test-1", provider: .openAI, modelID: "different", displayName: "Different",
            description: "Different", contextWindow: 0, maxOutput: 0,
            requiresPaidTier: true, capabilities: .default, pricing: nil
        )
        XCTAssertEqual(a, b, "Equality should be based on id only")
    }

    func testEnhancedModelRawValue() {
        for provider in AIProvider.allCases {
            let model = EnhancedAIModel(
                id: "test", provider: provider, modelID: "the-model-id", displayName: "Test",
                description: "d", contextWindow: 1000, maxOutput: 100,
                requiresPaidTier: false, capabilities: .default, pricing: nil
            )
            XCTAssertEqual(model.rawValue, "the-model-id")
        }
    }

    // MARK: - ProviderConfiguration

    func testProviderConfigDefaults() {
        let config = ProviderConfiguration(provider: .anthropic)
        XCTAssertEqual(config.provider, .anthropic)
        XCTAssertNil(config.apiKey)
        XCTAssertEqual(config.baseURL, AIProvider.anthropic.defaultBaseURL)
        XCTAssertTrue(config.isEnabled)
        XCTAssertTrue(config.customHeaders.isEmpty)
    }

    func testProviderConfigCustomURL() {
        let config = ProviderConfiguration(provider: .openRouter, baseURL: "http://myserver:8080/v1")
        XCTAssertEqual(config.baseURL, "http://myserver:8080/v1")
    }

    func testAPIKeyIsNeverPersisted() throws {
        // The old build wrote keys into UserDefaults via this struct's Codable
        // conformance. The key must not survive an encode/decode round trip,
        // and must not appear anywhere in the encoded bytes.
        let config = ProviderConfiguration(provider: .anthropic, apiKey: "sk-ant-secret-123")
        let data = try JSONEncoder().encode(config)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("sk-ant-secret-123"), "API key leaked into encoded config")
        XCTAssertFalse(json.contains("apiKey"), "apiKey field should not be encoded at all")

        let decoded = try JSONDecoder().decode(ProviderConfiguration.self, from: data)
        XCTAssertNil(decoded.apiKey)
        XCTAssertEqual(decoded.provider, .anthropic)
        XCTAssertEqual(decoded.baseURL, AIProvider.anthropic.defaultBaseURL)
    }

    // MARK: - AIModelRegistry

    func testRegistrySharedExists() {
        XCTAssertNotNil(AIModelRegistry.shared)
    }

    func testRegistryHasModels() {
        XCTAssertFalse(AIModelRegistry.shared.getAllModels().isEmpty)
    }

    func testRegistryModelsAreSorted() {
        let models = AIModelRegistry.shared.getAllModels()
        for i in 1..<models.count {
            XCTAssertLessThanOrEqual(models[i-1].displayName, models[i].displayName)
        }
    }

    func testRegistryModelsByProvider() {
        for provider in AIProvider.allCases {
            for model in AIModelRegistry.shared.getModels(for: provider) {
                XCTAssertEqual(model.provider, provider)
            }
        }
    }

    func testRegistryGetNonexistentModel() {
        XCTAssertNil(AIModelRegistry.shared.getModel(by: "nonexistent-model-xyz-999"))
    }

    func testRegistryModelIDsUnique() {
        let ids = AIModelRegistry.shared.getAllModels().map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
