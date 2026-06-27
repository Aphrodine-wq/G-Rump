import Foundation
import SwiftUI

// MARK: - Agent Loop Extension
//
// Contains the main agent loop (multi-turn streaming with tool execution),
// fast reply path, intent detection, and retry logic.
// Extracted from ChatViewModel.swift for maintainability.

extension ChatViewModel {

    // MARK: - Agent Loop (Multi-turn with parallel tool execution)

    internal func runAgentLoop() async {
        // Phase 3: Cache config + MCP tools once for entire agent run
        let (_, cachedPrompt, nativeTools, maxIterations) = effectiveAgentConfig()
        let mcpTools = await loadMCPTools()
        let tools = nativeTools + mcpTools

        var iterationCount = 0
        currentAgentStepMax = maxIterations

        repeat {
            if Task.isCancelled { break }
            iterationCount += 1
            currentAgentStep = iterationCount

            var textBuffer = ""
            var toolCallBuffers: [Int: (id: String, name: String, args: String)] = [:]

            let apiMessages = buildAPIMessages(cachedPrompt: cachedPrompt)
            let stream: AsyncThrowingStream<StreamEvent, Error>

            stream = createProviderStream(messages: apiMessages, tools: tools)

            var finishReason = ""
            var lastStreamPublishTime = Date()
            var lastPublishedLength = 0

            // Start metrics tracking for this iteration
            if iterationCount == 1 { streamMetrics.startStream() }
            streamMetrics.setPhase(.waiting)
            isThinking = true

            do {
                for try await event in stream {
                    if Task.isCancelled { break }
                    switch event {
                    case .text(let chunk):
                        textBuffer += chunk
                        // Approximate token count (~4 chars per token)
                        let approxTokens = max(1, chunk.count / 4)
                        streamMetrics.recordTokens(approxTokens)

                        // --- Claude-style thinking block extraction ---
                        let displayText = Self.extractThinkingBlocks(from: textBuffer, thinkingContent: &thinkingContent)

                        // Transition from thinking → streaming when visible text appears
                        if isThinking && !displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            isThinking = false
                            streamMetrics.setPhase(.streaming)
                        }

                        let now = Date()
                        let elapsed = now.timeIntervalSince(lastStreamPublishTime)
                        let charGrowth = displayText.count - lastPublishedLength
                        // Adaptive throttle: tune interval based on model speed
                        let adaptiveInterval = streamMetrics.recommendedUpdateInterval
                        let adaptiveBatch = streamMetrics.recommendedBatchSize
                        let shouldPublish = elapsed >= adaptiveInterval || charGrowth >= adaptiveBatch || chunk.contains("\n")
                        if shouldPublish {
                            lastStreamPublishTime = now
                            lastPublishedLength = displayText.count
                            // Strip any XML tool-call markup before displaying
                            if XMLToolCallParser.containsXMLToolCalls(displayText) {
                                let parsed = XMLToolCallParser.parse(displayText)
                                streamingContent = parsed.strippedText
                            } else {
                                streamingContent = displayText
                            }
                            FrameLoopService.shared.markStreaming(for: 0.5)
                        }

                    case .toolCallDelta(let deltas):
                        for delta in deltas {
                            let idx = delta.index ?? 0
                            var existing = toolCallBuffers[idx] ?? (id: delta.id ?? "", name: "", args: "")
                            if let id = delta.id, !id.isEmpty { existing.id = id }
                            if let name = delta.function?.name { existing.name += name }
                            if let args = delta.function?.arguments { existing.args += args }
                            toolCallBuffers[idx] = existing
                        }

                    case .done(let reason):
                        finishReason = reason
                    }
                }
                // Parse and strip XML tool calls from final buffer
                if XMLToolCallParser.containsXMLToolCalls(textBuffer) {
                    let parsed = XMLToolCallParser.parse(textBuffer)
                    textBuffer = parsed.strippedText
                    // Inject parsed XML tool calls into toolCallBuffers
                    for xmlCall in parsed.toolCalls {
                        let nextIdx = (toolCallBuffers.keys.max() ?? -1) + 1
                        toolCallBuffers[nextIdx] = (
                            id: "xml-\(UUID().uuidString.prefix(8))",
                            name: xmlCall.name,
                            args: xmlCall.argumentsJSON
                        )
                    }
                    if finishReason.isEmpty && !parsed.toolCalls.isEmpty {
                        finishReason = "tool_calls"
                    }
                }
                // Ensure final content is published (throttle may have skipped last chunk)
                let finalDisplay = Self.extractThinkingBlocks(from: textBuffer, thinkingContent: &thinkingContent)
                streamingContent = finalDisplay
                isThinking = false
            } catch is CancellationError {
                currentAgentStep = nil
                currentAgentStepMax = nil
                streamingContent = ""
                thinkingContent = ""
                isThinking = false
                streamMetrics.endStream()
                return
            } catch {
                if !textBuffer.isEmpty {
                    let partial = Message(role: .assistant, content: textBuffer + "\n\n(Partial response: stream interrupted.)")
                    currentConversation?.messages.append(partial)
                    syncConversation()
                }

                if shouldRetry(error: error, attempt: iterationCount) {
                    try? await Task.sleep(nanoseconds: UInt64(retryDelay(attempt: iterationCount) * 1_000_000_000))
                    continue
                }

                currentAgentStep = nil
                currentAgentStepMax = nil
                let friendly = friendlyErrorMessage(error)
                errorMessage = friendly
                streamingContent = ""
                thinkingContent = ""
                isThinking = false
                streamMetrics.endStream(error: friendly)

                // Preserve partial content + error for inline retry UI
                streamErrorPartialContent = textBuffer.isEmpty ? nil : textBuffer
                streamErrorMessage = friendly

                // Notify user of task failure
                if let conv = currentConversation {
                    GRumpNotificationService.shared.notifyTaskFailed(
                        conversationId: conv.id,
                        conversationTitle: conv.title,
                        errorMessage: friendly
                    )
                }
                return
            }

            if Task.isCancelled {
                currentAgentStep = nil
                currentAgentStepMax = nil
                if !textBuffer.isEmpty {
                    let toolCalls: [ToolCall]? = toolCallBuffers.isEmpty ? nil : toolCallBuffers.sorted(by: { $0.key < $1.key }).map {
                        ToolCall(id: $0.value.id, name: $0.value.name, arguments: $0.value.args)
                    }
                    let assistantMsg = Message(role: .assistant, content: textBuffer, toolCalls: toolCalls)
                    currentConversation?.messages.append(assistantMsg)
                    syncConversation()
                }
                streamingContent = ""
                return
            }

            // Commit assistant message
            let toolCalls: [ToolCall]? = toolCallBuffers.isEmpty ? nil : toolCallBuffers.sorted(by: { $0.key < $1.key }).map {
                ToolCall(id: $0.value.id, name: $0.value.name, arguments: $0.value.args)
            }
            if !textBuffer.isEmpty || toolCalls != nil {
                let assistantMsg = Message(role: .assistant, content: textBuffer, toolCalls: toolCalls)
                currentConversation?.messages.append(assistantMsg)
                syncConversation()
                streamingContent = ""
            }

            if toolCallBuffers.isEmpty || finishReason == "stop" {
                break
            }

            // Execute tool calls in parallel
            streamMetrics.setPhase(.toolUse)
            let sortedCalls = toolCallBuffers.sorted(by: { $0.key < $1.key })

            // Update UI with active tool calls
            let now = Date()
            activeToolCalls = sortedCalls.map { (_, call) in
                ToolCallStatus(
                    id: call.id,
                    name: call.name,
                    arguments: call.args,
                    status: .running,
                    result: nil,
                    progress: 0.0,
                    startTime: now,
                    currentStep: ToolProgressHelpers.initialStep(for: call.name),
                    totalSteps: ToolProgressHelpers.estimatedSteps(for: call.name),
                    currentStepNumber: 0
                )
            }

            // Phase 3: Pipeline — pre-build next API messages while tools execute
            let pipelinedMessages = buildAPIMessages(cachedPrompt: cachedPrompt)
            _ = pipelinedMessages // Pre-computed, ready for next iteration

            let results = await executeToolCallsParallel(sortedCalls.map { $0.value })

            // Post tool results (truncate large outputs to preserve context budget)
            for (idx, (_, call)) in sortedCalls.enumerated() {
                let result = truncateToolResult(results[idx], maxChars: 12000)
                let toolMsg = Message(role: .tool, content: result, toolCallId: call.id)
                currentConversation?.messages.append(toolMsg)

                if idx < activeToolCalls.count {
                    activeToolCalls[idx].status = result.lowercased().hasPrefix("error") ? .failed : .completed
                    activeToolCalls[idx].result = String(result.prefix(200))
                    activeToolCalls[idx].progress = 1.0
                    activeToolCalls[idx].endTime = Date()
                    activeToolCalls[idx].currentStepNumber = activeToolCalls[idx].totalSteps
                    activeToolCalls[idx].currentStep = result.lowercased().hasPrefix("error") ? "Failed" : "Completed"
                }

                let success = !result.lowercased().hasPrefix("error")
                var metadata: ActivityEntry.Metadata?
                if let data = call.args.data(using: .utf8),
                   let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    metadata = ActivityEntry.Metadata(
                        filePath: args["path"] as? String ?? (args["paths"] as? [String])?.first,
                        command: args["command"] as? String
                    )
                }
                activityStore.append(ActivityEntry(
                    toolName: call.name,
                    summary: String(result.prefix(150)).trimmingCharacters(in: .whitespacesAndNewlines),
                    success: success,
                    conversationId: currentConversation?.id,
                    metadata: metadata
                ))

                // --- Cognitive Loop Detector: record each tool action ---
                if let pivot = await cognitiveLoopDetector.recordAction(
                    toolName: call.name,
                    arguments: call.args,
                    result: result,
                    wasError: !success
                ) {
                    // Inject pivot strategy as a system message to break the loop
                    let pivotMsg = Message(role: .system, content: pivot.systemMessage)
                    currentConversation?.messages.append(pivotMsg)
                }

                // --- Code Change Tracking: record file modifications for adversarial review ---
                let writeTools: Set<String> = ["edit_file", "write_file", "create_file", "append_file"]
                if writeTools.contains(call.name), success,
                   let data = call.args.data(using: .utf8),
                   let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let path = args["path"] as? String {
                    let op: CodeChange.Operation = call.name == "create_file" ? .created : .edited
                    currentRunCodeChanges.append(CodeChange(filePath: path, operation: op, content: String(result.prefix(2000))))
                }

                // --- Causal Regression Tracker: analyze build/test failures ---
                let buildTestTools: Set<String> = ["run_build", "run_tests"]
                if buildTestTools.contains(call.name), !success {
                    if let analysis = await regressionTracker.analyze(
                        errorOutput: result,
                        failedCommand: call.name,
                        workingDirectory: workingDirectory
                    ) {
                        let analysisMsg = Message(role: .system, content: analysis.markdownSummary)
                        currentConversation?.messages.append(analysisMsg)
                    }
                }
            }
            // Phase 4: Single sync after all tool results instead of per-result
            syncConversation()

        } while iterationCount < maxIterations

        await runPostAgentCleanup(iterationCount: iterationCount, maxIterations: maxIterations)
    }


    // MARK: - Retry Logic

    func shouldRetry(error: Error, attempt: Int) -> Bool {
        if attempt > 3 { return false }
        if let urlError = error as? URLError {
            return [.timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost].contains(urlError.code)
        }
        if let serviceError = error as? OpenRouterService.ServiceError {
            if case .apiError(let code, _) = serviceError {
                return [429, 500, 502, 503, 504].contains(code)
            }
        }
        return false
    }

    func retryDelay(attempt: Int) -> Double {
        return Double(min(attempt * attempt, 20))
    }


    // MARK: - Retry Last Message

    func retryLastMessage() {
        guard var conversation = currentConversation else { return }
        while let last = conversation.messages.last, last.role == .assistant || last.role == .tool {
            conversation.messages.removeLast()
        }
        currentConversation = conversation
        syncConversation()

        isLoading = true
        errorMessage = nil
        streamingContent = ""
        activeToolCalls = []

        streamTask?.cancel()
        streamTask = Task {
            await runAgentLoop()
            streamTask = nil
            isLoading = false
        }
    }

}
