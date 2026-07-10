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

    // MARK: - F2b: new JSON schema (top-level modelID + parent JOIN for providerID)

    /// Builds a fresh temp DB seeded for the new-schema test cases described
    /// below. Each test owns its own DB so cleanup is per-call.
    private func createNewSchemaDB(
        includeOldSchemaRow: Bool = false
    ) async throws -> String {
        let dir = NSTemporaryDirectory() + "opencode_new_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/opencode.db"
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, """
            CREATE TABLE message (
                id TEXT PRIMARY KEY,
                session_id TEXT,
                time_created INTEGER,
                time_updated INTEGER,
                data TEXT
            )
        """, nil, nil, nil)

        // New-schema user (parent) has model.providerID, no modelID.
        // New-schema assistant has modelID (camelCase top-level) + parentID, no model.providerID.
        var inserts = """
            INSERT INTO message VALUES
            ('msg_parent_user', 'ses_new', 1000, 1000, '{"role":"user","sessionID":"ses_new","model":{"providerID":"minimax-cn","modelID":"MiniMax-M3"}}'),
            ('msg_child_assistant', 'ses_new', 2000, 2000, '{"role":"assistant","sessionID":"ses_new","parentID":"msg_parent_user","tokens":{"input":452509,"output":574,"reasoning":0,"cache":{"read":1920,"write":0}},"modelID":"MiniMax-M3","cost":0.2731134,"time":{"created":1781070432579}}')
        """
        if includeOldSchemaRow {
            inserts += """
                ,\n            ('msg_old', 'ses_new', 500, 500, '{"role":"assistant","sessionID":"ses_new","tokens":{"input":50,"output":25},"model":{"providerID":"moonshot","modelID":"kimi-for-coding"},"time":{"created":1779261699000}}')
            """
        }
        sqlite3_exec(db, inserts, nil, nil, nil)
        sqlite3_close(db)
        return dir
    }

    func testNewSchemaMessageWithValidParentExtracted() async throws {
        let dir = try await createNewSchemaDB()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []

        XCTAssertEqual(events.count, 1)
        let event = events.first
        XCTAssertEqual(event?.provider, .minimaxCN)
        XCTAssertEqual(event?.model, "MiniMax-M3")
        XCTAssertEqual(event?.source, .opencode)
        XCTAssertEqual(event?.sessionId, "ses_new")
    }

    func testNewSchemaMessageWithoutValidParentSkipped() async throws {
        // Build a DB where the assistant's parentID references a non-existent message.
        let dir = NSTemporaryDirectory() + "opencode_new_orphan_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/opencode.db"
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, """
            CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT)
        """, nil, nil, nil)
        // Assistant with parentID pointing to a message that does NOT exist.
        sqlite3_exec(db, """
            INSERT INTO message VALUES
            ('msg_orphan_assistant', 'ses_o', 2000, 2000, '{"role":"assistant","sessionID":"ses_o","parentID":"msg_does_not_exist","tokens":{"input":100,"output":50,"reasoning":0,"cache":{"read":0,"write":0}},"modelID":"MiniMax-M3","time":{"created":1781070432579}}')
        """, nil, nil, nil)
        sqlite3_close(db)

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []

        // No valid providerID recoverable; message must be skipped (not extracted).
        XCTAssertEqual(events.count, 0)
    }

    func testNewAndOldSchemaCoexistInSameDatabase() async throws {
        let dir = try await createNewSchemaDB(includeOldSchemaRow: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []
        let byModel = Dictionary(uniqueKeysWithValues: events.map { ($0.model, $0.provider) })

        // New schema message: MiniMax-M3 via parent JOIN -> .minimaxCN.
        XCTAssertEqual(byModel["MiniMax-M3"], .minimaxCN)
        // Old schema message: kimi-for-coding via in-row model.providerID -> .kimi.
        XCTAssertEqual(byModel["kimi-for-coding"], .kimi)
        XCTAssertEqual(events.count, 2)
    }

    // MARK: - F2b fix: cacheRead/cacheWrite are session-cumulative in
    // OpenCode's `tokens.cache.read` / `tokens.cache.write` JSON fields; the
    // extractor MUST convert them to per-event deltas before storing, or the
    // F2b totals double-count the actual cache usage.

    private func createCumulativeCacheDB(
        sessionId: String,
        cumulativeCacheReads: [Int],
        cumulativeCacheWrites: [Int]? = nil,
        oldSchema: Bool = true
    ) throws -> String {
        precondition(cumulativeCacheReads.count >= 1)
        let writes = cumulativeCacheWrites ?? Array(repeating: 0, count: cumulativeCacheReads.count)
        precondition(writes.count == cumulativeCacheReads.count)

        let dir = NSTemporaryDirectory() + "opencode_cumcache_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/opencode.db"
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, """
            CREATE TABLE message (
                id TEXT PRIMARY KEY,
                session_id TEXT,
                time_created INTEGER,
                time_updated INTEGER,
                data TEXT
            )
        """, nil, nil, nil)

        var rows: [String] = []
        for (i, cacheRead) in cumulativeCacheReads.enumerated() {
            let cacheWrite = writes[i]
            let id = "msg_\(i)"
            let modelField = oldSchema
                ? "\"model\":{\"providerID\":\"openai\",\"modelID\":\"gpt-4o\"}"
                : "\"modelID\":\"gpt-4o\""
            let data = """
                {"role":"assistant","sessionID":"\(sessionId)","tokens":{"input":10,"output":5,"cache":{"read":\(cacheRead),"write":\(cacheWrite)}},\(modelField),"time":{"created":\(1700000000000 + i * 1000)}}
                """
            rows.append("('\(id)', '\(sessionId)', \(1000 + i), \(1000 + i), '\(data)')")
        }
        let sql = "INSERT INTO message VALUES " + rows.joined(separator: ", ")
        sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_close(db)
        return dir
    }

    /// With the bug, the extractor stored `cache.read` directly (cumulative).
    /// So the three events above would record 100, 250, 300 — summing to 650
    /// when the real per-event cache usage was only 300. The fixed extractor
    /// emits 100, 150, 50 (deltas of the cumulative session field).
    func testCacheReadIsPerEventDeltaNotCumulative() async throws {
        let dir = try createCumulativeCacheDB(
            sessionId: "ses_cache",
            cumulativeCacheReads: [100, 250, 300]
        )
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].tokens.cacheRead, 100,
                       "First event in session: full cumulative value as delta")
        XCTAssertEqual(events[1].tokens.cacheRead, 150,
                       "Second event: delta = 250 - 100 = 150")
        XCTAssertEqual(events[2].tokens.cacheRead, 50,
                       "Third event: delta = 300 - 250 = 50")
    }

    /// After `/compact` the cumulative cache counter resets down. The
    /// extractor must clamp the resulting negative delta to zero rather than
    /// emit a negative cacheRead.
    func testCacheReadClampedToZeroAfterCompact() async throws {
        let dir = try createCumulativeCacheDB(
            sessionId: "ses_compact",
            cumulativeCacheReads: [100, 200, 50]
        )
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].tokens.cacheRead, 100)
        XCTAssertEqual(events[1].tokens.cacheRead, 100)
        XCTAssertEqual(events[2].tokens.cacheRead, 0,
                       "Cumulative dropped (50 < 200): negative delta clamped to 0")
    }

    /// Same delta tracking applies to `cache.write` (cumulative in the source).
    func testCacheWriteIsPerEventDeltaNotCumulative() async throws {
        let dir = try createCumulativeCacheDB(
            sessionId: "ses_write",
            cumulativeCacheReads: [0, 0, 0],
            cumulativeCacheWrites: [40, 110, 110]
        )
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[0].tokens.cacheWrite, 40)
        XCTAssertEqual(events[1].tokens.cacheWrite, 70,
                       "Delta = 110 - 40 = 70")
        XCTAssertEqual(events[2].tokens.cacheWrite, 0,
                       "Cumulative unchanged: delta = 0")
    }

    /// Two distinct sessions must each track their own cumulative cacheRead
    /// independently — events from session A must not "consume" session B's
    /// previous reading.
    func testCacheReadTrackingIsScopedPerSession() async throws {
        let dirA = try createCumulativeCacheDB(
            sessionId: "ses_a",
            cumulativeCacheReads: [50, 80]
        )
        let dirB = try createCumulativeCacheDB(
            sessionId: "ses_b",
            cumulativeCacheReads: [200, 250]
        )
        defer {
            try? FileManager.default.removeItem(atPath: dirA)
            try? FileManager.default.removeItem(atPath: dirB)
        }

        let extractorA = OpenCodeExtractor(rootPath: dirA)
        let extractorB = OpenCodeExtractor(rootPath: dirB)
        let eventsA = (try? await extractorA.extractAll()) ?? []
        let eventsB = (try? await extractorB.extractAll()) ?? []

        XCTAssertEqual(eventsA.count, 2)
        XCTAssertEqual(eventsA[0].tokens.cacheRead, 50)
        XCTAssertEqual(eventsA[1].tokens.cacheRead, 30,
                       "Session A delta = 80 - 50 = 30")

        XCTAssertEqual(eventsB.count, 2)
        XCTAssertEqual(eventsB[0].tokens.cacheRead, 200,
                       "Session B starts fresh; not contaminated by session A")
        XCTAssertEqual(eventsB[1].tokens.cacheRead, 50)
    }

    /// The new-schema path (parent JOIN to recover providerID) must apply the
    /// same delta tracking. Without this, new-schema events would still
    /// store the cumulative value.
    func testCacheReadDeltaAppliedOnNewSchema() async throws {
        let dir = NSTemporaryDirectory() + "opencode_cumcache_new_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/opencode.db"
        var db: OpaquePointer?
        sqlite3_open(path, &db)
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
            ('parent', 'ses_new', 1000, 1000, '{"role":"user","sessionID":"ses_new","model":{"providerID":"openai","modelID":"gpt-4o"}}'),
            ('m1', 'ses_new', 2000, 2000, '{"role":"assistant","sessionID":"ses_new","parentID":"parent","tokens":{"input":10,"output":5,"cache":{"read":300,"write":0}},"modelID":"gpt-4o","time":{"created":1700000001000}}'),
            ('m2', 'ses_new', 3000, 3000, '{"role":"assistant","sessionID":"ses_new","parentID":"parent","tokens":{"input":10,"output":5,"cache":{"read":500,"write":0}},"modelID":"gpt-4o","time":{"created":1700000002000}}')
        """, nil, nil, nil)
        sqlite3_close(db)

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].tokens.cacheRead, 300)
        XCTAssertEqual(events[1].tokens.cacheRead, 200,
                       "New-schema path: delta = 500 - 300 = 200")
    }
}