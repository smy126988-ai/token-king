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

    /// Pre-unification behavior: this test asserted orphan-parent events were
    /// silently dropped. After the unified-SQL refactor, the assistant message
    /// still carries a recoverable `modelID` and `tokens`; the providerID falls
    /// through to empty and is resolved via model-based normalization. The
    /// event is now extracted — using the model field to classify instead of
    /// being discarded entirely. `matchProvider("MiniMax-M3", "")` enters the
    /// minimax branch on the model name and resolves to `.minimax`.
    func testNewSchemaOrphanParentStillExtractsWithModelBasedClassification() async throws {
        let dir = NSTemporaryDirectory() + "opencode_new_orphan_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "/opencode.db"
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, """
            CREATE TABLE message (id TEXT PRIMARY KEY, session_id TEXT, time_created INTEGER, time_updated INTEGER, data TEXT)
        """, nil, nil, nil)
        sqlite3_exec(db, """
            INSERT INTO message VALUES
            ('msg_orphan_assistant', 'ses_o', 2000, 2000, '{"role":"assistant","sessionID":"ses_o","parentID":"msg_does_not_exist","tokens":{"input":100,"output":50,"reasoning":0,"cache":{"read":0,"write":0}},"modelID":"MiniMax-M3","time":{"created":1781070432579}}')
        """, nil, nil, nil)
        sqlite3_close(db)

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []

        XCTAssertEqual(events.count, 1, "Orphan-parent assistant is now extracted (not silently dropped) because the model field is recoverable")
        XCTAssertEqual(events.first?.model, "MiniMax-M3", "ModelID recovered from assistant's top-level field")
        XCTAssertEqual(events.first?.provider, .minimax, "Without a recoverable providerID the model name drives classification (MiniMax-* → minimax branch)")
        XCTAssertEqual(events.first?.tokens.input, 100)
        XCTAssertEqual(events.first?.tokens.output, 50)
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

    // MARK: - Real-world new-schema data lacks `$.sessionID` in the JSON blob.
    //
    // In production (verified against ~/.local/share/opencode/opencode.db),
    // the new schema emits assistant messages with NO `sessionID` field in
    // the `data` JSON. The session identity lives ONLY on the `message`
    // table's `session_id` column. The buggy extractor reads
    // `json_extract(data, '$.sessionID')` (always NULL for new schema) and
    // falls back to per-event message id, which breaks the per-session
    // cache delta tracking.

    private func createNewSchemaWithoutSessionIDInJSONDB() throws -> String {
        let dir = NSTemporaryDirectory() + "opencode_nosid_\(UUID().uuidString)"
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
        sqlite3_exec(db, """
            INSERT INTO message VALUES
            ('parent', 'ses_real', 1000, 1000, '{"role":"user","model":{"providerID":"openai","modelID":"gpt-4o"}}'),
            ('msg_a', 'ses_real', 2000, 2000, '{"role":"assistant","parentID":"parent","tokens":{"input":10,"output":5,"cache":{"read":1024,"write":0}},"modelID":"gpt-4o","time":{"created":1781000000000}}'),
            ('msg_b', 'ses_real', 3000, 3000, '{"role":"assistant","parentID":"parent","tokens":{"input":10,"output":5,"cache":{"read":3072,"write":0}},"modelID":"gpt-4o","time":{"created":1781000001000}}')
        """, nil, nil, nil)
        sqlite3_close(db)
        return dir
    }

    /// Two new-schema events from the same session (where the JSON has NO
    /// `$.sessionID`) MUST receive the SAME `sessionId` after extraction —
    /// i.e. the extractor must read from the `message.session_id` column,
    /// not from `json_extract(data, '$.sessionID')`.
    func testSessionIdFromNewSchemaUsesMessageTableColumn() async throws {
        let dir = try createNewSchemaWithoutSessionIDInJSONDB()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].sessionId, "ses_real",
                       "First event: sessionId must come from message.session_id column, not JSON")
        XCTAssertEqual(events[1].sessionId, "ses_real",
                       "Second event: same session_id as first — the bug would emit per-event message id")
        XCTAssertNotEqual(events[0].sessionId, events[0].sourceId,
                          "sessionId must not be a per-event message id (would defeat cache delta tracking)")
    }

    /// Across 3 new-schema events with cumulative cache values, deltas must
    /// be small (a few K per turn), not the full cumulative value (200K+).
    /// The bug — using per-event message id as the cacheState key —
    /// causes each new-schema event to start fresh state and emit the full
    /// cumulative value as the "delta".
    func testCacheReadDeltaAcrossMultipleEventsInSameSession() async throws {
        let dir = NSTemporaryDirectory() + "opencode_nosid_cum_\(UUID().uuidString)"
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
            ('parent', 'ses_real', 1000, 1000, '{"role":"user","model":{"providerID":"openai","modelID":"gpt-4o"}}'),
            ('ev1', 'ses_real', 2000, 2000, '{"role":"assistant","parentID":"parent","tokens":{"input":10,"output":5,"cache":{"read":2000,"write":0}},"modelID":"gpt-4o","time":{"created":1781000000000}}'),
            ('ev2', 'ses_real', 3000, 3000, '{"role":"assistant","parentID":"parent","tokens":{"input":10,"output":5,"cache":{"read":4500,"write":0}},"modelID":"gpt-4o","time":{"created":1781000001000}}'),
            ('ev3', 'ses_real', 4000, 4000, '{"role":"assistant","parentID":"parent","tokens":{"input":10,"output":5,"cache":{"read":6200,"write":0}},"modelID":"gpt-4o","time":{"created":1781000002000}}')
        """, nil, nil, nil)
        sqlite3_close(db)

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 3)
        let sessions = Set(events.map(\.sessionId))
        XCTAssertEqual(sessions, ["ses_real"],
                       "All 3 events must share the same sessionId (column), not per-event message ids")
        XCTAssertEqual(events[0].tokens.cacheRead, 2000,
                       "First event in session: full cumulative value (no prior state)")
        XCTAssertEqual(events[1].tokens.cacheRead, 2500,
                       "Second event: per-event delta = 4500 - 2000 = 2500")
        XCTAssertEqual(events[2].tokens.cacheRead, 1700,
                       "Third event: per-event delta = 6200 - 4500 = 1700")
        XCTAssertEqual(
            events.map(\.tokens.cacheRead).reduce(0, +),
            6200,
            "Sum of per-event deltas equals final cumulative value when cacheState key matches session_id"
        )
    }

    // MARK: - F2b COALESCE regression: parent providerID flow.

    /// Real-world new-schema data has the assistant message's `data.model.providerID`
    /// as NULL while the parent user message carries the actual provider. The fix
    /// joins via parentID and COALESCEs the parent's providerID first. Before the fix
    /// the WHERE clause required `model.providerID IS NULL` on the assistant AND
    /// `modelID IS NOT NULL` AND `u.data.model.providerID IS NOT NULL`, which silently
    /// dropped events whose assistant had `modelID` only — leaving every such event
    /// in the F2b DB misclassified as `.nanoGpt`.
    func testAssistantWithParentUsesParentProviderID() async throws {
        // Production-shape: assistant has top-level modelID (camelCase), no
        // `$.model.providerID`. Parent user message has `$.model.providerID`.
        let dir = try await createProductionShapeDB()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []

        XCTAssertEqual(events.count, 1,
                       "Production-shape event must be extracted (was silently dropped by old WHERE clause)")
        let event = events.first
        XCTAssertEqual(event?.provider, .xiaomiTokenPlanCN,
                       "Model 'qwen3.7-max' with parent providerID 'xiaomi-token-plan-cn' must classify as .xiaomiTokenPlanCN — NOT .nanoGpt (the bug)")
        XCTAssertEqual(event?.model, "qwen3.7-max",
                       "ModelID should be read from assistant's top-level $.modelID field")
    }

    /// Old-schema events carry `data.model.providerID` and `data.model.modelID`
    /// directly on the assistant message (no parent participation). The unified
    /// SQL must continue extracting these via the assistant fallback path when
    /// no parent is reachable.
    func testFallbackToAssistantDataWhenNoParent() async throws {
        let dir = try await createOldShapeOrphanDB()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []

        XCTAssertEqual(events.count, 1,
                       "Orphan assistant with inline model.providerID must still be extracted via fallback")
        let event = events.first
        XCTAssertEqual(event?.provider, .claude,
                       "model 'claude-sonnet-4-5' with providerID 'anthropic' (from assistant data) must classify as .claude")
        XCTAssertEqual(event?.model, "claude-sonnet-4-5",
                       "modelID should be read from assistant's inline $.model.modelID (old-schema path)")
    }

    /// Regression guard: across a mixed DB of new-schema (parent JOIN) and
    /// old-schema (assistant inline) assistant messages, every extracted event
    /// must have a non-empty `provider_id`. The unified SQL's COALESCE always
    /// picks one of the two sources so neither shape returns NULL.
    func testAllExtractedEventsHaveNonEmptyProviderID() async throws {
        // Build a DB containing one event of every shape:
        //   new-schema with parent    -> providerID from parent
        //   old-schema orphan         -> providerID from assistant inline
        //   new-schema orphan (parent ID references missing row) -> still must
        //     yield a non-empty providerID via assistant inline fallback if
        //     available
        let dir = NSTemporaryDirectory() + "opencode_coalesce_guard_\(UUID().uuidString)"
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
            ('p_new', 'ses_x', 1000, 1000, '{"role":"user","model":{"providerID":"minimax-cn","modelID":"MiniMax-M3"}}'),
            ('ev_new', 'ses_x', 2000, 2000, '{"role":"assistant","parentID":"p_new","tokens":{"input":1,"output":2,"cache":{"read":0,"write":0}},"modelID":"MiniMax-M3","time":{"created":1700000001000}}'),
            ('ev_old', 'ses_y', 3000, 3000, '{"role":"assistant","tokens":{"input":1,"output":2,"cache":{"read":0,"write":0}},"model":{"providerID":"anthropic","modelID":"claude-sonnet-4-5"},"time":{"created":1700000002000}}')
        """, nil, nil, nil)
        sqlite3_close(db)

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []

        XCTAssertEqual(events.count, 2,
                       "Both shapes must be extracted via the unified SQL")
        for event in events {
            // Every extracted event must have a non-empty provider_id flowing
            // through TokenNormalizer. The old code's WHERE clause would drop
            // events with no providerID fallback and the remaining ones with
            // unknown shapes would fall through to `.nanoGpt` silently.
            XCTAssertNotEqual(event.provider, .nanoGpt,
                              "Event \(event.sourceId) (\(event.model)) misclassified as .nanoGpt — the bug resurfacing")
        }
    }

    // MARK: - Helpers for COALESCE regression tests

    /// Builds a production-shape DB: parent user message has
    /// `$.model.providerID`, assistant has top-level `$.modelID` (no inline
    /// `$.model.providerID`). Mirrors the real row that the user reported.
    private func createProductionShapeDB() async throws -> String {
        let dir = NSTemporaryDirectory() + "opencode_prod_shape_\(UUID().uuidString)"
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
        sqlite3_exec(db, """
            INSERT INTO message VALUES
            ('user_parent', 'ses_real', 1000, 1000, '{"role":"user","model":{"providerID":"xiaomi-token-plan-cn","modelID":"qwen3.7-max"}}'),
            ('asst_msg', 'ses_real', 2000, 2000, '{"role":"assistant","parentID":"user_parent","tokens":{"input":452509,"output":574,"reasoning":0,"cache":{"read":1920,"write":0}},"modelID":"qwen3.7-max","time":{"created":1781070432579}}')
        """, nil, nil, nil)
        sqlite3_close(db)
        return dir
    }

    /// Builds an old-schema DB with no parent at all (assistant has inline
    /// `$.model.providerID` and `$.model.modelID`). Used to verify the
    /// fallback path through the assistant's own data.
    private func createOldShapeOrphanDB() async throws -> String {
        let dir = NSTemporaryDirectory() + "opencode_old_orphan_\(UUID().uuidString)"
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
        sqlite3_exec(db, """
            INSERT INTO message VALUES
            ('asst_old', 'ses_o', 2000, 2000, '{"role":"assistant","tokens":{"input":10,"output":5,"cache":{"read":0,"write":0}},"model":{"providerID":"anthropic","modelID":"claude-sonnet-4-5"},"time":{"created":1782000000000}}')
        """, nil, nil, nil)
        sqlite3_close(db)
        return dir
    }

    /// When the assistant message has BOTH an inline `$.model.providerID`
    /// AND a reachable parent with a different `$.model.providerID`,
    /// the unified SQL must prefer the parent providerID (the user's chosen
    /// provider). The old two-path code would have routed the event through
    /// the old-schema branch and used the assistant's own providerID — losing
    /// the parent signal. This test exercises the COALESCE's preference for
    /// parent data.
    func testPrefersParentProviderIDWhenAssistantAlsoHasInline() async throws {
        let dir = NSTemporaryDirectory() + "opencode_prefer_parent_\(UUID().uuidString)"
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
            ('p_kimi', 'ses_kp', 1000, 1000, '{"role":"user","model":{"providerID":"kimi-cn","modelID":"kimi-for-coding"}}'),
            ('asst_both', 'ses_kp', 2000, 2000, '{"role":"assistant","parentID":"p_kimi","tokens":{"input":10,"output":5,"cache":{"read":0,"write":0}},"model":{"providerID":"anthropic","modelID":"claude-sonnet-4-5"},"modelID":"kimi-for-coding","time":{"created":1700000001000}}')
        """, nil, nil, nil)
        sqlite3_close(db)

        let extractor = OpenCodeExtractor(rootPath: dir)
        let events = (try? await extractor.extractAll()) ?? []

        XCTAssertEqual(events.count, 1,
                       "One event expected after COALESCE unification (old two-path code emitted ONE event via old-schema path; unified SQL still emits one but with a different providerID source)")
        let event = events.first
        XCTAssertEqual(event?.provider, .kimiCN,
                       "When both inline and parent providerID exist, parent (kimi-cn) must win — old two-path code would emit .claude from the inline anthropic value")
        XCTAssertEqual(event?.model, "kimi-for-coding",
                       "modelID should also prefer parent (kimi-for-coding) over assistant's inline claude-sonnet-4-5")
    }
}