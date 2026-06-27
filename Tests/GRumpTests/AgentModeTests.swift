import XCTest
@testable import GRump

@MainActor
final class AgentModeTests: XCTestCase {

    func testAllModesHaveDisplayNames() {
        for mode in AgentMode.allCases {
            XCTAssertFalse(mode.displayName.isEmpty, "\(mode.rawValue) missing displayName")
        }
    }

    func testAllModesHaveIcons() {
        for mode in AgentMode.allCases {
            XCTAssertFalse(mode.icon.isEmpty, "\(mode.rawValue) missing icon")
        }
    }

    func testAllModesHaveDescriptions() {
        for mode in AgentMode.allCases {
            XCTAssertFalse(mode.description.isEmpty, "\(mode.rawValue) missing description")
        }
    }

    func testAllModesHaveToastMessages() {
        for mode in AgentMode.allCases {
            XCTAssertFalse(mode.toastMessage.isEmpty, "\(mode.rawValue) missing toastMessage")
        }
    }

    func testModeCodableRoundTrip() throws {
        for mode in AgentMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(AgentMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testModeCount() {
        // Ensure we don't accidentally drop a mode
        XCTAssertEqual(AgentMode.allCases.count, 3, "Expected 3 modes: Plan, Build, Spec")
    }

    func testModeRawValues() {
        XCTAssertEqual(AgentMode.plan.rawValue, "plan")
        XCTAssertEqual(AgentMode.fullStack.rawValue, "fullStack")
        XCTAssertEqual(AgentMode.spec.rawValue, "spec")
    }

    // MARK: - Expanded Tests

    func testIdentifiable() {
        for mode in AgentMode.allCases {
            XCTAssertEqual(mode.id, mode.rawValue)
        }
    }

    func testUniqueIds() {
        let ids = AgentMode.allCases.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All AgentMode IDs should be unique")
    }

    func testUniqueDisplayNames() {
        let names = AgentMode.allCases.map(\.displayName)
        XCTAssertEqual(names.count, Set(names).count, "All display names should be unique")
    }

    func testUniqueIcons() {
        let icons = AgentMode.allCases.map(\.icon)
        XCTAssertEqual(icons.count, Set(icons).count, "All icons should be unique")
    }

    func testDisplayNamesAreHumanReadable() {
        for mode in AgentMode.allCases {
            let name = mode.displayName
            XCTAssertTrue(name.first?.isUppercase ?? false,
                "\(mode.rawValue) displayName '\(name)' should be capitalized")
            XCTAssertLessThanOrEqual(name.count, 20,
                "\(mode.rawValue) displayName should be short")
        }
    }

    func testDescriptionsAreSentences() {
        for mode in AgentMode.allCases {
            let desc = mode.description
            XCTAssertTrue(desc.first?.isUppercase ?? false,
                "\(mode.rawValue) description should start capitalized")
            XCTAssertTrue(desc.hasSuffix("."),
                "\(mode.rawValue) description should end with period")
        }
    }

    func testToastMessagesContainModeName() {
        for mode in AgentMode.allCases {
            XCTAssertTrue(mode.toastMessage.contains(mode.displayName),
                "\(mode.rawValue) toast should contain display name")
        }
    }

    func testSpecificDisplayNames() {
        XCTAssertEqual(AgentMode.plan.displayName, "Plan")
        XCTAssertEqual(AgentMode.fullStack.displayName, "Build")
        XCTAssertEqual(AgentMode.spec.displayName, "Spec")
    }

    func testModeFromRawValue() {
        for mode in AgentMode.allCases {
            let recreated = AgentMode(rawValue: mode.rawValue)
            XCTAssertEqual(recreated, mode)
        }
    }

    func testInvalidRawValueReturnsNil() {
        XCTAssertNil(AgentMode(rawValue: "nonexistent"))
        XCTAssertNil(AgentMode(rawValue: ""))
    }

    // MARK: - Accent Colors

    func testUniqueModeAccentColors() {
        var seen: Set<String> = []
        for mode in AgentMode.allCases {
            let colorDesc = "\(mode.modeAccentColor)"
            XCTAssertFalse(seen.contains(colorDesc),
                "\(mode.rawValue) accent color duplicates another mode")
            seen.insert(colorDesc)
        }
    }

    // MARK: - Description Constraints

    func testDescriptionMinimumLength() {
        for mode in AgentMode.allCases {
            XCTAssertGreaterThanOrEqual(mode.description.count, 20,
                "\(mode.rawValue) description should be at least 20 chars, got \(mode.description.count)")
        }
    }

    // MARK: - Toast Message Format

    func testToastMessagesStartWithSwitchedTo() {
        for mode in AgentMode.allCases {
            XCTAssertTrue(mode.toastMessage.hasPrefix("Switched to"),
                "\(mode.rawValue) toast '\(mode.toastMessage)' should start with 'Switched to'")
        }
    }

    // MARK: - Icon SF Symbol Format

    func testIconsAreSFSymbolFormat() {
        for mode in AgentMode.allCases {
            let icon = mode.icon
            // SF Symbols use dot-separated segments, no spaces
            XCTAssertFalse(icon.contains(" "),
                "\(mode.rawValue) icon '\(icon)' should not contain spaces")
            XCTAssertFalse(icon.isEmpty)
        }
    }
}
