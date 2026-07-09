import XCTest
@testable import GRump

final class ProviderMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    // Unique per test instance: `swift test --parallel` spreads methods across
    // worker processes, and a fixed suite name is a shared cfprefsd domain —
    // sibling tests contaminate each other through it.
    private var suiteName = ""
    private var keychainWrites: [(account: String, value: String)] = []

    override func setUp() {
        super.setUp()
        suiteName = "ProviderMigrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        keychainWrites = []
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func runMigration() {
        ProviderMigration.runIfNeeded(defaults: defaults) { account, value in
            self.keychainWrites.append((account, value))
        }
    }

    private func seedQwenEra() throws {
        defaults.set("qwen", forKey: "CurrentAIProvider")
        defaults.set("qwen-coder-plus", forKey: "CurrentAIModel")
        defaults.set("qwen-turbo", forKey: "SelectedModel")
        defaults.set("https://dashscope-intl.aliyuncs.com/compatible-mode/v1", forKey: "QwenBaseURL")
        let configs: [[String: Any]] = [
            ["provider": "qwen", "apiKey": "sk-qwen-stray", "baseURL": "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", "isEnabled": true, "customHeaders": [:]]
        ]
        let data = try JSONSerialization.data(withJSONObject: configs)
        defaults.set(data, forKey: "AIProviderConfigurations")
    }

    // MARK: - Full Qwen-era fixture

    func testMigratesQwenEraDefaults() throws {
        try seedQwenEra()
        runMigration()

        XCTAssertEqual(defaults.string(forKey: "CurrentAIProvider"), "anthropic")
        XCTAssertEqual(defaults.string(forKey: "CurrentAIModel"), "claude-sonnet-5",
                       "qwen-coder-plus contains 'plus' → Sonnet tier")
        XCTAssertNil(defaults.object(forKey: "QwenBaseURL"))
        XCTAssertNil(defaults.object(forKey: "SelectedModel"))
        XCTAssertNil(defaults.data(forKey: "AIProviderConfigurations"),
                     "Old registry blob must be dropped — it contains 'qwen' entries")
        XCTAssertTrue(defaults.bool(forKey: ProviderMigration.flagKey))
    }

    func testHoistsStrayKeysToKeychain() throws {
        try seedQwenEra()
        runMigration()

        XCTAssertEqual(keychainWrites.count, 1)
        XCTAssertEqual(keychainWrites.first?.account, "QwenAPIKey",
                       "Qwen key lands under the legacy account, left unused")
        XCTAssertEqual(keychainWrites.first?.value, "sk-qwen-stray")
    }

    func testHoistsPreQwenProviderKeys() throws {
        let configs: [[String: Any]] = [
            ["provider": "openai", "apiKey": "sk-openai-old"],
            ["provider": "anthropic", "apiKey": "sk-ant-old"],
            ["provider": "ollama"]  // no key — skipped
        ]
        defaults.set(try JSONSerialization.data(withJSONObject: configs), forKey: "AIProviderConfigurations")
        runMigration()

        XCTAssertEqual(keychainWrites.map(\.account).sorted(), ["AnthropicAPIKey", "OpenAIAPIKey"])
    }

    // MARK: - Idempotence

    func testSecondRunIsNoOp() throws {
        try seedQwenEra()
        runMigration()
        defaults.set("google", forKey: "CurrentAIProvider")
        keychainWrites = []
        runMigration()

        XCTAssertEqual(defaults.string(forKey: "CurrentAIProvider"), "google",
                       "Flag is set — a second run must not touch anything")
        XCTAssertTrue(keychainWrites.isEmpty)
    }

    // MARK: - Fresh install / already-current state

    func testFreshInstallJustSetsFlag() {
        runMigration()
        XCTAssertTrue(defaults.bool(forKey: ProviderMigration.flagKey))
        XCTAssertEqual(defaults.string(forKey: "CurrentAIProvider"), "anthropic")
        XCTAssertNil(defaults.string(forKey: "CurrentAIModel"))
    }

    func testCurrentProviderAndModelPassThrough() {
        defaults.set("openai", forKey: "CurrentAIProvider")
        defaults.set("gpt-5.2", forKey: "CurrentAIModel")
        runMigration()
        XCTAssertEqual(defaults.string(forKey: "CurrentAIProvider"), "openai")
        XCTAssertEqual(defaults.string(forKey: "CurrentAIModel"), "gpt-5.2")
    }

    // MARK: - Model ID mapping rules

    func testModelIDMapping() {
        // Light tiers → Haiku
        XCTAssertEqual(ModelIDMigration.map("qwen-turbo"), "claude-haiku-4-5")
        XCTAssertEqual(ModelIDMigration.map("some-flash-model"), "claude-haiku-4-5")
        XCTAssertEqual(ModelIDMigration.map("o4-mini"), "claude-haiku-4-5")
        // Mid tiers → Sonnet
        XCTAssertEqual(ModelIDMigration.map("qwen-plus"), "claude-sonnet-5")
        XCTAssertEqual(ModelIDMigration.map("qwen-coder-plus"), "claude-sonnet-5")
        // Everything else → Opus
        XCTAssertEqual(ModelIDMigration.map("qwen-max"), "claude-opus-4-8")
        XCTAssertEqual(ModelIDMigration.map("mystery-model"), "claude-opus-4-8")
        // Current ids pass through untouched
        XCTAssertEqual(ModelIDMigration.map("claude-fable-5"), "claude-fable-5")
        XCTAssertEqual(ModelIDMigration.map("claude-haiku-4-5"), "claude-haiku-4-5")
        XCTAssertEqual(ModelIDMigration.map("gpt-5.3-codex"), "gpt-5.3-codex")
        XCTAssertEqual(ModelIDMigration.map("gemini-2.5-flash"), "gemini-2.5-flash")
        XCTAssertEqual(ModelIDMigration.map("qwen/qwen3-coder"), "qwen/qwen3-coder")
    }
}
