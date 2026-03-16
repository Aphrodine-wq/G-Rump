import SwiftUI

// MARK: - Block Parsing Extension

extension MarkdownTextView {

    // MARK: - Block Types

    enum Block {
        case codeBlock(language: String, code: String)
        case streamingCodeBlock(language: String, code: String)
        case paragraph(String)
        case header(Int, String)
        case listItem(indent: Int, ordered: Bool, number: Int, content: String)
        case taskListItem(indent: Int, checked: Bool, content: String)
        case blockquote(String)
        case horizontalRule
        case table(headers: [String], rows: [[String]])
        case collapsibleSection(summary: String, content: String, isOpen: Bool)
        case image(alt: String, url: String)
    }

    // MARK: - Parsing API

    /// Static version for background thread use (no self capture needed).
    nonisolated static func parseBlocksStatic(_ text: String) -> [Block] {
        parseBlocksImpl(text)
    }

    func parseBlocks(_ text: String) -> [Block] {
        Self.parseBlocksImpl(text)
    }

    // MARK: - Core Parser

    /// Pure function that converts a markdown string into an array of typed blocks.
    /// Handles fenced code blocks, collapsible sections, horizontal rules, headers,
    /// blockquotes, tables, ordered/unordered lists, and paragraph merging.
    nonisolated static func parseBlocksImpl(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0

        while i < lines.count {
            let line = lines[i]

            // Fenced code block
            if line.hasPrefix("```") {
                let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                var foundClosing = false
                while i < lines.count {
                    if lines[i].hasPrefix("```") {
                        foundClosing = true
                        i += 1 // Skip closing ```
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                if foundClosing {
                    blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                } else {
                    // Unclosed code block = still streaming
                    blocks.append(.streamingCodeBlock(language: language, code: codeLines.joined(separator: "\n")))
                }
                continue
            }

            // Collapsible section: <details> ... </details>
            let trimmedForDetails = line.trimmingCharacters(in: .whitespaces)
            if trimmedForDetails.lowercased().hasPrefix("<details") {
                var summaryText = "Details"
                var contentLines: [String] = []
                i += 1
                // Look for <summary>
                if i < lines.count {
                    let summaryLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if summaryLine.lowercased().hasPrefix("<summary>") {
                        summaryText = summaryLine
                            .replacingOccurrences(of: "<summary>", with: "", options: .caseInsensitive)
                            .replacingOccurrences(of: "</summary>", with: "", options: .caseInsensitive)
                            .trimmingCharacters(in: .whitespaces)
                        i += 1
                    }
                }
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("</details") {
                    contentLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 } // Skip </details>
                let isOpen = trimmedForDetails.lowercased().contains("open")
                blocks.append(.collapsibleSection(summary: summaryText, content: contentLines.joined(separator: "\n"), isOpen: isOpen))
                continue
            }

            // Horizontal rule: ---, ***, ___
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            if trimmedLine.count >= 3 && (
                trimmedLine.allSatisfy({ $0 == "-" }) ||
                trimmedLine.allSatisfy({ $0 == "*" }) ||
                trimmedLine.allSatisfy({ $0 == "_" })
            ) {
                blocks.append(.horizontalRule)
                i += 1; continue
            }

            // Headers (H1-H6)
            if line.hasPrefix("###### ") {
                blocks.append(.header(6, String(line.dropFirst(7))))
                i += 1; continue
            }
            if line.hasPrefix("##### ") {
                blocks.append(.header(5, String(line.dropFirst(6))))
                i += 1; continue
            }
            if line.hasPrefix("#### ") {
                blocks.append(.header(4, String(line.dropFirst(5))))
                i += 1; continue
            }
            if line.hasPrefix("### ") {
                blocks.append(.header(3, String(line.dropFirst(4))))
                i += 1; continue
            }
            if line.hasPrefix("## ") {
                blocks.append(.header(2, String(line.dropFirst(3))))
                i += 1; continue
            }
            if line.hasPrefix("# ") {
                blocks.append(.header(1, String(line.dropFirst(2))))
                i += 1; continue
            }

            // Blockquote
            if line.hasPrefix("> ") || line == ">" {
                var quoteLines: [String] = []
                while i < lines.count && (lines[i].hasPrefix("> ") || lines[i] == ">") {
                    let content = lines[i].hasPrefix("> ") ? String(lines[i].dropFirst(2)) : ""
                    quoteLines.append(content)
                    i += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: " ")))
                continue
            }

            // Table detection: line with pipes
            if line.contains("|") && i + 1 < lines.count {
                let nextLine = lines[i + 1]
                // Check if next line is a separator row (contains |---| pattern)
                if nextLine.contains("|") && nextLine.contains("-") {
                    let headerCells = parsePipeLine(line)
                    if headerCells.count > 1 {
                        i += 2 // Skip header + separator
                        var dataRows: [[String]] = []
                        while i < lines.count && lines[i].contains("|") {
                            let cells = parsePipeLine(lines[i])
                            if !cells.isEmpty {
                                dataRows.append(cells)
                            }
                            i += 1
                        }
                        blocks.append(.table(headers: headerCells, rows: dataRows))
                        continue
                    }
                }
            }

            // Image: ![alt](url)
            if let imgMatch = trimmedLine.range(of: #"^!\[([^\]]*)\]\(([^)]+)\)$"#, options: .regularExpression) {
                let imgText = String(trimmedLine[imgMatch])
                if let altEnd = imgText.firstIndex(of: "]"),
                   let urlStart = imgText.range(of: "](")?.upperBound,
                   let urlEnd = imgText.lastIndex(of: ")") {
                    let alt = String(imgText[imgText.index(imgText.startIndex, offsetBy: 2)..<altEnd])
                    let url = String(imgText[urlStart..<urlEnd])
                    blocks.append(.image(alt: alt, url: url))
                    i += 1; continue
                }
            }

            // Task list items: - [ ] or - [x] or * [ ] or * [x]
            if let taskMatch = line.range(of: #"^(\s*)[-*]\s\[([ xX])\]\s"#, options: .regularExpression) {
                let prefix = String(line[taskMatch])
                let indent = prefix.prefix(while: { $0 == " " }).count / 2
                let checked = prefix.contains("x") || prefix.contains("X")
                let content = String(line[taskMatch.upperBound...])
                blocks.append(.taskListItem(indent: indent, checked: checked, content: content))
                i += 1; continue
            }

            // List items (unordered)
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                let content = String(line.dropFirst(2))
                blocks.append(.listItem(indent: 0, ordered: false, number: 0, content: content))
                i += 1; continue
            }

            // Indented list items
            if let indentMatch = line.range(of: #"^(\s+)[-*]\s"#, options: .regularExpression) {
                let indentStr = line[indentMatch].filter({ $0 == " " })
                let indent = indentStr.count / 2
                let content = String(line[indentMatch.upperBound...])
                blocks.append(.listItem(indent: indent, ordered: false, number: 0, content: content))
                i += 1; continue
            }

            // Numbered list
            if let range = line.range(of: #"^(\s*)(\d+)\.\s"#, options: .regularExpression) {
                let prefix = String(line[range])
                let indent = prefix.prefix(while: { $0 == " " }).count / 2
                let numberStr = prefix.trimmingCharacters(in: .whitespaces).dropLast() // remove trailing dot+space chars
                let number = Int(numberStr.filter(\.isNumber)) ?? 1
                blocks.append(.listItem(indent: indent, ordered: true, number: number, content: String(line[range.upperBound...])))
                i += 1; continue
            }

            // Empty line
            if trimmedLine.isEmpty {
                i += 1; continue
            }

            // Paragraph: merge consecutive non-special lines
            var paragraphLines: [String] = [line]
            i += 1
            while i < lines.count {
                let nextLine = lines[i]
                let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                // Stop merging at special lines
                if nextTrimmed.isEmpty || nextLine.hasPrefix("```") || nextLine.hasPrefix("#") ||
                   nextLine.hasPrefix("- ") || nextLine.hasPrefix("* ") || nextLine.hasPrefix("> ") ||
                   (nextTrimmed.count >= 3 && (nextTrimmed.allSatisfy({ $0 == "-" }) || nextTrimmed.allSatisfy({ $0 == "*" }) || nextTrimmed.allSatisfy({ $0 == "_" }))) ||
                   nextLine.range(of: #"^\s*\d+\.\s"#, options: .regularExpression) != nil ||
                   nextLine.range(of: #"^\s+[-*]\s"#, options: .regularExpression) != nil ||
                   (nextLine.contains("|") && i + 1 < lines.count && lines[i + 1].contains("|") && lines[i + 1].contains("-")) {
                    break
                }
                paragraphLines.append(nextLine)
                i += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
        }

        return blocks
    }

    // MARK: - Pipe Line Parser (Tables)

    nonisolated static func parsePipeLine(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let stripped = trimmed.hasPrefix("|") ? String(trimmed.dropFirst()) : trimmed
        let end = stripped.hasSuffix("|") ? String(stripped.dropLast()) : stripped
        return end.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Block Length Estimation

    nonisolated static func blockLengthStatic(_ block: Block) -> Int {
        switch block {
        case .codeBlock(_, let code):
            return code.count + 6 // ```\n...\n```
        case .paragraph(let content):
            return content.count
        case .header(_, let content):
            return content.count + 2 // #\n
        case .listItem(_, _, _, let content):
            return content.count + 2 // •\n
        case .blockquote(let content):
            return content.count + 2 // >\n
        case .horizontalRule:
            return 3 // ---
        case .table(let headers, let rows):
            let headerLength = headers.joined().count
            let rowLength = rows.flatMap { $0 }.joined().count
            return headerLength + rowLength
        case .streamingCodeBlock(_, let code):
            return code.count + 3 // ```\n... (no closing)
        case .collapsibleSection(_, let content, _):
            return content.count + 20 // <details>...</details>
        case .taskListItem(_, _, let content):
            return content.count + 6 // - [ ] \n
        case .image(_, let url):
            return url.count + 6 // ![]()\n
        }
    }
}
