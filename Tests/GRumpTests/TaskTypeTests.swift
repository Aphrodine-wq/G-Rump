import XCTest
@testable import GRump

/// Tests for TaskType enum properties — displayName, icon, raw values,
/// and CaseIterable conformance.
final class TaskTypeTests: XCTestCase {

    // MARK: - Display Names

    func testAllTaskTypesHaveDisplayNames() {
        for taskType in TaskType.allCases {
            XCTAssertFalse(taskType.displayName.isEmpty,
                "\(taskType.rawValue) has empty displayName")
        }
    }

    func testDisplayNamesAreCapitalized() {
        for taskType in TaskType.allCases {
            let first = taskType.displayName.first!
            XCTAssertTrue(first.isUppercase,
                "\(taskType.rawValue) displayName '\(taskType.displayName)' should start uppercase")
        }
    }

    func testDisplayNamesAreUnique() {
        var seen: Set<String> = []
        for taskType in TaskType.allCases {
            XCTAssertFalse(seen.contains(taskType.displayName),
                "Duplicate displayName: \(taskType.displayName)")
            seen.insert(taskType.displayName)
        }
    }

    // MARK: - Icons

    func testAllTaskTypesHaveIcons() {
        for taskType in TaskType.allCases {
            XCTAssertFalse(taskType.icon.isEmpty,
                "\(taskType.rawValue) has empty icon")
        }
    }

    func testIconsDoNotContainSpaces() {
        for taskType in TaskType.allCases {
            XCTAssertFalse(taskType.icon.contains(" "),
                "\(taskType.rawValue) icon '\(taskType.icon)' should not contain spaces")
        }
    }

    func testIconsAreUnique() {
        var seen: Set<String> = []
        for taskType in TaskType.allCases {
            XCTAssertFalse(seen.contains(taskType.icon),
                "Duplicate icon: \(taskType.icon) for \(taskType.rawValue)")
            seen.insert(taskType.icon)
        }
    }

    // MARK: - Raw Values

    func testAllRawValuesAreLowerSnakeCase() {
        for taskType in TaskType.allCases {
            let raw = taskType.rawValue
            XCTAssertEqual(raw, raw.lowercased(),
                "\(raw) should be lowercase")
            XCTAssertFalse(raw.contains(" "),
                "\(raw) should not contain spaces")
        }
    }

    func testRawValuesAreUnique() {
        let rawValues = TaskType.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count)
    }

    // MARK: - CaseIterable

    func testTaskTypeCount() {
        XCTAssertEqual(TaskType.allCases.count, 13)
    }

    // MARK: - Codable Round-Trip

    func testTaskTypeCodableRoundTrip() throws {
        for taskType in TaskType.allCases {
            let data = try JSONEncoder().encode(taskType)
            let decoded = try JSONDecoder().decode(TaskType.self, from: data)
            XCTAssertEqual(decoded, taskType)
        }
    }

    func testTaskTypeInvalidRawValue() {
        XCTAssertNil(TaskType(rawValue: "nonexistent"))
        XCTAssertNil(TaskType(rawValue: ""))
    }

    // MARK: - Specific Task Types

    func testReasoningTaskType() {
        let t = TaskType.reasoning
        XCTAssertEqual(t.displayName, "Reasoning")
        XCTAssertEqual(t.icon, "brain")
        XCTAssertEqual(t.rawValue, "reasoning")
    }

    func testDebuggingTaskType() {
        let t = TaskType.debugging
        XCTAssertEqual(t.displayName, "Debugging")
        XCTAssertEqual(t.icon, "ant")
        XCTAssertEqual(t.rawValue, "debugging")
    }

    func testCodeGenTaskType() {
        let t = TaskType.codeGen
        XCTAssertEqual(t.displayName, "Code Generation")
        XCTAssertEqual(t.rawValue, "code_gen")
    }
}
