import XCTest
@testable import GRump

final class SSEProviderParserTests: XCTestCase {

    // MARK: - Anthropic

    func testAnthropicToolUseStartAssignsOrdinalAndCarriesName() {
        var state = SSELineParser.AnthropicStreamState()
        // Text block occupies index 0; the tool block arrives at index 1 but
        // must map to tool ordinal 0 for the agent loop's buffers.
        let events = SSELineParser.parseAnthropicEvent([
            "type": "content_block_start",
            "index": 1,
            "content_block": ["type": "tool_use", "id": "toolu_01", "name": "read_file"]
        ], state: &state)

        guard case .toolCallDelta(let deltas)? = events.first else {
            return XCTFail("Expected toolCallDelta, got \(events)")
        }
        XCTAssertEqual(deltas.first?.index, 0)
        XCTAssertEqual(deltas.first?.id, "toolu_01")
        XCTAssertEqual(deltas.first?.function?.name, "read_file")
        XCTAssertEqual(deltas.first?.function?.arguments, "")
    }

    func testAnthropicInputJSONDeltaStreamsArguments() {
        // THE fix: input_json_delta events carry the tool arguments. The old
        // parser ignored them — every Anthropic tool call arrived empty.
        var state = SSELineParser.AnthropicStreamState()
        _ = SSELineParser.parseAnthropicEvent([
            "type": "content_block_start", "index": 1,
            "content_block": ["type": "tool_use", "id": "toolu_01", "name": "read_file"]
        ], state: &state)

        let first = SSELineParser.parseAnthropicEvent([
            "type": "content_block_delta", "index": 1,
            "delta": ["type": "input_json_delta", "partial_json": "{\"path\": \"/tm"]
        ], state: &state)
        let second = SSELineParser.parseAnthropicEvent([
            "type": "content_block_delta", "index": 1,
            "delta": ["type": "input_json_delta", "partial_json": "p/a\"}"]
        ], state: &state)

        var arguments = ""
        for events in [first, second] {
            guard case .toolCallDelta(let deltas)? = events.first else {
                return XCTFail("Expected toolCallDelta")
            }
            XCTAssertEqual(deltas.first?.index, 0, "Argument deltas must target the same ordinal as the start event")
            XCTAssertNil(deltas.first?.function?.name, "Name must not repeat — the loop concatenates it")
            arguments += deltas.first?.function?.arguments ?? ""
        }
        XCTAssertEqual(arguments, "{\"path\": \"/tmp/a\"}")
    }

    func testAnthropicSecondToolBlockGetsNextOrdinal() {
        var state = SSELineParser.AnthropicStreamState()
        _ = SSELineParser.parseAnthropicEvent([
            "type": "content_block_start", "index": 1,
            "content_block": ["type": "tool_use", "id": "t1", "name": "a"]
        ], state: &state)
        let events = SSELineParser.parseAnthropicEvent([
            "type": "content_block_start", "index": 2,
            "content_block": ["type": "tool_use", "id": "t2", "name": "b"]
        ], state: &state)
        guard case .toolCallDelta(let deltas)? = events.first else {
            return XCTFail("Expected toolCallDelta")
        }
        XCTAssertEqual(deltas.first?.index, 1)
    }

    func testAnthropicTextDelta() {
        var state = SSELineParser.AnthropicStreamState()
        let events = SSELineParser.parseAnthropicEvent([
            "type": "content_block_delta", "index": 0,
            "delta": ["type": "text_delta", "text": "Hello"]
        ], state: &state)
        guard case .text(let text)? = events.first else {
            return XCTFail("Expected text event")
        }
        XCTAssertEqual(text, "Hello")
    }

    func testAnthropicStopReasonNormalization() {
        XCTAssertEqual(SSELineParser.normalizedAnthropicStopReason("tool_use"), "tool_calls",
                       "The agent loop drives on the literal string \"tool_calls\"")
        XCTAssertEqual(SSELineParser.normalizedAnthropicStopReason("end_turn"), "stop")
        XCTAssertEqual(SSELineParser.normalizedAnthropicStopReason("stop_sequence"), "stop")
        XCTAssertEqual(SSELineParser.normalizedAnthropicStopReason("max_tokens"), "max_tokens")
        XCTAssertEqual(SSELineParser.normalizedAnthropicStopReason("refusal"), "refusal")
    }

