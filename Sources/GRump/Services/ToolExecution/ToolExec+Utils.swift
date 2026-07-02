import Foundation

// MARK: - Utility Tool Execution
// Extracted from ChatViewModel+ToolExecution.swift for maintainability.

extension ChatViewModel {

    // MARK: - Data & Utility Tools

    func executeGetCurrentTime() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    func executeFormatDate(_ args: [String: Any]) -> String {
        guard let dateStr = args["date"] as? String else { return "Error: missing date" }
        let format = (args["format"] as? String) ?? "iso"
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fallback.locale = Locale(identifier: "en_US_POSIX")
        var date = iso.date(from: dateStr) ?? fallback.date(from: dateStr)
        if date == nil, let secs = Double(dateStr), secs > 0 { date = Date(timeIntervalSince1970: secs) }
        guard let d = date else { return "Error: could not parse date" }
        switch format {
        case "unix": return "\(Int(d.timeIntervalSince1970))"
        case "short": return DateFormatter.localizedString(from: d, dateStyle: .short, timeStyle: .short)
        case "long": return DateFormatter.localizedString(from: d, dateStyle: .long, timeStyle: .medium)
        default: return iso.string(from: d)
        }
    }

    func executeCalculate(_ args: [String: Any]) async -> String {
        guard let expr = args["expression"] as? String else { return "Error: missing expression" }
        let safe = expr.replacingOccurrences(of: "'", with: "'\\''")
        return await runShellCommand("echo '\(safe)' | bc -l 2>/dev/null || python3 -c \"import ast; print(ast.literal_eval('\(safe)'))\" 2>/dev/null", cwd: nil, timeoutSeconds: 5)
    }

    func executeCountWords(_ args: [String: Any]) -> String {
        var text: String
        if let t = args["text"] as? String { text = t } else if let p = args["path"] as? String {
            let resolved = resolvePath(p)
            guard let content = try? String(contentsOfFile: resolved, encoding: .utf8) else { return "Error: could not read file" }
            text = content
        } else { return "Error: provide text or path" }
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let lines = text.components(separatedBy: .newlines)
        return "Words: \(words.count)\nLines: \(lines.count)\nCharacters: \(text.count)"
    }

    func executeExtractUrls(_ args: [String: Any]) -> String {
        var text: String
        if let t = args["text"] as? String { text = t } else if let p = args["path"] as? String {
            let resolved = resolvePath(p)
            guard let content = try? String(contentsOfFile: resolved, encoding: .utf8) else { return "Error: could not read file" }
            text = content
        } else { return "Error: provide text or path" }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        var urls: [String] = []
        detector?.enumerateMatches(in: text, range: NSRange(text.startIndex..., in: text)) { m, _, _ in
            if let url = m?.url?.absoluteString { urls.append(url) }
        }
        return urls.isEmpty ? "No URLs found" : urls.joined(separator: "\n")
    }

