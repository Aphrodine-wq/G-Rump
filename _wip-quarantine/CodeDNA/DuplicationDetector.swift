import Foundation

// MARK: - Duplication Detector

/// Detects code duplication across files using token-based normalization
/// and Rabin-Karp rolling hash for efficient substring matching.
final class DuplicationDetector: Sendable {

    // MARK: - Configuration

    private let defaultMinLines: Int = 6
    private let defaultMinTokens: Int = 25

    /// Patterns to ignore as trivial duplications.
    private let trivialPatterns: Set<String> = [
        "import", "return", "break", "continue", "pass", "default:",
        "case", "}", "{", "};", "else {", "} else {"
    ]

    // MARK: - Detection

    /// Detect code duplication across all provided files.
    func detectDuplication(in filePaths: [String], basePath: String,
                           minLines: Int? = nil) async -> [DuplicationCluster] {
        let threshold = minLines ?? defaultMinLines

        // Step 1: Normalize all files in parallel
        let normalizedFiles = await withTaskGroup(of: (String, [NormalizedLine])?.self) { group in
            for path in filePaths {
                group.addTask {
                    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
                    let ext = (path as NSString).pathExtension
                    let language = Language.from(extension: ext)
                    let relativePath = self.makeRelativePath(path, from: basePath)
                    let normalized = self.normalizeSource(content, language: language)
                    return (relativePath, normalized)
                }
            }

            var results: [(String, [NormalizedLine])] = []
            for await result in group {
                if let r = result {
                    results.append(r)
                }
            }
            return results
        }

        // Step 2: Build hash index using rolling hash windows
        var hashIndex: [UInt64: [(file: String, startLine: Int, lines: [NormalizedLine])]] = [:]

        for (filePath, normalizedLines) in normalizedFiles {
            let windows = rollingHashWindows(normalizedLines, windowSize: threshold)

            for window in windows {
                hashIndex[window.hash, default: []].append((
                    file: filePath,
                    startLine: window.startIndex,
                    lines: Array(normalizedLines[window.startIndex..<min(window.startIndex + threshold, normalizedLines.count)])
                ))
            }
        }

        // Step 3: Group matches into clusters
        var clusters: [String: [CodeFragment]] = [:]  // hash -> fragments

        for (hash, matches) in hashIndex {
            guard matches.count > 1 else { continue }

            // Verify actual content match (not just hash collision)
            let verified = verifyMatches(matches, windowSize: threshold)

            for group in verified {
                guard group.count > 1 else { continue }

                let hashKey = "\(hash)_\(group[0].lines.map(\.normalized).joined())"
                let contentHashStr = String(hashKey.hashValue, radix: 16)

                for match in group {
                    let startLine = match.startLine + 1  // 1-indexed
                    let endLine = startLine + threshold - 1
                    let content = match.lines.map(\.original).joined(separator: "\n")

                    let fragment = CodeFragment(
                        filePath: match.file,
                        startLine: startLine,
                        endLine: endLine,
                        content: content
                    )

                    clusters[contentHashStr, default: []].append(fragment)
                }
            }
        }

        // Step 4: Deduplicate fragments within clusters
        var result: [DuplicationCluster] = []

        for (hash, fragments) in clusters {
            let uniqueFragments = deduplicateFragments(fragments)
            guard uniqueFragments.count > 1 else { continue }

            // Filter trivial clusters
            if isTrivialDuplication(uniqueFragments) { continue }

            result.append(DuplicationCluster(hash: hash, fragments: uniqueFragments))
        }

        // Step 5: Merge overlapping clusters and sort by impact
        let merged = mergeOverlappingClusters(result)
        return merged.sorted(by: { $0.totalDuplicatedLines > $1.totalDuplicatedLines })
    }

    // MARK: - Source Normalization

