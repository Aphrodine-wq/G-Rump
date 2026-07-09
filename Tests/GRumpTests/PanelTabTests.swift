import XCTest
@testable import GRump

final class PanelTabTests: XCTestCase {

    // MARK: - All Cases

    func testAllCasesCount() {
        XCTAssertEqual(PanelTab.allCases.count, 19)
    }

    func testRawValues() {
        let expected = ["chat", "files", "preview", "simulator", "git", "tests", "build",
                        "assets", "localization", "schema", "profiling", "logs",
                        "spm", "xcode", "docs", "terminal", "appstore", "accessibility", "memory"]
        let actual = PanelTab.allCases.map(\.rawValue)
        XCTAssertEqual(actual, expected)
    }

    // MARK: - Identifiable

    func testIdentifiable() {
        for tab in PanelTab.allCases {
            XCTAssertEqual(tab.id, tab.rawValue)
        }
    }

    func testUniqueIDs() {
        let ids = PanelTab.allCases.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All PanelTab IDs should be unique")
    }

    // MARK: - Icons

    func testAllTabsHaveIcons() {
        for tab in PanelTab.allCases {
            XCTAssertFalse(tab.icon.isEmpty, "\(tab.rawValue) missing icon")
        }
    }

    func testIconsAreUnique() {
        let icons = PanelTab.allCases.map(\.icon)
        XCTAssertEqual(icons.count, Set(icons).count, "All PanelTab icons should be unique")
    }

    func testSpecificIcons() {
        XCTAssertEqual(PanelTab.chat.icon, "bubble.left.and.bubble.right.fill")
        XCTAssertEqual(PanelTab.files.icon, "folder.fill")
        XCTAssertEqual(PanelTab.git.icon, "arrow.triangle.branch")
        XCTAssertEqual(PanelTab.terminal.icon, "terminal.fill")
    }

    // MARK: - Labels

    func testAllTabsHaveLabels() {
        for tab in PanelTab.allCases {
            XCTAssertFalse(tab.label.isEmpty, "\(tab.rawValue) missing label")
        }
    }

    func testSpecificLabels() {
        XCTAssertEqual(PanelTab.chat.label, "Chat")
        XCTAssertEqual(PanelTab.files.label, "Files")
        XCTAssertEqual(PanelTab.spm.label, "Packages")
        XCTAssertEqual(PanelTab.appstore.label, "App Store")
        XCTAssertEqual(PanelTab.accessibility.label, "A11y")
    }

    // MARK: - Shortcuts

    func testTabsWithShortcutsCount() {
        let tabsWithShortcuts = PanelTab.allCases.filter { $0.shortcut != nil }
        XCTAssertEqual(tabsWithShortcuts.count, 10, "Should have 10 tabs with shortcuts")
    }

    func testSpecificShortcuts() {
        XCTAssertEqual(PanelTab.chat.shortcut, "1")
        XCTAssertEqual(PanelTab.files.shortcut, "2")
        XCTAssertEqual(PanelTab.preview.shortcut, "3")
        XCTAssertEqual(PanelTab.simulator.shortcut, "4")
        XCTAssertEqual(PanelTab.git.shortcut, "5")
        XCTAssertEqual(PanelTab.tests.shortcut, "6")
        XCTAssertEqual(PanelTab.terminal.shortcut, "7")
        XCTAssertEqual(PanelTab.spm.shortcut, "8")
        XCTAssertEqual(PanelTab.docs.shortcut, "9")
        XCTAssertEqual(PanelTab.memory.shortcut, "0")
    }

    func testTabsWithoutShortcuts() {
        let noShortcut: [PanelTab] = [.build, .assets, .localization, .schema, .profiling, .logs, .xcode, .appstore, .accessibility]
        for tab in noShortcut {
            XCTAssertNil(tab.shortcut, "\(tab.rawValue) should not have a shortcut")
        }
    }

    // MARK: - Build Tab

    func testBuildTabExists() {
        XCTAssertEqual(PanelTab.build.rawValue, "build")
        XCTAssertEqual(PanelTab.build.label, "Build")
        XCTAssertEqual(PanelTab.build.icon, "hammer.circle")
    }

    func testShortcutsAreUnique() {
        let shortcuts = PanelTab.allCases.compactMap(\.shortcut)
        XCTAssertEqual(shortcuts.count, Set(shortcuts).count, "Shortcuts should be unique")
    }

    func testShortcutsAreNumeric() {
        for tab in PanelTab.allCases {
            if let shortcut = tab.shortcut {
                XCTAssertNotNil(Int(shortcut), "\(tab.rawValue) shortcut '\(shortcut)' should be numeric")
            }
        }
    }

    // MARK: - Memory Tab

    func testMemoryTabExists() {
        XCTAssertEqual(PanelTab.memory.rawValue, "memory")
        XCTAssertEqual(PanelTab.memory.label, "Memory")
        XCTAssertEqual(PanelTab.memory.icon, "brain.head.profile")
    }

    // MARK: - Labels Are Unique

    func testLabelsAreUnique() {
        let labels = PanelTab.allCases.map(\.label)
        XCTAssertEqual(labels.count, Set(labels).count, "All PanelTab labels should be unique")
    }
}
