import XCTest
@testable import OpenCode_Bar

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

    private func writeSample(root: String) {
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o","id":"ses1"},"timestamp":1700000000}
        {"type":"turn_context","payload":{"model":"gpt-4o"},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"output_tokens":500,"cached_input_tokens":300,"reasoning_output_tokens":100,"total_tokens":1900},"last_token_usage":{"input_tokens":200,"output_tokens":50,"cached_input_tokens":100,"reasoning_output_tokens":20,"total_tokens":370}}},"timestamp":1700000002}
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
        {"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1,"output_tokens":2,"total_tokens":3},"last_token_usage":{"input_tokens":4,"output_tokens":5,"cached_input_tokens":1,"reasoning_output_tokens":0,"total_tokens":10}}},"timestamp":1700000000}
        garbage line
        """
        try? jsonl.write(
            toFile: brokenDir + "/rollout-bad.jsonl", atomically: true, encoding: .utf8
        )

        let extractor = CodexExtractor(rootPath: brokenDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.tokens.output, 5,
                       "Valid event with last_token_usage must be read directly from it")
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

    // MARK: - F2b fix: read `last_token_usage` directly (it IS the per-event
    // delta from Codex), NOT `total_token_usage` (which is cumulative context
    // size). The old proportional-split produced wrong per-field values even
    // though the total summed correctly.

    /// Single event with both `total_token_usage` (cumulative) and
    /// `last_token_usage` (per-event). Pre-fix the extractor read
    /// `cached_input_tokens` from `total_token_usage`, double-counting cache
    /// over time. After the fix it must come from `last_token_usage`.
    func testCacheReadFromLastTokenUsageNotCumulative() async throws {
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500000,"output_tokens":12000,"cached_input_tokens":300000,"reasoning_output_tokens":5000,"total_tokens":817000},"last_token_usage":{"input_tokens":800,"output_tokens":120,"cached_input_tokens":280,"reasoning_output_tokens":40,"total_tokens":1240}}},"timestamp":1700000001}
        """
        try? rollout.write(
            toFile: tmpDir + "/2026/07/08/rollout-last-usage.jsonl",
            atomically: true, encoding: .utf8
        )

        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)

        XCTAssertEqual(event.tokens.input, 800,
                       "input must come from last_token_usage.input_tokens, not cumulative")
        XCTAssertEqual(event.tokens.output, 120)
        XCTAssertEqual(event.tokens.cacheRead, 280,
                       "cacheRead must come from last_token_usage.cached_input_tokens (280), NOT total_token_usage (300000)")
        XCTAssertEqual(event.tokens.reasoning, 40)
        XCTAssertEqual(event.tokens.cacheWrite, 0,
                       "Codex does not expose cache_write; always 0")
        XCTAssertEqual(event.tokens.total, 800 + 120 + 280 + 40,
                       "total = input + output + cacheRead + reasoning (cacheWrite always 0)")
    }

    /// Each event in a multi-event rollout has its own `last_token_usage`.
    /// The extractor must read each one independently — no cumulative state
    /// is carried between events on the per-field path.
    func testPerEventLastTokenUsageReadIndependently() async throws {
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":50,"cached_input_tokens":0,"reasoning_output_tokens":0,"total_tokens":150},"last_token_usage":{"input_tokens":100,"output_tokens":50,"cached_input_tokens":0,"reasoning_output_tokens":0,"total_tokens":150}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":400,"output_tokens":150,"cached_input_tokens":50,"reasoning_output_tokens":10,"total_tokens":610},"last_token_usage":{"input_tokens":300,"output_tokens":100,"cached_input_tokens":50,"reasoning_output_tokens":10,"total_tokens":460}}},"timestamp":1700000002}
        """
        try? rollout.write(
            toFile: tmpDir + "/2026/07/08/rollout-multi-last.jsonl",
            atomically: true, encoding: .utf8
        )

        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)

        XCTAssertEqual(events[0].tokens.cacheRead, 0)
        XCTAssertEqual(events[0].tokens.total, 150)

        XCTAssertEqual(events[1].tokens.input, 300,
                       "Second event: input from its own last_token_usage")
        XCTAssertEqual(events[1].tokens.output, 100)
        XCTAssertEqual(events[1].tokens.cacheRead, 50)
        XCTAssertEqual(events[1].tokens.reasoning, 10)
        XCTAssertEqual(events[1].tokens.total, 460)
    }

    /// Legacy fallback: if `last_token_usage` is absent the extractor must
    /// still emit SOMETHING so the row is not silently dropped. The fallback
    /// assigns the cumulative delta to `input` (output / cacheRead /
    /// reasoning / cacheWrite all 0). This is approximate but at least
    /// non-zero and non-double-counted.
    func testFallbackWhenLastTokenUsageMissing() async throws {
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":100,"total_tokens":1200}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1500,"output_tokens":700,"cached_input_tokens":600,"reasoning_output_tokens":200,"total_tokens":3000}}},"timestamp":1700000002}
        """
        try? rollout.write(
            toFile: tmpDir + "/2026/07/08/rollout-fallback.jsonl",
            atomically: true, encoding: .utf8
        )

        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)

        // First event (no prev): full cumulative total = 1200 → input = 1200.
        XCTAssertEqual(events[0].tokens.input, 1200)
        XCTAssertEqual(events[0].tokens.cacheRead, 0,
                       "Fallback path: cacheRead=0 (cannot recover from cumulative-only data)")
        XCTAssertEqual(events[0].tokens.output, 0)
        XCTAssertEqual(events[0].tokens.reasoning, 0)
        XCTAssertEqual(events[0].tokens.total, 1200)

        // Second event: delta = 3000 - 1200 = 1800 → input = 1800.
        XCTAssertEqual(events[1].tokens.input, 1800)
        XCTAssertEqual(events[1].tokens.total, 1800)
    }

    /// Compaction detection: if the cumulative `total_token_usage.total_tokens`
    /// shrinks between events (e.g., after /compact), the per-event delta
    /// from `last_token_usage` is the correct per-event delta — but the
    /// legacy fallback path uses `prevCumulativeTotal` to compute delta, and
    /// that delta must be clamped to zero (a negative input would corrupt
    /// the breakdown).
    func testFallbackClampsNegativeDeltaAfterCompact() async throws {
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000,"output_tokens":500,"cached_input_tokens":800,"reasoning_output_tokens":50,"total_tokens":3000}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":800,"output_tokens":300,"cached_input_tokens":400,"reasoning_output_tokens":20,"total_tokens":1500}}},"timestamp":1700000002}
        """
        try? rollout.write(
            toFile: tmpDir + "/2026/07/08/rollout-compact.jsonl",
            atomically: true, encoding: .utf8
        )

        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].tokens.total, 3000,
                       "First event (no prev): full cumulative total = 3000")
        XCTAssertEqual(events[1].tokens.total, 0,
                       "Decreased cumulative total (after /compact): delta clamped to 0")
    }
}
