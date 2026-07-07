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

    func testExtractFromSampleData() {
        writeSample(root: tmpDir)
        let extractor = ClaudeCodeExtractor(rootPath: tmpDir)
        let events = (try? extractor.extractAll()) ?? []
        XCTAssertNotNil(events)
        XCTAssertEqual(events.count, 3)
        XCTAssertTrue(events.allSatisfy { $0.source == .claudeCode })
        let models = Set(events.map { $0.model })
        XCTAssertTrue(models.contains("claude-sonnet-4-5"))
        XCTAssertTrue(models.contains("claude-opus-4"))
    }

    func testEmptyDataSourceReturnsEmpty() {
        let emptyDir = NSTemporaryDirectory() + "claude_empty_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: emptyDir) }
        let extractor = ClaudeCodeExtractor(rootPath: emptyDir)
        let events = (try? extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testBrokenLineSkipped() {
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
        let events = (try? extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 2)
    }

    func testMultiSessionAggregation() {
        writeSample(root: tmpDir)
        let extractor = ClaudeCodeExtractor(rootPath: tmpDir)
        let events = (try? extractor.extractAll()) ?? []
        let sessionIds = Set(events.map { $0.sessionId })
        XCTAssertTrue(sessionIds.contains("sess1"))
        XCTAssertTrue(sessionIds.contains("sess2"))
    }

    func testProviderNormalizationApplied() {
        writeSample(root: tmpDir)
        let extractor = ClaudeCodeExtractor(rootPath: tmpDir)
        let events = (try? extractor.extractAll()) ?? []
        for event in events {
            XCTAssertEqual(event.provider, .claude)
        }
    }

    func testTokenBreakdownExtraction() {
        writeSample(root: tmpDir)
        let extractor = ClaudeCodeExtractor(rootPath: tmpDir)
        let events = (try? extractor.extractAll()) ?? []
        let sonnet = events.first { $0.model == "claude-sonnet-4-5" && $0.tokens.cacheWrite > 0 }
        XCTAssertNotNil(sonnet)
        XCTAssertEqual(sonnet?.tokens.input, 1000)
        XCTAssertEqual(sonnet?.tokens.output, 500)
        XCTAssertEqual(sonnet?.tokens.cacheRead, 300)
        XCTAssertEqual(sonnet?.tokens.cacheWrite, 200)
    }
}