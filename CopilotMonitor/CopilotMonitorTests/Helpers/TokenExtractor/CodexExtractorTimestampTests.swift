import XCTest
@testable import OpenCode_Bar

/// F2b F2-fixing: CodexExtractor must parse ISO 8601 timestamps with
/// fractional seconds (e.g. "2026-05-20T08:33:54.127Z") instead of falling
/// back to epoch zero, AND must use `last_token_usage` (per-event delta)
/// instead of `total_token_usage` (session-cumulative).
///
/// These tests live in their own file (matching the rest of the
/// Helper/TokenExtractor/*Extractor*Tests.swift pattern) to keep the
/// ISO 8601 / delta regressions covered independently of the legacy
/// epoch-numbered tests.
final class CodexExtractorTimestampTests: XCTestCase {

    private var tmpDir: String = ""

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "codex_ts_test_\(UUID().uuidString)"
        do {
            try FileManager.default.createDirectory(
                atPath: tmpDir + "/2026/07/08", withIntermediateDirectories: true
            )
        } catch {
            XCTFail("setUp: failed to create dir \(tmpDir)/2026/07/08: \(error)")
        }
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    private func writeRollout(name: String, lines: [String]) {
        let path = "\(tmpDir)/2026/07/08/\(name)"
        let content = lines.joined(separator: "\n") + "\n"
        do {
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            XCTFail("writeRollout failed: \(error); path=\(path)")
            return
        }
    }

    // MARK: - ISO 8601 timestamp parsing

    func testParsesISO8601TimestampWithFractionalSeconds() async throws {
        let sessionMeta = """
        {"timestamp":"2026-05-20T08:33:54.127Z","type":"session_meta","payload":{"id":"s1","cwd":"/tmp","model":"gpt-4o"}}
        """
        let eventMsg = """
        {"timestamp":"2026-05-20T08:34:30.500Z","type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100000,"cached_input_tokens":50000,"output_tokens":5000,"reasoning_output_tokens":1000,"total_tokens":106000},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":1060},"model_context_window":258400}}}
        """
        writeRollout(name: "rollout-iso-frac.jsonl", lines: [sessionMeta, eventMsg])

        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        let utc = TimeZone(identifier: "UTC") ?? TimeZone.current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                       from: event.timestamp)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 5)
        XCTAssertEqual(comps.day, 20)
        XCTAssertEqual(comps.hour, 8)
        XCTAssertEqual(comps.minute, 34)
        XCTAssertNotEqual(Int(event.timestamp.timeIntervalSince1970), 0,
                          "ISO 8601 timestamp must not collapse to epoch 0")
    }

    func testParsesISO8601TimestampWithoutFractionalSeconds() async throws {
        let sessionMeta = """
        {"timestamp":"2026-05-20T08:33:54Z","type":"session_meta","payload":{"id":"s1","model":"gpt-4o"}}
        """
        writeRollout(name: "rollout-iso-noflac.jsonl", lines: [sessionMeta])

        let extractor = CodexExtractor(rootPath: tmpDir)
        _ = try await extractor.extractAll()
    }

    // MARK: - last_token_usage is preferred over total_token_usage

    func testUsesLastTokenUsageDeltaNotCumulativeTotal() async throws {
        let sessionMeta = """
        {"timestamp":"2026-05-20T08:33:54.127Z","type":"session_meta","payload":{"id":"s1","model":"gpt-4o"}}
        """
        let eventMsg = """
        {"timestamp":"2026-05-20T08:34:30.500Z","type":"event_msg","id":"msg-1","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100000,"cached_input_tokens":50000,"output_tokens":5000,"reasoning_output_tokens":1000,"total_tokens":106000},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":1060},"model_context_window":258400}}}
        """
        writeRollout(name: "rollout-iso-delta.jsonl", lines: [sessionMeta, eventMsg])

        let extractor = CodexExtractor(rootPath: tmpDir)
        let events = try await extractor.extractAll()

        XCTAssertEqual(events.count, 1)
        let event = try XCTUnwrap(events.first)
        // Codex `last_token_usage.input_tokens` is the fresh / non-cached
        // tokens billed this turn — separate from `cached_input_tokens`.
        // So `input` is the raw value while `cacheRead` holds the cache
        // hits separately.
        XCTAssertEqual(event.tokens.input, 1000,
                       "Should use last_token_usage.input_tokens (raw, not subtracted), not cumulative")
        XCTAssertEqual(event.tokens.output, 50)
        XCTAssertEqual(event.tokens.cacheRead, 500)
        XCTAssertEqual(event.tokens.cacheWrite, 0)
        XCTAssertEqual(event.tokens.reasoning, 10)
    }
}
