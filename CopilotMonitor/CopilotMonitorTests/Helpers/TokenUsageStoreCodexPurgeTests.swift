import XCTest
import SQLite3
@testable import OpenCode_Bar

/// F2b extension: one-shot purge for pre-fix Codex events whose `ts_ms` is 0
/// (epoch 1970-01-01) and whose token counts are session-cumulative instead
/// of per-event deltas. After the timestamp / delta fix lands, refreshing the
/// scanner would otherwise re-emit identical (or worse, no-op-purely-due-to-
/// dedup) rows. The purge lets the next refresh write correct rows.
final class TokenUsageStoreCodexPurgeTests: XCTestCase {

    private var tempDir: URL!
    private var dbPath: String!
    private var store: TokenUsageStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk-purge-codex-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbPath = tempDir.appendingPathComponent("f2b.sqlite").path
        store = TokenUsageStore(dbPath: dbPath)
    }

    override func tearDown() async throws {
        try? await store?.close()
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - helpers

    private struct SeedRow {
        let provider: String
        let source: String
        let sessionId: String
        let sourceId: String
        let tsMs: Int64
        let input: Int
        let output: Int
        let cached: Int
    }

    /// Insert one row directly with the given (provider, ts_ms, ...) so we
    /// don't depend on `upsertEvent`'s binding machinery. Source/Provider must
    /// match the values stored by the production writer for `provider`
    /// = `.codex.rawValue` ("codex") and `source` = `.codexCli.rawValue`
    /// ("codexCli").
    private func insertRow(_ row: SeedRow) throws {
        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        defer { sqlite3_close(db) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let sql = """
            INSERT INTO token_events
              (provider, model, source, session_id, ts_ms, input, output, cache_read, cache_write, reasoning, source_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            XCTFail("Failed to prepare insert statement")
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, row.provider, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, "gpt-4o", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, row.source, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, row.sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 5, row.tsMs)
        sqlite3_bind_int64(stmt, 6, Int64(row.input))
        sqlite3_bind_int64(stmt, 7, Int64(row.output))
        sqlite3_bind_int64(stmt, 8, Int64(row.cached))
        sqlite3_bind_text(stmt, 9, row.sourceId, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            XCTFail("Failed to insert row")
            return
        }
    }

    private func countRows(matching whereClause: String, args: [String] = []) -> Int {
        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        defer { sqlite3_close(db) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        let sql = "SELECT COUNT(*) FROM token_events WHERE \(whereClause)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            return -1
        }
        defer { sqlite3_finalize(stmt) }
        for (i, arg) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), arg, -1, SQLITE_TRANSIENT)
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return -1 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func rawCount() -> Int { countRows(matching: "1=1") }

    // MARK: - tests

    func testPurgeDeletesCodexRowsWithTsMsZero() async throws {
        // Three rows with ts_ms = 0 (pre-fix codex events, all stamp 1970).
        // Different sources / models / sessions to make sure the WHERE only
        // matches on provider + ts_ms, not on any other column.
        try insertRow(.init(provider: "codex", source: "codexCli",
                            sessionId: "s1", sourceId: "codex:s1:main:m1",
                            tsMs: 0, input: 100, output: 50, cached: 80))
        try insertRow(.init(provider: "codex", source: "codexCli",
                            sessionId: "s2", sourceId: "codex:s2:main:m2",
                            tsMs: 0, input: 200, output: 70, cached: 150))
        try insertRow(.init(provider: "codex", source: "codexCli",
                            sessionId: "s3", sourceId: "codex:s3:main:m3",
                            tsMs: 0, input: 300, output: 90, cached: 220))
        // And one healthy codex row that MUST survive.
        try insertRow(.init(provider: "codex", source: "codexCli",
                            sessionId: "s4", sourceId: "codex:s4:main:m4",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 5, output: 1, cached: 4))
        // And one claude row with ts_ms = 0 — should be left alone.
        try insertRow(.init(provider: "claude", source: "claudeCode",
                            sessionId: "s5", sourceId: "claude:s5:main:m5",
                            tsMs: 0, input: 999, output: 999, cached: 999))

        let deleted = try await store.purgeCodexEventsWithBadTimestamps()
        XCTAssertEqual(deleted, 3, "All 3 codex rows with ts_ms=0 should be deleted")
        XCTAssertEqual(rawCount(), 2, "1 healthy codex + 1 claude ts_ms=0 must remain")
    }

    func testPurgeIsIdempotent() async throws {
        try insertRow(.init(provider: "codex", source: "codexCli",
                            sessionId: "s1", sourceId: "codex:s1:main:m1",
                            tsMs: 0, input: 100, output: 50, cached: 80))

        let first = try await store.purgeCodexEventsWithBadTimestamps()
        let second = try await store.purgeCodexEventsWithBadTimestamps()

        XCTAssertEqual(first, 1, "First run deletes the bad row")
        XCTAssertEqual(second, 0, "Second run finds nothing to delete")
        XCTAssertEqual(rawCount(), 0)
    }

    func testPurgeReturnsZeroWhenStoreClosed() async throws {
        try await store.close()

        let deleted = try await store.purgeCodexEventsWithBadTimestamps()
        XCTAssertEqual(deleted, 0, "Closed store should be a no-op, not throw")
    }

    func testPurgeLeavesHealthyCodexRowsAlone() async throws {
        // Healthy codex rows (no ts_ms=0) — must all survive.
        try insertRow(.init(provider: "codex", source: "codexCli",
                            sessionId: "s1", sourceId: "codex:s1:main:m1",
                            tsMs: healthyMs(year: 2026, month: 4, day: 1),
                            input: 100, output: 50, cached: 80))
        try insertRow(.init(provider: "codex", source: "codexCli",
                            sessionId: "s2", sourceId: "codex:s2:main:m2",
                            tsMs: healthyMs(year: 2026, month: 4, day: 2),
                            input: 200, output: 70, cached: 150))

        let deleted = try await store.purgeCodexEventsWithBadTimestamps()
        XCTAssertEqual(deleted, 0)
        XCTAssertEqual(rawCount(), 2)
    }

    // MARK: - calendar helpers

    /// Build a (non-zero) ms timestamp for a UTC date — keeps the test
    /// fixtures self-describing instead of hardcoded epoch numbers.
    private func healthyMs(year: Int, month: Int, day: Int) -> Int64 {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: comps) ?? Date()
        return Int64(date.timeIntervalSince1970 * 1000)
    }
}
