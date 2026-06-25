import SwiftUI
#if os(macOS)
import AppKit

/// A native `NSTextView`-backed text input that guarantees reliable keyboard focus on macOS.
/// SwiftUI's `TextEditor` can lose focus unpredictably when combined with modifiers like
/// `.onDrop`, `.onKeyPress`, `.contentShape`, and custom backgrounds. This wrapper gives
/// us direct control over the responder chain.
struct NativeTextInput: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textColor: NSColor
    var placeholderText: String
    var placeholderColor: NSColor
    var backgroundColor: NSColor
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var isFirstResponder: Bool
    var onReturnKey: ((NSEvent) -> Bool)?
    var onDrop: (([NSItemProvider]) -> Bool)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = InputTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.textContainer?.lineFragmentPadding = 4
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        textView.returnHandler = { event in
            context.coordinator.parent.onReturnKey?(event) ?? false
        }

        // Drop support
        if onDrop != nil {
            textView.registerForDraggedTypes([.fileURL])
            textView.dropHandler = { providers in
                context.coordinator.parent.onDrop?(providers) ?? false
            }
        }

        scrollView.documentView = textView
        context.coordinator.textView = textView

        // Become first responder on next run loop to avoid layout issues
        if isFirstResponder {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                textView.window?.makeFirstResponder(textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? InputTextView else { return }

        // Sync text from binding → view (only if different to avoid cursor resets)
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }

        textView.font = font
        textView.textColor = textColor
        textView.insertionPointColor = textColor

        // Update handlers
        textView.returnHandler = { event in
            context.coordinator.parent.onReturnKey?(event) ?? false
        }

        if onDrop != nil {
            textView.dropHandler = { providers in
                context.coordinator.parent.onDrop?(providers) ?? false
            }
        }

        // Resize scroll view based on text content
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
        let contentHeight = usedRect.height + textView.textContainerInset.height * 2
        let clampedHeight = max(minHeight, min(maxHeight, contentHeight))

        scrollView.frame.size.height = clampedHeight
        scrollView.invalidateIntrinsicContentSize()

        // Focus management
        if isFirstResponder && textView.window?.firstResponder !== textView {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NativeTextInput
        weak var textView: InputTextView?

        init(_ parent: NativeTextInput) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// Custom `NSTextView` subclass that intercepts return key and drop events.
class InputTextView: NSTextView {
    var returnHandler: ((NSEvent) -> Bool)?
    var dropHandler: (([NSItemProvider]) -> Bool)?

    override func keyDown(with event: NSEvent) {
        // Intercept Return key
        if event.keyCode == 36 { // Return key
            if let handler = returnHandler, handler(event) {
                return // Handled
            }
        }
        super.keyDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if dropHandler != nil {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let handler = dropHandler else {
            return super.performDragOperation(sender)
        }

        var providers: [NSItemProvider] = []
        sender.enumerateDraggingItems(
            options: [],
            for: nil,
            classes: [NSPasteboardItem.self],
            searchOptions: [:]
        ) { item, _, _ in
            if let pbItem = item.item as? NSPasteboardItem,
               let urlString = pbItem.string(forType: .fileURL),
               let url = URL(string: urlString) {
                let provider = NSItemProvider(contentsOf: url)
                if let p = provider {
                    providers.append(p)
                }
            }
        }

        if !providers.isEmpty {
            return handler(providers)
        }
        return false
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager, let textContainer = textContainer else {
            return super.intrinsicContentSize
        }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: usedRect.height + textContainerInset.height * 2
        )
    }
}

/// SwiftUI wrapper that adds height constraints and placeholder support for NativeTextInput.
struct NativeTextInputContainer: View {
    @Binding var text: String
    var font: NSFont = NSFont.systemFont(ofSize: 14)
    var textColor: NSColor = .labelColor
    var placeholderText: String = ""
    var placeholderColor: NSColor = .placeholderTextColor
    var backgroundColor: NSColor = .clear
    var minHeight: CGFloat = 44
    var maxHeight: CGFloat = 200
    var isFirstResponder: Bool = false
    var onReturnKey: ((NSEvent) -> Bool)?
    var onDrop: (([NSItemProvider]) -> Bool)?

    var body: some View {
        ZStack(alignment: .leading) {
            if text.isEmpty {
                Text(placeholderText)
                    .foregroundColor(Color(placeholderColor))
                    .font(Font(font))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .allowsHitTesting(false)
            }

            NativeTextInput(
                text: $text,
                font: font,
                textColor: textColor,
                placeholderText: placeholderText,
                placeholderColor: placeholderColor,
                backgroundColor: backgroundColor,
                minHeight: minHeight,
                maxHeight: maxHeight,
                isFirstResponder: isFirstResponder,
                onReturnKey: onReturnKey,
                onDrop: onDrop
            )
            .frame(minHeight: minHeight, maxHeight: maxHeight)
        }
    }
}
#endif
