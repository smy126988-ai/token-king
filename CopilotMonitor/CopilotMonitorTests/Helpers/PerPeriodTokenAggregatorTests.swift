import XCTest
@testable import OpenCode_Bar

/// F4 redesign: pure-function aggregator tests for `PerPeriodTokenAggregator`.
/// Verifies that `[DayAggregate]` rows (provider x model x day) collapse into
/// per-provider totals under the three period filters (today / week / month).
final class PerPeriodTokenAggregatorTests: XCTestCase {

    func testAggregateTodayGroupsByProviderAndSumsAllFields() {
        let aggregates = [
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-07-08", tokens: TokenBreakdown(input: 100, output: 50, cacheRead: 30, cacheWrite: 20, reasoning: 5)),
            DayAggregate(provider: "kimi", model: "kimi-k2.6", day: "2026-07-08", tokens: TokenBreakdown(input: 200, output: 100, cacheRead: 60, cacheWrite: 40, reasoning: 10)),
            DayAggregate(provider: "claude", model: "claude-sonnet-4-5", day: "2026-07-08", tokens: TokenBreakdown(input: 300, output: 150, cacheRead: 90, cacheWrite: 60, reasoning: 0)),
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-07-07", tokens: TokenBreakdown(input: 9999, output: 0, cacheRead: 0, cacheWrite: 0)),
        ]
        let result = PerPeriodTokenAggregator.aggregate(
            dayAggregates: aggregates,
            for: PerPeriodFilter(
                kind: .today,
                todayString: "2026-07-08",
                weekStart: Date(), weekEnd: Date(),
                monthPrefix: "2026-07",
                dayParser: { _ in nil }
            ),
            displayNameForProviderRaw: { $0 }
        )
        XCTAssertEqual(result.count, 2, "Should collapse to 2 providers for 2026-07-08")
        let claude = result.first { $0.providerRaw == "claude" }
        XCTAssertEqual(claude?.input, 300)
        XCTAssertEqual(claude?.output, 150)
        XCTAssertEqual(claude?.cacheRead, 90)
        XCTAssertEqual(claude?.cacheWrite, 60)
        XCTAssertEqual(claude?.reasoning, 0)
        let kimi = result.first { $0.providerRaw == "kimi" }
        XCTAssertEqual(kimi?.input, 300, "100 + 200")
        XCTAssertEqual(kimi?.output, 150, "50 + 100")
        XCTAssertEqual(kimi?.cacheRead, 90, "30 + 60")
        XCTAssertEqual(kimi?.cacheWrite, 60, "20 + 40")
        XCTAssertEqual(kimi?.reasoning, 15, "5 + 10")
        // 2026-07-07 row should NOT be in today totals
    }

    func testProviderTotalExcludesCacheRead() {
        // cacheRead is CACHE HITS (re-reads of prior context), typically free on
        // OpenAI and 90% discounted on Anthropic. They are NOT the "tokens spent"
        // number the user wants to see in 今日 Token / 本周 Token / 本月 Token.
        let total = PerPeriodTokenAggregator.ProviderTotal(
            providerRaw: "kimi", displayName: "Kimi",
            input: 100, output: 50, cacheRead: 1_000_000, cacheWrite: 20, reasoning: 7
        )
        // Billable = input + output + cacheWrite + reasoning (excludes cacheRead)
        XCTAssertEqual(total.total, 177, "ProviderTotal.total must be the billable sum, excluding cacheRead")
    }

    func testProviderTotalBillableWithZeroCacheWrite() {
        // Reasoning included even when cacheWrite = 0 (still billable).
        let total = PerPeriodTokenAggregator.ProviderTotal(
            providerRaw: "claude", displayName: "Claude",
            input: 10, output: 5, cacheRead: 999, cacheWrite: 0, reasoning: 3
        )
        XCTAssertEqual(total.total, 18, "Billable = input(10) + output(5) + cacheWrite(0) + reasoning(3)")
    }

