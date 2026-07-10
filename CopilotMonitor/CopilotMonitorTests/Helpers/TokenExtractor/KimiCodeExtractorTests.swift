import XCTest
@testable import OpenCode_Bar

final class KimiCodeExtractorTests: XCTestCase {

    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "kimic_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: tmpDir + "/ws1/session1/agents/main", withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            atPath: tmpDir + "/ws2/session2/agents/main", withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    private func writeSample(root: String) {
        let wire1 = """
        {"time":1700000000000,"model":"kimi-code/kimi-for-coding","usage":{"inputOther":2306,"output":420,"inputCacheRead":5120,"inputCacheCreation":0},"usageScope":"turn"}
        {"time":1700000001000,"model":"kimi-code/kimi-for-coding","usage":{"inputOther":1100,"output":300,"inputCacheRead":2048,"inputCacheCreation":100},"usageScope":"turn"}
        """
        try? wire1.write(
            toFile: root + "/ws1/session1/agents/main/wire.jsonl",
            atomically: true, encoding: .utf8
        )

        let wire2 = """
        {"time":1700000100000,"model":"kimi-code/kimi-k2","usage":{"inputOther":500,"output":100,"inputCacheRead":256,"inputCacheCreation":0},"usageScope":"turn"}
        """
        try? wire2.write(
            toFile: root + "/ws2/session2/agents/main/wire.jsonl",
            atomically: true, encoding: .utf8
        )
    }

    func testExtractFromSampleData() async {
        writeSample(root: tmpDir)
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertNotNil(events)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.first?.source, .kimiCode)
    }

    func testEmptyDataSourceReturnsEmpty() async {
        let emptyDir = NSTemporaryDirectory() + "kimic_empty_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: emptyDir) }
        let extractor = KimiCodeExtractor(rootPath: emptyDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testBrokenLineSkipped() async {
        let brokenDir = NSTemporaryDirectory() + "kimic_broken_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: brokenDir + "/ws/sess/agents/main", withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: brokenDir) }

        let jsonl = """
        not json at all
        {"time":1700000000000,"model":"kimi-code/kimi-for-coding","usage":{"inputOther":1,"output":2,"inputCacheRead":3,"inputCacheCreation":0}}
        {also broken
        """
        try? jsonl.write(
            toFile: brokenDir + "/ws/sess/agents/main/wire.jsonl",
            atomically: true, encoding: .utf8
        )

        let extractor = KimiCodeExtractor(rootPath: brokenDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 1)
    }

    func testMultiSessionAggregation() async {
        writeSample(root: tmpDir)
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let sessionIds = Set(events.map { $0.sessionId })
        XCTAssertEqual(sessionIds.count, 2)
    }

    func testProviderNormalizationApplied() async {
        writeSample(root: tmpDir)
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        for event in events {
            XCTAssertEqual(event.provider, .kimi)
        }
    }

    func testCamelCaseUsageFieldExtraction() async {
        writeSample(root: tmpDir)
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let session1 = events.first { $0.sessionId == "session1" }
        XCTAssertNotNil(session1)
        XCTAssertEqual(session1?.tokens.input, 2306)
        XCTAssertEqual(session1?.tokens.output, 420)
        XCTAssertEqual(session1?.tokens.cacheRead, 5120)
        XCTAssertEqual(session1?.tokens.cacheWrite, 0)
    }

    func testLookupKimiModelPrefersEnv() {
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        XCTAssertEqual(
            extractor.lookupKimiModel(env: ["KIMI_MODEL_NAME": "kimi-env"], configPath: nil),
            "kimi-env"
        )
    }

    func testLookupKimiModelFallsBackToConfig() throws {
        let configDir = NSTemporaryDirectory() + "kimi_config_\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: configDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: configDir) }
        let configPath = configDir + "/config.toml"
        try "default_model = \"kimi-config-model\"".write(
            toFile: configPath, atomically: true, encoding: .utf8
        )

        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        XCTAssertEqual(
            extractor.lookupKimiModel(env: [:], configPath: configPath),
            "kimi-config-model"
        )
    }

    func testLookupKimiModelEnvOverridesConfig() throws {
        let configDir = NSTemporaryDirectory() + "kimi_config_\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: configDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: configDir) }
        let configPath = configDir + "/config.toml"
        try "default_model = \"kimi-config-model\"".write(
            toFile: configPath, atomically: true, encoding: .utf8
        )

        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        XCTAssertEqual(
            extractor.lookupKimiModel(env: ["KIMI_MODEL_NAME": "kimi-env-model"], configPath: configPath),
            "kimi-env-model"
        )
    }

    func testLookupKimiModelUsesHardcodedFallback() {
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        let missingPath = "/nonexistent/kimi/config.toml"
        XCTAssertEqual(
            extractor.lookupKimiModel(env: [:], configPath: missingPath),
            "kimi-auto"
        )
    }

    func testSourceIdUsesRequestIdWhenPresent() async {
        let dir = tmpDir + "/ws_req/session1/agents/main"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let wire = """
        {"time":1700000000000,"model":"kimi-code/kimi-for-coding","request_id":"req-abc","usage":{"inputOther":10,"output":20,"inputCacheRead":0,"inputCacheCreation":0}}
        """
        try? wire.write(
            toFile: dir + "/wire.jsonl", atomically: true, encoding: .utf8
        )

        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.sourceId, "kimiCode:session1:main:req-abc")
    }

    func testSourceIdStableOnAppend() async {
        let dir = tmpDir + "/ws_append/session1/agents/main"
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        let path = dir + "/wire.jsonl"
        let line1 = "{\"time\":1700000000000,\"model\":\"kimi-code/kimi-for-coding\",\"usage\":{\"inputOther\":10,\"output\":20,\"inputCacheRead\":0,\"inputCacheCreation\":0}}"
        let line2 = "{\"time\":1700000001000,\"model\":\"kimi-code/kimi-for-coding\",\"usage\":{\"inputOther\":30,\"output\":40,\"inputCacheRead\":0,\"inputCacheCreation\":0}}"

        try? line1.write(toFile: path, atomically: true, encoding: .utf8)
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
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

    // MARK: - F2b fix: `inputCacheRead` and `inputCacheCreation` in Kimi Code
    // wire.jsonl are session-cumulative counters, not per-event deltas. The
    // extractor MUST convert them to per-event deltas per-session before
    // emitting, otherwise the F2b totals double-count the actual cache usage.

    /// Build a wire.jsonl file with explicit cumulative cache counters.
    /// Returns the directory hosting the wire.jsonl. Caller is responsible for
    /// cleanup.
    private func writeCumulativeCacheFile(
        root: String,
        sessionId: String,
        cumulativeCacheReads: [Int],
        cumulativeCacheWrites: [Int]? = nil
    ) throws {
        precondition(cumulativeCacheReads.count >= 1)
        let writes = cumulativeCacheWrites ?? Array(repeating: 0, count: cumulativeCacheReads.count)
        precondition(writes.count == cumulativeCacheReads.count)

        let dir = root + "/ws_cumcache/\(sessionId)/agents/main"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/wire.jsonl"
        var lines: [String] = []
        for (i, readVal) in cumulativeCacheReads.enumerated() {
            let writeVal = writes[i]
            let time = 1700000000000 + i * 1000
            let line = """
                {"time":\(time),"model":"kimi-code/kimi-for-coding","usage":{"inputOther":10,"output":5,"inputCacheRead":\(readVal),"inputCacheCreation":\(writeVal)}}
                """
            lines.append(line)
        }
        try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Pre-fix the three events above would store `inputCacheRead` verbatim
    /// (100, 250, 300 — summing to 650 when the real per-event cache
    /// was only 300). The fixed extractor emits per-event deltas
    /// (100, 150, 50).
    func testCacheReadIsPerEventDeltaNotCumulative() async throws {
        let root = NSTemporaryDirectory() + "kimic_cumcache_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        try writeCumulativeCacheFile(
            root: root,
            sessionId: "ses_cache",
            cumulativeCacheReads: [100, 250, 300]
        )

        let extractor = KimiCodeExtractor(rootPath: root)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].tokens.cacheRead, 100,
                       "First event in session: full cumulative value as delta")
        XCTAssertEqual(events[1].tokens.cacheRead, 150,
                       "Second event: delta = 250 - 100 = 150")
        XCTAssertEqual(events[2].tokens.cacheRead, 50,
                       "Third event: delta = 300 - 250 = 50")
    }

    /// After a Kimi Code cache reset / context compact the cumulative
    /// `inputCacheRead` value shrinks. The negative delta must be clamped to
    /// zero rather than emitted as a negative number.
    func testCacheReadClampedToZeroAfterCompact() async throws {
        let root = NSTemporaryDirectory() + "kimic_cumcache_compact_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        try writeCumulativeCacheFile(
            root: root,
            sessionId: "ses_compact",
            cumulativeCacheReads: [100, 200, 50]
        )

        let extractor = KimiCodeExtractor(rootPath: root)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].tokens.cacheRead, 100)
        XCTAssertEqual(events[1].tokens.cacheRead, 100)
        XCTAssertEqual(events[2].tokens.cacheRead, 0,
                       "Cumulative dropped (50 < 200): negative delta clamped to 0")
    }

    /// Same delta tracking applies to `inputCacheCreation`.
    func testCacheWriteIsPerEventDeltaNotCumulative() async throws {
        let root = NSTemporaryDirectory() + "kimic_cumcache_write_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: root) }
        try writeCumulativeCacheFile(
            root: root,
            sessionId: "ses_write",
            cumulativeCacheReads: [0, 0, 0],
            cumulativeCacheWrites: [40, 110, 110]
        )

        let extractor = KimiCodeExtractor(rootPath: root)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].tokens.cacheWrite, 40)
        XCTAssertEqual(events[1].tokens.cacheWrite, 70,
                       "Delta = 110 - 40 = 70")
        XCTAssertEqual(events[2].tokens.cacheWrite, 0,
                       "Cumulative unchanged: delta = 0")
    }
}