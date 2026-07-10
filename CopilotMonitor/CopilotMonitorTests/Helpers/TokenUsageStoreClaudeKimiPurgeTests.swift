import XCTest
import SQLite3
@testable import OpenCode_Bar

/// F2b extension: one-shot purges for pre-fix Claude Code and Kimi CLI
/// (legacy `context.jsonl`) events whose `ts_ms` is 0 (epoch 1970-01-01).
/// Both extractors' pre-fix `parseTimestamp` could not parse ISO 8601 strings
/// like `"2026-06-24T09:44:55.227Z"`, so every Claude event and every
/// legacy kimi event was stamped with epoch 0.
///
/// After the `parseTimestamp` fix lands, the next refresh re-scans the
/// source files and `INSERT OR IGNORE`s the corrected rows. Deleting the
/// bad rows lets the refresh write correct timestamps.
final class TokenUsageStoreClaudeKimiPurgeTests: XCTestCase {

    private var tempDir: URL!
    private var dbPath: String!
    private var store: TokenUsageStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk-purge-clk-\(UUID().uuidString)")
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

    /// Insert one row directly with the given (provider, source, ts_ms, ...)
    /// so we don't depend on `upsertEvent`'s binding machinery. Source/Provider
    /// must match the values stored by the production writers:
    /// - Claude Code:    provider="claude", source="claudeCode"
    /// - Kimi CLI legacy: provider="kimi",   source="kimiCli"
    /// - Kimi Code:       provider="kimi",   source="kimiCode" (NEW schema, must NOT be purged)
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
        sqlite3_bind_text(stmt, 2, "model", -1, SQLITE_TRANSIENT)
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

    // MARK: - tests

    func testPurgeDeletesClaudeRowsWithTsMsZero() async throws {
        // Three claude rows with ts_ms = 0 (pre-fix Claude Code events, all
        // stamp 1970). Different sessions to make sure the WHERE only
        // matches on provider + ts_ms, not on any other column.
        try insertRow(.init(provider: "claude", source: "claudeCode",
                            sessionId: "s1", sourceId: "claudeCode:s1:main:m1",
                            tsMs: 0, input: 100, output: 50, cached: 80))
        try insertRow(.init(provider: "claude", source: "claudeCode",
                            sessionId: "s2", sourceId: "claudeCode:s2:main:m2",
                            tsMs: 0, input: 200, output: 70, cached: 150))
        try insertRow(.init(provider: "claude", source: "claudeCode",
                            sessionId: "s3", sourceId: "claudeCode:s3:main:m3",
                            tsMs: 0, input: 300, output: 90, cached: 220))
        // And one healthy claude row that MUST survive.
        try insertRow(.init(provider: "claude", source: "claudeCode",
                            sessionId: "s4", sourceId: "claudeCode:s4:main:m4",
                            tsMs: healthyMs(year: 2026, month: 6, day: 1),
                            input: 5, output: 1, cached: 4))

        let deleted = try await store.purgeClaudeEventsWithBadTimestamps()
        XCTAssertEqual(deleted, 3, "All 3 claude rows with ts_ms=0 should be deleted")
        XCTAssertEqual(rawCount(), 1, "Only the healthy claude row must remain")
    }

    func testPurgeDeletesKimiCliRowsWithTsMsZero() async throws {
        // Three legacy kimi rows with ts_ms = 0 (pre-fix Kimi CLI events).
        try insertRow(.init(provider: "kimi", source: "kimiCli",
                            sessionId: "k1", sourceId: "kimi:k1:main:u1",
                            tsMs: 0, input: 100, output: 50, cached: 0))
        try insertRow(.init(provider: "kimi", source: "kimiCli",
                            sessionId: "k2", sourceId: "kimi:k2:main:u2",
                            tsMs: 0, input: 200, output: 70, cached: 0))
        // And one healthy legacy kimi row that MUST survive.
        try insertRow(.init(provider: "kimi", source: "kimiCli",
                            sessionId: "k3", sourceId: "kimi:k3:main:u3",
                            tsMs: healthyMs(year: 2026, month: 6, day: 1),
                            input: 5, output: 1, cached: 0))
        // And one newer-schema kimi row (source = kimiCode) with ts_ms = 0.
        // The legacy purge must NOT touch it — the new schema's path is
        // independent and pre-fix pre-fix only affected kimiCli, not kimiCode.
        try insertRow(.init(provider: "kimi", source: "kimiCode",
                            sessionId: "k4", sourceId: "kimi:k4:main:u4",
                            tsMs: 0, input: 999, output: 999, cached: 0))

        let deleted = try await store.purgeKimiCliEventsWithBadTimestamps()
        XCTAssertEqual(deleted, 2, "Only the 2 legacy kimiCli rows with ts_ms=0 should be deleted")
        XCTAssertEqual(rawCount(), 2, "1 healthy kimiCli + 1 kimiCode ts_ms=0 must remain")
    }

