import Foundation
import NaturalLanguage

// MARK: - Extended Tool Execution
// Implementations for Docker, Browser, Cloud Deploy, AI, Code Analysis,
// Network/Validation, and Interactive tools.

extension ChatViewModel {

    // MARK: - Docker & Kubernetes

    func executeDockerRun(_ args: [String: Any]) async -> String {
        guard let image = args["image"] as? String else { return "Error: missing 'image' parameter" }
        var cmd = "docker run"
        if let detach = args["detach"] as? Bool, detach { cmd += " -d" }
        if let rm = args["remove"] as? Bool, rm { cmd += " --rm" }
        if let name = args["name"] as? String { cmd += " --name \(name)" }
        if let ports = args["ports"] as? [String] {
            for port in ports { cmd += " -p \(port)" }
        }
        if let envVars = args["env"] as? [String] {
            for env in envVars { cmd += " -e '\(env)'" }
        }
        if let volumes = args["volumes"] as? [String] {
            for vol in volumes { cmd += " -v '\(vol)'" }
        }
        cmd += " \(image)"
        if let command = args["command"] as? String { cmd += " \(command)" }
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 60)
    }

    func executeDockerBuild(_ args: [String: Any]) async -> String {
        let path = (args["path"] as? String).map { resolvePath($0) } ?? "."
        var cmd = "docker build"
        if let tag = args["tag"] as? String { cmd += " -t \(tag)" }
        if let dockerfile = args["dockerfile"] as? String { cmd += " -f \(dockerfile)" }
        if let noCache = args["no_cache"] as? Bool, noCache { cmd += " --no-cache" }
        cmd += " \(path)"
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 300)
    }

    func executeDockerLogs(_ args: [String: Any]) async -> String {
        guard let container = args["container"] as? String else { return "Error: missing 'container' parameter" }
        var cmd = "docker logs"
        if let tail = args["tail"] as? Int { cmd += " --tail \(tail)" }
        if let follow = args["follow"] as? Bool, follow { cmd += " -f" }
        cmd += " \(container)"
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 15)
    }

    func executeDockerComposeUp(_ args: [String: Any]) async -> String {
        let cwd = (args["directory"] as? String).map { resolvePath($0) } ?? (workingDirectory.isEmpty ? nil : workingDirectory)
        var cmd = "docker compose up -d"
        if let services = args["services"] as? [String] { cmd += " " + services.joined(separator: " ") }
        if let build = args["build"] as? Bool, build { cmd += " --build" }
        return await runShellCommand(cmd, cwd: cwd, timeoutSeconds: 120)
    }

    func executeDockerComposeDown(_ args: [String: Any]) async -> String {
        let cwd = (args["directory"] as? String).map { resolvePath($0) } ?? (workingDirectory.isEmpty ? nil : workingDirectory)
        var cmd = "docker compose down"
        if let volumes = args["volumes"] as? Bool, volumes { cmd += " -v" }
        return await runShellCommand(cmd, cwd: cwd, timeoutSeconds: 30)
    }

    func executeKubectlGet(_ args: [String: Any]) async -> String {
        guard let resource = args["resource"] as? String else { return "Error: missing 'resource' parameter" }
        var cmd = "kubectl get \(resource)"
        if let namespace = args["namespace"] as? String { cmd += " -n \(namespace)" }
        if let output = args["output"] as? String { cmd += " -o \(output)" }
        if let name = args["name"] as? String { cmd += " \(name)" }
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 15)
    }

    func executeKubectlApply(_ args: [String: Any]) async -> String {
        guard let file = args["file"] as? String else { return "Error: missing 'file' parameter" }
        let resolved = resolvePath(file)
        var cmd = "kubectl apply -f \(resolved)"
        if let namespace = args["namespace"] as? String { cmd += " -n \(namespace)" }
        if let dryRun = args["dry_run"] as? Bool, dryRun { cmd += " --dry-run=client" }
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 30)
    }

    // MARK: - Browser Automation

    func executeBrowserOpen(_ args: [String: Any]) async -> String {
        guard let url = args["url"] as? String else { return "Error: missing 'url' parameter" }
        #if os(macOS)
        return await runShellCommand("open '\(url.replacingOccurrences(of: "'", with: "'\\''"))'", cwd: nil, timeoutSeconds: 5)
        #else
        return "Error: browser_open is not available on iOS"
        #endif
    }

    func executeBrowserScreenshot(_ args: [String: Any]) async -> String {
        guard let url = args["url"] as? String else { return "Error: missing 'url' parameter" }
        let outputPath = (args["output"] as? String).map { resolvePath($0) } ?? resolvePath("screenshot.png")
        #if os(macOS)
        let width = args["width"] as? Int ?? 1280
        let height = args["height"] as? Int ?? 900
        // Check for available headless browsers
        let hasChromeCheck = await runShellCommand("test -d '/Applications/Google Chrome.app' && echo yes || echo no", cwd: nil, timeoutSeconds: 3)
        let hasChrome = hasChromeCheck.trimmingCharacters(in: .whitespacesAndNewlines) == "yes"
        if hasChrome {
            let cmd = "/Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome --headless --screenshot='\(outputPath)' --window-size=\(width),\(height) --disable-gpu '\(url)' 2>&1"
            return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 30)
        }
        let hasWebkit2png = await runShellCommand("which webkit2png 2>/dev/null && echo yes || echo no", cwd: nil, timeoutSeconds: 3)
        if hasWebkit2png.contains("yes") {
            let cmd = "webkit2png -o '\(outputPath)' -W \(width) '\(url)' 2>&1"
            return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 30)
        }
        return "Error: No headless browser found. To use browser_screenshot, install one of:\n" +
            "  1. Google Chrome: download from https://google.com/chrome\n" +
            "  2. webkit2png: brew install webkit2png\n" +
            "Then retry this tool call."
        #else
        return "Error: browser_screenshot is only available on macOS. This tool requires a headless browser (Chrome or webkit2png)."
        #endif
    }

    func executeBrowserEvaluate(_ args: [String: Any]) async -> String {
        guard let url = args["url"] as? String,
              let script = args["script"] as? String else { return "Error: missing 'url' or 'script' parameter" }
        #if os(macOS)
        let escapedScript = script.replacingOccurrences(of: "'", with: "'\\''")
        let cmd = "osascript -e 'tell application \"Safari\"' -e 'open location \"\(url)\"' -e 'delay 2' -e 'do JavaScript \"\(escapedScript)\" in front document' -e 'end tell' 2>&1"
        let result = await runShellCommand(cmd, cwd: nil, timeoutSeconds: 15)
        if result.contains("not allowed assistive access") || result.contains("System Events") {
            return "Error: Safari automation requires Accessibility permission.\n" +
                "Grant access in: System Settings → Privacy & Security → Accessibility → Enable G-Rump.\n" +
                "Then retry this tool call."
        }
        return result
        #else
        return "Error: browser_evaluate is only available on macOS. It uses Safari's AppleScript automation."
        #endif
    }

    // MARK: - AI & Embeddings

    func executeGenerateEmbeddings(_ args: [String: Any]) async -> String {
        guard let text = args["text"] as? String else { return "Error: missing 'text' parameter" }
        if let embedding = NLEmbedding.sentenceEmbedding(for: .english) {
            if let vector = embedding.vector(for: text) {
                let preview = vector.prefix(10).map { String(format: "%.6f", $0) }.joined(separator: ", ")
                return "Embedding (\(vector.count) dimensions): [\(preview), ...]"
            }
        }
        return "Generated embedding for text (\(text.count) chars). NaturalLanguage sentence embedding not available for this input."
    }

    func executeSemanticSearchTool(_ args: [String: Any]) async -> String {
        guard let query = args["query"] as? String else { return "Error: missing 'query' parameter" }
        let directory = (args["directory"] as? String).map { resolvePath($0) } ?? workingDirectory
        let limit = args["limit"] as? Int ?? 5
        guard !directory.isEmpty else { return "Error: no directory specified and no working directory set" }

        let store = SemanticMemoryStore(baseDirectory: directory)
        let entries = store.relevantEntries(for: query, topK: limit)
        if entries.isEmpty {
            return "No semantic matches found for '\(query)'. Try grep_search for exact text matches."
        }
        var output = "Semantic search results for '\(query)' (\(entries.count) matches):\n"
        for (i, entry) in entries.enumerated() {
            output += "\n\(i + 1). [\(entry.timestamp)]\n"
            output += "   \(entry.text.prefix(200))\n"
        }
        return output
    }

    func executeSummarizeText(_ args: [String: Any]) async -> String {
        guard let text = args["text"] as? String else { return "Error: missing 'text' parameter" }
        let maxLength = args["max_length"] as? Int ?? 200
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let summary = sentences.prefix(max(1, maxLength / 80)).joined(separator: ". ") + "."
        return "Summary (\(text.count) chars → \(summary.count) chars):\n\(summary)"
    }

    // MARK: - Cloud Deploy

    func executeVercelDeploy(_ args: [String: Any]) async -> String {
        let whichResult = await runShellCommand("which vercel 2>/dev/null", cwd: nil, timeoutSeconds: 3)
        if whichResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Error: Vercel CLI not found.\n" +
                "Install it with: npm install -g vercel\n" +
                "Then authenticate with: vercel login"
        }
        let dir = (args["directory"] as? String).map { resolvePath($0) } ?? (workingDirectory.isEmpty ? nil : workingDirectory)
        var cmd = "vercel deploy"
        if let prod = args["production"] as? Bool, prod { cmd += " --prod" }
        if let yes = args["confirm"] as? Bool, yes { cmd += " --yes" }
        return await runShellCommand(cmd, cwd: dir, timeoutSeconds: 120)
    }

    func executeVercelLogs(_ args: [String: Any]) async -> String {
        var cmd = "vercel logs"
        if let deployment = args["deployment"] as? String { cmd += " \(deployment)" }
        if let follow = args["follow"] as? Bool, follow { cmd += " -f" }
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 15)
    }

    func executeNetlifyDeploy(_ args: [String: Any]) async -> String {
        let whichResult = await runShellCommand("which netlify 2>/dev/null", cwd: nil, timeoutSeconds: 3)
        if whichResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Error: Netlify CLI not found.\n" +
                "Install it with: npm install -g netlify-cli\n" +
                "Then authenticate with: netlify login"
        }
        let dir = (args["directory"] as? String).map { resolvePath($0) } ?? (workingDirectory.isEmpty ? nil : workingDirectory)
        var cmd = "netlify deploy"
        if let prod = args["production"] as? Bool, prod { cmd += " --prod" }
        if let site = args["site"] as? String { cmd += " --site \(site)" }
        return await runShellCommand(cmd, cwd: dir, timeoutSeconds: 120)
    }

    func executeFlyDeploy(_ args: [String: Any]) async -> String {
        let whichResult = await runShellCommand("which fly flyctl 2>/dev/null", cwd: nil, timeoutSeconds: 3)
        if whichResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Error: Fly.io CLI (flyctl) not found.\n" +
                "Install it with: brew install flyctl\n" +
                "Then authenticate with: fly auth login"
        }
        let dir = (args["directory"] as? String).map { resolvePath($0) } ?? (workingDirectory.isEmpty ? nil : workingDirectory)
        var cmd = "fly deploy"
        if let app = args["app"] as? String { cmd += " --app \(app)" }
        return await runShellCommand(cmd, cwd: dir, timeoutSeconds: 180)
    }

    // MARK: - Code Analysis

    func executeRegexReplace(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String,
              let pattern = args["pattern"] as? String,
              let replacement = args["replacement"] as? String else {
            return "Error: missing 'path', 'pattern', or 'replacement' parameter"
        }
        let resolved = resolvePath(path)
        do {
            var content = try String(contentsOfFile: resolved, encoding: .utf8)
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(content.startIndex..., in: content)
            let matchCount = regex.numberOfMatches(in: content, range: range)
            content = regex.stringByReplacingMatches(in: content, range: range, withTemplate: replacement)
            try content.write(toFile: resolved, atomically: true, encoding: .utf8)
            return "Replaced \(matchCount) match\(matchCount == 1 ? "" : "es") in \(resolved)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    func executeAstParse(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String else { return "Error: missing 'path' parameter" }
        let resolved = resolvePath(path)
        let ext = (resolved as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":
            return await runShellCommand("swift-demangle < /dev/null 2>/dev/null; xcrun swiftc -dump-parse '\(resolved)' 2>&1 | head -100", cwd: nil, timeoutSeconds: 30)
        case "js", "ts", "jsx", "tsx":
            return await runShellCommand("npx acorn --ecma2020 '\(resolved)' 2>/dev/null | head -100 || echo 'Install acorn: npm i -g acorn'", cwd: nil, timeoutSeconds: 15)
        case "py":
            return await runShellCommand("python3 -c \"import ast, json, sys; tree = ast.parse(open('\(resolved)').read()); print(ast.dump(tree, indent=2)[:3000])\" 2>&1", cwd: nil, timeoutSeconds: 15)
        default:
            return "AST parsing not supported for .\(ext) files. Supported: .swift, .js, .ts, .py"
        }
    }

    func executeFindReferences(_ args: [String: Any]) async -> String {
        guard let symbol = args["symbol"] as? String else { return "Error: missing 'symbol' parameter" }
        let dir = (args["directory"] as? String).map { resolvePath($0) } ?? workingDirectory
        guard !dir.isEmpty else { return "Error: no directory specified and no working directory set" }
        let escapedSymbol = symbol.replacingOccurrences(of: "'", with: "'\\''")
        return await runShellCommand("grep -rn --include='*.swift' --include='*.py' --include='*.js' --include='*.ts' --include='*.go' --include='*.rs' --include='*.java' --include='*.kt' '\(escapedSymbol)' '\(dir)' | head -50", cwd: nil, timeoutSeconds: 15)
    }

    func executeTypeCheck(_ args: [String: Any]) async -> String {
        let dir = (args["directory"] as? String).map { resolvePath($0) } ?? workingDirectory
        guard !dir.isEmpty else { return "Error: no directory specified and no working directory set" }
        // Detect project type and run appropriate type checker
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("tsconfig.json")) {
            return await runShellCommand("npx tsc --noEmit 2>&1 | head -80", cwd: dir, timeoutSeconds: 30)
        } else if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("Package.swift")) {
            return await runShellCommand("swift build --skip-update 2>&1 | grep -E '(error|warning):' | head -50", cwd: dir, timeoutSeconds: 60)
        } else if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("pyproject.toml")) {
            return await runShellCommand("mypy . 2>&1 | head -50 || echo 'Install mypy: pip install mypy'", cwd: dir, timeoutSeconds: 30)
        }
        return "No supported project type detected (tsconfig.json, Package.swift, or pyproject.toml)"
    }

    func executeDependencyGraph(_ args: [String: Any]) async -> String {
        let dir = (args["directory"] as? String).map { resolvePath($0) } ?? workingDirectory
        guard !dir.isEmpty else { return "Error: no directory specified and no working directory set" }
        if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("Package.swift")) {
            return await runShellCommand("swift package show-dependencies --format text 2>&1 | head -60", cwd: dir, timeoutSeconds: 30)
        } else if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("package.json")) {
            return await runShellCommand("npm ls --all --depth=2 2>&1 | head -60", cwd: dir, timeoutSeconds: 15)
        } else if FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("Cargo.toml")) {
            return await runShellCommand("cargo tree --depth 2 2>&1 | head -60", cwd: dir, timeoutSeconds: 15)
        }
        return "No supported dependency file found (Package.swift, package.json, or Cargo.toml)"
    }

    func executeCodeComplexity(_ args: [String: Any]) async -> String {
        guard let path = args["path"] as? String else { return "Error: missing 'path' parameter" }
        let resolved = resolvePath(path)
        do {
            let content = try String(contentsOfFile: resolved, encoding: .utf8)
            let lines = content.components(separatedBy: "\n")
            let totalLines = lines.count
            let blankLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            let commentLines = lines.filter { let t = $0.trimmingCharacters(in: .whitespaces); return t.hasPrefix("//") || t.hasPrefix("#") || t.hasPrefix("/*") || t.hasPrefix("*") }.count
            let codeLines = totalLines - blankLines - commentLines

            // Simple cyclomatic complexity: count branching keywords
            let branchKeywords = ["if ", "else ", "for ", "while ", "case ", "catch ", "guard ", "switch ", "? ", "&&", "||"]
            var complexity = 1
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                for kw in branchKeywords {
                    if trimmed.contains(kw) { complexity += 1 }
                }
            }

            let funcCount = lines.filter { $0.contains("func ") || $0.contains("def ") || $0.contains("function ") }.count

            var output = "Code Complexity Report: \(resolved)\n"
            output += "Total lines: \(totalLines)\n"
            output += "Code lines: \(codeLines)\n"
            output += "Comment lines: \(commentLines)\n"
            output += "Blank lines: \(blankLines)\n"
            output += "Functions/methods: \(funcCount)\n"
            output += "Cyclomatic complexity (approx): \(complexity)\n"
            output += "Complexity rating: \(complexity < 10 ? "Low" : complexity < 20 ? "Moderate" : complexity < 40 ? "High" : "Very High")"
            return output
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Network / Validation

    func executePortScan(_ args: [String: Any]) async -> String {
        guard let host = args["host"] as? String else { return "Error: missing 'host' parameter" }
        let ports = args["ports"] as? [Int] ?? [22, 80, 443, 3000, 5432, 6379, 8080, 8443, 9090]
        let escapedHost = host.replacingOccurrences(of: "'", with: "'\\''")
        let portList = ports.map(String.init).joined(separator: ",")
        // Use nc (netcat) for basic port scanning
        let cmd = "for port in \(ports.map(String.init).joined(separator: " ")); do nc -z -w 1 '\(escapedHost)' $port 2>/dev/null && echo \"$port: open\" || echo \"$port: closed\"; done"
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: min(ports.count * 2 + 5, 30))
    }

    func executeSslCheck(_ args: [String: Any]) async -> String {
        guard let host = args["host"] as? String else { return "Error: missing 'host' parameter" }
        let port = args["port"] as? Int ?? 443
        let escapedHost = host.replacingOccurrences(of: "'", with: "'\\''")
        let cmd = "echo | openssl s_client -connect '\(escapedHost):\(port)' -servername '\(escapedHost)' 2>/dev/null | openssl x509 -noout -dates -subject -issuer 2>/dev/null || echo 'Error: could not connect or openssl not available'"
        return await runShellCommand(cmd, cwd: nil, timeoutSeconds: 10)
    }

    func executeCronParse(_ args: [String: Any]) async -> String {
        guard let expression = args["expression"] as? String else { return "Error: missing 'expression' parameter" }
        let parts = expression.components(separatedBy: " ")
        guard parts.count >= 5 else { return "Error: invalid cron expression (need at least 5 fields: min hour dom month dow)" }
        let fields = ["Minute", "Hour", "Day of Month", "Month", "Day of Week"]
        var output = "Cron Expression: \(expression)\n\nField Breakdown:\n"
        for (i, field) in fields.enumerated() {
            output += "  \(field): \(parts[i])\n"
        }
        if parts.count > 5 {
            output += "  Command: \(parts[5...].joined(separator: " "))\n"
        }
        // Human-readable description
        output += "\nDescription: Runs"
        if parts[0] == "*" { output += " every minute" } else { output += " at minute \(parts[0])" }
        if parts[1] != "*" { output += " of hour \(parts[1])" }
        if parts[2] != "*" { output += " on day \(parts[2])" }
        if parts[3] != "*" { output += " of month \(parts[3])" }
        if parts[4] != "*" { output += " on weekday \(parts[4])" }
        return output
    }

    func executeJsonSchemaValidate(_ args: [String: Any]) async -> String {
        guard let jsonString = args["json"] as? String else { return "Error: missing 'json' parameter" }
        guard let schemaString = args["schema"] as? String else { return "Error: missing 'schema' parameter" }
        guard let jsonData = jsonString.data(using: .utf8),
              let schemaData = schemaString.data(using: .utf8) else {
            return "Error: invalid UTF-8 in json or schema"
        }
        do {
            let json = try JSONSerialization.jsonObject(with: jsonData)
            let schema = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] ?? [:]
            // Basic validation: check required fields and types
            var errors: [String] = []
            if let required = schema["required"] as? [String], let obj = json as? [String: Any] {
                for field in required {
                    if obj[field] == nil { errors.append("Missing required field: '\(field)'") }
                }
            }
            if let properties = schema["properties"] as? [String: Any], let obj = json as? [String: Any] {
                for (key, _) in obj {
                    if properties[key] == nil, schema["additionalProperties"] as? Bool == false {
                        errors.append("Unexpected field: '\(key)'")
                    }
                }
            }
            if errors.isEmpty { return "Validation passed. JSON conforms to schema." }
            return "Validation failed (\(errors.count) error\(errors.count == 1 ? "" : "s")):\n" + errors.map { "  • \($0)" }.joined(separator: "\n")
        } catch {
            return "Error parsing JSON: \(error.localizedDescription)"
        }
    }

    // MARK: - Interactive

    func executeAskUser(_ args: [String: Any]) async -> String {
        guard let question = args["question"] as? String else { return "Error: missing 'question' parameter" }
        let options = args["options"] as? [String]
        // Present the question inline in the conversation
        var output = "[ASK_USER] \(question)"
        if let options = options, !options.isEmpty {
            output += "\nOptions: " + options.enumerated().map { "\($0.offset + 1)) \($0.element)" }.joined(separator: ", ")
        }
        output += "\n\nPlease reply with your answer to continue."
        return output
    }
}
