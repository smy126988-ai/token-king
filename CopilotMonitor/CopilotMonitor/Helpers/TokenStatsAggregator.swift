import Foundation

/// F4: cross-provider token aggregation for the "全局统计" submenu.
/// Pure functions — no I/O. Takes a snapshot of `DayAggregate`s.
enum TokenStatsAggregator {

    struct Snapshot {
        let todayTotal: TokenBreakdown
        let weekTotal: TokenBreakdown
        let monthTotal: TokenBreakdown
    }

    /// Compute today / week / month totals from a list of `DayAggregate`s.
    ///
    /// - Parameters:
    ///   - monthTotalOverride: when non-nil, replaces the `monthTotal` derived
    ///     from `dayAggregates`. P0-2 fix: callers that already hold a
    ///     authoritative month total (e.g. `TokenUsageStore.fetchMonthAggregatesSum`,
    ///     which reads `month_aggregates`) should pass it here so the F4 "本月"
    ///     row and the F1 "本月 Token" header reflect the full month instead
    ///     of the partial `day_aggregates` subset.
    static func snapshot(dayAggregates: [DayAggregate],
                         todayString: String,
                         weekStart: Date,
                         weekEnd: Date,
                         monthPrefix: String,
                         monthTotalOverride: TokenBreakdown? = nil) -> Snapshot {
        let todayTotal = dayAggregates
            .filter { $0.day == todayString }
            .reduce(TokenBreakdown.zero) { $0.adding($1.tokens) }
        let weekTotal = dayAggregates
            .filter { agg in
                guard let dayDate = parseDay(agg.day) else { return false }
                return dayDate >= weekStart && dayDate <= weekEnd
            }
            .reduce(TokenBreakdown.zero) { $0.adding($1.tokens) }
        let monthTotalFromDays = dayAggregates
            .filter { $0.day.hasPrefix(monthPrefix) }
            .reduce(TokenBreakdown.zero) { $0.adding($1.tokens) }
        let monthTotal = monthTotalOverride ?? monthTotalFromDays
        return Snapshot(todayTotal: todayTotal, weekTotal: weekTotal, monthTotal: monthTotal)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = .utc
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func parseDay(_ s: String) -> Date? {
        dayFormatter.date(from: s)
    }
}
