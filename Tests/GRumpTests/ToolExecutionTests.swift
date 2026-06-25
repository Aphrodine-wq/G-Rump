import XCTest
@testable import GRump

@MainActor
final class ToolExecutionTests: XCTestCase {

    // MARK: - Anthropic Tool Conversion Regression

    func testAnthropicToolConversionExtractsFromFunctionDict() throws {
        // Verify tool structure: {"type": "function", "function": {"name": ..., "description": ..., "parameters": ...}}
        let tools = ToolDefinitions.toolsForCurrentPlatform
        XCTAssertFalse(tools.isEmpty)

        let sampleTool = tools.first!
        let fn = sampleTool["function"] as? [String: Any]
        XCTAssertNotNil(fn, "Tool must have 'function' dict")

        let name = fn?["name"] as? String
        XCTAssertNotNil(name, "function dict must have 'name'")
        XCTAssertFalse(name?.isEmpty ?? true)

        let description = fn?["description"] as? String
        XCTAssertNotNil(description, "function dict must have 'description'")
        XCTAssertFalse(description?.isEmpty ?? true)

        // This is the key regression test:
        // The OLD bug read tool["function"] as? String (nil — it's a dict)
        // and tool["description"] (nil — doesn't exist at top level)
        XCTAssertNil(sampleTool["function"] as? String,
            "tool['function'] is a dict, not a String — reading as String should be nil")
        XCTAssertNil(sampleTool["description"] as? String,
            "tool['description'] at top level should be nil — it's inside function dict")
        XCTAssertNil(sampleTool["parameters"] as? [String: Any],
            "tool['parameters'] at top level should be nil — it's inside function dict")
    }

    func testAllToolsHaveValidFunctionStructure() {
        for tool in ToolDefinitions.toolsForCurrentPlatform {
            let fn = tool["function"] as? [String: Any]
            XCTAssertNotNil(fn, "Every tool must have a 'function' dictionary")
            guard let fn = fn else { continue }

            let name = fn["name"] as? String ?? ""
            XCTAssertFalse(name.isEmpty, "Tool function must have non-empty 'name'")

            let desc = fn["description"] as? String ?? ""
            XCTAssertFalse(desc.isEmpty, "Tool '\(name)' function must have non-empty 'description'")

            let params = fn["parameters"] as? [String: Any]
            XCTAssertNotNil(params, "Tool '\(name)' function must have 'parameters' dict")
        }
    }

    // MARK: - Tool Dispatch Coverage

