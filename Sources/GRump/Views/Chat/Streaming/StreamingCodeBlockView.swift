import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A code block view that renders incrementally during streaming.
/// Characters appear with real-time syntax highlighting and line numbers
/// update live as new lines arrive. Transitions seamlessly into the
/// final `CodeBlockView` when streaming completes.
struct StreamingCodeBlockView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    let language: String
    let code: String
    let isStreaming: Bool

    /// During streaming, only show the last N lines for performance.
    private static let streamingTailLines = 8

    @State private var cachedLineTokens: [[SyntaxHighlighter.Token]] = []
    @State private var lastHighlightedCode: String = ""

    private var codeLines: [String] {
        code.components(separatedBy: "\n")
    }

    private var bgCode: Color {
        colorScheme == .dark
            ? Color(red: 0.078, green: 0.078, blue: 0.098)
            : Color(red: 0.96, green: 0.96, blue: 0.98)
    }
    private var bgHeader: Color {
        colorScheme == .dark
            ? Color(red: 0.102, green: 0.102, blue: 0.129)
            : Color(red: 0.92, green: 0.92, blue: 0.95)
    }
    private var lineNumColor: Color {
        colorScheme == .dark
            ? Color(red: 0.4, green: 0.4, blue: 0.5)
            : Color(red: 0.6, green: 0.6, blue: 0.7)
    }
    private var langColor: Color {
        Color(red: 0.561, green: 0.337, blue: 1.000).opacity(colorScheme == .dark ? 0.85 : 1.0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            headerBar

            Divider()
                .background(themeManager.palette.effectiveAccent.opacity(0.15))

            // Truncation indicator
            if isStreaming && codeLines.count > Self.streamingTailLines {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 9, weight: .medium))
                    Text("\(codeLines.count - Self.streamingTailLines) lines above")
                        .font(Typography.codeMicro)
                }
                .foregroundColor(lineNumColor)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Spacing.sm)
                .background(bgCode)
            }

            // Code content with live line numbers
            codeContent
        }
        .background(bgCode)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(
                    isStreaming
                        ? themeManager.palette.effectiveAccent.opacity(0.3)
                        : themeManager.palette.borderCrisp.opacity(0.4),
                    lineWidth: isStreaming ? 1.5 : 1
                )
        )
        .onAppear { refreshHighlight() }
        .onChange(of: code) { _, newCode in
            incrementalHighlight(newCode)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: Spacing.md) {
                Image(systemName: languageIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(langColor)
                Text(language.isEmpty ? "code" : language.lowercased())
                    .font(Typography.captionSmallSemibold)
                    .fontDesign(.monospaced)
                    .foregroundColor(langColor)
            }

            Spacer()

            if isStreaming {
                HStack(spacing: Spacing.sm) {
                    StreamingCursorView(lineHeight: 12, cursorWidth: 1.5)
                    Text("\(codeLines.count) lines")
                        .font(Typography.captionSmallMedium)
                        .fontDesign(.monospaced)
                        .foregroundColor(themeManager.palette.textMuted)
                }
            }
        }
        .padding(.horizontal, Spacing.xxxl)
        .padding(.vertical, 9)
        .background(bgHeader)
    }

    // MARK: - Code Content

    private var codeContent: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                // Line numbers gutter
                let startLineNumber = isStreaming && codeLines.count > Self.streamingTailLines
                    ? codeLines.count - Self.streamingTailLines + 1 : 1
                VStack(alignment: .trailing, spacing: 0) {
                    ForEach(Array(visibleLines.enumerated()), id: \.offset) { idx, _ in
                        Text("\(startLineNumber + idx)")
                            .font(Typography.codeScaled(scale: themeManager.contentSize.scaleFactor))
                            .foregroundColor(lineNumColor)
                            .frame(height: 18)
                    }
                }
                .padding(.leading, Spacing.xl)
                .padding(.trailing, Spacing.lg)
                .padding(.vertical, Spacing.xl)
                .animation(.easeOut(duration: 0.1), value: codeLines.count)

                // Separator
                Rectangle()
                    .fill(langColor.opacity(0.15))
                    .frame(width: 1)
                    .padding(.vertical, Spacing.md)

                // Syntax-highlighted code
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleTokens.enumerated()), id: \.offset) { idx, tokens in
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                                Text(token.text)
                                    .font(Typography.codeLargeScaled(scale: themeManager.contentSize.scaleFactor))
                                    .foregroundColor(SyntaxHighlighter.color(for: token.kind, scheme: colorScheme))
                            }

                            // Show cursor on last line while streaming
                            if isStreaming && idx == cachedLineTokens.count - 1 {
                                StreamingCursorView(lineHeight: 14, cursorWidth: 1.5)
                                    .padding(.leading, 1)
                            }

                            Spacer(minLength: 0)
                        }
                        .frame(height: 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.leading, Spacing.xl)
                .padding(.trailing, Spacing.xxxl)
                .padding(.vertical, Spacing.xl)
                .textSelection(.enabled)
            }
            .frame(minWidth: 0, alignment: .leading)
        }
        .frame(maxHeight: min(CGFloat(visibleLines.count) * 18 + 20, 400))
        .background(bgCode)
    }

    // MARK: - Incremental Highlighting

    /// Only re-highlight lines that changed (new lines or last modified line).
    private func incrementalHighlight(_ newCode: String) {
        let highlighter = SyntaxHighlighter(language: language)
        let newLines = newCode.components(separatedBy: "\n")

        if cachedLineTokens.isEmpty {
            cachedLineTokens = newLines.map { highlighter.highlight($0) }
        } else {
            // Only update the last line (which is still being streamed) and any new lines
            let existingCount = cachedLineTokens.count
            if newLines.count > existingCount {
                // Re-highlight the last existing line (it may have grown)
                if existingCount > 0 {
                    cachedLineTokens[existingCount - 1] = highlighter.highlight(newLines[existingCount - 1])
                }
                // Add new lines
                for i in existingCount..<newLines.count {
                    cachedLineTokens.append(highlighter.highlight(newLines[i]))
                }
            } else if newLines.count == existingCount && existingCount > 0 {
                // Same line count — only re-highlight the last line
                cachedLineTokens[existingCount - 1] = highlighter.highlight(newLines[existingCount - 1])
            }
        }
        lastHighlightedCode = newCode
    }

    private func refreshHighlight() {
        let highlighter = SyntaxHighlighter(language: language)
        cachedLineTokens = codeLines.map { highlighter.highlight($0) }
        lastHighlightedCode = code
    }

    /// Lines visible — tail-only during streaming for performance.
    private var visibleLines: [String] {
        if isStreaming && codeLines.count > Self.streamingTailLines {
            return Array(codeLines.suffix(Self.streamingTailLines))
        }
        return codeLines
    }

    /// Tokens visible — matches visibleLines.
    private var visibleTokens: [[SyntaxHighlighter.Token]] {
        if isStreaming && cachedLineTokens.count > Self.streamingTailLines {
            return Array(cachedLineTokens.suffix(Self.streamingTailLines))
        }
        return cachedLineTokens
    }

    // MARK: - Language Icon

    private var languageIcon: String {
        switch language.lowercased() {
        case "swift": return "swift"
        case "python", "py": return "chevron.left.forwardslash.chevron.right"
        case "javascript", "js", "typescript", "ts", "jsx", "tsx": return "curlybraces"
        case "html", "xml", "svg": return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "sass": return "paintbrush"
        case "json", "yaml", "yml", "toml": return "doc.text"
        case "shell", "bash", "zsh", "sh": return "terminal"
        case "rust", "go", "c", "cpp", "c++", "objc": return "gearshape"
        case "sql": return "cylinder"
        case "markdown", "md": return "text.alignleft"
        case "ruby", "rb": return "diamond"
        case "java", "kotlin": return "cup.and.saucer"
        default: return "chevron.left.forwardslash.chevron.right"
        }
    }
}