    func testBothPurgesAreIdempotent() async throws {
        // Seed one bad row for each extractor, run each purge twice.
        try insertRow(.init(provider: "claude", source: "claudeCode",
                            sessionId: "c1", sourceId: "claudeCode:c1:main:m1",
                            tsMs: 0, input: 1, output: 2, cached: 0))
        try insertRow(.init(provider: "kimi", source: "kimiCli",
                            sessionId: "k1", sourceId: "kimi:k1:main:u1",
                            tsMs: 0, input: 1, output: 2, cached: 0))

        let c1 = try await store.purgeClaudeEventsWithBadTimestamps()
        let c2 = try await store.purgeClaudeEventsWithBadTimestamps()
        let k1 = try await store.purgeKimiCliEventsWithBadTimestamps()
        let k2 = try await store.purgeKimiCliEventsWithBadTimestamps()

        XCTAssertEqual(c1, 1, "First claude run deletes the bad row")
        XCTAssertEqual(c2, 0, "Second claude run finds nothing to delete")
        XCTAssertEqual(k1, 1, "First kimiCli run deletes the bad row")
        XCTAssertEqual(k2, 0, "Second kimiCli run finds nothing to delete")
        XCTAssertEqual(rawCount(), 0)
    }

    func testPurgesPreserveOtherProvidersAndSources() async throws {
        // Pre-fix bad rows for claude + kimiCli.
        try insertRow(.init(provider: "claude", source: "claudeCode",
                            sessionId: "c1", sourceId: "claudeCode:c1:main:m1",
                            tsMs: 0, input: 100, output: 50, cached: 80))
        try insertRow(.init(provider: "kimi", source: "kimiCli",
                            sessionId: "k1", sourceId: "kimi:k1:main:u1",
                            tsMs: 0, input: 200, output: 70, cached: 0))
        // Rows from other providers / sources that MUST survive.
        try insertRow(.init(provider: "codex", source: "codexCli",
                            sessionId: "cx1", sourceId: "codex:cx1:main:m1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 300, output: 90, cached: 220))
        try insertRow(.init(provider: "kimi", source: "kimiCode",
                            sessionId: "kc1", sourceId: "kimi:kc1:main:u1",
                            tsMs: 0, input: 400, output: 100, cached: 0))
        try insertRow(.init(provider: "opencode", source: "opencode",
                            sessionId: "o1", sourceId: "opencode:o1:main:m1",
                            tsMs: 0, input: 500, output: 120, cached: 0))

        let deletedC = try await store.purgeClaudeEventsWithBadTimestamps()
        let deletedK = try await store.purgeKimiCliEventsWithBadTimestamps()

        XCTAssertEqual(deletedC, 1, "Only the claude ts_ms=0 row must be deleted")
        XCTAssertEqual(deletedK, 1, "Only the kimiCli ts_ms=0 row must be deleted")
        XCTAssertEqual(rawCount(), 3, "codex + kimiCode + opencode must survive")
        XCTAssertEqual(countRows(matching: "provider = ?", args: ["codex"]), 1)
        XCTAssertEqual(countRows(matching: "provider = ?", args: ["kimi"]),
                       1, "Only the kimiCode row (source=kimiCode) must remain; the kimiCli ts_ms=0 row is purged")
        XCTAssertEqual(countRows(matching: "source = ?", args: ["kimiCode"]), 1,
                       "kimiCode rows must never be touched by the legacy purge")
    }
}
