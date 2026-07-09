import XCTest
@testable import GRump

final class WorkflowPresetTests: XCTestCase {

    // MARK: - Init

    func testDefaultInit() {
        let preset = WorkflowPreset(
            name: "Test",
            modelRawValue: "gpt-4o",
            systemPrompt: "Do things"
        )
        XCTAssertEqual(preset.name, "Test")
        XCTAssertEqual(preset.modelRawValue, "gpt-4o")
        XCTAssertEqual(preset.systemPrompt, "Do things")
        XCTAssertNil(preset.toolAllowlist)
        XCTAssertNil(preset.maxAgentSteps)
    }

    func testInitWithAllFields() {
        let id = UUID()
        let preset = WorkflowPreset(
            id: id,
            name: "Full",
            modelRawValue: "claude-opus-4-8",
            systemPrompt: "prompt",
            toolAllowlist: ["read_file", "write_file"],
            maxAgentSteps: 100
        )
        XCTAssertEqual(preset.id, id)
        XCTAssertEqual(preset.name, "Full")
        XCTAssertEqual(preset.toolAllowlist, ["read_file", "write_file"])
        XCTAssertEqual(preset.maxAgentSteps, 100)
    }

    // MARK: - Model resolution

    func testModelResolvesValidRawValue() {
        let preset = WorkflowPreset(
            name: "Test",
            modelRawValue: "claude-opus-4-8",
            systemPrompt: "p"
        )
        XCTAssertEqual(preset.model?.id, "claude-opus-4-8")
    }

    func testModelReturnsNilForInvalidRawValue() {
        let preset = WorkflowPreset(
            name: "Test",
            modelRawValue: "nonexistent-model-xyz",
            systemPrompt: "p"
        )
        XCTAssertNil(preset.model)
    }

    // MARK: - Equatable

    func testEquatable() {
        let id = UUID()
        let a = WorkflowPreset(id: id, name: "A", modelRawValue: "m", systemPrompt: "p")
        let b = WorkflowPreset(id: id, name: "A", modelRawValue: "m", systemPrompt: "p")
        XCTAssertEqual(a, b)
    }

    func testNotEqualDifferentName() {
        let id = UUID()
        let a = WorkflowPreset(id: id, name: "A", modelRawValue: "m", systemPrompt: "p")
        let b = WorkflowPreset(id: id, name: "B", modelRawValue: "m", systemPrompt: "p")
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Codable roundtrip

    func testCodableRoundtrip() throws {
        let preset = WorkflowPreset(
            name: "Roundtrip",
            modelRawValue: "gpt-4o",
            systemPrompt: "test prompt",
            toolAllowlist: ["grep_search"],
            maxAgentSteps: 75
        )
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(WorkflowPreset.self, from: data)
        XCTAssertEqual(preset, decoded)
    }

    func testCodableRoundtripNilOptionals() throws {
        let preset = WorkflowPreset(
            name: "Minimal",
            modelRawValue: "gpt-4o",
            systemPrompt: "p"
        )
        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(WorkflowPreset.self, from: data)
        XCTAssertEqual(preset, decoded)
        XCTAssertNil(decoded.toolAllowlist)
        XCTAssertNil(decoded.maxAgentSteps)
    }

    // MARK: - Default presets

    func testDefaultPresetsExist() {
        let defaults = WorkflowPresetsStorage.defaultPresets
        XCTAssertFalse(defaults.isEmpty, "Should have default presets")
        XCTAssertTrue(defaults.count >= 3, "Should have at least 3 default presets")
    }

    func testDefaultPresetsHaveValidModels() {
        for preset in WorkflowPresetsStorage.defaultPresets {
            XCTAssertNotNil(preset.model, "Default preset '\(preset.name)' should have a valid model")
        }
    }

    func testDefaultPresetsHaveNames() {
        for preset in WorkflowPresetsStorage.defaultPresets {
            XCTAssertFalse(preset.name.isEmpty, "Default preset must have a name")
            XCTAssertFalse(preset.systemPrompt.isEmpty, "Default preset '\(preset.name)' must have a prompt")
        }
    }

    func testReadOnlyPresetHasToolAllowlist() {
        let readOnly = WorkflowPresetsStorage.defaultPresets.first { $0.name.contains("Read-only") }
        XCTAssertNotNil(readOnly, "Should have a read-only preset")
        if let readOnly = readOnly {
            XCTAssertNotNil(readOnly.toolAllowlist, "Read-only preset should have tool allowlist")
            XCTAssertTrue(readOnly.toolAllowlist?.contains("read_file") == true)
        }
    }

    func testExtendedRunPresetHasMaxSteps() {
        let extended = WorkflowPresetsStorage.defaultPresets.first { $0.name.contains("Extended") }
        XCTAssertNotNil(extended, "Should have an extended run preset")
        if let extended = extended {
            XCTAssertNotNil(extended.maxAgentSteps)
            XCTAssertTrue((extended.maxAgentSteps ?? 0) > 25, "Extended run should have high max steps")
        }
    }

    // MARK: - Identifiable

    func testIdentifiable() {
        let a = WorkflowPreset(name: "A", modelRawValue: "m", systemPrompt: "p")
        let b = WorkflowPreset(name: "B", modelRawValue: "m", systemPrompt: "p")
        XCTAssertNotEqual(a.id, b.id, "Different presets should have different IDs")
    }
}
