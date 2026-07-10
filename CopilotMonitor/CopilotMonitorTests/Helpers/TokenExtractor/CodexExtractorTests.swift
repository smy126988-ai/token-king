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

    func testMultiTurnWithoutLastUsageUsesDeltaSplit() async throws {
        writeNoLastUsageSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)

        let first = events[0]
        let second = events[1]

        // First event (no prev): full cumulative total = 1150.
        // Components input=600, cached=200, output=300, reasoning=50 sum to
        // 1150 with no rounding remainder, so the proportional split keeps
        // them as-is. Input is nonCachedInput + remainder = 400 + 200 = 600.
        XCTAssertEqual(first.tokens.input, 600)
        XCTAssertEqual(first.tokens.output, 300)
        XCTAssertEqual(first.tokens.cacheRead, 200)
        XCTAssertEqual(first.tokens.reasoning, 50)
        XCTAssertEqual(first.tokens.total, 1150)
        // Second event: delta = 2650 - 1150 = 1500.
        XCTAssertEqual(second.tokens.total, 1500)
        XCTAssertEqual(second.tokens.cacheWrite, 0)
    }

    func testCumulativeStallOrDropProducesZeroDelta() async throws {
        writeStalledCumulativeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 3)

        // First event (no prev): full cumulative total = 1150; proportional
        // split distributes 1150 across input=600, output=300, cacheRead=200,
        // reasoning=50 (sums cleanly with 200 remainder added to input).
        XCTAssertEqual(events[0].tokens.input, 600)
        XCTAssertEqual(events[0].tokens.output, 300)
        XCTAssertEqual(events[0].tokens.cacheRead, 200)
        XCTAssertEqual(events[0].tokens.reasoning, 50)
        XCTAssertEqual(events[0].tokens.total, 1150)
        // Second event: same total → zero delta.
        XCTAssertEqual(events[1].tokens.total, 0)
        // Third event: total dropped (e.g., /compact) → negative delta clamped to 0.
        XCTAssertEqual(events[2].tokens.total, 0)
    }

    // MARK: - Delta from total_token_usage between events (regression for the
    // last_token_usage confusion: last_token_usage in Codex rollouts is the
    // CUMULATIVE context size at the last call, NOT a per-event delta).
    // Per-event deltas MUST be computed from total_token_usage.total_tokens.

    func testDeltaComputedFromTotalTokensBetweenEvents() async throws {
        // Two events with growing cumulative total.
        // Components are chosen so the proportional split sums cleanly to
        // the total (input - cached + cached + output + reasoning == total).
        // Event 1: total=900 (first event, prev=nil → full total as delta)
        // Event 2: total=1500 (delta = 1500 - 900 = 600)
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":100,"reasoning_output_tokens":0,"total_tokens":900}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"output_tokens":450,"cached_input_tokens":150,"reasoning_output_tokens":0,"total_tokens":1500}}},"timestamp":1700000002}
        """
        try? rollout.write(
            toFile: tmpDir + "/2026/07/08/rollout-delta-between.jsonl",
            atomically: true, encoding: .utf8
        )

        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)

        let first = try XCTUnwrap(events.first)
        XCTAssertEqual(first.tokens.total, 900,
                       "First event: delta equals the full cumulative total")
        XCTAssertEqual(events[1].tokens.total, 600,
                       "Second event: delta = total - prev = 1500 - 900 = 600")
    }

    func testFirstEventUsesFullTotalAsDelta() async throws {
        // Single event with no previous event. Per-event delta must equal
        // the cumulative total (because there is nothing to subtract).
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":100,"total_tokens":1000}}},"timestamp":1700000001}
        """
        try? rollout.write(
            toFile: tmpDir + "/2026/07/08/rollout-first.jsonl",
            atomically: true, encoding: .utf8
        )

        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        XCTAssertEqual(event.tokens.total, 1000,
                       "First event (no prev): delta equals cumulative total")
    }

    func testZeroDeltaWhenTotalUnchanged() async throws {
        // Same cumulative total reported twice (e.g., Codex emitted an event
        // with no new tokens). Delta must be 0, not negative.
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"output_tokens":200,"cached_input_tokens":100,"reasoning_output_tokens":50,"total_tokens":800}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":500,"output_tokens":200,"cached_input_tokens":100,"reasoning_output_tokens":50,"total_tokens":800}}},"timestamp":1700000002}
        """
        try? rollout.write(
            toFile: tmpDir + "/2026/07/08/rollout-zero.jsonl",
            atomically: true, encoding: .utf8
        )

        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].tokens.total, 800)
        XCTAssertEqual(events[1].tokens.total, 0,
                       "Same cumulative total twice → zero per-event delta")
    }

    func testNegativeDeltaClampedToZero() async throws {
        // After /compact the cumulative context shrinks. The next reported
        // total_token_usage.total_tokens can be smaller than the previous.
        // Delta must be clamped to 0 instead of going negative (which would
        // produce garbage breakdowns).
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2000,"output_tokens":500,"cached_input_tokens":800,"reasoning_output_tokens":50,"total_tokens":3000}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":800,"output_tokens":300,"cached_input_tokens":400,"reasoning_output_tokens":20,"total_tokens":1500}}},"timestamp":1700000002}
        """
        try? rollout.write(
            toFile: tmpDir + "/2026/07/08/rollout-negative.jsonl",
            atomically: true, encoding: .utf8
        )

        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].tokens.total, 3000)
        XCTAssertEqual(events[1].tokens.total, 0,
                       "Decreased cumulative total (after /compact) → clamped to 0")
    }

    func testRealisticCodexContextGrowth() async throws {
        // Real-world values from a long Codex session:
        //   total 206344 → 210003 → 211324
        // Expected per-event deltas:
        //   first  : 206344 (full cumulative total as delta, no prev)
        //   second : 210003 - 206344 = 3659
        //   third  : 211324 - 210003 = 1321
        // Per-event input/output/cached/reasoning below are plausible per-turn
        // deltas — the proportional split only needs to sum to the delta.
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o"},"timestamp":"2026-05-20T08:33:54Z"}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3500,"output_tokens":5000,"cached_input_tokens":2000,"reasoning_output_tokens":1344,"total_tokens":206344}}},"timestamp":"2026-05-20T08:34:30Z"}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":3700,"output_tokens":5050,"cached_input_tokens":2100,"reasoning_output_tokens":1344,"total_tokens":210003}}},"timestamp":"2026-05-20T08:35:30Z"}
        {"type":"event_msg","id":"msg-3","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1300,"output_tokens":5150,"cached_input_tokens":750,"reasoning_output_tokens":1344,"total_tokens":211324}}},"timestamp":"2026-05-20T08:36:30Z"}
        """
        try? rollout.write(
            toFile: tmpDir + "/2026/07/08/rollout-realistic.jsonl",
            atomically: true, encoding: .utf8
        )

        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()
        XCTAssertEqual(events.count, 3)

        XCTAssertEqual(events[0].tokens.total, 206344,
                       "First event: full cumulative total = 206344")
        XCTAssertEqual(events[1].tokens.total, 3659,
                       "Second event: 210003 - 206344 = 3659")
        XCTAssertEqual(events[2].tokens.total, 1321,
                       "Third event: 211324 - 210003 = 1321")
    }
}
