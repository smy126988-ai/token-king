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

    func testSourceIdUsesIdFieldWhenPresent() async {
        let dir = tmpDir + "/wd_id/session1"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let ctx = """
        {"role":"_usage","token_count":100,"timestamp":1700000000,"model":"kimi-for-coding","id":"usage-xyz"}
        """
        try? ctx.write(
            toFile: dir + "/context.jsonl", atomically: true, encoding: .utf8
        )

        let extractor = KimiCLILegacyExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.sourceId, "kimi:session1:main:usage-xyz")
    }

    func testSourceIdStableOnAppend() async {
        let dir = tmpDir + "/wd_append/session1"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let path = dir + "/context.jsonl"
        let line1 = "{\"role\":\"_usage\",\"token_count\":100,\"timestamp\":1700000000,\"model\":\"kimi-for-coding\"}"
        let line2 = "{\"role\":\"_usage\",\"token_count\":200,\"timestamp\":1700000001,\"model\":\"kimi-for-coding\"}"

        try? line1.write(toFile: path, atomically: true, encoding: .utf8)
        let extractor = KimiCLILegacyExtractor(rootPath: tmpDir)
        let events1 = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events1.count, 1)
        let ids1 = Set(events1.map { $0.sourceId })

        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(("\n" + line2).data(using: .utf8)!)
            handle.closeFile()
        }

        let events2 = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events2.count, events1.count + 1)
        let ids2 = Set(events2.map { $0.sourceId })
        XCTAssertTrue(ids1.isSubset(of: ids2), "Pre-existing sourceIds must stay stable after append")
        XCTAssertEqual(ids2.subtracting(ids1).count, 1, "Exactly one new sourceId should appear")

        let newSourceId = events2.first { !ids1.contains($0.sourceId) }?.sourceId ?? ""
        XCTAssertTrue(newSourceId.hasPrefix("file:"), "Hash fallback should use file: prefix")
        XCTAssertTrue(newSourceId.contains(":hash:"), "Hash fallback should include :hash: segment")
    }

    // MARK: - ISO 8601 timestamp parsing (F2b)

    /// Kimi CLI (legacy `context.jsonl`) stamps usage rows with ISO 8601 like
    /// `"2026-06-24T09:44:55.227Z"`. Before the parseTimestamp fix every row
    /// collapsed to epoch 0 (1970-01-01). This test pins the fractional-seconds
    /// path so a regression would re-introduce the 1970 collapse.
    func testParsesISO8601TimestampWithFractionalSeconds() async {
        let dir = tmpDir + "/iso-frac/session1"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let ctx = """
        {"role":"_usage","token_count":7426,"timestamp":"2026-06-24T09:44:55.227Z","model":"kimi-for-coding"}
        """
        try? ctx.write(
            toFile: dir + "/context.jsonl", atomically: true, encoding: .utf8
        )

        let extractor = KimiCLILegacyExtractor(rootPath: tmpDir)
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
    /// in case a future kimi-cli build drops the `.227Z` suffix.
    func testParsesISO8601TimestampWithoutFractionalSeconds() async {
        let dir = tmpDir + "/iso-noflac/session1"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let ctx = """
        {"role":"_usage","token_count":7426,"timestamp":"2026-06-24T09:44:55Z","model":"kimi-for-coding"}
        """
        try? ctx.write(
            toFile: dir + "/context.jsonl", atomically: true, encoding: .utf8
        )

        let extractor = KimiCLILegacyExtractor(rootPath: tmpDir)
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
        let dir = tmpDir + "/garbage/session1"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let ctx = """
        {"role":"_usage","token_count":7426,"timestamp":"not-a-timestamp","model":"kimi-for-coding"}
        """
        try? ctx.write(
            toFile: dir + "/context.jsonl", atomically: true, encoding: .utf8
        )

        let extractor = KimiCLILegacyExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []

        XCTAssertEqual(events.count, 1, "Garbage timestamp must not skip the event")
        let event = try? XCTUnwrap(events.first)
        XCTAssertEqual(event?.timestamp, Date(timeIntervalSince1970: 0),
                       "Unparseable timestamp must fall back to epoch 0")
    }
}