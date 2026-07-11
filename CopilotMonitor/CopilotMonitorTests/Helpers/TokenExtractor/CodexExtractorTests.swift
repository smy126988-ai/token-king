import XCTest
@testable import OpenCode_Bar

/// CodexExtractor fixture uses CUMULATIVE-per-session values that mirror the
/// real Codex CLI rollout shape (each `last_token_usage` carries the
/// cumulative session totals up to that event). The extractor must convert
/// those to per-event deltas; these tests assert the corrected shape.
final class CodexExtractorTests: XCTestCase {

    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "codex_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: tmpDir + "/2026/07/08", withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    /// Single-event sample: cumulative values are also the first-and-only
    /// turn, so the delta equals the raw cumulative.
    private func writeSample(root: String) {
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o","id":"ses1"},"timestamp":1700000000}
        {"type":"turn_context","payload":{"model":"gpt-4o"},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"output_tokens":500,"cached_input_tokens":300,"reasoning_output_tokens":100,"total_tokens":1900},"last_token_usage":{"input_tokens":1000,"output_tokens":500,"cached_input_tokens":300,"reasoning_output_tokens":100,"total_tokens":1900}}},"timestamp":1700000002}
        """
        try? rollout.write(
            toFile: root + "/2026/07/08/rollout-1.jsonl", atomically: true, encoding: .utf8
        )

        let rollout2 = """
        {"type":"session_meta","payload":{"model":"gpt-5"},"timestamp":1700000100}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"output_tokens":250,"cached_input_tokens":100,"reasoning_output_tokens":50,"total_tokens":900}}},"timestamp":1700000101}
        """
        try? rollout2.write(
            toFile: root + "/2026/07/08/rollout-2.jsonl", atomically: true, encoding: .utf8
        )
    }

    /// Two-event sample. Real Codex shape:
    ///   - input_tokens and cached_input_tokens are CUMULATIVE per session
    ///     (always grow, never decrease)
    ///   - output_tokens and reasoning_output_tokens are PER-TURN
    ///     (fluctuate independently of cumulative state)
    /// The extractor must convert the cumulative fields to per-session
    /// deltas while keeping output/reasoning as-is.
    private func writeMultiTurnSample(root: String) {
        // event 1: input=600, cache=200, output=438, reasoning=218
        //   → fresh input = 600-200 = 400, cache = 200, output = 438, reasoning = 218
        // event 2: input=1400, cache=400, output=254, reasoning=39
        //   → fresh input cumulative = (1400-400) - (600-200) = 600
        //     cache delta = 400-200 = 200
        //     output 254 (raw per-turn)
        //     reasoning 39 (raw per-turn)
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o","id":"ses1"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":600,"output_tokens":438,"cached_input_tokens":200,"reasoning_output_tokens":218,"total_tokens":1256},"last_token_usage":{"input_tokens":600,"output_tokens":438,"cached_input_tokens":200,"reasoning_output_tokens":218,"total_tokens":1256}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1400,"output_tokens":692,"cached_input_tokens":400,"reasoning_output_tokens":257,"total_tokens":2349},"last_token_usage":{"input_tokens":1400,"output_tokens":254,"cached_input_tokens":400,"reasoning_output_tokens":39,"total_tokens":2093}}},"timestamp":1700000002}
        """
        try? rollout.write(
            toFile: root + "/2026/07/08/rollout-multi.jsonl", atomically: true, encoding: .utf8
        )
    }

    /// Source has no `last_token_usage` (older Codex builds). The extractor
    /// must fall back to the cumulative-total proportional-split path.
    private func writeNoLastUsageSample(root: String) {
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o","id":"ses1"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":50,"total_tokens":1150}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1400,"output_tokens":700,"cached_input_tokens":400,"reasoning_output_tokens":150,"total_tokens":2650}}},"timestamp":1700000002}
        """
        try? rollout.write(
            toFile: root + "/2026/07/08/rollout-no-last.jsonl", atomically: true, encoding: .utf8
        )
    }

    /// Three-event sequence where cumulative growth stalls and then shrinks
    /// — the second event adds nothing, the third shrinks input. The
    /// extractor must clamp deltas to 0 instead of going negative.
    private func writeStalledCumulativeSample(root: String) {
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o","id":"ses1"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":50,"total_tokens":1150},"last_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":50,"total_tokens":1150}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":50,"total_tokens":1150},"last_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":50,"total_tokens":1150}}},"timestamp":1700000002}
        {"type":"event_msg","id":"msg-3","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"output_tokens":250,"cached_input_tokens":100,"reasoning_output_tokens":50,"total_tokens":900},"last_token_usage":{"input_tokens":500,"output_tokens":250,"cached_input_tokens":100,"reasoning_output_tokens":50,"total_tokens":900}}},"timestamp":1700000003}
        """
        try? rollout.write(
            toFile: root + "/2026/07/08/rollout-stalled.jsonl", atomically: true, encoding: .utf8
        )
    }

    func testExtractFromSampleData() async throws {
        writeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.source, .codexCli)
    }

    func testEmptyDataSourceReturnsEmpty() async throws {
        let emptyDir = NSTemporaryDirectory() + "codex_empty_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: emptyDir) }
        let extractor = CodexExtractor(rootPath: emptyDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 0)
    }

    func testBrokenLineSkipped() async throws {
        let brokenDir = NSTemporaryDirectory() + "codex_broken_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: brokenDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: brokenDir) }

        let jsonl = """
        not json
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3}}},"timestamp":1700000000}
        garbage line
        """
        try? jsonl.write(
            toFile: brokenDir + "/rollout-bad.jsonl", atomically: true, encoding: .utf8
        )

        let extractor = CodexExtractor(rootPath: brokenDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.tokens.output, 2)
    }

    func testMultiSessionAggregation() async throws {
        writeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        let sessionIds = Set(events.map { $0.sessionId })
        XCTAssertEqual(sessionIds.count, 2)
    }

    func testProviderNormalizationApplied() async throws {
        writeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        for event in events {
            XCTAssertEqual(event.provider, .codex)
        }
    }

    func testSingleEventUsesRawCumulativeAsDelta() async throws {
        // Single-event: raw cumulative == first-and-only turn; delta = raw.
        writeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        let gpt4o = events.first { $0.model == "gpt-4o" }
        XCTAssertNotNil(gpt4o)
        // First-and-only turn: fresh input = cumulative input - cumulative cache.
        XCTAssertEqual(gpt4o?.tokens.input, 700, "fresh input = 1000 - 300")
        XCTAssertEqual(gpt4o?.tokens.cacheRead, 300, "cache read is the cumulative cache")
        XCTAssertEqual(gpt4o?.tokens.output, 500)
        XCTAssertEqual(gpt4o?.tokens.reasoning, 100)
        XCTAssertEqual(gpt4o?.tokens.cacheWrite, 0)
    }

    /// Real Codex delta test: cumulative grows from event 1 to event 2;
    /// extractor must compute per-turn delta. Bug history: an earlier
    /// version of this test documented cumulative values as if they were
    /// per-turn deltas, which enshrined the 30× cache_read inflation bug.
    func testMultiTurnUsesPerSessionDelta() async throws {
        writeMultiTurnSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)

        let first = events[0]
        let second = events[1]

        // Event 1: first turn → uses raw cumulative as the delta.
        XCTAssertEqual(first.tokens.input, 400,
            "first event fresh input = 600 cumulative - 200 cumulative cache")
        XCTAssertEqual(first.tokens.cacheRead, 200,
            "first event cache read = cumulative cache for turn 1")
        XCTAssertEqual(first.tokens.output, 438,
            "output is per-turn; use raw value as-is")
        XCTAssertEqual(first.tokens.reasoning, 218,
            "reasoning is per-turn; use raw value as-is")

        // Event 2: cumulative growth -> per-turn delta for input/cache.
        //   input cum 600 -> 1400 (grew 800)
        //   cache cum 200 -> 400 (grew 200)
        //   fresh delta = 800 - 200 = 600
        XCTAssertEqual(second.tokens.input, 600,
            "second event fresh input = (1400-400) - (600-200) = 600")
        XCTAssertEqual(second.tokens.cacheRead, 200,
            "second event cache read = 400 - 200 = 200")
        // Output/reasoning are per-turn, raw value stays as-is.
        XCTAssertEqual(second.tokens.output, 254,
            "output is per-turn; raw value as-is")
        XCTAssertEqual(second.tokens.reasoning, 39,
            "reasoning is per-turn; raw value as-is")
    }

    func testMultiTurnWithoutLastUsageUsesDeltaSplit() async throws {
        writeNoLastUsageSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)

        let first = events[0]
        let second = events[1]

        XCTAssertEqual(first.tokens.input, 400)
        XCTAssertEqual(first.tokens.output, 300)
        XCTAssertEqual(first.tokens.cacheRead, 200)
        XCTAssertEqual(first.tokens.reasoning, 50)
        XCTAssertEqual(first.tokens.total, 950)
        XCTAssertEqual(second.tokens.total, 1500)
        XCTAssertEqual(second.tokens.cacheWrite, 0)
    }

    /// Cumulative growth stalls (event 2 grows by 0) and then shrinks (event
    /// 3 grows negatively). The cumulative fields (input, cacheRead) must
    /// clamp to 0 — never negative — so aggregate sums stay meaningful.
    /// Output and reasoning are per-turn, so they are not affected by
    /// cumulative stalls and pass through as-is.
    func testCumulativeStallOrDropProducesZeroDelta() async throws {
        writeStalledCumulativeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 3)

        // Event 1: first turn, raw cumulative -> becomes the first delta.
        XCTAssertEqual(events[0].tokens.input, 400, "600 cumulative - 200 cumulative cache")
        XCTAssertEqual(events[0].tokens.cacheRead, 200)
        XCTAssertEqual(events[0].tokens.output, 300)
        XCTAssertEqual(events[0].tokens.reasoning, 50)

        // Event 2: cumulative didn't grow, input/cache deltas clamp to 0.
        // Output and reasoning stay at their raw per-turn values.
        XCTAssertEqual(events[1].tokens.input, 0)
        XCTAssertEqual(events[1].tokens.cacheRead, 0)
        XCTAssertEqual(events[1].tokens.output, 300, "output is per-turn, not cumulative")
        XCTAssertEqual(events[1].tokens.reasoning, 50, "reasoning is per-turn, not cumulative")

        // Event 3: cumulative shrank across the board, input/cache clamp to 0.
        // Output and reasoning shrink with the per-turn values.
        XCTAssertEqual(events[2].tokens.input, 0)
        XCTAssertEqual(events[2].tokens.cacheRead, 0)
        XCTAssertEqual(events[2].tokens.output, 250, "per-turn value as-is")
        XCTAssertEqual(events[2].tokens.reasoning, 50, "per-turn value as-is")
    }
}