    func testAnthropicMessageDeltaEmitsNormalizedDone() {
        var state = SSELineParser.AnthropicStreamState()
        let events = SSELineParser.parseAnthropicEvent([
            "type": "message_delta",
            "delta": ["stop_reason": "tool_use"]
        ], state: &state)
        guard case .done(let reason)? = events.first else {
            return XCTFail("Expected done event")
        }
        XCTAssertEqual(reason, "tool_calls")
    }

    // MARK: - Anthropic native thinking (Fable 5 signs every block)

    func testAnthropicThinkingBlockCapturedAcrossDeltas() {
        var state = SSELineParser.AnthropicStreamState()
        XCTAssertTrue(SSELineParser.parseAnthropicEvent([
            "type": "content_block_start", "index": 0,
            "content_block": ["type": "thinking", "thinking": "", "signature": ""]
        ], state: &state).isEmpty, "Thinking start emits nothing — the block is buffered until stop")
        XCTAssertTrue(SSELineParser.parseAnthropicEvent([
            "type": "content_block_delta", "index": 0,
            "delta": ["type": "thinking_delta", "thinking": "First I'll read "]
        ], state: &state).isEmpty)
        XCTAssertTrue(SSELineParser.parseAnthropicEvent([
            "type": "content_block_delta", "index": 0,
            "delta": ["type": "thinking_delta", "thinking": "the file."]
        ], state: &state).isEmpty)
        XCTAssertTrue(SSELineParser.parseAnthropicEvent([
            "type": "content_block_delta", "index": 0,
            "delta": ["type": "signature_delta", "signature": "sig_abc123"]
        ], state: &state).isEmpty)

        let events = SSELineParser.parseAnthropicEvent([
            "type": "content_block_stop", "index": 0
        ], state: &state)
        guard case .thinkingBlock(let block)? = events.first else {
            return XCTFail("Expected thinkingBlock at content_block_stop, got \(events)")
        }
        XCTAssertEqual(block.thinking, "First I'll read the file.")
        XCTAssertEqual(block.signature, "sig_abc123")
        XCTAssertFalse(block.isRedacted)
        XCTAssertTrue(state.thinkingBuffers.isEmpty, "Buffer must clear after emission")
    }

    func testAnthropicRedactedThinkingRoundTripsFromStartEvent() {
        var state = SSELineParser.AnthropicStreamState()
        _ = SSELineParser.parseAnthropicEvent([
            "type": "content_block_start", "index": 0,
            "content_block": ["type": "redacted_thinking", "data": "opaque_payload=="]
        ], state: &state)
        let events = SSELineParser.parseAnthropicEvent([
            "type": "content_block_stop", "index": 0
        ], state: &state)
        guard case .thinkingBlock(let block)? = events.first else {
            return XCTFail("Expected thinkingBlock for redacted_thinking")
        }
        XCTAssertEqual(block.data, "opaque_payload==")
        XCTAssertTrue(block.isRedacted)
    }

    func testAnthropicContentBlockStopForNonThinkingBlockEmitsNothing() {
        var state = SSELineParser.AnthropicStreamState()
        _ = SSELineParser.parseAnthropicEvent([
            "type": "content_block_start", "index": 1,
            "content_block": ["type": "tool_use", "id": "toolu_01", "name": "read_file"]
        ], state: &state)
        XCTAssertTrue(SSELineParser.parseAnthropicEvent([
            "type": "content_block_stop", "index": 1
        ], state: &state).isEmpty, "tool_use / text stops must not emit thinking blocks")
    }

    func testAnthropicThinkingDoesNotDisturbToolOrdinals() {
        // A thinking block at index 0 must not shift tool ordinal mapping.
        var state = SSELineParser.AnthropicStreamState()
        _ = SSELineParser.parseAnthropicEvent([
            "type": "content_block_start", "index": 0,
            "content_block": ["type": "thinking", "thinking": "", "signature": ""]
        ], state: &state)
        let events = SSELineParser.parseAnthropicEvent([
            "type": "content_block_start", "index": 1,
            "content_block": ["type": "tool_use", "id": "toolu_01", "name": "read_file"]
        ], state: &state)
        guard case .toolCallDelta(let deltas)? = events.first else {
            return XCTFail("Expected toolCallDelta")
        }
        XCTAssertEqual(deltas.first?.index, 0, "First tool still maps to ordinal 0")
    }

