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

    private func writeMultiTurnSample(root: String) {
        let rollout = """
        {"type":"session_meta","payload":{"model":"gpt-4o","id":"ses1"},"timestamp":1700000000}
        {"type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":50,"total_tokens":1150},"last_token_usage":{"input_tokens":600,"output_tokens":300,"cached_input_tokens":200,"reasoning_output_tokens":50,"total_tokens":1150}}},"timestamp":1700000001}
        {"type":"event_msg","id":"msg-2","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1400,"output_tokens":700,"cached_input_tokens":400,"reasoning_output_tokens":150,"total_tokens":2650},"last_token_usage":{"input_tokens":800,"output_tokens":400,"cached_input_tokens":200,"reasoning_output_tokens":100,"total_tokens":1500}}},"timestamp":1700000002}
        """
        try? rollout.write(
            toFile: root + "/2026/07/08/rollout-multi.jsonl", atomically: true, encoding: .utf8
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

    func testExtractFromSampleData() throws {
        writeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try extractor.extractAll()
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.source, .codexCli)
    }

    func testEmptyDataSourceReturnsEmpty() throws {
        let emptyDir = NSTemporaryDirectory() + "codex_empty_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: emptyDir) }
        let extractor = CodexExtractor(rootPath: emptyDir)
        let events = try extractor.extractAll()
        XCTAssertEqual(events.count, 0)
    }

    func testBrokenLineSkipped() throws {
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
        let events = try extractor.extractAll()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.tokens.output, 2)
    }

    func testMultiSessionAggregation() throws {
        writeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try extractor.extractAll()
        let sessionIds = Set(events.map { $0.sessionId })
        XCTAssertEqual(sessionIds.count, 2)
    }

    func testProviderNormalizationApplied() throws {
        writeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try extractor.extractAll()
        for event in events {
            XCTAssertEqual(event.provider, .codex)
        }
    }

    func testLastTokenUsagePreferredForSingleEvent() throws {
        writeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try extractor.extractAll()
        let gpt4o = events.first { $0.model == "gpt-4o" }
        XCTAssertNotNil(gpt4o)
        XCTAssertEqual(gpt4o?.tokens.cacheRead, 100)
        XCTAssertEqual(gpt4o?.tokens.input, 100)
        XCTAssertEqual(gpt4o?.tokens.output, 50)
        XCTAssertEqual(gpt4o?.tokens.reasoning, 20)
        XCTAssertEqual(gpt4o?.tokens.cacheWrite, 0)
    }

    func testMultiTurnUsesLastTokenUsageDelta() throws {
        writeMultiTurnSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try extractor.extractAll()
        XCTAssertEqual(events.count, 2)

        let first = events[0]
        let second = events[1]

        XCTAssertEqual(first.tokens.cacheRead, 200)
        XCTAssertEqual(first.tokens.input, 400)
        XCTAssertEqual(first.tokens.output, 300)
        XCTAssertEqual(first.tokens.reasoning, 50)

        XCTAssertEqual(second.tokens.cacheRead, 200)
        XCTAssertEqual(second.tokens.input, 600)
        XCTAssertEqual(second.tokens.output, 400)
        XCTAssertEqual(second.tokens.reasoning, 100)

        XCTAssertNotEqual(second.tokens.total, 2650)
    }

    func testMultiTurnWithoutLastUsageUsesDeltaSplit() throws {
        writeNoLastUsageSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try extractor.extractAll()
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

    func testCumulativeStallOrDropProducesZeroDelta() throws {
        writeStalledCumulativeSample(root: tmpDir)
        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try extractor.extractAll()
        XCTAssertEqual(events.count, 3)

        XCTAssertEqual(events[0].tokens.input, 400)
        XCTAssertEqual(events[0].tokens.output, 300)
        XCTAssertEqual(events[0].tokens.cacheRead, 200)
        XCTAssertEqual(events[0].tokens.reasoning, 50)
        XCTAssertEqual(events[0].tokens.total, 950)
        XCTAssertEqual(events[1].tokens.total, 0)
        XCTAssertEqual(events[2].tokens.total, 0)
    }
}
