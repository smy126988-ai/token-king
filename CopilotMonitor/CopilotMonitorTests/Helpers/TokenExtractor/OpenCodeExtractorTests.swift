import XCTest
import SQLite3
@testable import OpenCode_Bar

final class OpenCodeExtractorTests: XCTestCase {

    private var tmpDir: String!
    private var dbPath: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "opencode_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        dbPath = tmpDir + "/opencode.db"

        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        sqlite3_exec(db, """
            CREATE TABLE message (
                id TEXT PRIMARY KEY,
                session_id TEXT,
                time_created INTEGER,
                time_updated INTEGER,
                data TEXT
            )
        """, nil, nil, nil)
        sqlite3_exec(db, """
            INSERT INTO message VALUES
            ('msg_1', 'ses_a', 1000, 1000, '{"role":"assistant","sessionID":"ses_a","tokens":{"input":100,"output":50,"cache":{"read":10,"write":0},"reasoning":5},"model":{"providerID":"moonshot","modelID":"kimi-for-coding"},"time":{"created":1779261697000}}'),
            ('msg_2', 'ses_a', 2000, 2000, '{"role":"assistant","sessionID":"ses_a","tokens":{"input":200,"output":100},"model":{"providerID":"anthropic","modelID":"claude-sonnet-4-5"},"time":{"created":1779261698000}}'),
            ('msg_3', 'ses_b', 3000, 3000, '{"role":"user","sessionID":"ses_b"}'),
            ('msg_4', 'ses_b', 4000, 4000, '{"role":"assistant","sessionID":"ses_b","tokens":{"input":0,"output":0},"model":{"providerID":"openai","modelID":"gpt-4o"},"time":{"created":1779261699000}}'),
            ('msg_5', 'ses_c', 5000, 5000, '{"role":"assistant","sessionID":"ses_c","tokens":{"input":50,"output":25,"cache":{"read":5,"write":0}},"model":{"providerID":"z-ai","modelID":"glm-4.6"},"time":{"created":1779261700000}}')
        """, nil, nil, nil)
        sqlite3_close(db)
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    func testExtractFromSampleData() async {
        let extractor = OpenCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertNotNil(events)
        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events.first?.source, .opencode)
    }

    func testEmptyDataSourceReturnsEmpty() async {
        let emptyDir = NSTemporaryDirectory() + "opencode_empty_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: emptyDir) }

        let extractor = OpenCodeExtractor(rootPath: emptyDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testBrokenJSONInDataSkipped() async {
        let brokenDir = NSTemporaryDirectory() + "opencode_broken_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: brokenDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: brokenDir) }

        let brokenDB = brokenDir + "/opencode.db"
        var db: OpaquePointer?
        sqlite3_open(brokenDB, &db)
        sqlite3_exec(db, """
            CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT)
        """, nil, nil, nil)
        sqlite3_exec(db, """
            INSERT INTO message VALUES
            ('msg_bad', 'ses_x', 1, 1, 'this is not valid json'),
            ('msg_ok', 'ses_x', 2, 2, '{"role":"assistant","sessionID":"ses_x","tokens":{"input":1,"output":2},"model":{"providerID":"moonshot","modelID":"kimi-for-coding"}}')
        """, nil, nil, nil)
        sqlite3_close(db)

        let extractor = OpenCodeExtractor(rootPath: brokenDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.sourceId, "opencode:ses_x:main:msg_ok")
    }

    func testMultiSessionAggregation() async {
        let extractor = OpenCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let sessionIds = Set((events ?? []).map { $0.sessionId })
        XCTAssertEqual(sessionIds.count, 3)
        XCTAssertTrue(sessionIds.contains("ses_a"))
        XCTAssertTrue(sessionIds.contains("ses_b"))
        XCTAssertTrue(sessionIds.contains("ses_c"))
    }

    func testProviderNormalizationApplied() async {
        let extractor = OpenCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let byModel = Dictionary(uniqueKeysWithValues: events.map { ($0.model, $0.provider) })

        XCTAssertEqual(byModel["kimi-for-coding"], .kimi)
        XCTAssertEqual(byModel["claude-sonnet-4-5"], .claude)
        XCTAssertEqual(byModel["gpt-4o"], .codex)
        XCTAssertEqual(byModel["glm-4.6"], .zai)
    }
}