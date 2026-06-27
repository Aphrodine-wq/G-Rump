import XCTest
@testable import GRump

final class ProjectConfigTests: XCTestCase {

    // MARK: - Decoding

    func testDecodeMinimalConfig() throws {
        let json = """
        {"model": "claude-sonnet-4-20250514"}
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(ProjectConfig.self, from: json)
        XCTAssertEqual(config.model, "claude-sonnet-4-20250514")
        XCTAssertNil(config.systemPrompt)
        XCTAssertNil(config.toolAllowlist)
        XCTAssertNil(config.projectFacts)
        XCTAssertNil(config.maxAgentSteps)
        XCTAssertNil(config.contextFile)
    }

    func testDecodeFullConfig() throws {
        let json = """
        {
            "model": "gpt-4o",
            "systemPrompt": "You are a test assistant.",
            "toolAllowlist": ["read_file", "write_file"],
            "projectFacts": ["Uses Swift", "macOS only"],
            "maxAgentSteps": 50,
            "contextFile": ".grump/context.md"
        }
        """.data(using: .utf8)!
        let config = try JSONDecoder().decode(ProjectConfig.self, from: json)
        XCTAssertEqual(config.model, "gpt-4o")
        XCTAssertEqual(config.systemPrompt, "You are a test assistant.")
        XCTAssertEqual(config.toolAllowlist, ["read_file", "write_file"])
        XCTAssertEqual(config.projectFacts, ["Uses Swift", "macOS only"])
        XCTAssertEqual(config.maxAgentSteps, 50)
        XCTAssertEqual(config.contextFile, ".grump/context.md")
    }

    func testDecodeEmptyObject() throws {
        let json = "{}".data(using: .utf8)!
        let config = try JSONDecoder().decode(ProjectConfig.self, from: json)
        XCTAssertNil(config.model)
        XCTAssertNil(config.systemPrompt)
    }

    // MARK: - Equatable

    func testEquatable() throws {
        let a = ProjectConfig(model: "gpt-4o", systemPrompt: "test")
        let b = ProjectConfig(model: "gpt-4o", systemPrompt: "test")
        let c = ProjectConfig(model: "claude-sonnet-4-20250514", systemPrompt: "test")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Merge

    func testMergeOverridesModel() {
        let config = ProjectConfig(model: AIModel.qwenCoderPlus.rawValue)
        let result = config.merged(
            currentModel: .qwenPlus,
            currentPrompt: "default prompt",
            currentMaxSteps: 25
        )
        XCTAssertEqual(result.model, .qwenCoderPlus)
        XCTAssertEqual(result.prompt, "default prompt")
        XCTAssertEqual(result.maxSteps, 25)
        XCTAssertNil(result.tools)
    }

    func testMergeOverridesPrompt() {
        let config = ProjectConfig(systemPrompt: "custom prompt")
        let result = config.merged(
            currentModel: .qwenPlus,
            currentPrompt: "default prompt",
            currentMaxSteps: 25
        )
        XCTAssertEqual(result.prompt, "custom prompt")
    }

    func testMergeKeepsDefaultsWhenNil() {
        let config = ProjectConfig()
        let result = config.merged(
            currentModel: .qwenPlus,
            currentPrompt: "keep this",
            currentMaxSteps: 42
        )
        XCTAssertEqual(result.model, .qwenPlus)
        XCTAssertEqual(result.prompt, "keep this")
        XCTAssertEqual(result.maxSteps, 42)
    }

    func testMergeOverridesMaxSteps() {
        let config = ProjectConfig(maxAgentSteps: 100)
        let result = config.merged(
            currentModel: .qwenPlus,
            currentPrompt: "p",
            currentMaxSteps: 25
        )
        XCTAssertEqual(result.maxSteps, 100)
    }

    func testMergeToolAllowlist() {
        let config = ProjectConfig(toolAllowlist: ["read_file"])
        let result = config.merged(
            currentModel: .qwenPlus,
            currentPrompt: "p",
            currentMaxSteps: 25
        )
        XCTAssertEqual(result.tools, ["read_file"])
    }

    // MARK: - AppendFacts

    func testAppendFactsAddsBlock() {
        let config = ProjectConfig(projectFacts: ["Fact 1", "Fact 2"])
        var prompt = "Base prompt"
        config.appendFacts(to: &prompt)
        XCTAssertTrue(prompt.contains("## Project Facts"))
        XCTAssertTrue(prompt.contains("Fact 1"))
        XCTAssertTrue(prompt.contains("Fact 2"))
    }

    func testAppendFactsNoOpWhenEmpty() {
        let config = ProjectConfig(projectFacts: [])
        var prompt = "Base prompt"
        config.appendFacts(to: &prompt)
        XCTAssertEqual(prompt, "Base prompt")
    }

    func testAppendFactsNoOpWhenNil() {
        let config = ProjectConfig()
        var prompt = "Base prompt"
        config.appendFacts(to: &prompt)
        XCTAssertEqual(prompt, "Base prompt")
    }

    // MARK: - Load from directory

    func testLoadReturnsNilForEmptyDirectory() {
        XCTAssertNil(ProjectConfig.load(from: ""))
    }

    func testLoadReturnsNilForNonexistentDirectory() {
        XCTAssertNil(ProjectConfig.load(from: "/nonexistent/path/that/does/not/exist"))
    }

    // MARK: - Roundtrip encoding

    func testEncodeDecode() throws {
        let config = ProjectConfig(
            model: "gpt-4o",
            systemPrompt: "test",
            toolAllowlist: ["a", "b"],
            projectFacts: ["f1"],
            maxAgentSteps: 30,
            contextFile: "ctx.md"
        )
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: data)
        XCTAssertEqual(config, decoded)
    }
}