    func testAnthropicRefusalStopReasonPassesThrough() {
        // Fable 5 safety classifiers end the turn with stop_reason "refusal"
        // on HTTP 200 — the loop needs to see it verbatim to notify the user.
        var state = SSELineParser.AnthropicStreamState()
        let events = SSELineParser.parseAnthropicEvent([
            "type": "message_delta",
            "delta": ["stop_reason": "refusal"]
        ], state: &state)
        guard case .done(let reason)? = events.first else {
            return XCTFail("Expected done event")
        }
        XCTAssertEqual(reason, "refusal")
    }

    // MARK: - Google (Gemini)

    func testGoogleTextChunk() {
        var state = SSELineParser.GoogleStreamState()
        let events = SSELineParser.parseGoogleChunk([
            "candidates": [["content": ["parts": [["text": "Hi there"]]]]]
        ], state: &state)
        guard case .text(let text)? = events.first else {
            return XCTFail("Expected text event")
        }
        XCTAssertEqual(text, "Hi there")
    }

    func testGoogleFunctionCallsGetSequentialOrdinalsAndArgsJSON() {
        var state = SSELineParser.GoogleStreamState()
        let events = SSELineParser.parseGoogleChunk([
            "candidates": [["content": ["parts": [
                ["functionCall": ["name": "list_files", "args": ["dir": "/tmp"]]],
                ["functionCall": ["name": "read_file", "args": ["path": "/tmp/a"]]]
            ]]]]
        ], state: &state)

        XCTAssertEqual(events.count, 2)
        guard case .toolCallDelta(let first)? = events.first,
              case .toolCallDelta(let second)? = events.last else {
            return XCTFail("Expected two toolCallDelta events")
        }
        XCTAssertEqual(first.first?.index, 0)
        XCTAssertEqual(second.first?.index, 1, "The old parser pinned every call to index 0 — parallel calls collided")
        XCTAssertEqual(first.first?.function?.name, "list_files")
        XCTAssertTrue(first.first?.function?.arguments?.contains("\"dir\"") ?? false)
        XCTAssertFalse(first.first?.id?.isEmpty ?? true, "Synthesized ids let results round-trip")
        XCTAssertNotEqual(first.first?.id, second.first?.id)
    }

    func testGoogleStopWithFunctionCallsReportsToolCalls() {
        // Gemini says STOP even on function-call turns; reporting "stop"
        // would end the agent loop without executing the tools.
        var state = SSELineParser.GoogleStreamState()
        _ = SSELineParser.parseGoogleChunk([
            "candidates": [["content": ["parts": [
                ["functionCall": ["name": "list_files", "args": [:]]]
            ]]]]
        ], state: &state)
        let events = SSELineParser.parseGoogleChunk([
            "candidates": [["finishReason": "STOP"]]
        ], state: &state)
        guard case .done(let reason)? = events.first else {
            return XCTFail("Expected done event")
        }
        XCTAssertEqual(reason, "tool_calls")
    }

    func testGoogleStopWithoutFunctionCallsReportsStop() {
        var state = SSELineParser.GoogleStreamState()
        let events = SSELineParser.parseGoogleChunk([
            "candidates": [[
                "content": ["parts": [["text": "Done."]]],
                "finishReason": "STOP"
            ]]
        ], state: &state)
        XCTAssertEqual(events.count, 2)
        guard case .done(let reason)? = events.last else {
            return XCTFail("Expected done event")
        }
        XCTAssertEqual(reason, "stop")
    }

    func testGoogleNonStopFinishReasonPassesThroughLowercased() {
        var state = SSELineParser.GoogleStreamState()
        let events = SSELineParser.parseGoogleChunk([
            "candidates": [["finishReason": "MAX_TOKENS"]]
        ], state: &state)
        guard case .done(let reason)? = events.first else {
            return XCTFail("Expected done event")
        }
        XCTAssertEqual(reason, "max_tokens")
    }

    func testGoogleEmptyChunkYieldsNothing() {
        var state = SSELineParser.GoogleStreamState()
        XCTAssertTrue(SSELineParser.parseGoogleChunk([:], state: &state).isEmpty)
        XCTAssertTrue(SSELineParser.parseGoogleChunk(["candidates": []], state: &state).isEmpty)
    }
}
