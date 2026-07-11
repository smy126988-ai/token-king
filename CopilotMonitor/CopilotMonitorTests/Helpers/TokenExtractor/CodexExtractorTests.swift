import XCTest
@testable import OpenCode_Bar

/// CodexExtractor fixture uses CUMULATIVE-per-session `last_token_usage`
/// values that mirror the real Codex CLI rollout shape. The extractor
/// treats Anthropic-style cache fields as PER-REQUEST (the cumulative
/// values happen to grow monotonically across turns, but each value is
/// already "what this API call had from cache", not session state).
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
    /// turn, so the per-request value equals the raw cumulative.
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

    /// Two-event sample. cache.value rises 200 -> 400 (cache grew).
    /// Each value is what this API call had from cache (per-request
    /// Anthropic semantics); no delta needed.
    private func writeMultiTurnSample(root: String) {
        // event 1: input=600, cache=200, output=300, reasoning=50
        //   → fresh input = 600-200 = 400, cache read = 200, output = 250
        //     (output - reasoning), reasoning = 50
        // event 2: input=1400, cache=400, output=700, reasoning=150
        //   → fresh input = 1400-400 = 1000, cache read = 400,
        //     output = 700-150 = 550, reasoning = 150
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o","id":"ses1"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":50,"total_tokens":1150},"last_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":50,"total_tokens":1150}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1400,"output_tokens":700,"cached_input_tokens":400,"reasoning_output_tokens":150,"total_tokens":2650},"last_token_usage":{"input_tokens":1400,"output_tokens":700,"cached_input_tokens":400,"reasoning_output_tokens":150,"total_tokens":2650}}},"timestamp":1700000002}
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

    /// Three-event sequence where cumulative growth stalls (event 2 grows
    /// by 0) and then shrinks (event 3 grows negatively). Cache values are
    /// stored raw per-request; the proportional-split fallback path
    /// handles non-monotonic cumulative growth.
    private func writeStalledCumulativeSample(root: String) {
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o","id":"ses1"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":50,"total_tokens":1150}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":50,"total_tokens":1150}}},"timestamp":1700000002}
        {"type":"event_msg","id":"msg-3","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"output_tokens":250,"cached_input_tokens":100,"reasoning_output_tokens":50,"total_tokens":900}}},"timestamp":1700000003}
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

    func testSingleEventUsesRawAsDelta() async throws {
        // Single-event: cumulative value == first-and-only turn's per-request
        // value. Stored as-is (no delta).
        writeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        let gpt4o = events.first { $0.model == "gpt-4o" }
        XCTAssertNotNil(gpt4o)
        // fresh input = total - cache, output = total - reasoning.
        XCTAssertEqual(gpt4o?.tokens.input, 700, "fresh input = 1000 - 300")
        XCTAssertEqual(gpt4o?.tokens.cacheRead, 300, "per-request cache hits")
        XCTAssertEqual(gpt4o?.tokens.output, 400, "output = 500 - 100 reasoning")
        XCTAssertEqual(gpt4o?.tokens.reasoning, 100)
        XCTAssertEqual(gpt4o?.tokens.cacheWrite, 0)
    }

    /// Each turn's value is THIS API call's billing value, not a session
    /// accumulator that must be turned into deltas. Sum across messages
    /// in a session gives the total tokens billed.
    func testMultiTurnStoresRawPerRequestValues() async throws {
        writeMultiTurnSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)

        let first = events[0]
        let second = events[1]

        // Event 1 (first turn): raw values, fresh = input - cache.
        XCTAssertEqual(first.tokens.input, 400, "fresh = 600 - 200")
        XCTAssertEqual(first.tokens.cacheRead, 200, "per-request cache = 200")
        XCTAssertEqual(first.tokens.output, 250, "output = 300 - 50 reasoning")
        XCTAssertEqual(first.tokens.reasoning, 50)

        // Event 2: cache grew. fresh = (1400-400) - 0 = 1000 over first turn.
        // Both events are stored raw; sum gives the session total.
        XCTAssertEqual(second.tokens.input, 1000, "fresh = 1400 - 400")
        XCTAssertEqual(second.tokens.cacheRead, 400, "per-request cache = 400")
        XCTAssertEqual(second.tokens.output, 550, "output = 700 - 150")
        XCTAssertEqual(second.tokens.reasoning, 150)
    }

    func testMultiTurnWithoutLastUsageUsesDeltaSplit() async throws {
        writeNoLastUsageSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)

        let first = events[0]
        let second = events[1]

        XCTAssertEqual(first.tokens.input, 400)
        XCTAssertEqual(first.tokens.output, 250)
        XCTAssertEqual(first.tokens.cacheRead, 200)
        XCTAssertEqual(first.tokens.reasoning, 50)
        XCTAssertEqual(second.tokens.cacheWrite, 0)
    }

    /// Cumulative growth stalls (event 2 grows by 0) and then shrinks
    /// (event 3 grows negatively). The proportional-split fallback path
    /// clamps deltas to 0 — never negative — so aggregate sums stay
    /// meaningful when source data is non-monotonic.
    func testCumulativeStallOrDropProducesZeroDelta() async throws {
        writeStalledCumulativeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 3)

        // Event 1: first turn, raw cumulative used as the first delta.
        // For the no-last_usage path, the first event always uses raw.
        XCTAssertEqual(events[0].tokens.input, 400, "fresh = 600 - 200")
        XCTAssertEqual(events[0].tokens.output, 250)
        XCTAssertEqual(events[0].tokens.cacheRead, 200)

        // Event 2: cumulative didn't grow, every delta must clamp to 0.
        XCTAssertEqual(events[1].tokens.input, 0)
        XCTAssertEqual(events[1].tokens.cacheRead, 0)

        // Event 3: cumulative shrank across the board, every delta clamps to 0.
        XCTAssertEqual(events[2].tokens.input, 0)
        XCTAssertEqual(events[2].tokens.cacheRead, 0)
    }
}
