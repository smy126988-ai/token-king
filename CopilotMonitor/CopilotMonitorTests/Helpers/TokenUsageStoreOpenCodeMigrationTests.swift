import XCTest
import SQLite3
@testable import OpenCode_Bar

/// F2b extension: migration of pre-existing token_events rows whose source is
/// OpenCode and whose original message providerID was one of the new targets
/// (minimax / minimax-cn / xiaomi / xiaomi-token-plan-cn). Before the migration
/// these rows were misclassified as `.nanoGpt` because TokenNormalizer did not
/// recognize the new providerIDs.
final class TokenUsageStoreOpenCodeMigrationTests: XCTestCase {

    private var tempDir: URL!
    private var f2bDBPath: String!
    private var openCodeDBPath: String!
    private var store: TokenUsageStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk-migrate-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        f2bDBPath = tempDir.appendingPathComponent("f2b.sqlite").path
        openCodeDBPath = tempDir.appendingPathComponent("opencode.db").path
        store = TokenUsageStore(dbPath: f2bDBPath)
    }

    override func tearDown() async throws {
        try? await store?.close()
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - helpers

    /// Create an OpenCode-like DB with a `message` table seeded with the given
    /// (id, providerID) pairs.
    private func seedOpenCodeDB(rows: [(id: String, providerID: String)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(openCodeDBPath, &db) == SQLITE_OK, let db else {
            XCTFail("Failed to open OpenCode DB at \(openCodeDBPath)")
            return
        }
        defer { sqlite3_close(db) }
        let create = """
            CREATE TABLE message (
                id TEXT PRIMARY KEY,
                session_id TEXT NOT NULL,
                time_created INTEGER NOT NULL,
                time_updated INTEGER NOT NULL,
                data TEXT NOT NULL
            )
        """
        guard sqlite3_exec(db, create, nil, nil, nil) == SQLITE_OK else {
            XCTFail("Failed to create message table")
            return
        }
        let insert = "INSERT INTO message (id, session_id, time_created, time_updated, data) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, insert, -1, &stmt, nil) == SQLITE_OK else {
            XCTFail("Failed to prepare insert")
            return
        }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for row in rows {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, row.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, "ses_test", -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 3, 1_700_000_000_000)
            sqlite3_bind_int64(stmt, 4, 1_700_000_000_000)
            let json = #"{"model":{"providerID":""# + row.providerID + #""}}"#
            sqlite3_bind_text(stmt, 5, json, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                XCTFail("Failed to insert row \(row.id)")
                return
            }
        }
    }

    /// Seed the F2b store with token_events that mirror the pre-migration state:
    /// provider='nanogpt' (the old misclassification), source='opencode',
    /// source_id of the form 'opencode:<sessionId>:main:<msgId>'.
    private func seedF2bEvents(openCodeMsgIDs: [String]) async throws {
        for msgId in openCodeMsgIDs {
            let event = TokenEvent(
                provider: .nanoGpt,
                model: "mimo-v2.5-pro",
                source: .opencode,
                sessionId: "ses_test",
                timestamp: Date(timeIntervalSince1970: 1_700_000_000),
                tokens: TokenBreakdown(input: 100, output: 50),
                sourceId: "opencode:ses_test:main:\(msgId)"
            )
            try await store.upsertEvent(event)
        }
    }

    private func providersForEvents(matching sourceIdLike: String) async -> [String] {
        let path = f2bDBPath!
        return await Task.detached {
            var db: OpaquePointer?
            sqlite3_open(path, &db)
            defer { sqlite3_close(db) }
            var stmt: OpaquePointer?
            let sql = "SELECT provider FROM token_events WHERE source_id LIKE ?"
            sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, sourceIdLike, -1, SQLITE_TRANSIENT)
            var providers: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                providers.append(sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? "")
            }
            return providers
        }.value
    }

    // MARK: - tests

    func testMigrationReclassifiesMiniMaxCN() async throws {
        try seedOpenCodeDB(rows: [
            (id: "msg_a", providerID: "minimax-cn"),
            (id: "msg_b", providerID: "minimax-cn-api"),
            (id: "msg_c", providerID: "minimax"),
        ])
        try await seedF2bEvents(openCodeMsgIDs: ["msg_a", "msg_b", "msg_c"])

        let updated = try await store.migrateOpenCodeProviderIDs(openCodeDBPath: openCodeDBPath)

        XCTAssertEqual(updated, 3, "All 3 rows should be reclassified")
        let providers = await providersForEvents(matching: "opencode:ses_test:main:msg_%")
        XCTAssertEqual(Set(providers), Set(["minimaxCN", "minimax"]),
                       "msg_a and msg_b -> minimaxCN, msg_c -> minimax")
    }

    func testMigrationReclassifiesXiaomiTokenPlanCN() async throws {
        try seedOpenCodeDB(rows: [
            (id: "msg_x", providerID: "xiaomi-token-plan-cn"),
            (id: "msg_y", providerID: "xiaomi"),
        ])
        try await seedF2bEvents(openCodeMsgIDs: ["msg_x", "msg_y"])

        let updated = try await store.migrateOpenCodeProviderIDs(openCodeDBPath: openCodeDBPath)

        XCTAssertEqual(updated, 2)
        let providers = await providersForEvents(matching: "opencode:ses_test:main:msg_%")
        XCTAssertEqual(Set(providers), Set(["xiaomiTokenPlanCN", "xiaomi"]))
    }

    func testMigrationLeavesUnrelatedRowsAlone() async throws {
        // OpenCode DB has only msg_k = kimi, msg_z = zai — neither is a migration target.
        try seedOpenCodeDB(rows: [
            (id: "msg_k", providerID: "kimi"),
            (id: "msg_z", providerID: "z-ai"),
        ])
        try await seedF2bEvents(openCodeMsgIDs: ["msg_k", "msg_z"])

        let updated = try await store.migrateOpenCodeProviderIDs(openCodeDBPath: openCodeDBPath)

        XCTAssertEqual(updated, 0, "No rows should be updated when OpenCode has no migration targets")
        let providers = await providersForEvents(matching: "opencode:ses_test:main:msg_%")
        XCTAssertEqual(Set(providers), Set(["nanoGpt"]),
                       "Pre-migration nanogpt rows must be untouched when source providerID is unrelated")
    }

    func testMigrationIsIdempotent() async throws {
        try seedOpenCodeDB(rows: [
            (id: "msg_i", providerID: "minimax-cn"),
        ])
        try await seedF2bEvents(openCodeMsgIDs: ["msg_i"])

        let firstRun = try await store.migrateOpenCodeProviderIDs(openCodeDBPath: openCodeDBPath)
        let secondRun = try await store.migrateOpenCodeProviderIDs(openCodeDBPath: openCodeDBPath)

        XCTAssertEqual(firstRun, 1, "First run reclassifies the row")
        XCTAssertEqual(secondRun, 0, "Second run is a no-op — row already correctly classified")
        let providers = await providersForEvents(matching: "opencode:ses_test:main:msg_i")
        XCTAssertEqual(providers, ["minimaxCN"])
    }

    func testMigrationRefreshesMonthAggregates() async throws {
        try seedOpenCodeDB(rows: [
            (id: "msg_m1", providerID: "minimax-cn"),
            (id: "msg_m2", providerID: "xiaomi-token-plan-cn"),
        ])
        try await seedF2bEvents(openCodeMsgIDs: ["msg_m1", "msg_m2"])

        _ = try await store.migrateOpenCodeProviderIDs(openCodeDBPath: openCodeDBPath)

        // Test events were seeded at 2023-11-14 — query that exact month so we
        // don't depend on the test runner's wall-clock for which year_month
        // fetchMonthAggregates() defaults to.
        let aggregates = await store.fetchMonthAggregates(yearMonth: "2023-11")
        let minimaxAgg = aggregates.first { $0.provider == "minimaxCN" }
        let xiaomiAgg = aggregates.first { $0.provider == "xiaomiTokenPlanCN" }
        XCTAssertNotNil(minimaxAgg, "minimaxCN aggregate should exist after migration + refresh")
        XCTAssertNotNil(xiaomiAgg, "xiaomiTokenPlanCN aggregate should exist after migration + refresh")
        XCTAssertEqual(minimaxAgg?.tokens.input, 100)
        XCTAssertEqual(xiaomiAgg?.tokens.input, 100)
        // The pre-migration nanogpt rows must NOT appear in aggregates anymore.
        XCTAssertNil(aggregates.first { $0.provider == "nanoGpt" },
                     "nanogpt aggregate should be absent since the migrated rows no longer classify as nanoGpt")
    }

    func testMigrationSkipsWhenOpenCodeDBMissing() async throws {
        let missing = tempDir.appendingPathComponent("does-not-exist.db").path
        let updated = try await store.migrateOpenCodeProviderIDs(openCodeDBPath: missing)
        XCTAssertEqual(updated, 0, "Missing OpenCode DB should be a no-op")
    }
}
