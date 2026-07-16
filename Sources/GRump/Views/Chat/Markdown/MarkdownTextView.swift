import SwiftUI

/// A view that renders markdown text with formatting support and progressive rendering.
/// Handles: **bold**, *italic*, `inline code`, ~~strikethrough~~, [links](url),
/// fenced code blocks, headers, lists, blockquotes, tables, and horizontal rules.
///
/// Parsing logic lives in `MarkdownTextView+Parsing.swift`.
/// Block rendering lives in `MarkdownTextView+BlockRendering.swift`.
struct MarkdownTextView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let text: String
    let onCodeBlockTap: ((String) -> Void)?

    // MARK: - Progressive Rendering State

    @State private(set) var renderedBlocks: [Block] = []
    @State private var isStreaming: Bool = false
    @State private var renderTask: Task<Void, Never>?
    @State private var lastRenderedLength: Int = 0

    /// Debounce task for non-streaming re-parse (edits/undo).
    @State private var debounceTask: Task<Void, Never>?
    /// Debounce task for streaming re-parse.
    @State private var streamDebounceTask: Task<Void, Never>?

    /// Animation configuration
    @State private var animationDuration: Double = 0.15

    init(text: String, themeManager: ThemeManager? = nil, onCodeBlockTap: ((String) -> Void)? = nil) {
        self.text = text
        self.onCodeBlockTap = onCodeBlockTap
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(renderedBlocks.enumerated()), id: \.offset) { index, block in
                blockView(block)
                    .padding(.top, topSpacing(for: block, previous: index > 0 ? renderedBlocks[index - 1] : nil))
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
                    .animation(.easeOut(duration: animationDuration), value: renderedBlocks.count)
            }

        }
        .onAppear {
            startProgressiveRendering()
        }
        .onChange(of: text) { _, newValue in
            detectStreamingChange(newValue)
        }
        .onDisappear {
            renderTask?.cancel()
            debounceTask?.cancel()
            streamDebounceTask?.cancel()
        }
    }

    // MARK: - Background Parse Helper

    func parseOnBackground(_ input: String) {
        debounceTask?.cancel()
        debounceTask = Task.detached(priority: .userInitiated) {
            let blocks = Self.parseBlocksStatic(input)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                renderedBlocks = blocks
            }
        }
    }

    // MARK: - Inline Formatting

    func buildInlineText(_ text: String) -> Text {
        let attrStr = buildAttributedString(text)
        return Text(attrStr)
    }

    /// Characters that can open an inline construct — everything else is batched
    /// into plain runs so long paragraphs cost a handful of appends, not one per char.
    private static let inlineDelimiters: Set<Character> = ["*", "_", "~", "`", "[", "\\"]

    /// Punctuation that a backslash escapes (CommonMark's ASCII punctuation set, trimmed
    /// to the constructs this renderer understands).
    private static let escapablePunctuation: Set<Character> = [
        "\\", "*", "_", "~", "`", "[", "]", "(", ")", "#", "!", "<", ">", "|"
    ]

    private func buildAttributedString(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[text.startIndex...]
        var plainRun = ""
        /// Last source character consumed — drives emphasis flanking rules without
        /// re-materializing the accumulated result.
        var lastChar: Character?

        func flushPlain() {
            guard !plainRun.isEmpty else { return }
            result.append(AttributedString(plainRun))
            plainRun = ""
        }

        while !remaining.isEmpty {
            let first = remaining[remaining.startIndex]

            // Fast path: batch plain characters until the next potential delimiter
            if !Self.inlineDelimiters.contains(first) {
                let runEnd = remaining.firstIndex(where: { Self.inlineDelimiters.contains($0) }) ?? remaining.endIndex
                plainRun += remaining[remaining.startIndex..<runEnd]
                lastChar = plainRun.last
                remaining = remaining[runEnd...]
                continue
            }

            // Escape: \* renders a literal *
            if first == "\\" {
                let next = remaining.index(after: remaining.startIndex)
                if next < remaining.endIndex, Self.escapablePunctuation.contains(remaining[next]) {
                    plainRun.append(remaining[next])
                    remaining = remaining[remaining.index(after: next)...]
                } else {
                    plainRun.append("\\")
                    remaining = remaining[next...]
                }
                lastChar = plainRun.last
                continue
            }

            // Bold + Italic: ***text***
            if remaining.hasPrefix("***"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 3)...].range(of: "***") {
                let content = String(remaining[remaining.index(remaining.startIndex, offsetBy: 3)..<endRange.lowerBound])
                flushPlain()
                let start = result.endIndex
                result.append(AttributedString(content))
                result[start..<result.endIndex].inlinePresentationIntent = [.stronglyEmphasized, .emphasized]
                remaining = remaining[endRange.upperBound...]
                lastChar = "*"
                continue
            }

            // Bold: **text** or __text__
            if remaining.hasPrefix("**") || remaining.hasPrefix("__") {
                let marker = String(remaining.prefix(2))
                if let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...].range(of: marker) {
                    let boldContent = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound])
                    flushPlain()
                    let start = result.endIndex
                    result.append(AttributedString(boldContent))
                    result[start..<result.endIndex].inlinePresentationIntent = .stronglyEmphasized
                    remaining = remaining[endRange.upperBound...]
                    lastChar = marker.last
                    continue
                }
            }

            // Strikethrough: ~~text~~
            if remaining.hasPrefix("~~"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...].range(of: "~~") {
                let content = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound])
                flushPlain()
                let start = result.endIndex
                result.append(AttributedString(content))
                result[start..<result.endIndex].strikethroughStyle = .single
                remaining = remaining[endRange.upperBound...]
                lastChar = "~"
                continue
            }

            // Inline code: `text` — styled with background pill
            if first == "`",
               let endIdx = remaining[remaining.index(after: remaining.startIndex)...].firstIndex(of: "`") {
                let codeContent = String(remaining[remaining.index(after: remaining.startIndex)..<endIdx])
                // Add a space-padded code span with monospace font and accent color
                let paddedCode = "\u{00A0}\(codeContent)\u{00A0}" // non-breaking spaces for visual padding
                flushPlain()
                let start = result.endIndex
                result.append(AttributedString(paddedCode))
                result[start..<result.endIndex].font = .system(.body, design: .monospaced).weight(.medium)
                result[start..<result.endIndex].foregroundColor = themeManager.palette.effectiveAccent
                result[start..<result.endIndex].backgroundColor = themeManager.palette.effectiveAccent.opacity(0.1)
                remaining = remaining[remaining.index(after: endIdx)...]
                lastChar = "`"
                continue
            }

            // Link: [text](url) — tappable via .link
            if first == "[",
               let closeBracket = remaining.firstIndex(of: "]"),
               remaining.index(after: closeBracket) < remaining.endIndex,
               remaining[remaining.index(after: closeBracket)] == "(",
               let closeParen = remaining[remaining.index(after: closeBracket)...].firstIndex(of: ")") {
                let linkText = String(remaining[remaining.index(after: remaining.startIndex)..<closeBracket])
                let urlStart = remaining.index(after: remaining.index(after: closeBracket))
                let urlString = String(remaining[urlStart..<closeParen])
                flushPlain()
                let start = result.endIndex
                result.append(AttributedString(linkText))
                result[start..<result.endIndex].foregroundColor = themeManager.palette.effectiveAccent
                result[start..<result.endIndex].underlineStyle = .single
                if let url = URL(string: urlString) {
                    result[start..<result.endIndex].link = url
                }
                remaining = remaining[remaining.index(after: closeParen)...]
                lastChar = ")"
                continue
            }

            // Italic: *text* or _text_ — flanking rules keep "2 * 3" and snake_case plain
            if first == "*" || first == "_",
               let endIdx = italicClosingIndex(in: remaining, marker: first, previous: lastChar) {
                let italicContent = String(remaining[remaining.index(after: remaining.startIndex)..<endIdx])
                flushPlain()
                let start = result.endIndex
                result.append(AttributedString(italicContent))
                result[start..<result.endIndex].inlinePresentationIntent = .emphasized
                remaining = remaining[remaining.index(after: endIdx)...]
                lastChar = first
                continue
            }

            // Delimiter char that didn't open anything — literal
            plainRun.append(first)
            lastChar = first
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
        }

        flushPlain()
        return result
    }

    /// Finds the closing delimiter for single-marker emphasis, or nil when the opener
    /// isn't valid emphasis. Rules (CommonMark-inspired, kept deliberately simple):
    /// the opener must be followed by non-whitespace, the closer preceded by
    /// non-whitespace, and `_` additionally requires a word boundary before the
    /// opener so identifiers like snake_case never italicize.
    private func italicClosingIndex(
        in remaining: Substring, marker: Character, previous: Character?
    ) -> Substring.Index? {
        let afterMarker = remaining.index(after: remaining.startIndex)
        guard afterMarker < remaining.endIndex else { return nil }
        // Opener must be left-flanking: next char is non-whitespace (and not the marker itself)
        let nextChar = remaining[afterMarker]
        guard !nextChar.isWhitespace, nextChar != marker else { return nil }
        // Underscore openers must sit at a word boundary
        if marker == "_", let prev = previous, prev.isLetter || prev.isNumber { return nil }

        var idx = afterMarker
        while let close = remaining[idx...].firstIndex(of: marker) {
            let beforeClose = remaining.index(before: close)
            if !remaining[beforeClose].isWhitespace {
                // Underscore closers must also end at a word boundary
                if marker == "_" {
                    let afterClose = remaining.index(after: close)
                    if afterClose < remaining.endIndex,
                       remaining[afterClose].isLetter || remaining[afterClose].isNumber {
                        idx = afterClose
                        continue
                    }
                }
                return close
            }
            idx = remaining.index(after: close)
        }
        return nil
    }

    // MARK: - Progressive Rendering

    private func startProgressiveRendering() {
        renderTask?.cancel()
        renderTask = Task {
            await renderProgressively()
        }
    }

    private func detectStreamingChange(_ newText: String) {
        let isIncreasing = newText.count > lastRenderedLength

        if !isIncreasing {
            // Text shrunk (edit/undo) — full re-parse
            isStreaming = false
            parseOnBackground(newText)
            lastRenderedLength = newText.count
            return
        }

        let delta = newText.count - lastRenderedLength
        lastRenderedLength = newText.count

        if delta > 0 {
            isStreaming = true
            // Debounce: coalesce rapid stream deltas into 16ms batches (~60fps)
            // Aligned with display refresh rate so rendering keeps pace with
            // the frame rate rather than lagging behind. Combined with the
            // 50ms parse debounce, this produces smooth, responsive streaming.
            streamDebounceTask?.cancel()
            streamDebounceTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 16_000_000) // 16ms (~60fps)
                guard !Task.isCancelled else { return }
                incrementalParse(text) // use latest `text` value
            }
        }
    }

    /// Debounced full re-parse on a background thread. The parser is a single
    /// line-oriented pass, so re-parsing the whole text every ~16ms tick is cheap —
    /// and unlike the previous offset-estimating tail parse, it can never drift and
    /// duplicate fragments mid-stream (block length estimates undercounted the blank
    /// lines between blocks, so the tail re-parse started inside already-stable text).
    private func incrementalParse(_ fullText: String) {
        renderTask?.cancel()
        renderTask = Task.detached(priority: .userInitiated) {
            let blocks = Self.parseBlocksStatic(fullText)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                renderedBlocks = blocks
            }
        }
    }

    @MainActor
    private func renderProgressively() async {
        let fullText = text

        // For initial render, parse on background thread
        let blocks = await Task.detached(priority: .userInitiated) {
            Self.parseBlocksStatic(fullText)
        }.value

        guard !Task.isCancelled else { return }

        renderedBlocks = blocks
        isStreaming = false
    }
}
