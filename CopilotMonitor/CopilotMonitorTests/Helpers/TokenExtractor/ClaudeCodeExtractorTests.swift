import XCTest
@testable import OpenCode_Bar

final class ClaudeCodeExtractorTests: XCTestCase {

    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "claude_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: tmpDir + "/proj1", withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            atPath: tmpDir + "/proj2", withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    private func writeSample(root: String) {
        let jsonl1 = """
        {"type":"user","message":{"role":"user","content":"hi"},"timestamp":1700000000}
        {"type":"assistant","message":{"id":"m1","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":200,"cache_read_input_tokens":300}},"timestamp":1700000001}
        {"type":"assistant","message":{"id":"m2","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":500,"output_tokens":250}},"timestamp":1700000002}
        """
        try? jsonl1.write(toFile: root + "/proj1/sess1.jsonl", atomically: true, encoding: .utf8)

        let jsonl2 = """
        {"type":"assistant","message":{"id":"m3","role":"assistant","model":"claude-opus-4","usage":{"input_tokens":800,"output_tokens":400,"cache_read_input_tokens":100}},"timestamp":1700000100}
        """
        try? jsonl2.write(toFile: root + "/proj2/sess2.jsonl", atomically: true, encoding: .utf8)
    }

    func testExtractFromSampleData() async {
        writeSample(root: tmpDir)
        let extractor = ClaudeCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertNotNil(events)
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(events.allSatisfy { $0.source == .claudeCode })
        let models = Set(events.map { $0.model })
        XCTAssertTrue(models.contains("claude-sonnet-4-5"))
        XCTAssertTrue(models.contains("claude-opus-4"))
    }

    func testEmptyDataSourceReturnsEmpty() async {
        let emptyDir = NSTemporaryDirectory() + "claude_empty_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: emptyDir) }
        let extractor = ClaudeCodeExtractor(rootPath: emptyDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testBrokenLineSkipped() async {
        let brokenDir = NSTemporaryDirectory() + "claude_broken_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: brokenDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: brokenDir) }

        let jsonl = """
        not json at all
        {"type":"assistant","message":{"id":"m1","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":1,"output_tokens":2}},"timestamp":1700000000}
        {also broken
        {"type":"assistant","message":{"id":"m2","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":3,"output_tokens":4}},"timestamp":1700000001}
        """
        try? jsonl.write(toFile: brokenDir + "/sess.jsonl", atomically: true, encoding: .utf8)

        let extractor = ClaudeCodeExtractor(rootPath: brokenDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 2)
    }

    func testMultiSessionAggregation() async {
        writeSample(root: tmpDir)
        let extractor = ClaudeCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let sessionIds = Set(events.map { $0.sessionId })
        XCTAssertTrue(sessionIds.contains("sess1"))
        XCTAssertTrue(sessionIds.contains("sess2"))
    }

    func testProviderNormalizationApplied() async {
        writeSample(root: tmpDir)
        let extractor = ClaudeCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        for event in events {
            XCTAssertEqual(event.provider, .claude)
        }
    }

    func testTokenBreakdownExtraction() async {
        writeSample(root: tmpDir)
        let extractor = ClaudeCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let sonnet = events.first { $0.model == "claude-sonnet-4-5" && $0.tokens.cacheWrite > 0 }
        XCTAssertNotNil(sonnet)
        XCTAssertEqual(sonnet?.tokens.input, 1000)
        XCTAssertEqual(sonnet?.tokens.output, 500)
        XCTAssertEqual(sonnet?.tokens.cacheRead, 300)
        XCTAssertEqual(sonnet?.tokens.cacheWrite, 200)
    }

    // MARK: - ISO 8601 timestamp parsing (F2b)

    /// Claude Code stamps events with ISO 8601 like
    /// `"2026-06-24T09:44:55.227Z"`. Before the parseTimestamp fix the row
    /// collapsed to epoch 0 (1970-01-01), so every Claude event landed in
    /// 1970. This test pins the fractional-seconds path.
    func testParsesISO8601TimestampWithFractionalSeconds() async {
        let dir = tmpDir + "/iso-frac/sess1"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let jsonl = """
        {"type":"assistant","message":{"id":"m1","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"2026-06-24T09:44:55.227Z"}
        """
        try? jsonl.write(toFile: dir + "/sess1.jsonl", atomically: true, encoding: .utf8)

        let extractor = ClaudeCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []

        XCTAssertEqual(events.count, 1)
        let event = try? XCTUnwrap(events.first)
        XCTAssertNotEqual(Int(event?.timestamp.timeIntervalSince1970 ?? 0), 0,
                         "ISO 8601 timestamp must not collapse to epoch 0")
        let utc = TimeZone(identifier: "UTC") ?? TimeZone.current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                       from: event?.timestamp ?? Date())
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 6)
        XCTAssertEqual(comps.day, 24)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 44)
    }

    /// Same parser must also accept plain ISO 8601 (no fractional seconds)
    /// in case a future Claude CLI build drops the `.227Z` suffix.
    func testParsesISO8601TimestampWithoutFractionalSeconds() async {
        let dir = tmpDir + "/iso-noflac/sess1"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let jsonl = """
        {"type":"assistant","message":{"id":"m1","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"2026-06-24T09:44:55Z"}
        """
        try? jsonl.write(toFile: dir + "/sess1.jsonl", atomically: true, encoding: .utf8)

        let extractor = ClaudeCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []

        XCTAssertEqual(events.count, 1)
        let event = try? XCTUnwrap(events.first)
        XCTAssertNotEqual(Int(event?.timestamp.timeIntervalSince1970 ?? 0), 0,
                         "Plain ISO 8601 timestamp must not collapse to epoch 0")
    }

    /// A row with a garbage timestamp string must not crash the extractor.
    /// The pre-fix `parseTimestamp` returned nil for unparseable input, so
    /// the caller fell back to `Date(timeIntervalSince1970: 0)` — a 1970
    /// stamp. The post-fix parser also returns nil for garbage and the
    /// same fallback applies, but the extractor must survive without
    /// throwing. This test pins that "swallow garbage" contract.
    func testDoesNotCrashOnUnparseableTimestamp() async {
        let dir = tmpDir + "/garbage/sess1"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let jsonl = """
        {"type":"assistant","message":{"id":"m1","role":"assistant","model":"claude-sonnet-4-5","usage":{"input_tokens":1000,"output_tokens":500}},"timestamp":"not-a-timestamp"}
        """
        try? jsonl.write(toFile: dir + "/sess1.jsonl", atomically: true, encoding: .utf8)

        let extractor = ClaudeCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []

        XCTAssertEqual(events.count, 1, "Garbage timestamp must not skip the event")
        let event = try? XCTUnwrap(events.first)
        XCTAssertEqual(event?.timestamp, Date(timeIntervalSince1970: 0),
                       "Unparseable timestamp must fall back to epoch 0")
    }
}