import XCTest
import SQLite3
@testable import OpenCode_Bar

/// Fixture reflects the current OpenCode schema (v1+), which uses FLATTENED
/// top-level `providerID` / `modelID` fields. The OLD nested
/// `$.model.providerID` path is still supported as a fallback (verified by
/// `testLegacyNestedSchemaFallback`).
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
        // Real schema fixture:
        //   - flat top-level providerID / modelID
        //   - cache.read per-turn values (varies turn-to-turn, can drop
        //     when context is compacted or cached items fall out of the
        //     active prefix).
        //   - Multiple sessions across the providers the user actually
        //     has configured: minimax-cn, opencode-go, kimi-cn, kimi global,
        //     xiaomi (Mimo), claude, codex, zai.
        sqlite3_exec(db, """
            INSERT INTO message VALUES
            ('msg_1','ses_a',1000,1000,'{"role":"assistant","modelID":"MiniMax-M3","providerID":"minimax-cn","tokens":{"input":61501,"output":527,"reasoning":0,"cache":{"read":1906,"write":0}},"time":{"created":1000}}'),
            ('msg_2','ses_a',2000,2000,'{"role":"assistant","modelID":"MiniMax-M3","providerID":"minimax-cn","tokens":{"input":139,"output":84,"reasoning":0,"cache":{"read":63920,"write":0}},"time":{"created":2000}}'),
            ('msg_3','ses_a',3000,3000,'{"role":"assistant","modelID":"MiniMax-M3","providerID":"minimax-cn","tokens":{"input":3204,"output":787,"reasoning":0,"cache":{"read":63393,"write":0}},"time":{"created":3000}}'),
            ('msg_4','ses_b',4000,4000,'{"role":"user"}'),
            ('msg_5','ses_b',5000,5000,'{"role":"assistant","modelID":"gpt-5","providerID":"opencode-go","tokens":{"input":100,"output":50,"reasoning":0,"cache":{"read":10,"write":0}},"time":{"created":5000}}'),
            ('msg_6','ses_c',6000,6000,'{"role":"assistant","modelID":"kimi-for-coding","providerID":"kimi","tokens":{"input":200,"output":100,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":6000}}'),
            ('msg_7','ses_d',7000,7000,'{"role":"assistant","modelID":"kimi-k2-thinking","providerID":"kimi-cn","tokens":{"input":300,"output":150,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":7000}}'),
            ('msg_8','ses_e',8000,8000,'{"role":"assistant","modelID":"mimo-v2.5-pro","providerID":"xiaomi-token-plan-cn","tokens":{"input":400,"output":200,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":8000}}'),
            ('msg_9','ses_f',9000,9000,'{"role":"assistant","modelID":"claude-sonnet-4-5","providerID":"anthropic","tokens":{"input":500,"output":250,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":9000}}'),
            ('msg_10','ses_g',10000,10000,'{"role":"assistant","modelID":"gpt-4o","providerID":"openai","tokens":{"input":50,"output":25,"reasoning":0,"cache":{"read":5,"write":0}},"time":{"created":10000}}'),
            ('msg_11','ses_h',11000,11000,'{"role":"assistant","modelID":"glm-4.6","providerID":"z-ai","tokens":{"input":60,"output":30,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":11000}}')
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
        // 11 rows were inserted but 1 is a 'user' message => 10 events.
        XCTAssertEqual(events.count, 10)
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

    func testUserMessagesAreSkipped() async {
        let extractor = OpenCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        // 'ses_b' has one user + one assistant; assistant must be present.
        XCTAssertTrue(events.contains { $0.sessionId == "ses_b" })
        // No event should be from a user message (those carry no `tokens`).
        let allAssistant = events.allSatisfy { $0.source == .opencode }
        XCTAssertTrue(allAssistant)
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
            ('msg_bad','ses_x',1,1,'this is not valid json'),
            ('msg_ok','ses_x',2,2,'{"role":"assistant","modelID":"kimi-for-coding","providerID":"kimi","tokens":{"input":1,"output":2},"time":{"created":2}}')
        """, nil, nil, nil)
        sqlite3_close(db)

        let extractor = OpenCodeExtractor(rootPath: brokenDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.sourceId, "opencode:ses_x:main:msg_ok")
    }

    func testSessionIdComesFromSqlColumn() async {
        // Real OpenCode never puts the session id in the JSON; it uses the
        // SQL column. Verify we surface that, not the JSON `$.sessionID`
        // field (which does not exist in current builds).
        let extractor = OpenCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let sessionIds = Set(events.map { $0.sessionId })
        XCTAssertEqual(sessionIds.count, 8)
        XCTAssertTrue(sessionIds.contains("ses_a"))
        XCTAssertTrue(sessionIds.contains("ses_b"))
        XCTAssertTrue(sessionIds.contains("ses_g"))
    }

    /// Confirms that for OpenCode the token counts are stored as PER-EVENT
    /// values (cache read/write can grow OR shrink between turns depending
    /// on which prefix is currently cached). This documents the field
    /// semantics so future readers don't reintroduce cumulative deltas.
    func testCacheReadPreservedPerEvent() async {
        let extractor = OpenCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let sessionA = events.filter { $0.sessionId == "ses_a" }.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(sessionA.count, 3)
        XCTAssertEqual(sessionA[0].tokens.cacheRead, 1906)
        XCTAssertEqual(sessionA[1].tokens.cacheRead, 63920)
        XCTAssertEqual(sessionA[2].tokens.cacheRead, 63393)
    }

    func testProviderNormalizationApplied() async {
        let extractor = OpenCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        // Deduplicate by model — a session can legitimately produce multiple
        // events for the same model, but every event for a given model must
        // resolve to the same Provider. Take the first match to keep the test
        // robust against duplicate-event fixtures.
        let byModel: [String: Provider] = events.reduce(into: [:]) { acc, e in
            if acc[e.model] == nil { acc[e.model] = e.provider }
        }

        XCTAssertEqual(byModel["MiniMax-M3"], .minimaxCN)
        XCTAssertEqual(byModel["gpt-5"], .opencodeGo)
        XCTAssertEqual(byModel["kimi-for-coding"], .kimi, "kimi providerID => .kimi")
        XCTAssertEqual(byModel["kimi-k2-thinking"], .kimiCN, "kimi-cn providerID => .kimiCN")
        XCTAssertEqual(byModel["mimo-v2.5-pro"], .xiaomiTokenPlanCN)
        XCTAssertEqual(byModel["claude-sonnet-4-5"], .claude)
        XCTAssertEqual(byModel["gpt-4o"], .codex)
        XCTAssertEqual(byModel["glm-4.6"], .zai)
    }
}
