import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Inline diff card for showing before/after file changes in chat.
/// Renders a unified diff with syntax highlighting, red/green lines,
/// and line numbers. Collapsible — shows summary by default.
struct InlineDiffCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.colorScheme) private var colorScheme

    let filePath: String
    let originalContent: String
    let newContent: String

    @State private var isExpanded: Bool = false
    @State private var viewMode: DiffViewMode = .unified
    @State private var copiedDiff: Bool = false

    enum DiffViewMode {
        case unified
        case sideBySide
    }

    private var diffLines: [DiffLine] {
        computeUnifiedDiff(original: originalContent, modified: newContent)
    }

    private var addedCount: Int { diffLines.filter { $0.type == .added }.count }
    private var removedCount: Int { diffLines.filter { $0.type == .removed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header — file path + change summary
            headerBar

            // Collapsed summary or expanded diff
            if isExpanded {
                Divider()
                diffContent
            }
        }
        .background(bgColor)
        .clipShape(RoundedRectangle(cornerRadius: Radius.standard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.standard, style: .continuous)
                .stroke(themeManager.palette.borderCrisp.opacity(0.3), lineWidth: Border.thin)
        )
    }

    // MARK: - Header

    private var headerBar: some View {
        Button(action: {
            withAnimation(Anim.spring) { isExpanded.toggle() }
        }) {
            HStack(spacing: Spacing.md) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(themeManager.palette.textMuted)
                    .frame(width: 12)

                Image(systemName: "doc.text")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(themeManager.palette.effectiveAccent)

                Text(filePath)
                    .font(Typography.captionSmallSemibold)
                    .fontDesign(.monospaced)
                    .foregroundColor(themeManager.palette.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Change badges
                if addedCount > 0 {
                    Text("+\(addedCount)")
                        .font(Typography.microSemibold)
                        .foregroundColor(diffGreen)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 1)
                        .background(diffGreen.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
                if removedCount > 0 {
                    Text("-\(removedCount)")
                        .font(Typography.microSemibold)
                        .foregroundColor(diffRed)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 1)
                        .background(diffRed.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                // Copy diff button (only when expanded)
                if isExpanded {
                    Button(action: copyDiff) {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: copiedDiff ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                            Text(copiedDiff ? "Copied" : "Copy")
                                .font(Typography.micro)
                        }
                        .foregroundColor(copiedDiff ? .accentGreen : themeManager.palette.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.xxl)
            .padding(.vertical, Spacing.lg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func copyDiff() {
        let diffText = diffLines.map { line in
            "\(line.type.prefix) \(line.content)"
        }.joined(separator: "\n")

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diffText, forType: .string)
        #else
        UIPasteboard.general.string = diffText
        #endif

        copiedDiff = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            copiedDiff = false
        }
    }

    // MARK: - Diff Content

    private var diffContent: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { _, line in
                    diffLineView(line)
                }
            }
            .frame(minWidth: 0, alignment: .leading)
        }
        .frame(maxHeight: min(CGFloat(diffLines.count) * 18 + 12, 400))
        .background(bgColor)
    }

    private func diffLineView(_ line: DiffLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Line number gutter
            HStack(spacing: 0) {
                Text(line.oldLineNum.map { "\($0)" } ?? "")
                    .frame(width: 30, alignment: .trailing)
                Text(line.newLineNum.map { "\($0)" } ?? "")
                    .frame(width: 30, alignment: .trailing)
            }
            .font(Typography.codeMicro)
            .foregroundColor(gutterColor)
            .padding(.trailing, Spacing.sm)

            // Change indicator
            Text(line.type.prefix)
                .font(Typography.codeMicro)
                .foregroundColor(line.type.color(diffGreen: diffGreen, diffRed: diffRed))
                .frame(width: 12)

            // Content
            Text(line.content)
                .font(Typography.codeSmall)
                .foregroundColor(line.type == .context ? themeManager.palette.textSecondary : themeManager.palette.textPrimary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .frame(height: 18)
        .padding(.horizontal, Spacing.lg)
        .background(line.type.bgColor(diffGreen: diffGreen, diffRed: diffRed))
    }

    // MARK: - Colors

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.075, blue: 0.095)
            : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    private var gutterColor: Color {
        colorScheme == .dark
            ? Color(red: 0.35, green: 0.35, blue: 0.45)
            : Color(red: 0.6, green: 0.6, blue: 0.7)
    }

    private var diffGreen: Color {
        colorScheme == .dark
            ? Color(red: 0.3, green: 0.8, blue: 0.4)
            : Color(red: 0.15, green: 0.6, blue: 0.25)
    }

    private var diffRed: Color {
        colorScheme == .dark
            ? Color(red: 0.9, green: 0.35, blue: 0.35)
            : Color(red: 0.8, green: 0.2, blue: 0.2)
    }

    // MARK: - Diff Algorithm

    struct DiffLine {
        let type: DiffType
        let content: String
        let oldLineNum: Int?
        let newLineNum: Int?
    }

    enum DiffType {
        case context
        case added
        case removed

        var prefix: String {
            switch self {
            case .context: return " "
            case .added: return "+"
            case .removed: return "-"
            }
        }

        func color(diffGreen: Color, diffRed: Color) -> Color {
            switch self {
            case .context: return .clear
            case .added: return diffGreen
            case .removed: return diffRed
            }
        }

        func bgColor(diffGreen: Color, diffRed: Color) -> Color {
            switch self {
            case .context: return .clear
            case .added: return diffGreen.opacity(0.08)
            case .removed: return diffRed.opacity(0.08)
            }
        }
    }

    private func computeUnifiedDiff(original: String, modified: String) -> [DiffLine] {
        let oldLines = original.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = modified.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        // Simple LCS-based diff
        let lcs = longestCommonSubsequence(oldLines, newLines)
        var result: [DiffLine] = []
        var oi = 0, ni = 0, li = 0
        var oldNum = 1, newNum = 1

        while oi < oldLines.count || ni < newLines.count {
            if li < lcs.count && oi < oldLines.count && ni < newLines.count && oldLines[oi] == lcs[li] && newLines[ni] == lcs[li] {
                result.append(DiffLine(type: .context, content: oldLines[oi], oldLineNum: oldNum, newLineNum: newNum))
                oi += 1; ni += 1; li += 1; oldNum += 1; newNum += 1
            } else {
                if oi < oldLines.count && (li >= lcs.count || oldLines[oi] != lcs[li]) {
                    result.append(DiffLine(type: .removed, content: oldLines[oi], oldLineNum: oldNum, newLineNum: nil))
                    oi += 1; oldNum += 1
                }
                if ni < newLines.count && (li >= lcs.count || newLines[ni] != lcs[li]) {
                    result.append(DiffLine(type: .added, content: newLines[ni], oldLineNum: nil, newLineNum: newNum))
                    ni += 1; newNum += 1
                }
            }
        }

        return result
    }

    private func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [String] {
        let m = a.count, n = b.count
        guard m > 0, n > 0 else { return [] }

        // For very large diffs, use a simplified approach
        if m > 500 || n > 500 {
            return simplifiedLCS(a, b)
        }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack
        var result: [String] = []
        var i = m, j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                result.append(a[i - 1])
                i -= 1; j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return result.reversed()
    }

    /// Simplified LCS for large files — uses line hashing to reduce memory.
    private func simplifiedLCS(_ a: [String], _ b: [String]) -> [String] {
        let bSet = Set(b)
        return a.filter { bSet.contains($0) }
    }
}
