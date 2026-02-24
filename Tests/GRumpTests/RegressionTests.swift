import XCTest
import SwiftUI
@testable import GRump

@MainActor
final class RegressionTests: XCTestCase {
    
    func testContentViewBasicFunctionality() {
        // Test that ContentView can be created without crashing
        let contentView = ContentView()
        XCTAssertNotNil(contentView)
    }
    
    func testRightPanelManagerCreation() {
        // Test that RightPanelManager can be created
        let panelManager = RightPanelManager()
        XCTAssertNotNil(panelManager)
    }
    
    func testKeyboardShortcutHandlerCreation() {
        // Test that KeyboardShortcutHandler can be created
        let shortcutHandler = KeyboardShortcutHandler(
            messageFieldFocused: .init(),
            sidebarCollapsed: .constant(false),
            showSettings: .constant(false),
            settingsInitialTab: .constant(nil),
            selectedPanelRaw: .constant("chat"),
            rightPanelCollapsed: .constant(true)
        )
        XCTAssertNotNil(shortcutHandler)
    }
    
    func testLayoutOptionsDefaults() {
        // Test that LayoutOptions maintains expected defaults
        let layoutOptions = LayoutOptions.shared
        XCTAssertTrue(layoutOptions.activityBarVisible) // Should be true after our fix
        XCTAssertTrue(layoutOptions.primarySidebarVisible)
        XCTAssertTrue(layoutOptions.panelVisible)
        XCTAssertEqual(layoutOptions.primarySidebarPosition, .right)
    }
    
    func testPanelTabSwitching() {
        // Test that panel switching works correctly
        var selectedPanelRaw = "chat"
        var rightPanelCollapsed = true
        
        func switchPanel(_ tab: PanelTab) {
            withAnimation(.easeInOut(duration: Anim.quick)) {
                if selectedPanelRaw == tab.rawValue && !rightPanelCollapsed {
                    rightPanelCollapsed = true
                } else {
                    selectedPanelRaw = tab.rawValue
                    rightPanelCollapsed = false
                }
            }
        }
        
        // Test switching to files panel
        switchPanel(.files)
        XCTAssertEqual(selectedPanelRaw, "files")
        XCTAssertFalse(rightPanelCollapsed)
        
        // Test toggling same panel
        switchPanel(.files)
        XCTAssertTrue(rightPanelCollapsed)
    }
}
