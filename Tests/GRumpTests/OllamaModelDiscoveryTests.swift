import XCTest
@testable import GRump

/// Pure-logic tests for the Ollama discovery pieces — no live server needed.
final class OllamaModelDiscoveryTests: XCTestCase {

    // MARK: - Native API root derivation

    func testNativeRootStripsV1Suffix() {
        XCTAssertEqual(OllamaModelDiscovery.nativeAPIRoot(from: "http://localhost:11434/v1"),
                       "http://localhost:11434")
        XCTAssertEqual(OllamaModelDiscovery.nativeAPIRoot(from: "http://localhost:11434/v1/"),
                       "http://localhost:11434")
    }

    func testNativeRootDefaultsWhenNilOrEmpty() {
        XCTAssertEqual(OllamaModelDiscovery.nativeAPIRoot(from: nil), "http://localhost:11434")
        XCTAssertEqual(OllamaModelDiscovery.nativeAPIRoot(from: ""), "http://localhost:11434")
    }

    func testNativeRootKeepsCustomHost() {
        XCTAssertEqual(OllamaModelDiscovery.nativeAPIRoot(from: "http://192.168.12.60:11434/v1"),
                       "http://192.168.12.60:11434")
    }

    // MARK: - /api/show parsing

    func testParseShowResponseReadsCapabilitiesAndContext() {
        let json: [String: Any] = [
            "capabilities": ["completion", "tools", "vision"],
            "model_info": ["llama.context_length": 131_072]
        ]
        let info = OllamaModelDiscovery.parseShowResponse(json)
        XCTAssertTrue(info.supportsTools)
        XCTAssertTrue(info.supportsVision)
        XCTAssertEqual(info.contextWindow, 131_072)
    }

    func testParseShowResponseDefaultsAreConservative() {
        let info = OllamaModelDiscovery.parseShowResponse([:])
        XCTAssertFalse(info.supportsTools, "unknown capability must default to no tools")
        XCTAssertFalse(info.supportsVision)
        XCTAssertEqual(info.contextWindow, 8_192)
    }

    func testParseShowResponseIgnoresZeroContextLength() {
        let json: [String: Any] = ["model_info": ["qwen2.context_length": 0]]
        XCTAssertEqual(OllamaModelDiscovery.parseShowResponse(json).contextWindow, 8_192)
    }

    // MARK: - Model construction

    func testMakeModelShape() {
        var info = OllamaModelDiscovery.ModelInfo()
        info.supportsTools = true
        info.contextWindow = 32_768
        let model = OllamaModelDiscovery.makeModel(name: "llama3.2:3b", info: info)

        XCTAssertEqual(model.id, "llama3.2:3b")
        XCTAssertEqual(model.modelID, "llama3.2:3b", "modelID must be the exact Ollama tag")
        XCTAssertEqual(model.provider, .ollama)
        XCTAssertEqual(model.contextWindow, 32_768)
        XCTAssertEqual(model.maxOutput, 8_192, "output cap clamps to 8K")
        XCTAssertTrue(model.capabilities.supportsTools)
        XCTAssertNil(model.pricing, "local models are free")
        XCTAssertFalse(model.requiresPaidTier)
    }

    func testMakeModelOutputFloorForTinyContext() {
        var info = OllamaModelDiscovery.ModelInfo()
        info.contextWindow = 1_024
        let model = OllamaModelDiscovery.makeModel(name: "tiny", info: info)
        XCTAssertEqual(model.maxOutput, 1_024, "floor keeps small models usable")
    }

    // MARK: - Registry merge

    func testReplaceModelsSwapsOnlyOllamaEntries() {
        let registry = AIModelRegistry.shared
        let cloudCountBefore = registry.getAllModels().filter { $0.provider != .ollama }.count

        let discovered = [OllamaModelDiscovery.makeModel(name: "test-model:latest",
                                                         info: OllamaModelDiscovery.ModelInfo())]
        registry.replaceModels(for: .ollama, with: discovered)
        XCTAssertEqual(registry.getModels(for: .ollama).map(\.id), ["test-model:latest"])
        XCTAssertEqual(registry.getAllModels().filter { $0.provider != .ollama }.count,
                       cloudCountBefore, "cloud entries must be untouched")

        registry.replaceModels(for: .ollama, with: [])
        XCTAssertTrue(registry.getModels(for: .ollama).isEmpty)
    }

    func testReplaceModelsDropsForeignProviders() {
        let registry = AIModelRegistry.shared
        let foreign = EnhancedAIModel(
            id: "sneaky", provider: .openAI, modelID: "sneaky", displayName: "Sneaky",
            description: "d", contextWindow: 1, maxOutput: 1,
            requiresPaidTier: false, capabilities: .default, pricing: nil
        )
        registry.replaceModels(for: .ollama, with: [foreign])
        XCTAssertNil(registry.getModel(by: "sneaky"),
                     "a model tagged with another provider must not enter via the Ollama merge")
    }
}
