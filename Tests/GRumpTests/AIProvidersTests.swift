import XCTest
@testable import GRump

final class AIProvidersTests: XCTestCase {

    // MARK: - AIProvider Enum

    func testAllCasesCount() {
        XCTAssertEqual(AIProvider.allCases, [.qwen])
    }

    func testRawValues() {
        XCTAssertEqual(AIProvider.qwen.rawValue, "qwen")
    }

    func testDisplayNameIsQwen() {
        XCTAssertEqual(AIProvider.qwen.displayName, "Qwen")
    }

    func testDisplayNames() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.displayName.isEmpty, "\(provider.rawValue) missing displayName")
        }
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

    func testRequiresAPIKey() {
        XCTAssertTrue(AIProvider.qwen.requiresAPIKey)
    }

    func testDefaultBaseURLs() {
        XCTAssertEqual(AIProvider.qwen.defaultBaseURL,
                       "https://dashscope-intl.aliyuncs.com/compatible-mode/v1")
        XCTAssertTrue(AIProvider.qwen.defaultBaseURL.contains("dashscope"))
    }

    func testQwenRequiresKeyAndHasBaseURL() {
        XCTAssertTrue(AIProvider.qwen.requiresAPIKey, "Qwen should require API key")
        XCTAssertFalse(AIProvider.qwen.defaultBaseURL.isEmpty, "Qwen should have a base URL")
    }

    func testCodableRoundtrip() throws {
        for provider in AIProvider.allCases {
            let data = try JSONEncoder().encode(provider)
            let decoded = try JSONDecoder().decode(AIProvider.self, from: data)
            XCTAssertEqual(decoded, provider)
        }
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

    func testModelPricingCodable() throws {
        let pricing = ModelPricing(inputPricePer1K: 0.002, outputPricePer1K: 0.008, currency: "USD")
        let data = try JSONEncoder().encode(pricing)
        let decoded = try JSONDecoder().decode(ModelPricing.self, from: data)
        XCTAssertEqual(decoded, pricing)
    }

    // MARK: - EnhancedAIModel

    func testEnhancedModelEquality() {
        let a = EnhancedAIModel(
            id: "test-1", provider: .qwen, modelID: "qwen-coder-plus", displayName: "Qwen Coder Plus",
            description: "Test", contextWindow: 128_000, maxOutput: 16_384,
            requiresPaidTier: false, capabilities: .default, pricing: nil
        )
        let b = EnhancedAIModel(
            id: "test-1", provider: .qwen, modelID: "different", displayName: "Different",
            description: "Different", contextWindow: 0, maxOutput: 0,
            requiresPaidTier: true, capabilities: .default, pricing: nil
        )
        XCTAssertEqual(a, b, "Equality should be based on id only")
    }

    func testEnhancedModelNotEqual() {
        let a = EnhancedAIModel(
            id: "test-1", provider: .qwen, modelID: "qwen-coder-plus", displayName: "Qwen Coder Plus",
            description: "Test", contextWindow: 128_000, maxOutput: 16_384,
            requiresPaidTier: false, capabilities: .default, pricing: nil
        )
        let b = EnhancedAIModel(
            id: "test-2", provider: .qwen, modelID: "qwen-coder-plus", displayName: "Qwen Coder Plus",
            description: "Test", contextWindow: 128_000, maxOutput: 16_384,
            requiresPaidTier: false, capabilities: .default, pricing: nil
        )
        XCTAssertNotEqual(a, b)
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

    func testEnhancedModelCodable() throws {
        let model = EnhancedAIModel(
            id: "test-codable", provider: .qwen, modelID: "qwen-plus",
            displayName: "Qwen Plus", description: "Fast",
            contextWindow: 200_000, maxOutput: 8_192,
            requiresPaidTier: false, capabilities: .default,
            pricing: ModelPricing(inputPricePer1K: 0.003, outputPricePer1K: 0.015, currency: "USD")
        )
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(EnhancedAIModel.self, from: data)
        XCTAssertEqual(decoded.id, model.id)
        XCTAssertEqual(decoded.provider, model.provider)
        XCTAssertEqual(decoded.modelID, model.modelID)
        XCTAssertEqual(decoded.contextWindow, model.contextWindow)
    }

    // MARK: - ProviderConfiguration

    func testProviderConfigDefaults() {
        let config = ProviderConfiguration(provider: .qwen)
        XCTAssertEqual(config.provider, .qwen)
        XCTAssertNil(config.apiKey)
        XCTAssertEqual(config.baseURL, AIProvider.qwen.defaultBaseURL)
        XCTAssertTrue(config.isEnabled)
        XCTAssertTrue(config.customHeaders.isEmpty)
    }

    func testProviderConfigCustomURL() {
        let config = ProviderConfiguration(provider: .qwen, baseURL: "http://myserver:11434/v1")
        XCTAssertEqual(config.baseURL, "http://myserver:11434/v1")
    }

    func testProviderConfigCodable() throws {
        let config = ProviderConfiguration(provider: .qwen, apiKey: "sk-test-key")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProviderConfiguration.self, from: data)
        XCTAssertEqual(decoded.provider, .qwen)
        XCTAssertEqual(decoded.apiKey, "sk-test-key")
    }

    // MARK: - AIModelRegistry

    func testRegistrySharedExists() {
        let registry = AIModelRegistry.shared
        XCTAssertNotNil(registry)
    }

    func testRegistryHasModels() {
        let models = AIModelRegistry.shared.getAllModels()
        XCTAssertFalse(models.isEmpty, "Registry should have default models loaded")
    }

    func testRegistryModelsAreSorted() {
        let models = AIModelRegistry.shared.getAllModels()
        for i in 1..<models.count {
            XCTAssertLessThanOrEqual(models[i-1].displayName, models[i].displayName,
                "Models should be sorted by displayName")
        }
    }

    func testRegistryModelsByProvider() {
        for provider in AIProvider.allCases {
            let models = AIModelRegistry.shared.getModels(for: provider)
            for model in models {
                XCTAssertEqual(model.provider, provider,
                    "Model \(model.id) should belong to \(provider.displayName)")
            }
        }
    }

    func testRegistryGetModelById() {
        let allModels = AIModelRegistry.shared.getAllModels()
        guard let first = allModels.first else { return }
        let found = AIModelRegistry.shared.getModel(by: first.id)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.id, first.id)
    }

    func testRegistryGetNonexistentModel() {
        let found = AIModelRegistry.shared.getModel(by: "nonexistent-model-xyz-999")
        XCTAssertNil(found)
    }

    func testRegistryOnlyHasQwenModels() {
        let models = AIModelRegistry.shared.getAllModels()
        XCTAssertFalse(models.isEmpty)
        for model in models {
            XCTAssertEqual(model.provider, .qwen, "Registry should only contain Qwen models")
            XCTAssertTrue(model.capabilities.supportsTools, "Qwen model \(model.id) should support tools")
        }
    }

    func testRegistryModelIDsUnique() {
        let models = AIModelRegistry.shared.getAllModels()
        let ids = models.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All model IDs should be unique")
    }

    func testRegistryAllModelsHaveValidFields() {
        for model in AIModelRegistry.shared.getAllModels() {
            XCTAssertFalse(model.id.isEmpty, "Model ID should not be empty")
            XCTAssertFalse(model.displayName.isEmpty, "Model \(model.id) displayName empty")
            XCTAssertFalse(model.description.isEmpty, "Model \(model.id) description empty")
            XCTAssertGreaterThan(model.contextWindow, 0, "Model \(model.id) contextWindow should be > 0")
            XCTAssertGreaterThan(model.maxOutput, 0, "Model \(model.id) maxOutput should be > 0")
        }
    }
}