    func executeJsonParse(_ args: [String: Any]) -> String {
        guard let json = args["json"] as? String else { return "Error: missing json" }
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) else {
            return "Error: invalid JSON"
        }
        return String(data: pretty, encoding: .utf8) ?? ""
    }

    func executeYamlParse(_ args: [String: Any]) async -> String {
        var path: String?
        if let p = args["path"] as? String { path = resolvePath(p) } else if let y = args["yaml"] as? String {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".yaml")
            try? y.write(to: tmp, atomically: true, encoding: .utf8)
            path = tmp.path
        }
        guard let fp = path, FileManager.default.fileExists(atPath: fp) else { return "Error: provide yaml or path" }
        let safe = fp.replacingOccurrences(of: "'", with: "'\\''")
        return await runShellCommand("python3 -c 'import yaml,sys; print(yaml.dump(yaml.safe_load(open(sys.argv[1]))))' '\(safe)' 2>/dev/null || ruby -r yaml -e 'puts YAML.load_file(ARGV[0]).to_yaml' '\(safe)' 2>/dev/null", cwd: nil, timeoutSeconds: 5)
    }

    func executeDiffFiles(_ args: [String: Any]) async -> String {
        guard let a = args["path_a"] as? String, let b = args["path_b"] as? String else { return "Error: missing path_a or path_b" }
        let pa = resolvePath(a).replacingOccurrences(of: "'", with: "'\\''")
        let pb = resolvePath(b).replacingOccurrences(of: "'", with: "'\\''")
        return await runShellCommand("diff '\(pa)' '\(pb)' 2>/dev/null || true", cwd: nil, timeoutSeconds: 10)
    }

    func executeFileHash(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let resolved = resolvePath(path)
        guard FileManager.default.fileExists(atPath: resolved) else { return "Error: file not found" }
        let algo = (args["algorithm"] as? String)?.lowercased() ?? "sha256"
        let cmd = algo == "md5" ? "md5 -q '\(resolved.replacingOccurrences(of: "'", with: "'\\''"))'" : "shasum -a 256 '\(resolved.replacingOccurrences(of: "'", with: "'\\''"))' | cut -d' ' -f1"
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 10)
    }

    func executeHashString(_ args: [String: Any]) async -> String {
        guard let text = args["text"] as? String else { return "Error: missing text" }
        let algo = (args["algorithm"] as? String)?.lowercased() ?? "sha256"
        let safe = text.replacingOccurrences(of: "'", with: "'\\''")
        let cmd = algo == "md5"
            ? "echo -n '\(safe)' | md5 -q 2>/dev/null || echo -n '\(safe)' | openssl dgst -md5 -binary | xxd -p"
            : "echo -n '\(safe)' | shasum -a 256 | cut -d' ' -f1"
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 5)
    }

    func executeBase64Encode(_ args: [String: Any]) -> String {
        guard let text = args["text"] as? String else { return "Error: missing text" }
        guard let data = text.data(using: .utf8) else { return "Error: could not encode text" }
        return data.base64EncodedString()
    }

    func executeBase64Decode(_ args: [String: Any]) -> String {
        guard let text = args["text"] as? String else { return "Error: missing text" }
        guard let data = Data(base64Encoded: text) else { return "Error: invalid Base64" }
        return String(data: data, encoding: .utf8) ?? "Error: decoded data is not valid UTF-8"
    }

    func executeGenerateUuid() -> String {
        return UUID().uuidString
    }

    func executeGetFileType(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else { return "Error: missing path" }
        _ = resolvePath(path)
        let ext = (path as NSString).pathExtension.lowercased()
        var mime = "application/octet-stream"
        switch ext {
        case "txt", "md": mime = "text/plain"
        case "html", "htm": mime = "text/html"
        case "json": mime = "application/json"
        case "png": mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        case "gif": mime = "image/gif"
        case "pdf": mime = "application/pdf"
        case "swift": mime = "text/x-swift"
        case "py": mime = "text/x-python"
        case "js": mime = "text/javascript"
        case "ts": mime = "text/typescript"
        default: break
        }
        return "Extension: \(ext)\nMIME: \(mime)"
    }

    func executeDetectLanguage(_ args: [String: Any]) -> String {
        guard let path = args["path"] as? String else { return "Error: missing path" }
        let ext = (path as NSString).pathExtension.lowercased()
        let lang: String
        switch ext {
        case "swift": lang = "Swift"
        case "py": lang = "Python"
        case "js": lang = "JavaScript"
        case "ts": lang = "TypeScript"
        case "rs": lang = "Rust"
        case "go": lang = "Go"
        case "java": lang = "Java"
        case "kt": lang = "Kotlin"
        case "rb": lang = "Ruby"
        case "php": lang = "PHP"
        case "c": lang = "C"
        case "cpp", "cc", "cxx": lang = "C++"
        case "h", "hpp": lang = "C/C++ Header"
        case "json": lang = "JSON"
        case "yaml", "yml": lang = "YAML"
        case "md": lang = "Markdown"
        case "html", "htm": lang = "HTML"
        case "css": lang = "CSS"
        case "sh", "bash": lang = "Shell"
        default: lang = "Unknown"
        }
        return "Language: \(lang) (from extension .\(ext))"
    }

    func executeGetProcessInfo(_ args: [String: Any]) async -> String {
        guard let pid = args["pid"] as? Int else { return "Error: missing pid" }
        return await runShellCommand("ps -p \(pid) -o pid,ppid,state,command 2>/dev/null || echo 'Process not found'", cwd: nil, timeoutSeconds: 5)
    }
}