    /// Normalize source code for comparison: strip comments, whitespace, and string literals.
    func normalizeSource(_ source: String, language: Language) -> [NormalizedLine] {
        let lines = source.components(separatedBy: .newlines)
        var normalized: [NormalizedLine] = []
        var inBlockComment = false
        let blockDelimiters = language.blockCommentDelimiters

        for (index, line) in lines.enumerated() {
            var trimmed = line.trimmingCharacters(in: .whitespaces)

            // Handle block comments
            if let delimiters = blockDelimiters {
                if inBlockComment {
                    if trimmed.contains(delimiters.end) {
                        inBlockComment = false
                        if let endRange = trimmed.range(of: delimiters.end) {
                            trimmed = String(trimmed[endRange.upperBound...])
                                .trimmingCharacters(in: .whitespaces)
                        }
                    }
                    if trimmed.isEmpty { continue }
                }
                if trimmed.hasPrefix(delimiters.start) {
                    if !trimmed.contains(delimiters.end) {
                        inBlockComment = true
                    }
                    continue
                }
            }

            // Skip line comments
            if trimmed.hasPrefix(language.lineCommentPrefix) { continue }

            // Strip inline comments
            if let commentRange = trimmed.range(of: " \(language.lineCommentPrefix)") {
                trimmed = String(trimmed[..<commentRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
            }

            // Skip empty lines
            if trimmed.isEmpty { continue }

            // Normalize: collapse whitespace, replace string literals
            let norm = normalizeLineContent(trimmed, language: language)

            // Skip trivial lines
            if trivialPatterns.contains(norm) { continue }
            if norm.count < 3 { continue }

            normalized.append(NormalizedLine(
                lineNumber: index,
                original: line.trimmingCharacters(in: .whitespaces),
                normalized: norm
            ))
        }

        return normalized
    }

    /// Normalize a single line: collapse whitespace, replace literals with placeholders.
    private func normalizeLineContent(_ line: String, language: Language) -> String {
        var result = line

        // Replace string literals with placeholder
        result = replaceStringLiterals(result)

        // Replace numeric literals with placeholder
        if let regex = try? NSRegularExpression(pattern: #"\b\d+(\.\d+)?\b"#) {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "NUM"
            )
        }

        // Collapse whitespace
        result = result.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return result.lowercased()
    }

    /// Replace string literals with a placeholder.
    private func replaceStringLiterals(_ source: String) -> String {
        var result = ""
        var inString = false
        var delimiter: Character = "\""
        var prevChar: Character = " "

        for char in source {
            if (char == "\"" || char == "'") && prevChar != "\\" {
                if inString && char == delimiter {
                    inString = false
                    result.append("STR")
                } else if !inString {
                    inString = true
                    delimiter = char
                }
            } else if !inString {
                result.append(char)
            }
            prevChar = char
        }

        return result
    }

    // MARK: - Rolling Hash (Rabin-Karp)

    /// Generate rolling hash values for windows of normalized lines.
    func rollingHashWindows(_ lines: [NormalizedLine], windowSize: Int) -> [(hash: UInt64, startIndex: Int)] {
        guard lines.count >= windowSize else { return [] }

        var results: [(hash: UInt64, startIndex: Int)] = []
        let base: UInt64 = 31
        let modulus: UInt64 = 1_000_000_007

        // Precompute hash for each normalized line
        let lineHashes: [UInt64] = lines.map { line in
            rabinHash(line.normalized, base: base, modulus: modulus)
        }

        // Compute hash for first window
        var windowHash: UInt64 = 0
        var basePower: UInt64 = 1

        for i in 0..<windowSize {
            windowHash = (windowHash &+ lineHashes[i] &* basePower) % modulus
            if i < windowSize - 1 {
                basePower = (basePower &* base) % modulus
            }
        }

        results.append((hash: windowHash, startIndex: 0))

        // Slide the window
        let highPower = basePower
        for i in 1...(lines.count - windowSize) {
            // Remove old hash contribution and add new
            let oldHash = lineHashes[i - 1]
            let newHash = lineHashes[i + windowSize - 1]

            // Rolling: remove first, shift, add last
            windowHash = (windowHash &+ modulus &- oldHash) % modulus
            // Divide by base (multiply by modular inverse, approximated here)
            windowHash = (windowHash &* modularInverse(base, modulus)) % modulus
            windowHash = (windowHash &+ newHash &* highPower) % modulus

            results.append((hash: windowHash, startIndex: i))
        }

        return results
    }

    /// Rabin hash for a string.
    private func rabinHash(_ string: String, base: UInt64, modulus: UInt64) -> UInt64 {
        var hash: UInt64 = 0
        var power: UInt64 = 1

        for char in string.utf8 {
            hash = (hash &+ UInt64(char) &* power) % modulus
            power = (power &* base) % modulus
        }

        return hash
    }

    /// Modular multiplicative inverse using extended Euclidean algorithm.
    private func modularInverse(_ a: UInt64, _ m: UInt64) -> UInt64 {
        // Using Fermat's little theorem: a^(m-2) mod m (for prime m)
        var result: UInt64 = 1
        var base = a % m
        var exp = m - 2

        while exp > 0 {
            if exp % 2 == 1 {
                result = (result &* base) % m
            }
            exp /= 2
            base = (base &* base) % m
        }

        return result
    }

    // MARK: - Match Verification

    /// Verify that hash matches are actual content matches (not collisions).
    private func verifyMatches(_ matches: [(file: String, startLine: Int, lines: [NormalizedLine])],
                               windowSize: Int) -> [[(file: String, startLine: Int, lines: [NormalizedLine])]] {
        var groups: [[(file: String, startLine: Int, lines: [NormalizedLine])]] = []
        var assigned = Set<Int>()

        for i in 0..<matches.count {
            guard !assigned.contains(i) else { continue }

            var group = [matches[i]]
            assigned.insert(i)

            for j in (i + 1)..<matches.count {
                guard !assigned.contains(j) else { continue }

                // Compare normalized content
                let contentA = matches[i].lines.map(\.normalized)
                let contentB = matches[j].lines.map(\.normalized)

                if contentA == contentB {
                    group.append(matches[j])
                    assigned.insert(j)
                }
            }

            if group.count > 1 {
                groups.append(group)
            }
        }

        return groups
    }

    // MARK: - Fragment Deduplication

    /// Remove duplicate fragments (same file, overlapping line ranges).
    private func deduplicateFragments(_ fragments: [CodeFragment]) -> [CodeFragment] {
        var unique: [CodeFragment] = []

        for fragment in fragments {
            let isDuplicate = unique.contains { existing in
                existing.filePath == fragment.filePath
                && existing.startLine == fragment.startLine
                && existing.endLine == fragment.endLine
            }

            if !isDuplicate {
                unique.append(fragment)
            }
        }

        return unique
    }

    // MARK: - Cluster Merging

    /// Merge clusters where fragments overlap.
    private func mergeOverlappingClusters(_ clusters: [DuplicationCluster]) -> [DuplicationCluster] {
        guard clusters.count > 1 else { return clusters }

        var result: [DuplicationCluster] = []
        var merged = Set<Int>()

        for i in 0..<clusters.count {
            guard !merged.contains(i) else { continue }

            var combinedFragments = clusters[i].fragments

            for j in (i + 1)..<clusters.count {
                guard !merged.contains(j) else { continue }

                let hasOverlap = clusters[j].fragments.contains { fragB in
                    combinedFragments.contains { fragA in
                        fragA.filePath == fragB.filePath
                        && fragA.startLine <= fragB.endLine
                        && fragB.startLine <= fragA.endLine
                    }
                }

                if hasOverlap {
                    combinedFragments.append(contentsOf: clusters[j].fragments)
                    merged.insert(j)
                }
            }

            let deduplicated = deduplicateFragments(combinedFragments)
            result.append(DuplicationCluster(
                hash: clusters[i].hash,
                fragments: deduplicated
            ))
        }

        return result
    }

    // MARK: - Trivial Detection

    /// Check if a duplication cluster is trivially not interesting.
    private func isTrivialDuplication(_ fragments: [CodeFragment]) -> Bool {
        guard let first = fragments.first else { return true }

        let lines = first.content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // All import statements
        if lines.allSatisfy({ $0.hasPrefix("import ") || $0.hasPrefix("from ") || $0.hasPrefix("#include") }) {
            return true
        }

        // Simple getter/setter pattern
        if lines.count <= 3 && lines.contains(where: { $0.contains("return self.") || $0.contains("get {") }) {
            return true
        }

        // Only braces and keywords
        let significantLines = lines.filter { $0.count > 5 }
        if significantLines.isEmpty { return true }

        return false
    }

    // MARK: - Statistics

    /// Calculate overall duplication statistics for a set of files.
    func calculateDuplicationStats(clusters: [DuplicationCluster],
                                   totalCodeLines: Int) -> DuplicationStats {
        let totalDuplicated = clusters.reduce(0) { $0 + $1.totalDuplicatedLines }
        let affectedFiles = Set(clusters.flatMap { $0.fragments.map(\.filePath) })

        let percentage: Double
        if totalCodeLines > 0 {
            percentage = Double(totalDuplicated) / Double(totalCodeLines) * 100
        } else {
            percentage = 0
        }

        return DuplicationStats(
            totalClusters: clusters.count,
            totalDuplicatedLines: totalDuplicated,
            duplicationPercentage: percentage,
            affectedFileCount: affectedFiles.count,
            largestCluster: clusters.max(by: { $0.totalDuplicatedLines < $1.totalDuplicatedLines })
        )
    }

    // MARK: - Helpers

    private func makeRelativePath(_ path: String, from base: String) -> String {
        if path.hasPrefix(base) {
            var relative = String(path.dropFirst(base.count))
            if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
            return relative
        }
        return path
    }
}

// MARK: - Supporting Types

struct NormalizedLine: Sendable, Equatable {
    let lineNumber: Int
    let original: String
    let normalized: String
}

struct DuplicationStats: Sendable {
    let totalClusters: Int
    let totalDuplicatedLines: Int
    let duplicationPercentage: Double
    let affectedFileCount: Int
    let largestCluster: DuplicationCluster?

    var description: String {
        "\(totalClusters) clusters, \(totalDuplicatedLines) duplicated lines (\(String(format: "%.1f%%", duplicationPercentage))), \(affectedFileCount) files affected"
    }
}
