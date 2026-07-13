import XCTest
@testable import OpenCode_Bar

/// F4: pure-function aggregator tests.
/// Verifies today / week / month aggregation from a `[DayAggregate]` list.
final class TokenStatsAggregatorTests: XCTestCase {

    func testSnapshotAggregatesTodayWeekMonth() {
        // day1: 2026-07-08 (Wednesday)
        let day1 = makeDay(provider: "kimi", model: "kimi-k2.5", day: "2026-07-08", input: 100, output: 50)
        // day2: 2026-07-06 (Monday — start of ISO week)
        let day2 = makeDay(provider: "claude", model: "claude-sonnet-4-5", day: "2026-07-06", input: 200, output: 100)
        let weekStart = Self.date(2026, 7, 6)
        let weekEnd = Self.date(2026, 7, 12)
        let snap = TokenStatsAggregator.snapshot(
            dayAggregates: [day1, day2],
            todayString: "2026-07-08",
            weekStart: weekStart, weekEnd: weekEnd,
            monthPrefix: "2026-07"
        )
        // Today: only 2026-07-08 row counts
        XCTAssertEqual(snap.todayTotal.input, 100)
        XCTAssertEqual(snap.todayTotal.output, 50)
        // Week: both days within Mon-Sun, sum all
        XCTAssertEqual(snap.weekTotal.input, 300)
        XCTAssertEqual(snap.weekTotal.output, 150)
        // Month: all rows with '2026-07' prefix
        XCTAssertEqual(snap.monthTotal.input, 300)
        XCTAssertEqual(snap.monthTotal.output, 150)
    }

    func testSnapshotEmptyAggregatesReturnsZero() {
        let snap = TokenStatsAggregator.snapshot(
            dayAggregates: [],
            todayString: "2026-07-08",
            weekStart: Date(), weekEnd: Date(),
            monthPrefix: "2026-07"
        )
        XCTAssertEqual(snap.todayTotal, TokenBreakdown.zero)
        XCTAssertEqual(snap.weekTotal, TokenBreakdown.zero)
        XCTAssertEqual(snap.monthTotal, TokenBreakdown.zero)
    }

    func testSnapshotMonthFilterIgnoresOtherMonths() {
        // Day outside the target month
        let day = makeDay(provider: "kimi", model: "kimi-k2.5", day: "2026-08-15", input: 100, output: 50)
        let snap = TokenStatsAggregator.snapshot(
            dayAggregates: [day],
            todayString: "2026-08-15",
            weekStart: Self.date(2026, 8, 11), weekEnd: Self.date(2026, 8, 17),
            monthPrefix: "2026-08"
        )
        XCTAssertEqual(snap.monthTotal.input, 100)
        // Different month prefix should yield zero
        let otherMonthSnap = TokenStatsAggregator.snapshot(
            dayAggregates: [day],
            todayString: "2026-08-15",
            weekStart: Self.date(2026, 8, 11), weekEnd: Self.date(2026, 8, 17),
            monthPrefix: "2026-07"
        )
        XCTAssertEqual(otherMonthSnap.monthTotal, TokenBreakdown.zero, "Different month prefix should not aggregate")
    }

    func testSnapshotWeekFilterIgnoresDaysOutsideRange() {
        // 2026-07-05 is Sunday of the PREVIOUS week (Mon 6/29 - Sun 7/5)
        let prevWeek = makeDay(provider: "kimi", model: "kimi-k2.5", day: "2026-07-05", input: 999)
        let thisWeek = makeDay(provider: "kimi", model: "kimi-k2.5", day: "2026-07-08", input: 100)
        let weekStart = Self.date(2026, 7, 6)
        let weekEnd = Self.date(2026, 7, 12)
        let snap = TokenStatsAggregator.snapshot(
            dayAggregates: [prevWeek, thisWeek],
            todayString: "2026-07-08",
            weekStart: weekStart, weekEnd: weekEnd,
            monthPrefix: "2026-07"
        )
        // Week should only count the 7/8 row, not the 7/5 row (previous week)
        XCTAssertEqual(snap.weekTotal.input, 100)
        // Month should still count both
        XCTAssertEqual(snap.monthTotal.input, 1099)
    }

    // P0-2 fix: `monthTotalOverride` (sourced from `month_aggregates` sum) replaces
    // the day-derived month total. This is what the F1 "本月 Token" header and F4
    // "本月" row use in production to avoid the 84% underreport caused by partial
    // `day_aggregates` (which is single-day incremental).
    func testSnapshotMonthTotalOverrideReplacesDayAggregatesMonthTotal() {
        // day_aggregates only has 2026-07-08 (monthTotalFromDays = 100); override
        // supplies the authoritative full-month total from month_aggregates.
        let dayOnly = makeDay(provider: "kimi", model: "kimi-k2.5", day: "2026-07-08", input: 100)
        let override = TokenBreakdown(input: 1_000, output: 500, cacheRead: 50_000)
        let snap = TokenStatsAggregator.snapshot(
            dayAggregates: [dayOnly],
            todayString: "2026-07-08",
            weekStart: Self.date(2026, 7, 6),
            weekEnd: Self.date(2026, 7, 12),
            monthPrefix: "2026-07",
            monthTotalOverride: override
        )
        XCTAssertEqual(snap.monthTotal.input, 1_000, "Override must replace day-derived month total")
        XCTAssertEqual(snap.monthTotal.output, 500)
        XCTAssertEqual(snap.monthTotal.cacheRead, 50_000)
        // today/week still derived from dayAggregates (override is month-only)
        XCTAssertEqual(snap.todayTotal.input, 100)
        XCTAssertEqual(snap.weekTotal.input, 100)
    }

    // P0-2 fix back-compat: when no override is supplied (e.g. older callers that
    // only know about day_aggregates), behavior must match the pre-P0-2 contract
    // — month total is summed from day_aggregates.
    func testSnapshotWithoutOverrideFallsBackToDayAggregates() {
        let dayOnly = makeDay(provider: "kimi", model: "kimi-k2.5", day: "2026-07-08", input: 100)
        let snap = TokenStatsAggregator.snapshot(
            dayAggregates: [dayOnly],
            todayString: "2026-07-08",
            weekStart: Self.date(2026, 7, 6),
            weekEnd: Self.date(2026, 7, 12),
            monthPrefix: "2026-07"
        )
        XCTAssertEqual(snap.monthTotal.input, 100, "Without override, must use dayAggregates (back-compat)")
    }

    // MARK: - Helpers

    private func makeDay(provider: String, model: String, day: String, input: Int, output: Int = 0) -> DayAggregate {
        DayAggregate(
            provider: provider, model: model, day: day,
            tokens: TokenBreakdown(input: input, output: output)
        )
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        // Hour 0 (not 12) so that day boundaries align with day-aggregates parsed
        // at 00:00 UTC via the production dayFormatter.
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 0
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone.utc
        return cal.date(from: c) ?? Date(timeIntervalSince1970: 0)
    }
}
