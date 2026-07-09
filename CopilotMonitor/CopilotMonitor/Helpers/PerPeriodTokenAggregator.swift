import Foundation

/// F4 redesign: pure-function aggregator that converts `[DayAggregate]`
/// (per provider x model x day, already stored in the F2b `day_aggregates` table)
/// into per-period per-provider Input/Output/Cache totals.
///
/// Decoupled from any UIKit / AppKit / actor dependency so it can be unit-tested
/// without constructing a `StatusBarController` or wiring an SQLite store.
/// The async data fetch lives in `StatusBarController.refreshTopLevelTokenCache`.
enum PerPeriodTokenAggregator {

    /// One row of the per-period per-provider breakdown rendered under each
    /// top-level "今日 Token: X.Xk" / "本周 Token: X.Xk" / "本月 Token: X.Xk"
    /// submenu.
    struct ProviderTotal {
        let providerRaw: String       // F2b `Provider.rawValue`: e.g. "kimi" / "kimiCN" / "claude"
        let displayName: String       // UI label, e.g. "Kimi for Coding" / "Kimi for Coding（国内）"
        let input: Int
        let output: Int
        let cacheRead: Int
        let cacheWrite: Int
        let reasoning: Int

        var total: Int { input + output + cacheRead + cacheWrite + reasoning }
    }

    /// Aggregate day_aggregates into per-provider totals, filtered to `period`.
    ///
    /// - Parameters:
    ///   - dayAggregates: raw rows from the F2b `day_aggregates` table. May
    ///     contain multiple providers × multiple models × multiple days.
    ///   - period: filter selecting which days to include.
    ///   - displayNameForProviderRaw: maps a F2b raw provider value to the
    ///     user-facing display name (e.g. `.kimiCN.displayName`).
    /// - Returns: one `ProviderTotal` per distinct providerRaw that has any
    ///     day rows matching `period`, sorted by `displayName` ascending.
    static func aggregate(
        dayAggregates: [DayAggregate],
        for period: PerPeriodFilter,
        displayNameForProviderRaw: (String) -> String
    ) -> [ProviderTotal] {
        let filtered = dayAggregates.filter { period.includes(day: $0.day) }
        let groupedByProvider = Dictionary(grouping: filtered, by: { $0.provider })
        return groupedByProvider.map { (raw, aggs) in
            let totals = aggs.reduce(into: (input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0)) { acc, agg in
                acc.input += agg.tokens.input
                acc.output += agg.tokens.output
                acc.cacheRead += agg.tokens.cacheRead
                acc.cacheWrite += agg.tokens.cacheWrite
                acc.reasoning += agg.tokens.reasoning
            }
            return ProviderTotal(
                providerRaw: raw,
                displayName: displayNameForProviderRaw(raw),
                input: totals.input,
                output: totals.output,
                cacheRead: totals.cacheRead,
                cacheWrite: totals.cacheWrite,
                reasoning: totals.reasoning
            )
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
}

/// Per-period date filter used by `PerPeriodTokenAggregator.aggregate`.
///
/// `todayString` is the UTC day in `"yyyy-MM-dd"` form; `weekStart` / `weekEnd`
/// are the inclusive UTC dates of the ISO week; `monthPrefix` is `"yyyy-MM"`.
/// `dayParser` converts a `"yyyy-MM-dd"` string into a UTC `Date` for the
/// week-range comparison (caller supplies to keep the aggregator free of any
/// `DateFormatter` cache).
struct PerPeriodFilter {
    enum Kind { case today, week, month }

    let kind: Kind
    let todayString: String
    let weekStart: Date
    let weekEnd: Date
    let monthPrefix: String
    let dayParser: (String) -> Date?

    /// Returns `true` when `day` (a `"yyyy-MM-dd"` UTC string) falls inside
    /// this filter's window. For `.week`, the parsed `Date` must lie in
    /// `[weekStart, weekEnd]` inclusive.
    func includes(day: String) -> Bool {
        switch kind {
        case .today:
            return day == todayString
        case .month:
            return day.hasPrefix(monthPrefix)
        case .week:
            guard let parsed = dayParser(day) else { return false }
            return parsed >= weekStart && parsed <= weekEnd
        }
    }
}
