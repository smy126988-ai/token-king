import XCTest
@testable import OpenCode_Bar

final class KimiCLILegacyExtractorTests: XCTestCase {

    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "kimi_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: tmpDir + "/workdir1/session1", withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            atPath: tmpDir + "/workdir2/session2", withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    private func writeSample(root: String) {
        let ctx1 = """
        {"role":"user","content":"hi"}
        {"role":"_usage","token_count":7426,"timestamp":1700000000,"model":"kimi-for-coding"}
        {"role":"_usage","token_count":8420,"timestamp":1700000001,"model":"kimi-for-coding"}
        """
        try? ctx1.write(
            toFile: root + "/workdir1/session1/context.jsonl", atomically: true, encoding: .utf8
        )

        let ctx2 = """
        {"role":"_usage","token_count":12000,"timestamp":1700000100,"model":"kimi-k2"}
        """
        try? ctx2.write(
            toFile: root + "/workdir2/session2/context.jsonl", atomically: true, encoding: .utf8
        )
    }

    func testExtractFromSampleData() async {
        writeSample(root: tmpDir)
        let extractor = KimiCLILegacyExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertNotNil(events)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.first?.source, .kimiCli)
    }

    func testEmptyDataSourceReturnsEmpty() async {
        let emptyDir = NSTemporaryDirectory() + "kimi_empty_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: emptyDir) }
        let extractor = KimiCLILegacyExtractor(rootPath: emptyDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testBrokenLineSkipped() async {
        let brokenDir = NSTemporaryDirectory() + "kimi_broken_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: brokenDir + "/wd/sess", withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: brokenDir) }

        let jsonl = """
        not json
        {"role":"_usage","token_count":100}
        {garbled
        {"role":"_usage","token_count":200}
        """
        try? jsonl.write(
            toFile: brokenDir + "/wd/sess/context.jsonl", atomically: true, encoding: .utf8
        )

        let extractor = KimiCLILegacyExtractor(rootPath: brokenDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 2)
    }

    func testMultiSessionAggregation() async {
        writeSample(root: tmpDir)
        let extractor = KimiCLILegacyExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let sessionIds = Set(events.map { $0.sessionId })
        XCTAssertEqual(sessionIds.count, 2)
        XCTAssertTrue(sessionIds.contains("session1"))
        XCTAssertTrue(sessionIds.contains("session2"))
    }

    func testProviderNormalizationApplied() async {
        writeSample(root: tmpDir)
        let extractor = KimiCLILegacyExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        for event in events {
            XCTAssertEqual(event.provider, .kimi)
        }
    }

    func testTokenCountMapsToOutput() async {
        writeSample(root: tmpDir)
        let extractor = KimiCLILegacyExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let session1 = events.first { $0.sessionId == "session1" }
        XCTAssertNotNil(session1)
        XCTAssertEqual(session1?.tokens.output, 7426)
        XCTAssertEqual(session1?.tokens.input, 0)
    }
}
