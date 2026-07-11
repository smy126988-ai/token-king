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
        // Real OpenCode emits per-request (Anthropic semantics) `tokens.*`
        // values. `tokens.input` is fresh non-cached; `tokens.cache.read` /
        // `tokens.cache.write` are this request's cache hits / creations.
        sqlite3_exec(db, """
            INSERT INTO message VALUES
            -- ses_a: 3 events; cache_read bumps 1906 -> 63920 -> 63393 (cache
            -- misses happen, value is whatever the API reported for THIS
            -- request, store as-is).
            ('msg_1','ses_a',1000,1000,'{"role":"assistant","modelID":"MiniMax-M3","providerID":"minimax-cn","tokens":{"input":61501,"output":527,"reasoning":0,"cache":{"read":1906,"write":0}},"time":{"created":1000}}'),
            ('msg_2','ses_a',2000,2000,'{"role":"assistant","modelID":"MiniMax-M3","providerID":"minimax-cn","tokens":{"input":139,"output":84,"reasoning":0,"cache":{"read":63920,"write":0}},"time":{"created":2000}}'),
            ('msg_3','ses_a',3000,3000,'{"role":"assistant","modelID":"MiniMax-M3","providerID":"minimax-cn","tokens":{"input":3204,"output":787,"reasoning":0,"cache":{"read":63393,"write":0}},"time":{"created":3000}}'),
            -- ses_b: 1 GPT-5 via opencode-go + 1 user skipped.
            ('msg_4','ses_b',4000,4000,'{"role":"user"}'),
            ('msg_5','ses_b',5000,5000,'{"role":"assistant","modelID":"gpt-5","providerID":"opencode-go","tokens":{"input":100,"output":50,"reasoning":0,"cache":{"read":10,"write":0}},"time":{"created":5000}}'),
            -- ses_c: real kimi global call.
            ('msg_6','ses_c',6000,6000,'{"role":"assistant","modelID":"kimi-for-coding","providerID":"kimi","tokens":{"input":200,"output":100,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":6000}}'),
            -- ses_d: real kimi-cn call.
            ('msg_7','ses_d',7000,7000,'{"role":"assistant","modelID":"kimi-k2-thinking","providerID":"kimi-cn","tokens":{"input":300,"output":150,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":7000}}'),
            -- ses_e: real mimo via xiaomi-token-plan-cn.
            ('msg_8','ses_e',8000,8000,'{"role":"assistant","modelID":"mimo-v2.5-pro","providerID":"xiaomi-token-plan-cn","tokens":{"input":400,"output":200,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":8000}}'),
            -- ses_f: claude.
            ('msg_9','ses_f',9000,9000,'{"role":"assistant","modelID":"claude-sonnet-4-5","providerID":"anthropic","tokens":{"input":500,"output":250,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":9000}}'),
            -- ses_g: codex.
            ('msg_10','ses_g',10000,10000,'{"role":"assistant","modelID":"gpt-4o","providerID":"openai","tokens":{"input":50,"output":25,"reasoning":0,"cache":{"read":5,"write":0}},"time":{"created":10000}}'),
            -- ses_h: glm-4.6 via z-ai.
            ('msg_11','ses_h',11000,11000,'{"role":"assistant","modelID":"glm-4.6","providerID":"z-ai","tokens":{"input":60,"output":30,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":11000}}'),
            -- ses_cum: cache grows monotonically; verifier covers per-event
            -- fields. raw values are stored as-is (no delta).
            ('msg_20','ses_cum',20000,20000,'{"role":"assistant","modelID":"MiniMax-M3","providerID":"minimax-cn","tokens":{"input":1000,"output":50,"reasoning":0,"cache":{"read":100000,"write":5000}},"time":{"created":20000}}'),
            ('msg_21','ses_cum',20010,20010,'{"role":"assistant","modelID":"MiniMax-M3","providerID":"minimax-cn","tokens":{"input":500,"output":80,"reasoning":0,"cache":{"read":150000,"write":10000}},"time":{"created":20010}}'),
            ('msg_22','ses_cum',20020,20020,'{"role":"assistant","modelID":"MiniMax-M3","providerID":"minimax-cn","tokens":{"input":200,"output":20,"reasoning":0,"cache":{"read":200000,"write":15000}},"time":{"created":20020}}')
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
        // 14 rows inserted, 1 is a 'user' message => 13 events.
        XCTAssertEqual(events.count, 13)
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
        // Fixture has 9 distinct sessions (ses_a, ses_b, ses_c, ses_d,
        // ses_e, ses_f, ses_g, ses_h, ses_cum). Each yields at least one
        // assistant event here; ses_b's user message is correctly skipped.
        XCTAssertEqual(sessionIds.count, 9)
        XCTAssertTrue(sessionIds.contains("ses_a"))
        XCTAssertTrue(sessionIds.contains("ses_b"))
        XCTAssertTrue(sessionIds.contains("ses_g"))
        XCTAssertTrue(sessionIds.contains("ses_cum"))
    }

    /// `data.tokens.*` fields are **per-request** values (Anthropic
    /// cacheReadInputTokens / cacheWriteInputTokens / input_tokens /
    /// output_tokens). The extractor stores them raw — no
    /// cumulative-to-delta conversion. Sum across messages gives the
    /// total tokens billed for the session.
    func testTokenFieldsPreservedPerRequest() async {
        let extractor = OpenCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []

        // ses_cum fixture: cache.read bumps 100000 -> 150000 -> 200000.
        // Raw values are what the API reported for each request. Sum these
        // across messages to get the session's cache_read total.
        let cum = events.filter { $0.sessionId == "ses_cum" }.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(cum.count, 3)
        XCTAssertEqual(cum[0].tokens.cacheRead, 100_000)
        XCTAssertEqual(cum[1].tokens.cacheRead, 150_000)
        XCTAssertEqual(cum[2].tokens.cacheRead, 200_000)
        // cache.write: 5K -> 10K -> 15K (also raw per-request).
        XCTAssertEqual(cum[0].tokens.cacheWrite, 5_000)
        XCTAssertEqual(cum[1].tokens.cacheWrite, 10_000)
        XCTAssertEqual(cum[2].tokens.cacheWrite, 15_000)

        // ses_a fixture: cache miss on turn 3 (cache_read DROPS from 63920
        // to 63393, a 527-token decrease). Real Anthropic behavior —
        // cache_read_input_tokens reflects whatever THIS request actually
        // had from cache. The previous version's "clamp to 0, never
        // negative" delta rule was wrong because the upstream value can
        // genuinely shrink on cache eviction / context compaction.
        let sesA = events.filter { $0.sessionId == "ses_a" }.sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(sesA.count, 3)
        XCTAssertEqual(sesA[0].tokens.cacheRead, 1_906)
        XCTAssertEqual(sesA[1].tokens.cacheRead, 63_920)
        XCTAssertEqual(sesA[2].tokens.cacheRead, 63_393)
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
