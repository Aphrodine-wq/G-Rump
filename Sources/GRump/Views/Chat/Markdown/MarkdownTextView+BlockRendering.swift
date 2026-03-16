import SwiftUI

// MARK: - Block Rendering Extension

extension MarkdownTextView {

    // MARK: - Block View Router

    /// Renders a single parsed `Block` into its corresponding SwiftUI view.
    @ViewBuilder
    func blockView(_ block: Block) -> some View {
        switch block {
        case .codeBlock(let language, let code):
            CodeBlockView(language: language, code: code)

        case .streamingCodeBlock(let language, let code):
            StreamingCodeBlockView(language: language, code: code, isStreaming: true)

        case .paragraph(let content):
            buildInlineText(content)
                .font(Typography.bodyScaled(scale: themeManager.contentSize.scaleFactor))
                .foregroundColor(themeManager.palette.textPrimary)
                .textSelection(.enabled)
                .lineSpacing(Typography.userLineSpacing)

        case .header(let level, let content):
            buildInlineText(content)
                .font(headerFont(level))
                .foregroundColor(themeManager.palette.textPrimary)

        case .listItem(let indent, let ordered, let number, let content):
            listItemView(indent: indent, ordered: ordered, number: number, content: content)

        case .blockquote(let content):
            blockquoteView(content)

        case .horizontalRule:
            Rectangle()
                .fill(themeManager.palette.borderSubtle)
                .frame(height: 1)
                .padding(.vertical, Spacing.sm)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .collapsibleSection(let summary, let content, _):
            CollapsibleSectionView(summary: summary, content: content)

        case .taskListItem(let indent, let checked, let content):
            taskListItemView(indent: indent, checked: checked, content: content)

        case .image(let alt, let url):
            imageView(alt: alt, urlString: url)
        }
    }

    // MARK: - List Item

    private func listItemView(indent: Int, ordered: Bool, number: Int, content: String) -> some View {
        let bodyFont = Typography.bodyScaled(scale: themeManager.contentSize.scaleFactor)
        return HStack(alignment: .top, spacing: Spacing.md) {
            Text(ordered ? "\(number)." : "•")
                .font(bodyFont)
                .foregroundColor(themeManager.palette.effectiveAccentLightVariant)
                .frame(width: ordered ? 20 : 12, alignment: ordered ? .trailing : .center)
            buildInlineText(content)
                .font(bodyFont)
                .foregroundColor(themeManager.palette.textPrimary)
                .lineSpacing(Typography.userLineSpacing * 0.67)
        }
        .padding(.leading, CGFloat(indent) * 20)
    }

    // MARK: - Task List Item

    private func taskListItemView(indent: Int, checked: Bool, content: String) -> some View {
        let bodyFont = Typography.bodyScaled(scale: themeManager.contentSize.scaleFactor)
        return HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(checked ? .accentGreen : themeManager.palette.textMuted)
                .frame(width: 18, alignment: .center)
            buildInlineText(content)
                .font(bodyFont)
                .foregroundColor(checked ? themeManager.palette.textSecondary : themeManager.palette.textPrimary)
                .strikethrough(checked, color: themeManager.palette.textMuted.opacity(0.5))
                .lineSpacing(Typography.userLineSpacing * 0.67)
        }
        .padding(.leading, CGFloat(indent) * 20)
    }

    // MARK: - Image

    @ViewBuilder
    private func imageView(alt: String, urlString: String) -> some View {
        if let url = URL(string: urlString) {
            MarkdownImageLoader(url: url, alt: alt)
                .environmentObject(themeManager)
        } else {
            Text("[\(alt)](\(urlString))")
                .font(Typography.captionSmall)
                .foregroundColor(themeManager.palette.textMuted)
        }
    }

    // MARK: - Blockquote

    private func blockquoteView(_ content: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(themeManager.palette.effectiveAccent.opacity(0.4))
                .frame(width: 3)
            buildInlineText(content)
                .font(Typography.bodyScaled(scale: themeManager.contentSize.scaleFactor))
                .foregroundColor(themeManager.palette.textSecondary)
                .italic()
                .lineSpacing(Typography.userLineSpacing * 0.67)
                .padding(.leading, Spacing.xxl)
        }
    }

    // MARK: - Table

    func tableView(headers: [String], rows: [[String]]) -> some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                ForEach(headers.indices, id: \.self) { i in
                    buildInlineText(headers[i].trimmingCharacters(in: .whitespaces))
                        .font(Typography.captionSmallSemibold)
                        .foregroundColor(themeManager.palette.textPrimary)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(themeManager.palette.bgElevated)

            Divider()

            // Data rows
            ForEach(rows.indices, id: \.self) { rowIdx in
                HStack(spacing: 0) {
                    ForEach(rows[rowIdx].indices, id: \.self) { colIdx in
                        buildInlineText(rows[rowIdx][colIdx].trimmingCharacters(in: .whitespaces))
                            .font(Typography.captionSmall)
                            .foregroundColor(themeManager.palette.textPrimary)
                            .padding(.horizontal, Spacing.lg)
                            .padding(.vertical, Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if rowIdx < rows.count - 1 {
                    Divider()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).stroke(themeManager.palette.borderCrisp, lineWidth: Border.thin))
    }

    // MARK: - Context-Aware Spacing

    /// Calculates the top spacing between two adjacent blocks for visual rhythm.
    func topSpacing(for block: Block, previous: Block?) -> CGFloat {
        guard previous != nil else { return 0 }
        switch block {
        case .header(1, _): return 24
        case .header(2, _): return 20
        case .header(3, _): return 16
        case .header(_, _): return 14
        case .paragraph: return 12
        case .listItem: return 4
        case .codeBlock: return 16
        case .streamingCodeBlock: return 16
        case .blockquote: return 12
        case .horizontalRule: return 16
        case .table: return 16
        case .collapsibleSection: return 12
        case .taskListItem: return 4
        case .image: return 16
        }
    }

    // MARK: - Header Font

    func headerFont(_ level: Int) -> Font {
        switch level {
        case 1: return Typography.heading1
        case 2: return Typography.heading2
        case 3: return Typography.heading3
        case 4: return .system(size: 15, weight: .semibold)
        case 5: return .system(size: 14, weight: .semibold)
        case 6: return .system(size: 13, weight: .medium)
        default: return Typography.bodyLarge
        }
    }
}