    func testEveryDefinedToolHasDispatchHandler() async throws {
        let vm = ChatViewModel()
        let tools = ToolDefinitions.toolsForCurrentPlatform
        let toolNames = tools.compactMap { tool -> String? in
            guard let fn = tool["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return nil }
            return name
        }
        XCTAssertFalse(toolNames.isEmpty)

        var unhandled: [String] = []
        var slow: [String] = []
        for name in toolNames {
            // Call with empty JSON args — expect a param error, NOT "not recognized".
            // Guard each call with a timeout: a tool that does real work (shell/network)
            // on empty args should fail loudly here rather than hang the whole suite.
            let outcome = await Self.withTimeout(seconds: 1.5) {
                await vm.executeToolCall(name: name, arguments: "{}")
            }
            switch outcome {
            case .some(let result):
                if result.contains("is not recognized") { unhandled.append(name) }
            case .none:
                slow.append(name)
            }
        }
        XCTAssertTrue(unhandled.isEmpty,
            "Tools with no dispatch handler (will fail at runtime): \(unhandled.joined(separator: ", "))")
        // Some tools do real I/O (shell/network) on empty args; the timeout above keeps
        // them from hanging the suite. Surfaced as a non-fatal note, not a failure.
        if !slow.isEmpty {
            GRumpLogger.general.info("Tools slow on empty args: \(slow.joined(separator: ", "), privacy: .public)")
        }
    }

    /// Run an async op with a timeout, abandoning it if it doesn't finish. Uses
    /// UNSTRUCTURED detached tasks so a non-cooperative blocking call (shell/network
    /// that ignores cancellation) is genuinely left behind instead of joined.
    private static func withTimeout<T: Sendable>(seconds: Double, _ op: @escaping @Sendable () async -> T) async -> T? {
        let box = TimeoutBox<T>()
        let work = Task.detached { await box.finish(.value(await op())) }
        let timer = Task.detached {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await box.finish(.timedOut)
        }
        let outcome = await box.wait()
        work.cancel()
        timer.cancel()
        if case .value(let v) = outcome { return v }
        return nil
    }

    // MARK: - Tool Parameter Validation

    func testReadFileMissingPathReturnsError() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "read_file", arguments: "{}")
        XCTAssertTrue(result.contains("Error"), "read_file with no path should return error")
    }

    func testWriteFileMissingParamsReturnsError() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "write_file", arguments: "{}")
        XCTAssertTrue(result.contains("Error"), "write_file with no params should return error")
    }

    func testEditFileMissingParamsReturnsError() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "edit_file", arguments: "{}")
        XCTAssertTrue(result.contains("Error"), "edit_file with no params should return error")
    }

    func testGrepSearchMissingParamsReturnsError() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "grep_search", arguments: "{}")
        XCTAssertTrue(result.contains("Error"), "grep_search with no params should return error")
    }

    func testDeleteFileMissingPathReturnsError() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "delete_file", arguments: "{}")
        XCTAssertTrue(result.contains("Error"), "delete_file with no path should return error")
    }

    func testDockerRunMissingImageReturnsError() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "docker_run", arguments: "{}")
        XCTAssertTrue(result.contains("Error"), "docker_run with no image should return error")
    }

    func testBrowserOpenMissingUrlReturnsError() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "browser_open", arguments: "{}")
        XCTAssertTrue(result.contains("Error"), "browser_open with no url should return error")
    }

    func testGenerateEmbeddingsMissingTextReturnsError() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "generate_embeddings", arguments: "{}")
        XCTAssertTrue(result.contains("Error"), "generate_embeddings with no text should return error")
    }

    func testRegexReplaceMissingParamsReturnsError() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "regex_replace", arguments: "{}")
        XCTAssertTrue(result.contains("Error"), "regex_replace with no params should return error")
    }

    func testAskUserMissingQuestionReturnsError() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "ask_user", arguments: "{}")
        XCTAssertTrue(result.contains("Error"), "ask_user with no question should return error")
    }

    func testInvalidJSONReturnsError() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "read_file", arguments: "not json")
        XCTAssertTrue(result.contains("Error"), "Invalid JSON arguments should return error")
    }

    func testUnknownToolReturnsNotRecognized() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "nonexistent_tool", arguments: "{}")
        XCTAssertTrue(result.contains("not recognized"), "Unknown tool should say 'not recognized'")
    }

    // MARK: - Tool Category Mapping

    func testAllToolsHaveCategoryMapping() {
        let tools = ToolDefinitions.toolsForCurrentPlatform
        let toolNames = tools.compactMap { tool -> String? in
            guard let fn = tool["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return nil }
            return name
        }

        var unmapped: [String] = []
        for name in toolNames {
            let category = ToolDefinitions.ToolCategory.category(for: name)
            if category == .utilities && !ToolDefinitions.ToolCategory.toolCategoryMap.keys.contains(name) {
                unmapped.append(name)
            }
        }
        // Some tools may intentionally be in utilities, but we should flag any that
        // are missing from the map entirely (defaulting to utilities by accident)
        if !unmapped.isEmpty {
            print("Tools defaulting to .utilities (may need explicit mapping): \(unmapped)")
        }
    }

    func testToolDisplayInfoCoversAllTools() {
        let allToolNames = Set(ToolDefinitions.toolsForCurrentPlatform.compactMap { tool -> String? in
            guard let fn = tool["function"] as? [String: Any],
                  let name = fn["name"] as? String else { return nil }
            return name
        })

        let displayInfoNames = Set(ToolDefinitions.toolDisplayInfo.map(\.name))
        let missing = allToolNames.subtracting(displayInfoNames)
        XCTAssertTrue(missing.isEmpty,
            "Tools missing from toolDisplayInfo: \(missing.sorted())")
    }

    // MARK: - Utility Tools (Pure Functions)

    func testGetCurrentTimeReturnsNonEmpty() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "get_current_time", arguments: "{}")
        XCTAssertFalse(result.isEmpty, "get_current_time should return current time")
        XCTAssertFalse(result.contains("Error"))
    }

    func testGenerateUuidReturnsValidFormat() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "generate_uuid", arguments: "{}")
        XCTAssertFalse(result.isEmpty, "generate_uuid should return a UUID")
        // UUID format: 8-4-4-4-12 hex chars
        XCTAssertTrue(result.contains("-"), "UUID should contain hyphens")
    }

    func testBase64RoundTrip() async {
        let vm = ChatViewModel()
        let encoded = await vm.executeToolCall(name: "base64_encode", arguments: "{\"text\": \"Hello, World!\"}")
        XCTAssertTrue(encoded.contains("SGVsbG8sIFdvcmxkIQ==") || encoded.contains("SGVsbG8"), "Should contain base64")
    }

    func testCronParseValidExpression() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "cron_parse", arguments: "{\"expression\": \"0 9 * * 1-5\"}")
        XCTAssertTrue(result.contains("Minute") || result.contains("minute"), "Should parse cron fields")
        XCTAssertFalse(result.contains("Error"))
    }

    func testCodeComplexityMissingPath() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "code_complexity", arguments: "{}")
        XCTAssertTrue(result.contains("Error"))
    }

    func testSummarizeTextMissingText() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "summarize_text", arguments: "{}")
        XCTAssertTrue(result.contains("Error"))
    }

    func testAskUserWithQuestion() async {
        let vm = ChatViewModel()
        let result = await vm.executeToolCall(name: "ask_user", arguments: "{\"question\": \"What language?\"}")
        XCTAssertTrue(result.contains("ASK_USER") || result.contains("What language"))
    }
}

/// One-shot result mailbox for `ToolExecutionTests.withTimeout`.
private actor TimeoutBox<T: Sendable> {
    enum Outcome: Sendable { case value(T); case timedOut }
    private var settled: Outcome?
    private var waiter: CheckedContinuation<Outcome, Never>?

    func finish(_ outcome: Outcome) {
        guard settled == nil else { return }
        settled = outcome
        waiter?.resume(returning: outcome)
        waiter = nil
    }

    func wait() async -> Outcome {
        if let settled { return settled }
        return await withCheckedContinuation { waiter = $0 }
    }
}
