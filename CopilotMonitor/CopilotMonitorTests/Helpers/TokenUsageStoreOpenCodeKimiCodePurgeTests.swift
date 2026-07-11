import XCTest
import SQLite3
@testable import OpenCode_Bar

/// F2b extension: one-shot purge for pre-fix OpenCode and KimiCode events
/// whose `cacheRead` / `cacheWrite` are session-cumulative (stored verbatim)
/// instead of per-event deltas. After the extractor fix lands, refreshing the
/// scanners would otherwise re-emit identical (or no-op-purely-due-to-dedup)
/// rows. The purges let the next refresh write correct per-event delta counts.
final class TokenUsageStoreOpenCodeKimiCodePurgeTests: XCTestCase {

    private var tempDir: URL!
    private var dbPath: String!
    private var store: TokenUsageStore!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk-purge-okkp-\(UUID().uuidString)")
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
        let cachedWrite: Int
    }

    /// Insert one row directly. Source/Provider must match the values stored
    /// by the production writer for each extractor (see TokenSource enum).
    private func insertRow(_ row: SeedRow) throws {
        var db: OpaquePointer?
        sqlite3_open(dbPath, &db)
        defer { sqlite3_close(db) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let sql = """
            INSERT INTO token_events
              (provider, model, source, session_id, ts_ms, input, output, cache_read, cache_write, reasoning, source_id)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            XCTFail("Failed to prepare insert statement")
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, row.provider, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, "model-x", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, row.source, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, row.sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 5, row.tsMs)
        sqlite3_bind_int64(stmt, 6, Int64(row.input))
        sqlite3_bind_int64(stmt, 7, Int64(row.output))
        sqlite3_bind_int64(stmt, 8, Int64(row.cached))
        sqlite3_bind_int64(stmt, 9, Int64(row.cachedWrite))
        sqlite3_bind_text(stmt, 10, row.sourceId, -1, SQLITE_TRANSIENT)
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

    private func healthyMs(year: Int, month: Int, day: Int) -> Int64 {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.timeZone = TimeZone(identifier: "UTC")
        let date = Calendar(identifier: .gregorian).date(from: comps) ?? Date()
        return Int64(date.timeIntervalSince1970 * 1000)
    }

    // MARK: - purgeAllOpenCodeEvents

    func testPurgeAllOpenCodeEventsDeletesEverything() async throws {
        // A mix of opencode rows (some healthy, some ts_ms=0) — every single
        // one must be purged, regardless of timestamp.
        try insertRow(.init(provider: "kimi", source: "opencode",
                            sessionId: "s1", sourceId: "opencode:s1:main:m1",
                            tsMs: 0, input: 100, output: 50, cached: 80, cachedWrite: 0))
        try insertRow(.init(provider: "claude", source: "opencode",
                            sessionId: "s2", sourceId: "opencode:s2:main:m2",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 200, output: 70, cached: 150, cachedWrite: 5))
        try insertRow(.init(provider: "codex", source: "opencode",
                            sessionId: "s3", sourceId: "opencode:s3:main:m3",
                            tsMs: healthyMs(year: 2026, month: 6, day: 15),
                            input: 300, output: 90, cached: 220, cachedWrite: 10))

        let deleted = try await store.purgeAllOpenCodeEvents()

        XCTAssertEqual(deleted, 3, "All 3 opencode rows must be purged")
        XCTAssertEqual(countRows(matching: "source = ?", args: ["opencode"]), 0,
                       "No opencode rows should remain after the all-events purge")
    }

    func testPurgeAllOpenCodeEventsIsIdempotent() async throws {
        try insertRow(.init(provider: "claude", source: "opencode",
                            sessionId: "s1", sourceId: "opencode:s1:main:m1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 100, output: 50, cached: 80, cachedWrite: 0))

        let first = try await store.purgeAllOpenCodeEvents()
        let second = try await store.purgeAllOpenCodeEvents()

        XCTAssertEqual(first, 1, "First run deletes the opencode row")
        XCTAssertEqual(second, 0, "Second run finds nothing to delete")
        XCTAssertEqual(rawCount(), 0)
    }

    func testPurgeAllOpenCodeEventsPreservesOtherProviders() async throws {
        // Two opencode rows (both must be purged) plus rows from codex and
        // kimiCode (both must survive). Note: opencode can normalize to ANY
        // provider (.kimi, .claude, .codex, .zai, .minimax, .xiaomi etc),
        // so the WHERE clause scopes on `source = 'opencode'`, NOT on
        // `provider = ?`.
        try insertRow(.init(provider: "kimi", source: "opencode",
                            sessionId: "o1", sourceId: "opencode:o1:main:m1",
                            tsMs: 0, input: 100, output: 50, cached: 80, cachedWrite: 0))
        try insertRow(.init(provider: "claude", source: "opencode",
                            sessionId: "o2", sourceId: "opencode:o2:main:m2",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 200, output: 70, cached: 150, cachedWrite: 5))
        try insertRow(.init(provider: "codex", source: "codexCli",
                            sessionId: "c1", sourceId: "codex:c1:main:m1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 2),
                            input: 400, output: 100, cached: 300, cachedWrite: 0))
        try insertRow(.init(provider: "kimi", source: "kimiCode",
                            sessionId: "k1", sourceId: "kimiCode:k1:main:m1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 3),
                            input: 500, output: 120, cached: 380, cachedWrite: 0))

        let deleted = try await store.purgeAllOpenCodeEvents()

        XCTAssertEqual(deleted, 2, "Only the 2 opencode rows must be deleted")
        XCTAssertEqual(rawCount(), 2, "codexCli + kimiCode rows must survive")
        XCTAssertEqual(countRows(matching: "source = ?", args: ["codexCli"]), 1)
        XCTAssertEqual(countRows(matching: "source = ?", args: ["kimiCode"]), 1)
    }

    func testPurgeAllOpenCodeEventsWhenStoreClosed() async throws {
        try await store.close()

        let deleted = try await store.purgeAllOpenCodeEvents()
        XCTAssertEqual(deleted, 0, "Closed store should be a no-op, not throw")
    }

    // MARK: - purgeMismatchedOpencodeAsNanoGpt

    /// Two misclassified `opencode + nanoGpt` rows (pre-fix bug) plus one
    /// correctly-classified `opencode + kimi` row. Only the nanoGpt pair
    /// must be deleted; the correctly classified kimi row survives.
    func testPurgeMismatchedOpencodeAsNanoGptDeletesOnlyMisclassified() async throws {
        try insertRow(.init(provider: "nanoGpt", source: "opencode",
                            sessionId: "m1", sourceId: "opencode:m1:main:a1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 100, output: 50, cached: 80, cachedWrite: 0))
        try insertRow(.init(provider: "nanoGpt", source: "opencode",
                            sessionId: "m2", sourceId: "opencode:m2:main:a2",
                            tsMs: healthyMs(year: 2026, month: 5, day: 2),
                            input: 200, output: 70, cached: 150, cachedWrite: 5))
        try insertRow(.init(provider: "kimi", source: "opencode",
                            sessionId: "k1", sourceId: "opencode:k1:main:k1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 3),
                            input: 300, output: 90, cached: 220, cachedWrite: 10))

        let deleted = try await store.purgeMismatchedOpencodeAsNanoGpt()

        XCTAssertEqual(deleted, 2, "Both misclassified opencode + nanoGpt rows are removed")
        XCTAssertEqual(rawCount(), 1, "The correctly-classified opencode + kimi row survives")
        XCTAssertEqual(countRows(matching: "source = ? AND provider = ?",
                                 args: ["opencode", "nanoGpt"]), 0,
                       "No opencode + nanoGpt rows should remain")
    }

    /// Real-world: the `NanoGPTExtractor` also writes `source = 'nanoGpt'` /
    /// `provider = 'nanoGpt'` for its own data. The purge must scope on
    /// `source = 'opencode'`, leaving NanoGPT's own rows intact.
    func testPurgeMismatchedOpencodeAsNanoGptPreservesNanoGPTExtractorRows() async throws {
        try insertRow(.init(provider: "nanoGpt", source: "opencode",
                            sessionId: "o1", sourceId: "opencode:o1:main:a1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 100, output: 50, cached: 80, cachedWrite: 0))
        try insertRow(.init(provider: "nanoGpt", source: "nanoGptCli",
                            sessionId: "n1", sourceId: "nanoGptCli:n1:main:n1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 2),
                            input: 400, output: 100, cached: 300, cachedWrite: 0))

        let deleted = try await store.purgeMismatchedOpencodeAsNanoGpt()

        XCTAssertEqual(deleted, 1, "Only the (opencode, nanoGpt) row is removed")
        XCTAssertEqual(rawCount(), 1, "The NanoGPT-Extractor row (source='nanoGptCli') survives")
    }

    /// Re-running the purge is a no-op once the misclassified rows are gone.
    func testPurgeMismatchedOpencodeAsNanoGptIsIdempotent() async throws {
        try insertRow(.init(provider: "nanoGpt", source: "opencode",
                            sessionId: "o1", sourceId: "opencode:o1:main:a1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 100, output: 50, cached: 80, cachedWrite: 0))

        let first = try await store.purgeMismatchedOpencodeAsNanoGpt()
        let second = try await store.purgeMismatchedOpencodeAsNanoGpt()

        XCTAssertEqual(first, 1, "First run removes the misclassified row")
        XCTAssertEqual(second, 0, "Second run finds nothing to delete")
    }

    /// When no misclassified rows exist, the purge returns 0 without throwing.
    func testPurgeMismatchedOpencodeAsNanoGptWithNoMatches() async throws {
        try insertRow(.init(provider: "kimi", source: "opencode",
                            sessionId: "k1", sourceId: "opencode:k1:main:k1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 100, output: 50, cached: 80, cachedWrite: 0))

        let deleted = try await store.purgeMismatchedOpencodeAsNanoGpt()

        XCTAssertEqual(deleted, 0, "No opencode + nanoGpt rows means zero deletions")
        XCTAssertEqual(rawCount(), 1, "The correctly-classified row is untouched")
    }

    /// Closed store is a no-op, mirrors the other purge methods' behavior.
    func testPurgeMismatchedOpencodeAsNanoGptWhenStoreClosed() async throws {
        try await store.close()

        let deleted = try await store.purgeMismatchedOpencodeAsNanoGpt()
        XCTAssertEqual(deleted, 0, "Closed store should be a no-op, not throw")
    }

    // MARK: - purgeMismatchedOpencodeEvents (alias)

    /// `purgeMismatchedOpencodeEvents` is a thin alias that delegates to the
    /// underlying purge. It exists so call sites can use a name reflecting the
    /// broader scope (any opencode providerID routed to .nanoGpt, including
    /// the `opencode-go` / `opencode` cases) rather than the legacy specific
    /// name. This test verifies the alias actually performs the deletion.
    func testPurgeMismatchedOpencodeEventsDeletesMisclassifiedOpencodeNanoGptRows() async throws {
        // Simulate the pre-fix bug: opencode events whose providerID was
        // `opencode-go` / `opencode` (lacking normalizer rules) landed in
        // .nanoGpt. After the fix, the next refresh re-extracts them via the
        // new providerID-first routing into the correct provider bucket.
        try insertRow(.init(provider: "nanoGpt", source: "opencode",
                            sessionId: "go1", sourceId: "opencode:go1:main:g1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 100, output: 50, cached: 80, cachedWrite: 0))
        try insertRow(.init(provider: "nanoGpt", source: "opencode",
                            sessionId: "bare1", sourceId: "opencode:bare1:main:b1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 2),
                            input: 200, output: 70, cached: 150, cachedWrite: 5))
        // And a row that was correctly classified BEFORE the fix and must
        // remain after the purge (so we don't accidentally destroy good data).
        try insertRow(.init(provider: "kimi", source: "opencode",
                            sessionId: "k_ok", sourceId: "opencode:k_ok:main:k_ok",
                            tsMs: healthyMs(year: 2026, month: 5, day: 3),
                            input: 300, output: 90, cached: 220, cachedWrite: 10))

        let deleted = try await store.purgeMismatchedOpencodeEvents()

        XCTAssertEqual(deleted, 2, "Both pre-fix opencode + nanoGpt rows are removed")
        XCTAssertEqual(rawCount(), 1, "Only the correctly-classified opencode + kimi row remains")
        XCTAssertEqual(countRows(matching: "source = ? AND provider = ?",
                                 args: ["opencode", "nanoGpt"]), 0)
    }

    /// Idempotency: running `purgeMismatchedOpencodeEvents` twice is safe —
    /// the second run finds no misclassified rows and returns 0.
    func testPurgeMismatchedOpencodeEventsIsIdempotent() async throws {
        try insertRow(.init(provider: "nanoGpt", source: "opencode",
                            sessionId: "go1", sourceId: "opencode:go1:main:g1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 100, output: 50, cached: 80, cachedWrite: 0))

        let first = try await store.purgeMismatchedOpencodeEvents()
        let second = try await store.purgeMismatchedOpencodeEvents()

        XCTAssertEqual(first, 1, "First run removes the misclassified row")
        XCTAssertEqual(second, 0, "Second run finds nothing to delete")
    }

    /// Closed store is a no-op for the alias too.
    func testPurgeMismatchedOpencodeEventsWhenStoreClosed() async throws {
        try await store.close()

        let deleted = try await store.purgeMismatchedOpencodeEvents()
        XCTAssertEqual(deleted, 0, "Closed store should be a no-op, not throw")
    }

    // MARK: - purgeAllKimiCodeEvents

    func testPurgeAllKimiCodeEventsDeletesEverything() async throws {
        try insertRow(.init(provider: "kimi", source: "kimiCode",
                            sessionId: "k1", sourceId: "kimiCode:k1:main:m1",
                            tsMs: 0, input: 100, output: 50, cached: 80, cachedWrite: 0))
        try insertRow(.init(provider: "kimi", source: "kimiCode",
                            sessionId: "k2", sourceId: "kimiCode:k2:main:m2",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 200, output: 70, cached: 150, cachedWrite: 5))
        try insertRow(.init(provider: "kimi", source: "kimiCode",
                            sessionId: "k3", sourceId: "kimiCode:k3:main:m3",
                            tsMs: healthyMs(year: 2026, month: 6, day: 15),
                            input: 300, output: 90, cached: 220, cachedWrite: 10))

        let deleted = try await store.purgeAllKimiCodeEvents()

        XCTAssertEqual(deleted, 3, "All 3 kimiCode rows must be purged")
        XCTAssertEqual(countRows(matching: "source = ?", args: ["kimiCode"]), 0,
                       "No kimiCode rows should remain after the all-events purge")
    }

    func testPurgeAllKimiCodeEventsIsIdempotent() async throws {
        try insertRow(.init(provider: "kimi", source: "kimiCode",
                            sessionId: "k1", sourceId: "kimiCode:k1:main:m1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 100, output: 50, cached: 80, cachedWrite: 0))

        let first = try await store.purgeAllKimiCodeEvents()
        let second = try await store.purgeAllKimiCodeEvents()

        XCTAssertEqual(first, 1, "First run deletes the kimiCode row")
        XCTAssertEqual(second, 0, "Second run finds nothing to delete")
        XCTAssertEqual(rawCount(), 0)
    }

    func testPurgeAllKimiCodeEventsPreservesOtherProviders() async throws {
        // Two kimiCode rows (both must be purged) plus rows from opencode and
        // codex (both must survive). Scoped on `source = 'kimiCode'` so the
        // legacy `kimiCli` rows (older Kimi CLI JSONL scanner) are untouched.
        try insertRow(.init(provider: "kimi", source: "kimiCode",
                            sessionId: "k1", sourceId: "kimiCode:k1:main:m1",
                            tsMs: 0, input: 100, output: 50, cached: 80, cachedWrite: 0))
        try insertRow(.init(provider: "kimi", source: "kimiCode",
                            sessionId: "k2", sourceId: "kimiCode:k2:main:m2",
                            tsMs: healthyMs(year: 2026, month: 5, day: 1),
                            input: 200, output: 70, cached: 150, cachedWrite: 5))
        try insertRow(.init(provider: "kimi", source: "kimiCli",
                            sessionId: "k3", sourceId: "kimiCli:k3:main:m3",
                            tsMs: healthyMs(year: 2026, month: 5, day: 2),
                            input: 300, output: 90, cached: 220, cachedWrite: 0))
        try insertRow(.init(provider: "codex", source: "codexCli",
                            sessionId: "c1", sourceId: "codex:c1:main:m1",
                            tsMs: healthyMs(year: 2026, month: 5, day: 3),
                            input: 400, output: 100, cached: 300, cachedWrite: 0))

        let deleted = try await store.purgeAllKimiCodeEvents()

        XCTAssertEqual(deleted, 2, "Only the 2 kimiCode rows must be deleted")
        XCTAssertEqual(rawCount(), 2, "kimiCli + codexCli rows must survive")
        XCTAssertEqual(countRows(matching: "source = ?", args: ["kimiCli"]), 1)
        XCTAssertEqual(countRows(matching: "source = ?", args: ["codexCli"]), 1)
    }

    func testPurgeAllKimiCodeEventsWhenStoreClosed() async throws {
        try await store.close()

        let deleted = try await store.purgeAllKimiCodeEvents()
        XCTAssertEqual(deleted, 0, "Closed store should be a no-op, not throw")
    }
}