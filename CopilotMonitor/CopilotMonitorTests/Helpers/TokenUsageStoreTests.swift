import XCTest
import SQLite3
@testable import OpenCode_Bar

/// F2b Task 4 — TokenUsageStore actor + SQLite tests.
final class TokenUsageStoreTests: XCTestCase {

    private var tempDBPath: String!
    private var store: TokenUsageStore!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDBPath = dir.appendingPathComponent("f2b.sqlite").path
        store = TokenUsageStore(dbPath: tempDBPath)
    }

    override func tearDown() async throws {
        try? await store?.close()
        if let path = tempDBPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        try await super.tearDown()
    }

    private func makeEvent(
        provider: Provider = .claude,
        model: String = "claude-sonnet-4-5",
        source: TokenSource = .claudeCode,
        sourceId: String,
        tokens: TokenBreakdown = TokenBreakdown(input: 10, output: 5),
        timestamp: Date = Date()
    ) -> TokenEvent {
        TokenEvent(
            provider: provider,
            model: model,
            source: source,
            sessionId: "sess-\(sourceId)",
            timestamp: timestamp,
            tokens: tokens,
            sourceId: sourceId
        )
    }

    // MARK: - 1. dedup

    func testUpsertAndDedup() async throws {
        let e1 = makeEvent(sourceId: "dup-1")
        let e2 = makeEvent(sourceId: "dup-1")
        try await store.upsertEvent(e1)
        try await store.upsertEvent(e2)
        let count = try await countRows(in: "token_events")
        XCTAssertEqual(count, 1, "Same sourceId should dedup to 1 row")
    }

    // MARK: - 2. aggregate correctness

    func testMonthAggregateCorrectness() async throws {
        try await store.upsertEvent(makeEvent(
            provider: .claude, model: "claude-sonnet", sourceId: "a",
            tokens: TokenBreakdown(input: 100, output: 50)
        ))
        try await store.upsertEvent(makeEvent(
            provider: .claude, model: "claude-sonnet", sourceId: "b",
            tokens: TokenBreakdown(input: 200, output: 80)
        ))
        try await store.upsertEvent(makeEvent(
            provider: .kimi, model: "kimi-k2", sourceId: "c",
            tokens: TokenBreakdown(input: 500, output: 100)
        ))
        try await store.refreshMonthAggregates()
        let aggregates = await store.fetchMonthAggregates()
        let claude = aggregates.first { $0.provider == "claude" && $0.model == "claude-sonnet" }
        XCTAssertEqual(claude?.tokens.input, 300)
        XCTAssertEqual(claude?.tokens.output, 130)
        let kimi = aggregates.first { $0.provider == "kimi" && $0.model == "kimi-k2" }
        XCTAssertEqual(kimi?.tokens.input, 500)
        XCTAssertEqual(kimi?.tokens.output, 100)
    }

    // MARK: - 3. calendar month window

    func testCalendarMonthWindow() async throws {
        let pastDate = Date(timeIntervalSince1970: 1_577_836_800)  // 2020-01-01 UTC
        try await store.upsertEvent(makeEvent(
            provider: .claude, sourceId: "past", timestamp: pastDate
        ))
        try await store.upsertEvent(makeEvent(
            provider: .claude, sourceId: "now", timestamp: Date()
        ))
        try await store.refreshMonthAggregates()
        let aggregates = await store.fetchMonthAggregates()
        let claude = aggregates.first { $0.provider == "claude" }
        XCTAssertNotNil(claude)
        XCTAssertEqual(claude?.tokens.input, 10, "Only current month events should aggregate")
    }

    // MARK: - 4. schema version

    func testSchemaVersionCreated() async throws {
        var db: OpaquePointer?
        sqlite3_open(tempDBPath, &db)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT version FROM schema_version", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int64(stmt, 0), 1)
    }

    // MARK: - 5. empty db

    func testNoDataReturnsEmpty() async throws {
        try await store.refreshMonthAggregates()
        let aggregates = await store.fetchMonthAggregates()
        XCTAssertTrue(aggregates.isEmpty)
    }

    // MARK: - 6. idempotent 10x

    func testIdempotentUpsert() async throws {
        for _ in 0..<10 {
            try await store.upsertEvent(makeEvent(sourceId: "idempotent-1"))
        }
        let count = try await countRows(in: "token_events")
        XCTAssertEqual(count, 1)
    }

    // MARK: - 7. concurrent

    func testConcurrentUpsert() async throws {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try? await self.store.upsertEvent(
                        self.makeEvent(sourceId: "concurrent-\(i)")
                    )
                }
            }
        }
        let count = try await countRows(in: "token_events")
        XCTAssertEqual(count, 10, "10 distinct sourceIds should yield 10 rows")
    }

    // MARK: - 8. restart persistence

    func testRefreshAfterRestart() async throws {
        try await store.upsertEvent(makeEvent(
            provider: .codex, model: "gpt-4o", sourceId: "restart-1",
            tokens: TokenBreakdown(input: 999, output: 333)
        ))
        try await store.refreshMonthAggregates()
        let store2 = TokenUsageStore(dbPath: tempDBPath)
        let aggregates = await store2.fetchMonthAggregates()
        let codex = aggregates.first { $0.provider == "codex" && $0.model == "gpt-4o" }
        XCTAssertEqual(codex?.tokens.input, 999)
        XCTAssertEqual(codex?.tokens.output, 333)
        try? await store2.close()
    }

    // MARK: - 9. SQLite error path

    func testOpenFailureThrowsOnOperation() async throws {
        let invalidPath = "/dev/null/this-cannot-be-a-db.sqlite"
        let badStore = TokenUsageStore(dbPath: invalidPath)
        do {
            try await badStore.upsertEvent(makeEvent(sourceId: "bad"))
            XCTFail("Expected SQLiteError due to invalid db path")
        } catch let error as SQLiteError {
            guard case .storeUninitialized(let underlying) = error,
                  case .openFailed = underlying else {
                XCTFail("Expected storeUninitialized wrapping openFailed, got \(error)")
                return
            }
        }
    }

    // MARK: - 10. close then upsert throws

    func testCloseThenUpsertThrows() async throws {
        try await store.upsertEvent(makeEvent(sourceId: "before-close"))
        try await store.close()
        do {
            try await store.upsertEvent(makeEvent(sourceId: "after-close"))
            XCTFail("Expected SQLiteError.storeClosed")
        } catch let error as SQLiteError {
            guard case .storeClosed = error else {
                XCTFail("Expected storeClosed, got \(error)")
                return
            }
        }
    }

    // MARK: - 11. UTC month boundary consistency

    func testYearMonthUTCConsistency() async throws {
        let pst = TimeZone(identifier: "America/Los_Angeles")!
        let original = NSTimeZone.default
        NSTimeZone.default = pst
        defer { NSTimeZone.default = original }

        // 2021-01-01 00:00:00 UTC == 2020-12-31 16:00:00 PST.
        let boundary = Date(timeIntervalSince1970: 1_609_459_200)

        // currentYearMonth must use UTC, not the system time zone.
        let ym = await store.currentYearMonth(for: boundary)
        XCTAssertEqual(ym, "2021-01")

        // A local-time formatter under PST classifies the same instant as 2020-12.
        let localFormatter = DateFormatter()
        localFormatter.timeZone = pst
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.dateFormat = "yyyy-MM"
        XCTAssertEqual(localFormatter.string(from: boundary), "2020-12")

        // Insert at the UTC boundary and aggregate for the UTC month.
        try await store.upsertEvent(makeEvent(
            provider: .claude,
            sourceId: "tz-boundary",
            timestamp: boundary
        ))
        try await store.refreshMonthAggregates(for: ym)

        let january = await store.fetchMonthAggregates(yearMonth: ym)
        XCTAssertTrue(january.contains { $0.provider == "claude" },
                      "UTC boundary event must aggregate into \(ym)")

        let december = await store.fetchMonthAggregates(yearMonth: "2020-12")
        XCTAssertFalse(december.contains { $0.provider == "claude" },
                       "UTC boundary event must not leak into local-time month 2020-12")
    }

    // MARK: - helpers

    private func countRows(in table: String) async throws -> Int {
        let path = tempDBPath!
        return try await Task.detached {
            var db: OpaquePointer?
            sqlite3_open(path, &db)
            defer { sqlite3_close(db) }
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }.value
    }

    // MARK: - P0-3 snapshot upsert (REPLACE on source_id conflict)

    /// P0-3 regression: second snapshot with the same source_id MUST overwrite
    /// the first (not be silently dropped by INSERT OR IGNORE). The latest
    /// cumulative counters win, so aggregates reflect current API state.
    func testSnapshotUpsertReplacesPrevious() async throws {
        let snapshotId = "zai:api:snapshot:month"
        let e1 = makeEvent(
            provider: .zai, model: "glm-4.6", source: .zaiApi,
            sourceId: snapshotId,
            tokens: TokenBreakdown(input: 100, output: 50)
        )
        let e2 = makeEvent(
            provider: .zai, model: "glm-4.6", source: .zaiApi,
            sourceId: snapshotId,
            tokens: TokenBreakdown(input: 999, output: 333)
        )
        try await store.upsertSnapshot(e1)
        try await store.upsertSnapshot(e2)

        // One row, latest values.
        let count = try await countRows(in: "token_events")
        XCTAssertEqual(count, 1, "upsertSnapshot must replace on source_id conflict")

        try await store.refreshMonthAggregates()
        let aggregates = await store.fetchMonthAggregates()
        let zai = aggregates.first { $0.provider == "zai" && $0.model == "glm-4.6" }
        XCTAssertNotNil(zai)
        XCTAssertEqual(zai?.tokens.input, 999, "latest snapshot wins, not the first")
        XCTAssertEqual(zai?.tokens.output, 333)
    }

    /// Regression guard: streaming events (e.g. Claude Code batches) MUST keep
    /// INSERT OR IGNORE semantics via `upsertEvent`. Two events with the same
    /// source_id collapse to one row, preserving the original dedup contract.
    func testStreamingEventStillDedupes() async throws {
        let e1 = makeEvent(sourceId: "streaming-1", tokens: TokenBreakdown(input: 10))
        let e2 = makeEvent(sourceId: "streaming-1", tokens: TokenBreakdown(input: 99))
        try await store.upsertEvent(e1)
        try await store.upsertEvent(e2)
        let count = try await countRows(in: "token_events")
        XCTAssertEqual(count, 1, "upsertEvent keeps INSERT OR IGNORE semantics")
    }

    /// Snapshot with timestamp: the second upsert at a later `timestamp` must
    /// still overwrite (REPLACE on source_id is the only conflict resolved),
    /// and `ts_ms` reflects the latest snapshot.
    func testSnapshotUpsertUpdatesTimestamp() async throws {
        let snapshotId = "nanogpt:api:snapshot:month"
        // Use timestamps inside the current UTC month so month_aggregates
        // (which is filtered by year-month) actually includes them.
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        var cal = calendar
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        let earlier = cal.date(byAdding: .day, value: -1, to: now) ?? now
        let later = now
        try await store.upsertSnapshot(makeEvent(
            provider: .nanoGpt, model: "gpt-4o", source: .nanoGptApi,
            sourceId: snapshotId, tokens: TokenBreakdown(input: 1), timestamp: earlier
        ))
        try await store.upsertSnapshot(makeEvent(
            provider: .nanoGpt, model: "gpt-4o", source: .nanoGptApi,
            sourceId: snapshotId, tokens: TokenBreakdown(input: 2), timestamp: later
        ))
        let count = try await countRows(in: "token_events")
        XCTAssertEqual(count, 1)

        // The latest snapshot should drive the aggregate.
        try await store.refreshMonthAggregates()
        let aggregates = await store.fetchMonthAggregates()
        let row = aggregates.first { $0.provider == "nanoGpt" && $0.model == "gpt-4o" }
        XCTAssertEqual(row?.tokens.input, 2)
    }

    /// Two snapshots with DIFFERENT source_ids coexist (e.g. zai-month + zai-day
    /// hypothetical): the snapshot upsert never collapses distinct source_ids.
    func testSnapshotUpsertDoesNotCollapseDistinctIDs() async throws {
        try await store.upsertSnapshot(makeEvent(
            provider: .zai, model: "glm-4.6", source: .zaiApi,
            sourceId: "zai:api:snapshot:month"
        ))
        try await store.upsertSnapshot(makeEvent(
            provider: .zai, model: "glm-4.6", source: .zaiApi,
            sourceId: "zai:api:snapshot:day"
        ))
        let count = try await countRows(in: "token_events")
        XCTAssertEqual(count, 2)
    }
}
