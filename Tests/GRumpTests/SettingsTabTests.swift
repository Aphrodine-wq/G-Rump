import XCTest
@testable import GRump

final class SettingsTabTests: XCTestCase {

    func testCategoryLabelsMatchApprovedGrouping() {
        XCTAssertEqual(
            SettingsTab.categories.map(\.label),
            ["Account", "AI", "Project", "Agent", "Appearance", "General", "About"]
        )
    }

    func testEveryTabAppearsInExactlyOneCategory() {
        let grouped = SettingsTab.categories.flatMap(\.tabs)
        XCTAssertEqual(grouped.count, Set(grouped).count, "a tab is listed in two categories")
        XCTAssertEqual(Set(grouped), Set(SettingsTab.allCases), "a tab is missing from the sidebar")
    }

    func testAgentGroupOwnsTheAgentSurfaces() {
        let agent = SettingsTab.categories.first { $0.label == "Agent" }?.tabs ?? []
        XCTAssertEqual(agent, [.skills, .soul, .brain, .memory])
    }

    func testProjectGroupOwnsProjectSurfaces() {
        let project = SettingsTab.categories.first { $0.label == "Project" }?.tabs ?? []
        #if os(macOS)
        XCTAssertEqual(project, [.project, .tools, .mcp, .security])
        #else
        XCTAssertEqual(project, [.project, .tools, .mcp])
        #endif
    }
}
