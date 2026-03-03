import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct CodeBlockView: View {
    @EnvironmentObject var themeManager: ThemeManager
    let language: String
    let code: String
    var filePath: String? = nil
    var blockId: String? = nil
    @State private var copied = false
    @State private var applied = false
    @State private var rejected = false
    @State private var applyError: String? = nil
    @State private var cachedLineTokens: [[SyntaxHighlighter.Token]] = []
    @Environment(\.colorScheme) private var colorScheme

    private var codeLines: [String] {
        code.components(separatedBy: "\n")
    }

    private func refreshHighlightCache() {
        let highlighter = SyntaxHighlighter(language: language)
        cachedLineTokens = codeLines.map { highlighter.highlight($0) }
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
    private var codeColor: Color {
        colorScheme == .dark
            ? Color(red: 0.847, green: 0.820, blue: 1.000)
            : Color(red: 0.15, green: 0.15, blue: 0.20)
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
            // Header bar — language label + actions
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

                HStack(spacing: Spacing.lg) {
                    #if os(macOS)
                    // Run in Terminal button (shell commands only)
                    if isShellLanguage {
                        Button(action: runInTerminal) {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .semibold))
                                Text("Run")
                                    .font(Typography.captionSmallMedium)
                            }
                            .foregroundColor(.accentGreen)
                        }
                        .buttonStyle(ScaleButtonStyle())
                        .accessibilityLabel("Run in Terminal")
                        .help("Run this command in Terminal")
                    }

                    Button(action: openInXcode) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "hammer")
                                .font(Typography.captionSmall)
                            Text("Xcode")
                                .font(Typography.captionSmallMedium)
                        }
                        .foregroundColor(lineNumColor)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel("Open in Xcode")
                    #endif

                    Button(action: copyToClipboard) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(Typography.captionSmall)
                            Text(copied ? "Copied!" : "Copy")
                                .font(Typography.captionSmallMedium)
                        }
                        .foregroundColor(copied ? .accentGreen : lineNumColor)
                        .animation(.easeInOut(duration: Anim.quick), value: copied)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .accessibilityLabel(copied ? "Copied to clipboard" : "Copy code")
                }
            }
            .padding(.horizontal, Spacing.xxxl)
            .padding(.vertical, 9)
            .background(bgHeader)

            Divider()
                .background(themeManager.palette.effectiveAccent.opacity(0.15))

            // Code content with line numbers
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers gutter
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(Array(codeLines.enumerated()), id: \.offset) { idx, _ in
                            Text("\(idx + 1)")
                                .font(Typography.codeScaled(scale: themeManager.contentSize.scaleFactor))
                                .foregroundColor(lineNumColor)
                                .frame(height: 14 + Typography.userLineSpacing)
                        }
                    }
                    .padding(.leading, Spacing.xl)
                    .padding(.trailing, Spacing.lg)
                    .padding(.vertical, Spacing.xl)

                    // Separator
                    Rectangle()
                        .fill(langColor.opacity(0.15))
                        .frame(width: 1)
                        .padding(.vertical, Spacing.md)

                    // Code text (syntax-highlighted) — uses cached tokens to avoid per-render highlighting
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(cachedLineTokens.enumerated()), id: \.offset) { idx, tokens in
                            highlightedLineView(tokens: tokens)
                                .frame(height: 14 + Typography.userLineSpacing)
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
            .frame(maxHeight: min(CGFloat(codeLines.count) * (14 + Typography.userLineSpacing) + 20, 400))
            .background(bgCode)

            // Apply/Reject footer bar (Cursor-style)
            if filePath != nil, let bid = blockId {
                applyRejectBar(blockId: bid)
            }
        }
        .background(bgCode)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(
                    applied ? Color.accentGreen.opacity(0.4) :
                    rejected ? themeManager.palette.textMuted.opacity(0.2) :
                    themeManager.palette.borderCrisp.opacity(0.4),
                    lineWidth: applied || rejected ? 1 : 1
                )
        )
        .opacity(rejected ? 0.6 : 1.0)
        .onAppear { refreshHighlightCache() }
        .onChange(of: code) { _, _ in refreshHighlightCache() }
        .onChange(of: language) { _, _ in refreshHighlightCache() }
    }

    // MARK: - Apply/Reject Bar

    @ViewBuilder
    private func applyRejectBar(blockId: String) -> some View {
        Divider()
            .background(themeManager.palette.effectiveAccent.opacity(0.15))

        HStack(spacing: Spacing.lg) {
            // File path label
            if let path = filePath {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9, weight: .semibold))
                    Text(path)
                        .font(Typography.codeMicro)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundColor(themeManager.palette.textMuted)
            }

            Spacer()

            if let error = applyError {
                Text(error)
                    .font(Typography.micro)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }

            if applied {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentGreen)
                        .font(.system(size: 11))
                    Text("Applied")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(.accentGreen)

                    Button("Undo") {
                        undoApply(blockId: blockId)
                    }
                    .font(Typography.captionSmallMedium)
                    .foregroundColor(themeManager.palette.textMuted)
                    .buttonStyle(.plain)
                }
            } else if rejected {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(themeManager.palette.textMuted)
                        .font(.system(size: 11))
                    Text("Rejected")
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textMuted)
                }
            } else {
                HStack(spacing: Spacing.lg) {
                    Button(action: { rejectCode(blockId: blockId) }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Reject")
                                .font(Typography.captionSmallMedium)
                        }
                        .foregroundColor(themeManager.palette.textMuted)
                    }
                    .buttonStyle(ScaleButtonStyle())

                    Button(action: { applyCode(blockId: blockId) }) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("Apply")
                                .font(Typography.captionSmallSemibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.sm)
                        .background(themeManager.palette.effectiveAccent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
            }
        }
        .padding(.horizontal, Spacing.xxxl)
        .padding(.vertical, Spacing.lg)
        .background(bgHeader)
    }

    private func applyCode(blockId: String) {
        guard let path = filePath else { return }
        let result = CodeApplyService.shared.apply(blockId: blockId, code: code, toFile: path)
        if let error = result {
            applyError = error
        } else {
            withAnimation(Anim.springSnap) { applied = true }
        }
    }

    private func rejectCode(blockId: String) {
        CodeApplyService.shared.reject(blockId: blockId)
        withAnimation(Anim.springSnap) { rejected = true }
    }

    private func undoApply(blockId: String) {
        guard let path = filePath else { return }
        let result = CodeApplyService.shared.undo(blockId: blockId, filePath: path)
        if let error = result {
            applyError = error
        } else {
            withAnimation(Anim.springSnap) {
                applied = false
                applyError = nil
            }
        }
    }

    @ViewBuilder
    private func highlightedLineView(tokens: [SyntaxHighlighter.Token]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                Text(token.text)
                    .font(Typography.codeLargeScaled(scale: themeManager.contentSize.scaleFactor))
                    .foregroundColor(SyntaxHighlighter.color(for: token.kind, scheme: colorScheme))
            }
            Spacer(minLength: 0)
        }
    }

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

    #if os(macOS)
    private func openInXcode() {
        let ext = language.isEmpty ? "txt" : language.lowercased()
        let mappedExt: String
        switch ext {
        case "javascript": mappedExt = "js"
        case "typescript": mappedExt = "ts"
        case "python": mappedExt = "py"
        case "shell", "bash", "zsh": mappedExt = "sh"
        case "markdown": mappedExt = "md"
        case "ruby": mappedExt = "rb"
        default: mappedExt = ext
        }
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("grump_snippet.\(mappedExt)")
        try? code.write(to: fileURL, atomically: true, encoding: .utf8)
        if let xcodeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") {
            NSWorkspace.shared.open([fileURL], withApplicationAt: xcodeURL, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(fileURL)
        }
    }
    #endif

    private var isShellLanguage: Bool {
        let lang = language.lowercased()
        return ["shell", "bash", "zsh", "sh", "fish", "terminal", "console", ""].contains(lang)
    }

    #if os(macOS)
    private func runInTerminal() {
        // Run directly via Process instead of AppleScript (which requires Automation permission)
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", code]
            process.environment = ProcessInfo.processInfo.environment

            let pipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = pipe
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                // Process launch failed — log to stderr
                NSLog("[G-Rump] runInTerminal failed: \(error.localizedDescription)")
            }
        }
    }
    #endif

    private func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #else
        UIPasteboard.general.string = code
        #endif

        withAnimation { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation { copied = false }
        }
    }
}
