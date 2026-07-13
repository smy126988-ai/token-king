import XCTest
import SQLite3
@testable import OpenCode_Bar

/// P0-2 fix: `fetchMonthAggregatesSum` reads from `month_aggregates` instead of
/// `day_aggregates`. Verifies the new method's contract: returns the same SUM as
/// `token_events` for the given month (within the small tick-window delta), and
/// does NOT depend on `day_aggregates` being populated.
final class TokenUsageStoreMonthAggregatesSumTests: XCTestCase {

    private var tempDBPath: String!
    private var store: TokenUsageStore!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk-month-sum-\(UUID().uuidString)")
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

    // MARK: - month_aggregates-sum contract

    /// P0-2 core invariant: `fetchMonthAggregatesSum` after `refreshMonthAggregates`
    /// must equal the SUM of `token_events` for the same `year_month`. If the two
    /// diverge by more than a tick-window delta, the UI's "本月 Token" will be wrong.
    func testFetchMonthAggregatesSumEqualsTokenEventsSum() async throws {
        let ym = "2026-07"
        // Insert events spanning multiple providers/models.
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
            tokens: TokenBreakdown(input: 500, output: 100, cacheRead: 1000)
        ))
        try await store.refreshMonthAggregates(for: ym)

        let fromAggregates = await store.fetchMonthAggregatesSum(yearMonth: ym)
        let fromEvents = try await sumTokenEvents(yearMonth: ym)

        XCTAssertEqual(fromAggregates.input, fromEvents.input, "input mismatch: aggregates=\(fromAggregates.input), events=\(fromEvents.input)")
        XCTAssertEqual(fromAggregates.output, fromEvents.output, "output mismatch")
        XCTAssertEqual(fromAggregates.cacheRead, fromEvents.cacheRead, "cacheRead mismatch")
        XCTAssertEqual(fromAggregates.total, fromEvents.total, "total mismatch")
    }

    /// P0-2 regression: `fetchMonthAggregatesSum` must NOT depend on `day_aggregates`.
    /// Populate only `month_aggregates`; leave `day_aggregates` empty. The sum
    /// must still return the full month total.
    func testFetchMonthAggregatesSumDoesNotRequireDayAggregates() async throws {
        let ym = "2026-07"
        try await store.upsertEvent(makeEvent(
            provider: .codex, model: "gpt-5", sourceId: "x",
            tokens: TokenBreakdown(input: 999, output: 333, cacheRead: 50_000)
        ))
        try await store.refreshMonthAggregates(for: ym)

        // Sanity: day_aggregates should still be empty here (we did not call refreshDayAggregates).
        let days = await store.fetchDayAggregates(yearMonth: ym)
        XCTAssertTrue(days.isEmpty, "Pre-condition: day_aggregates must be empty for this test")

        let total = await store.fetchMonthAggregatesSum(yearMonth: ym)
        XCTAssertEqual(total.input, 999)
        XCTAssertEqual(total.output, 333)
        XCTAssertEqual(total.cacheRead, 50_000)
    }

    /// P0-2 regression: even when `day_aggregates` is partial (some days missing),
    /// `fetchMonthAggregatesSum` returns the full month total. This is the scenario
    /// that caused the 84% underreport in production: day_aggregates only had rows
    /// for 3 of 13 days.
    func testFetchMonthAggregatesSumReturnsFullMonthWhenDayAggregatesPartial() async throws {
        let ym = "2026-07"
        // Insert events for two distinct days.
        let day1 = date(year: 2026, month: 7, day: 1)
        let day2 = date(year: 2026, month: 7, day: 12)
        try await store.upsertEvent(makeEvent(
            provider: .claude, model: "claude-opus", sourceId: "old",
            tokens: TokenBreakdown(input: 1000, output: 100), timestamp: day1
        ))
        try await store.upsertEvent(makeEvent(
            provider: .claude, model: "claude-opus", sourceId: "new",
            tokens: TokenBreakdown(input: 2000, output: 200), timestamp: day2
        ))
        try await store.refreshMonthAggregates(for: ym)

        // Refresh day_aggregates only for day2 (mimics production RefreshActor behavior).
        try await store.refreshDayAggregates(for: day2)

        let total = await store.fetchMonthAggregatesSum(yearMonth: ym)
        XCTAssertEqual(total.input, 3000, "Month total must include BOTH days")
        XCTAssertEqual(total.output, 300)

        // And the old `fetchMonthTotalTokens` (which reads day_aggregates) WILL
        // miss day1's input — confirming the bug it used to ship.
        let dayOnlyTotal = await store.fetchMonthTotalTokens(yearMonth: ym)
        XCTAssertEqual(dayOnlyTotal.input, 2000, "Old method returns only day2 (partial)")
        XCTAssertNotEqual(dayOnlyTotal.input, total.input, "Old method must differ from full-month sum")
    }

    func testFetchMonthAggregatesSumEmptyDatabaseReturnsZero() async {
        let total = await store.fetchMonthAggregatesSum(yearMonth: "2026-07")
        XCTAssertEqual(total, TokenBreakdown.zero)
    }

    // MARK: - helpers

    private func sumTokenEvents(yearMonth: String) async throws -> TokenBreakdown {
        let path = tempDBPath!
        return try await Task.detached { [path] in
            var db: OpaquePointer?
            sqlite3_open(path, &db)
            defer { sqlite3_close(db) }
            let sql = """
                SELECT COALESCE(SUM(input), 0), COALESCE(SUM(output), 0),
                       COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0),
                       COALESCE(SUM(reasoning), 0)
                FROM token_events
                WHERE strftime('%Y-%m', ts_ms / 1000, 'unixepoch') = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                return TokenBreakdown.zero
            }
            defer { sqlite3_finalize(stmt) }
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, yearMonth, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return TokenBreakdown.zero }
            return TokenBreakdown(
                input: Int(sqlite3_column_int64(stmt, 0)),
                output: Int(sqlite3_column_int64(stmt, 1)),
                cacheRead: Int(sqlite3_column_int64(stmt, 2)),
                cacheWrite: Int(sqlite3_column_int64(stmt, 3)),
                reasoning: Int(sqlite3_column_int64(stmt, 4))
            )
        }.value
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.utc
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }
}
