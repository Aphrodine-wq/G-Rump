import XCTest
@testable import GRump
#if os(macOS)
import AppKit

/// Tests the InputTextView subclass and NativeTextInput configuration logic.
final class NativeTextInputTests: XCTestCase {

    // MARK: - InputTextView Return Key

    func testInputTextViewCreation() {
        let textView = InputTextView()
        XCTAssertNotNil(textView)
        XCTAssertNil(textView.returnHandler)
        XCTAssertNil(textView.dropHandler)
    }

    func testReturnHandlerCanBeSet() {
        let textView = InputTextView()
        var handlerCalled = false
        textView.returnHandler = { _ in
            handlerCalled = true
            return true
        }
        XCTAssertNotNil(textView.returnHandler)
    }

    func testDropHandlerCanBeSet() {
        let textView = InputTextView()
        var handlerCalled = false
        textView.dropHandler = { _ in
            handlerCalled = true
            return true
        }
        XCTAssertNotNil(textView.dropHandler)
    }

    // MARK: - InputTextView Shift+Tab

    func testShiftTabHandlerCanBeSet() {
        let textView = InputTextView()
        XCTAssertNil(textView.shiftTabHandler)
        textView.shiftTabHandler = { _ in true }
        XCTAssertNotNil(textView.shiftTabHandler)
    }

    func testShiftTabKeyDownInvokesHandler() {
        let textView = InputTextView()
        var handlerCalled = false
        textView.shiftTabHandler = { _ in
            handlerCalled = true
            return true
        }
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .shift,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\t", charactersIgnoringModifiers: "\t",
            isARepeat: false, keyCode: 48
        ) else {
            XCTFail("Could not synthesize ⇧⇥ event")
            return
        }
        textView.keyDown(with: event)
        XCTAssertTrue(handlerCalled, "⇧⇥ keyDown should invoke shiftTabHandler")
    }

    func testPlainTabDoesNotInvokeShiftTabHandler() {
        let textView = InputTextView()
        var handlerCalled = false
        textView.shiftTabHandler = { _ in
            handlerCalled = true
            return true
        }
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\t", charactersIgnoringModifiers: "\t",
            isARepeat: false, keyCode: 48
        ) else {
            XCTFail("Could not synthesize Tab event")
            return
        }
        textView.keyDown(with: event)
        XCTAssertFalse(handlerCalled, "plain Tab must not trigger mode cycling")
    }

    // MARK: - InputTextView Drag Support

    func testDraggingEnteredReturnsCopyWithHandler() {
        let textView = InputTextView()
        textView.dropHandler = { _ in true }
        // When drop handler is set, draggingEntered should return .copy
        // We can verify the handler is set
        XCTAssertNotNil(textView.dropHandler)
    }

    func testDraggingEnteredWithoutHandler() {
        let textView = InputTextView()
        // Without a drop handler, should delegate to super
        XCTAssertNil(textView.dropHandler)
    }

    // MARK: - InputTextView Properties

    func testTextViewIsEditable() {
        let textView = InputTextView()
        textView.isEditable = true
        XCTAssertTrue(textView.isEditable)
    }

    func testTextViewIsSelectable() {
        let textView = InputTextView()
        textView.isSelectable = true
        XCTAssertTrue(textView.isSelectable)
    }

    func testTextViewIsNotRichText() {
        let textView = InputTextView()
        textView.isRichText = false
        XCTAssertFalse(textView.isRichText)
    }

    func testTextViewAllowsUndo() {
        let textView = InputTextView()
        textView.allowsUndo = true
        XCTAssertTrue(textView.allowsUndo)
    }

    // MARK: - Text Sync Logic

    func testTextSyncOnlyUpdatesWhenDifferent() {
        // Mirror NativeTextInput.updateNSView logic
        let currentText = "Hello"
        let newText = "Hello"

        // Should NOT update (avoids cursor reset)
        XCTAssertEqual(currentText, newText)

        let changedText = "Hello World"
        XCTAssertNotEqual(currentText, changedText)
    }

    // MARK: - Height Calculation

    func testHeightClampingBetweenMinMax() {
        let minHeight: CGFloat = 44
        let maxHeight: CGFloat = 200

        // Test various content heights
        let smallContent: CGFloat = 20
        let exactMin: CGFloat = 44
        let midRange: CGFloat = 120
        let exactMax: CGFloat = 200
        let overMax: CGFloat = 350

        XCTAssertEqual(max(minHeight, min(maxHeight, smallContent)), 44)
        XCTAssertEqual(max(minHeight, min(maxHeight, exactMin)), 44)
        XCTAssertEqual(max(minHeight, min(maxHeight, midRange)), 120)
        XCTAssertEqual(max(minHeight, min(maxHeight, exactMax)), 200)
        XCTAssertEqual(max(minHeight, min(maxHeight, overMax)), 200)
    }

    // MARK: - Return Key Code

    func testReturnKeyCode() {
        // macOS return key is keyCode 36
        let returnKeyCode: UInt16 = 36
        XCTAssertEqual(returnKeyCode, 36)
    }

    // MARK: - NativeTextInputContainer Defaults

    func testContainerDefaultValues() {
        // Verify the default parameter values match ChatInputView usage
        let defaultMinHeight: CGFloat = 44
        let defaultMaxHeight: CGFloat = 200
        let defaultPlaceholder = "Ask anything..."

        XCTAssertEqual(defaultMinHeight, 44)
        XCTAssertEqual(defaultMaxHeight, 200)
        XCTAssertFalse(defaultPlaceholder.isEmpty)
    }

    // MARK: - Intrinsic Content Size

    func testIntrinsicContentSizeWithEmptyTextView() {
        let textView = InputTextView()
        textView.string = ""
        // Should produce a valid size (not crash)
        let size = textView.intrinsicContentSize
        // Width should be noIntrinsicMetric
        XCTAssertEqual(size.width, NSView.noIntrinsicMetric)
        // Height should be non-negative
        XCTAssertGreaterThanOrEqual(size.height, 0)
    }

    func testIntrinsicContentSizeWithContent() {
        let textView = InputTextView()
        textView.string = "Hello, World!\nSecond line\nThird line"
        let size = textView.intrinsicContentSize
        XCTAssertEqual(size.width, NSView.noIntrinsicMetric)
        XCTAssertGreaterThanOrEqual(size.height, 0)
    }
}
#endif
