import Foundation

// MARK: - File Operation Tool Execution
// Extracted from ChatViewModel+ToolExecution.swift for maintainability.

extension ChatViewModel {

    // MARK: - File Read/Write/Edit

    func executeReadFile(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        do {
            let content = try String(contentsOfFile: resolved, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")

            if let startLine = args["start_line"] as? Int {
                let endLine = (args["end_line"] as? Int) ?? lines.count
                let start = max(0, startLine - 1)
                let end = min(lines.count, endLine)
                let numberedLines = (start..<end).map { idx in
                    String(format: "%4d | %@", idx + 1, lines[idx])
                }
                return "File: \(resolved) (lines \(startLine)-\(endLine) of \(lines.count))\n" + numberedLines.joined(separator: "\n")
            }

            if lines.count > 500 {
                let numbered = lines.prefix(500).enumerated().map { idx, line in
                    String(format: "%4d | %@", idx + 1, line)
                }
                return "File: \(resolved) (\(lines.count) lines total, showing first 500)\n" + numbered.joined(separator: "\n") + "\n\n[... \(lines.count - 500) more lines. Use start_line/end_line to read specific sections.]"
            }

            let numbered = lines.enumerated().map { idx, line in
                String(format: "%4d | %@", idx + 1, line)
            }
            return "File: \(resolved) (\(lines.count) lines)\n" + numbered.joined(separator: "\n")
        } catch {
            return "Error reading file '\(resolved)': \(error.localizedDescription)"
        }
    }

    func executeBatchReadFiles(_ args: [String: Any]) -> String {
        guard let paths = args["paths"] as? [String] else { return "Error: missing paths array" }
        var results: [String] = []
        for path in paths.prefix(10) {
            let resolved = resolvePath(path)
            do {
                let content = try String(contentsOfFile: resolved, encoding: .utf8)
                let lines = content.components(separatedBy: "\n")
                if lines.count > 200 {
                    let numbered = lines.prefix(200).enumerated().map { idx, line in
                        String(format: "%4d | %@", idx + 1, line)
                    }
                    results.append("=== \(resolved) (\(lines.count) lines, showing first 200) ===\n" + numbered.joined(separator: "\n"))
                } else {
                    let numbered = lines.enumerated().map { idx, line in
                        String(format: "%4d | %@", idx + 1, line)
                    }
                    results.append("=== \(resolved) (\(lines.count) lines) ===\n" + numbered.joined(separator: "\n"))
                }
            } catch {
                results.append("=== \(resolved) === Error: \(error.localizedDescription)")
            }
        }
        if paths.count > 10 {
            results.append("[Truncated: only first 10 of \(paths.count) files shown]")
        }
        return results.joined(separator: "\n\n")
    }

    func executeCreateFile(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String,
              let content = args["content"] as? String else { return "Error: missing path or content" }
        let resolved = resolvePath(path)
        guard !FileManager.default.fileExists(atPath: resolved) else {
            return "Error: file already exists at '\(resolved)'. Use write_file to overwrite or edit_file to modify."
        }
        do {
            let url = URL(fileURLWithPath: resolved)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            let lineCount = content.components(separatedBy: "\n").count
            return "Created \(resolved) (\(lineCount) lines, \(content.count) chars)"
        } catch {
            return "Error creating file: \(error.localizedDescription)"
        }
    }

    func executeWriteFile(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String,
              let content = args["content"] as? String else { return "Error: missing path or content" }
        let resolved = resolvePath(path)
        do {
            let url = URL(fileURLWithPath: resolved)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            let lineCount = content.components(separatedBy: "\n").count
            return "Written \(resolved) (\(lineCount) lines, \(content.count) chars)"
        } catch {
            return "Error writing file: \(error.localizedDescription)"
        }
    }

    func executeEditFile(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String,
              let oldContent = args["old_content"] as? String,
              let newContent = args["new_content"] as? String else {
            return "Error: missing path, old_content, or new_content"
        }
        let replaceAll = args["replace_all"] as? Bool ?? false
        let resolved = resolvePath(path)
        do {
            var fileContent = try String(contentsOfFile: resolved, encoding: .utf8)
            let occurrences = fileContent.components(separatedBy: oldContent).count - 1

            if occurrences > 1 && !replaceAll {
                return "Error: old_content matches \(occurrences) locations in \(resolved). Include more surrounding lines to make it unique, or pass replace_all: true to replace every occurrence."
            }

            if occurrences >= 1 {
                fileContent = fileContent.replacingOccurrences(of: oldContent, with: newContent)
                try fileContent.write(toFile: resolved, atomically: true, encoding: .utf8)
                let newLineCount = fileContent.components(separatedBy: "\n").count
                return "Edited \(resolved) (\(occurrences) replacement\(occurrences == 1 ? "" : "s"), \(newLineCount) lines total)"
            }

            // Whitespace-tolerant fallback: slide a window over the file comparing
            // per-line trimmed content. Applied ONLY on exactly one match; the
            // replacement lines are spliced VERBATIM (no re-indent guessing).
            let fileLines = fileContent.components(separatedBy: "\n")
            let searchLines = oldContent.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            if !searchLines.isEmpty && searchLines.count <= fileLines.count {
                var matchStarts: [Int] = []
                for start in 0...(fileLines.count - searchLines.count) {
                    var allMatch = true
                    for offset in 0..<searchLines.count where fileLines[start + offset].trimmingCharacters(in: .whitespaces) != searchLines[offset] {
                        allMatch = false
                        break
                    }
                    if allMatch { matchStarts.append(start) }
                }
                if matchStarts.count == 1, let start = matchStarts.first {
                    var updatedLines = fileLines
                    updatedLines.replaceSubrange(start..<(start + searchLines.count), with: newContent.components(separatedBy: "\n"))
                    try updatedLines.joined(separator: "\n").write(toFile: resolved, atomically: true, encoding: .utf8)
                    return "Edited \(resolved) via whitespace-tolerant match at lines \(start + 1)-\(start + searchLines.count) — the exact old_content was not found, so verify the result with read_file."
                }
                if matchStarts.count > 1 {
                    return "Error: old_content matches \(matchStarts.count) locations (whitespace-tolerant) in \(resolved). Include more surrounding lines to make it unique."
                }
            }

            // Near-miss hints (kept as the final fallback).
            if let firstSearchLine = oldContent.components(separatedBy: "\n").first {
                let matches = fileLines.enumerated().filter { $0.element.contains(firstSearchLine.trimmingCharacters(in: .whitespaces)) }
                if !matches.isEmpty {
                    let locations = matches.prefix(3).map { "line \($0.offset + 1)" }.joined(separator: ", ")
                    return "Error: exact old_content not found, but similar content exists at \(locations). Check whitespace/indentation and try again with the exact content."
                }
            }
            return "Error: old_content not found in \(resolved). Use read_file to verify the current content first."
        } catch {
            return "Error editing file: \(error.localizedDescription)"
        }
    }

    // MARK: - Directory & Search

    func executeListDirectory(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        let recursive = args["recursive"] as? Bool ?? false
        let showHidden = args["show_hidden"] as? Bool ?? false

        do {
            let fm = FileManager.default
            let items: [String]
            if recursive {
                guard let enumerator = fm.enumerator(atPath: resolved) else {
                    return "Error: cannot enumerate directory"
                }
                var all: [String] = []
                while let item = enumerator.nextObject() as? String {
                    if !showHidden && item.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
                        continue
                    }
                    if item.contains("node_modules/") || item.contains(".git/") { continue }
                    all.append(item)
                    if all.count >= 500 { break }
                }
                items = all.sorted()
            } else {
                items = try fm.contentsOfDirectory(atPath: resolved)
                    .filter { showHidden || !$0.hasPrefix(".") }
                    .sorted()
            }

            var output: [String] = ["Directory: \(resolved) (\(items.count) items)"]
            for item in items {
                let fullPath = (resolved as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                let attrs = try? fm.attributesOfItem(atPath: fullPath)
                let size = attrs?[.size] as? UInt64 ?? 0
                let icon = isDir.boolValue ? "📁" : "📄"
                let sizeStr = isDir.boolValue ? "" : " (\(formatFileSize(size)))"
                output.append("\(icon) \(item)\(sizeStr)")
            }
            return output.joined(separator: "\n")
        } catch {
            return "Error listing directory: \(error.localizedDescription)"
        }
    }

    func executeTreeView(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        let maxDepth = args["max_depth"] as? Int ?? 4
        return await runProcess(
            executablePath: "/usr/bin/find",
            arguments: [resolved, "-maxdepth", "\(maxDepth)", "-not", "-path", "*/.git/*", "-not", "-path", "*/node_modules/*", "-not", "-path", "*/__pycache__/*", "-not", "-path", "*/.build/*", "-not", "-name", ".DS_Store"],
            cwd: nil,
            stdoutLimitLines: 200
        )
    }

    func executeGrepSearch(_ args: [String: Any]) async -> String {
        guard let query = args["query"] as? String,
              let path = args["path"] as? String else {
            return "Error: missing query or path"
        }
        let resolved = resolvePath(path)
        let isRegex = args["is_regex"] as? Bool ?? false
        var grepArgs = ["-rn", "--color=never"]
        if let include = args["include"] as? String, !include.isEmpty {
            grepArgs.append(contentsOf: ["--include", include])
        }
        grepArgs.append(contentsOf: ["--exclude-dir=.git", "--exclude-dir=node_modules", "--exclude-dir=.build", "--exclude-dir=__pycache__"])
        grepArgs.append(isRegex ? "-E" : "-F")
        grepArgs.append(query)
        grepArgs.append(resolved)
        return await runProcess(executablePath: "/usr/bin/grep", arguments: grepArgs, cwd: nil, stdoutLimitLines: 100)
    }

    func executeFindAndReplace(_ args: [String: Any]) async -> String {
        guard let directory = args["directory"] as? String,
              let find = args["find"] as? String,
              let replace = args["replace"] as? String else {
            return "Error: missing directory, find, or replace"
        }
        let resolved = resolvePath(directory)
        let include = args["include"] as? String
        let dryRun = args["dry_run"] as? Bool ?? false

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: resolved) else {
            return "Error: cannot access directory"
        }

        var modified: [(String, Int)] = []
        var errors: [String] = []

        while let item = enumerator.nextObject() as? String {
            if item.contains(".git/") || item.contains("node_modules/") || item.contains(".build/") { continue }
            if let include = include {
                let ext = "*." + (item as NSString).pathExtension
                if ext != include && !item.hasSuffix(include.replacingOccurrences(of: "*", with: "")) { continue }
            }

            let fullPath = (resolved as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            if isDir.boolValue { continue }

            do {
                let content = try String(contentsOfFile: fullPath, encoding: .utf8)
                let count = content.components(separatedBy: find).count - 1
                if count > 0 {
                    if !dryRun {
                        let updated = content.replacingOccurrences(of: find, with: replace)
                        try updated.write(toFile: fullPath, atomically: true, encoding: .utf8)
                    }
                    modified.append((item, count))
                }
            } catch {
                errors.append("\(item): \(error.localizedDescription)")
            }
        }

        if modified.isEmpty {
            return "No occurrences of '\(find)' found in \(resolved)"
        }

        let totalReplacements = modified.reduce(0) { $0 + $1.1 }
        var result = dryRun ? "[DRY RUN] " : ""
        result += "Replaced '\(find)' → '\(replace)' in \(modified.count) file(s), \(totalReplacements) total occurrence(s):\n"
        for (file, count) in modified {
            result += "  \(file): \(count) replacement(s)\n"
        }
        if !errors.isEmpty {
            result += "\nErrors:\n" + errors.map { "  \($0)" }.joined(separator: "\n")
        }
        return result
    }

    // MARK: - File Helpers

    func executeAppendFile(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String, let content = args["content"] as? String else {
            return "Error: missing path or content"
        }
        let resolved = resolvePath(path)
        do {
            let url = URL(fileURLWithPath: resolved)
            var existing = ""
            if FileManager.default.fileExists(atPath: resolved) {
                existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            try (existing + content).write(to: url, atomically: true, encoding: .utf8)
            return "Appended \(content.count) characters to \(resolved)"
        } catch {
            return "Error appending: \(error.localizedDescription)"
        }
    }

    func executeCreateDirectory(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        do {
            try FileManager.default.createDirectory(atPath: resolved, withIntermediateDirectories: true)
            return "Created directory: \(resolved)"
        } catch {
            return "Error creating directory: \(error.localizedDescription)"
        }
    }

    func executeCompressFiles(_ args: [String: Any]) async -> String {
        guard let paths = args["paths"] as? [String], let output = args["output"] as? String else {
            return "Error: missing paths or output"
        }
        let cwd = workingDirectory.isEmpty ? nil : workingDirectory
        let resolvedPaths = paths.map { resolvePath($0) }
        let resolvedOutput = resolvePath(output)
        let pathsArg = resolvedPaths.map { $0.replacingOccurrences(of: "'", with: "'\\''") }.joined(separator: " ")
        return await runShellCommand("zip -r '\(resolvedOutput.replacingOccurrences(of: "'", with: "'\\''"))' \(pathsArg)", cwd: cwd, timeoutSeconds: 120)
    }

    func executeExtractArchive(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String, let dest = args["destination"] as? String else {
            return "Error: missing path or destination"
        }
        let resolvedPath = resolvePath(path)
        let resolvedDest = resolvePath(dest)
        let cmd = (resolvedPath as NSString).pathExtension.lowercased() == "zip"
            ? "unzip -o '\(resolvedPath.replacingOccurrences(of: "'", with: "'\\''"))' -d '\(resolvedDest.replacingOccurrences(of: "'", with: "'\\''"))'"
            : "tar -xf '\(resolvedPath.replacingOccurrences(of: "'", with: "'\\''"))' -C '\(resolvedDest.replacingOccurrences(of: "'", with: "'\\''"))'"
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 60)
    }

    func executeMoveFile(_ args: [String: Any]) -> String {
        guard let source = args["source"] as? String,
              let dest = args["destination"] as? String else {
            return "Error: missing source or destination"
        }
        let srcResolved = resolvePath(source)
        let dstResolved = resolvePath(dest)
        do {
            let dstURL = URL(fileURLWithPath: dstResolved)
            if dstURL.pathExtension.isEmpty {
                try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            if FileManager.default.fileExists(atPath: dstResolved) {
                try FileManager.default.removeItem(atPath: dstResolved)
            }
            try FileManager.default.moveItem(atPath: srcResolved, toPath: dstResolved)
            return "Moved: \(srcResolved) → \(dstResolved)"
        } catch {
            return "Error moving: \(error.localizedDescription)"
        }
    }

    func executeCopyFile(_ args: [String: Any]) -> String {
        guard let source = args["source"] as? String,
              let dest = args["destination"] as? String else {
            return "Error: missing source or destination"
        }
        let srcResolved = resolvePath(source)
        let dstResolved = resolvePath(dest)
        let overwrite = args["overwrite"] as? Bool ?? false
        do {
            if FileManager.default.fileExists(atPath: dstResolved) && !overwrite {
                return "Error: destination exists. Set overwrite: true to replace."
            }
            if FileManager.default.fileExists(atPath: dstResolved) {
                try FileManager.default.removeItem(atPath: dstResolved)
            }
            let dstURL = URL(fileURLWithPath: dstResolved)
            try FileManager.default.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(atPath: srcResolved, toPath: dstResolved)
            return "Copied: \(srcResolved) → \(dstResolved)"
        } catch {
            return "Error copying: \(error.localizedDescription)"
        }
    }

    func executeFileInfo(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: resolved) else {
            return "Path does not exist: \(resolved)"
        }
        var isDir: ObjCBool = false
        fm.fileExists(atPath: resolved, isDirectory: &isDir)
        do {
            let attrs = try fm.attributesOfItem(atPath: resolved)
            let size = attrs[.size] as? UInt64 ?? 0
            let mod = attrs[.modificationDate] as? Date
            let ext = (resolved as NSString).pathExtension
            var out = "path: \(resolved)\nis_directory: \(isDir.boolValue)\nsize: \(formatFileSize(size))"
            if let mod = mod {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                out += "\nmodified: \(formatter.string(from: mod))"
            }
            if !ext.isEmpty {
                out += "\nextension: \(ext)"
            }
            return out
        } catch {
            return "Error reading attributes: \(error.localizedDescription)"
        }
    }

    func executePathExists(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: resolved)
        var isDir: ObjCBool = false
        if exists {
            fm.fileExists(atPath: resolved, isDirectory: &isDir)
        }
        return "exists: \(exists)\nis_directory: \(isDir.boolValue)"
    }

    func executeCountLines(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        do {
            let content = try String(contentsOfFile: resolved, encoding: .utf8)
            let lines = content.components(separatedBy: .newlines)
            let count = lines.count
            let lastEmpty = lines.last?.isEmpty ?? true
            return "\(resolved): \(count) lines (including trailing newline: \(lastEmpty))"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func executeBackupFile(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        let suffix = (args["suffix"] as? String) ?? ".bak"
        let backup = resolved + suffix
        do {
            if FileManager.default.fileExists(atPath: backup) { try FileManager.default.removeItem(atPath: backup) }
            try FileManager.default.copyItem(atPath: resolved, toPath: backup)
            return "Backed up to \(backup)"
        } catch { return "Error: \(error.localizedDescription)" }
    }
}
