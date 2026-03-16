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
    @State private var pendingText: String = ""
    @State private var isStreaming: Bool = false
    @State private var renderTask: Task<Void, Never>?
    @State private var lastRenderedLength: Int = 0
    
    /// Incremental parsing state — tracks how far we've parsed to avoid re-parsing the whole text
    @State private var lastParsedOffset: Int = 0
    @State private var stableBlockCount: Int = 0
    
    /// Cached parsed blocks; debounced to avoid parse-per-keystroke during streaming.
    @State private var cachedBlocks: [Block] = []
    @State private var debounceTask: Task<Void, Never>?
    /// Debounce task for streaming incremental parse.
    @State private var streamDebounceTask: Task<Void, Never>?
    
    /// Animation configuration
    @State private var animationDuration: Double = 0.15
    @State private var chunkSize: Int = 100
    

    
    private var debounceNs: UInt64 {
        let ms = UserDefaults.standard.object(forKey: "StreamDebounceMs") as? Int ?? 50
        return UInt64(max(0, ms)) * 1_000_000
    }
    
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
            let count = input.count
            await MainActor.run {
                renderedBlocks = blocks
                cachedBlocks = blocks
                lastParsedOffset = count
                stableBlockCount = blocks.count
            }
        }
    }

    // MARK: - Inline Formatting

    func buildInlineText(_ text: String) -> Text {
        let attrStr = buildAttributedString(text)
        return Text(attrStr)
    }

    private func buildAttributedString(_ text: String) -> AttributedString {
        var result = AttributedString()
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Bold + Italic: ***text***
            if remaining.hasPrefix("***"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 3)...].range(of: "***") {
                let content = String(remaining[remaining.index(remaining.startIndex, offsetBy: 3)..<endRange.lowerBound])
                let start = result.endIndex
                result.append(AttributedString(content))
                result[start..<result.endIndex].inlinePresentationIntent = [.stronglyEmphasized, .emphasized]
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Bold: **text**
            if remaining.hasPrefix("**"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...].range(of: "**") {
                let boldContent = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound])
                let start = result.endIndex
                result.append(AttributedString(boldContent))
                result[start..<result.endIndex].inlinePresentationIntent = .stronglyEmphasized
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Strikethrough: ~~text~~
            if remaining.hasPrefix("~~"),
               let endRange = remaining[remaining.index(remaining.startIndex, offsetBy: 2)...].range(of: "~~") {
                let content = String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<endRange.lowerBound])
                let start = result.endIndex
                result.append(AttributedString(content))
                result[start..<result.endIndex].strikethroughStyle = .single
                remaining = remaining[endRange.upperBound...]
                continue
            }

            // Inline code: `text` — styled with background pill
            if remaining.hasPrefix("`"),
               let endIdx = remaining[remaining.index(after: remaining.startIndex)...].firstIndex(of: "`") {
                let codeContent = String(remaining[remaining.index(after: remaining.startIndex)..<endIdx])
                // Add a space-padded code span with monospace font and accent color
                let paddedCode = "\u{00A0}\(codeContent)\u{00A0}" // non-breaking spaces for visual padding
                let start = result.endIndex
                result.append(AttributedString(paddedCode))
                result[start..<result.endIndex].font = .system(.body, design: .monospaced).weight(.medium)
                result[start..<result.endIndex].foregroundColor = themeManager.palette.effectiveAccent
                result[start..<result.endIndex].backgroundColor = themeManager.palette.effectiveAccent.opacity(0.1)
                remaining = remaining[remaining.index(after: endIdx)...]
                continue
            }

            // Link: [text](url) — tappable via .link
            if remaining.hasPrefix("["),
               let closeBracket = remaining.firstIndex(of: "]"),
               remaining.index(after: closeBracket) < remaining.endIndex,
               remaining[remaining.index(after: closeBracket)] == "(",
               let closeParen = remaining[remaining.index(after: closeBracket)...].firstIndex(of: ")") {
                let linkText = String(remaining[remaining.index(after: remaining.startIndex)..<closeBracket])
                let urlStart = remaining.index(after: remaining.index(after: closeBracket))
                let urlString = String(remaining[urlStart..<closeParen])
                let start = result.endIndex
                result.append(AttributedString(linkText))
                result[start..<result.endIndex].foregroundColor = themeManager.palette.effectiveAccent
                result[start..<result.endIndex].underlineStyle = .single
                if let url = URL(string: urlString) {
                    result[start..<result.endIndex].link = url
                }
                remaining = remaining[remaining.index(after: closeParen)...]
                continue
            }

            // Italic: *text*
            if remaining.hasPrefix("*"),
               let endIdx = remaining[remaining.index(after: remaining.startIndex)...].firstIndex(of: "*") {
                let italicContent = String(remaining[remaining.index(after: remaining.startIndex)..<endIdx])
                let start = result.endIndex
                result.append(AttributedString(italicContent))
                result[start..<result.endIndex].inlinePresentationIntent = .emphasized
                remaining = remaining[remaining.index(after: endIdx)...]
                continue
            }

            // Regular character
            let char = remaining[remaining.startIndex]
            result.append(AttributedString(String(char)))
            remaining = remaining[remaining.index(after: remaining.startIndex)...]
        }

        return result
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
            // Text shrunk (edit/undo) — trim blocks and full re-parse
            isStreaming = false
            lastParsedOffset = 0
            stableBlockCount = 0
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
    
    /// Incremental append-only parse: re-parses only from the last "stable" block boundary.
    /// During streaming, the last block is often incomplete (e.g., a paragraph still being typed).
    /// We keep all blocks except the last one as stable, and only re-parse from there.
    private func incrementalParse(_ fullText: String) {
        renderTask?.cancel()
        renderTask = Task.detached(priority: .userInitiated) {
            // Find the offset where stable blocks end
            let currentBlocks = await MainActor.run { renderedBlocks }
            let stableCount = max(0, currentBlocks.count - 1) // Last block may be incomplete
            
            // Compute character offset of stable blocks
            var stableOffset = 0
            for i in 0..<stableCount {
                stableOffset += Self.blockLengthStatic(currentBlocks[i])
            }
            
            // Parse only the tail portion (from stable offset onward)
            let tailStart = fullText.index(fullText.startIndex, offsetBy: min(stableOffset, fullText.count))
            let tailText = String(fullText[tailStart...])
            let tailBlocks = Self.parseBlocksStatic(tailText)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                // Replace blocks from stableCount onward with newly parsed tail blocks
                var merged = Array(currentBlocks.prefix(stableCount))
                merged.append(contentsOf: tailBlocks)
                renderedBlocks = merged
                cachedBlocks = merged
                pendingText = ""
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
        cachedBlocks = blocks
        lastParsedOffset = fullText.count
        stableBlockCount = blocks.count
        isStreaming = false
        pendingText = ""
    }
    
    private func blockLength(_ block: Block) -> Int {
        Self.blockLengthStatic(block)
    }
}