    func testAggregateEmptyDayAggregatesReturnsEmpty() {
        let result = PerPeriodTokenAggregator.aggregate(
            dayAggregates: [],
            for: PerPeriodFilter(
                kind: .today, todayString: "2026-07-08",
                weekStart: Date(), weekEnd: Date(),
                monthPrefix: "2026-07", dayParser: { _ in nil }
            ),
            displayNameForProviderRaw: { $0 }
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testAggregateMonthFilterUsesHasPrefix() {
        let aggregates = [
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-07-08", tokens: TokenBreakdown(input: 100)),
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-08-01", tokens: TokenBreakdown(input: 999)),
        ]
        let result = PerPeriodTokenAggregator.aggregate(
            dayAggregates: aggregates,
            for: PerPeriodFilter(
                kind: .month, todayString: "",
                weekStart: Date(), weekEnd: Date(),
                monthPrefix: "2026-07", dayParser: { _ in nil }
            ),
            displayNameForProviderRaw: { $0 }
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.input, 100, "Should exclude August data")
    }

    func testAggregateWeekFilterUsesDateRange() {
        let parser = utcDayParser()
        let weekStart = parser("2026-07-06") ?? Date()
        let weekEnd = parser("2026-07-12") ?? Date()
        let aggregates = [
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-07-05", tokens: TokenBreakdown(input: 999)),
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-07-06", tokens: TokenBreakdown(input: 100)),
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-07-12", tokens: TokenBreakdown(input: 200)),
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-07-13", tokens: TokenBreakdown(input: 999)),
        ]
        let result = PerPeriodTokenAggregator.aggregate(
            dayAggregates: aggregates,
            for: PerPeriodFilter(
                kind: .week, todayString: "",
                weekStart: weekStart, weekEnd: weekEnd,
                monthPrefix: "2026-07", dayParser: parser
            ),
            displayNameForProviderRaw: { $0 }
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.input, 300, "100 + 200 (in-week only)")
    }

    func testAggregateSortsByDisplayNameAscending() {
        let aggregates = [
            DayAggregate(provider: "zebra", model: "z", day: "2026-07-08", tokens: TokenBreakdown(input: 1)),
            DayAggregate(provider: "alpha", model: "a", day: "2026-07-08", tokens: TokenBreakdown(input: 1)),
            DayAggregate(provider: "Mike", model: "m", day: "2026-07-08", tokens: TokenBreakdown(input: 1)),
        ]
        let result = PerPeriodTokenAggregator.aggregate(
            dayAggregates: aggregates,
            for: PerPeriodFilter(
                kind: .today, todayString: "2026-07-08",
                weekStart: Date(), weekEnd: Date(),
                monthPrefix: "2026-07", dayParser: { _ in nil }
            ),
            displayNameForProviderRaw: { $0 }
        )
        XCTAssertEqual(result.map(\.providerRaw), ["alpha", "Mike", "zebra"])
    }

    // MARK: - PerPeriodFilter

    func testPerPeriodFilterTodayOnlyMatchesExactDay() {
        let filter = PerPeriodFilter(
            kind: .today, todayString: "2026-07-08",
            weekStart: Date(), weekEnd: Date(),
            monthPrefix: "2026-07", dayParser: { _ in nil }
        )
        XCTAssertTrue(filter.includes(day: "2026-07-08"))
        XCTAssertFalse(filter.includes(day: "2026-07-09"))
        XCTAssertFalse(filter.includes(day: "2026-07-07"))
    }

    func testPerPeriodFilterMonthMatchesPrefix() {
        let filter = PerPeriodFilter(
            kind: .month, todayString: "",
            weekStart: Date(), weekEnd: Date(),
            monthPrefix: "2026-07", dayParser: { _ in nil }
        )
        XCTAssertTrue(filter.includes(day: "2026-07-01"))
        XCTAssertTrue(filter.includes(day: "2026-07-31"))
        XCTAssertFalse(filter.includes(day: "2026-08-01"))
        XCTAssertFalse(filter.includes(day: "2026-06-30"))
    }

    func testPerPeriodFilterWeekMatchesDateRangeInclusive() {
        let parser = utcDayParser()
        let weekStart = parser("2026-07-06") ?? Date()
        let weekEnd = parser("2026-07-12") ?? Date()
        let filter = PerPeriodFilter(
            kind: .week, todayString: "",
            weekStart: weekStart, weekEnd: weekEnd,
            monthPrefix: "2026-07", dayParser: parser
        )
        XCTAssertTrue(filter.includes(day: "2026-07-06"), "Monday (week start) inclusive")
        XCTAssertTrue(filter.includes(day: "2026-07-12"), "Sunday (week end) inclusive")
        XCTAssertTrue(filter.includes(day: "2026-07-09"), "mid-week")
        XCTAssertFalse(filter.includes(day: "2026-07-05"), "Sunday before week start")
        XCTAssertFalse(filter.includes(day: "2026-07-13"), "Monday after week end")
    }

    func testPerPeriodFilterWeekRejectsUnparseableDay() {
        let filter = PerPeriodFilter(
            kind: .week, todayString: "",
            weekStart: Date(), weekEnd: Date(),
            monthPrefix: "2026-07", dayParser: { _ in nil }
        )
        XCTAssertFalse(filter.includes(day: "garbage"), "Unparseable day must be rejected")
    }

    // MARK: - Helpers

    /// UTC `yyyy-MM-dd` parser matching the production `dayFormatter` used by
    /// `TokenUsageStore` / `TokenUsageFormatter`.
    private func utcDayParser() -> (String) -> Date? {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone.utc
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return { fmt.date(from: $0) }
    }
}
