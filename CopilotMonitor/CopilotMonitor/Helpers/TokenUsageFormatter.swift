//
//  TokenUsageFormatter.swift
//  CopilotMonitor
//
//  Token and time-window formatting helpers for F1 / F3 / F4 UI.
//  All time calculations use UTC (B46 / B53: never `TimeZone(identifier:)!`).
//

import Foundation

/// Token and time-window formatting helpers for F1 / F3 / F4 UI.
/// All time calculations use UTC (B46 / B53: never `TimeZone(identifier:)!`).
enum TokenUsageFormatter {

    // MARK: - Token formatting

    /// Format a token count using k / M / plain suffixes.
    /// - 0..999: plain integer ("0" / "999")
    /// - 1_000..999_999: 1 decimal + k ("1.0k" / "999.9k")
    /// - ≥1_000_000: 1 decimal + M ("1.0M" / "12.3M")
    static func format(tokens: Int) -> String {
        if tokens < 1_000 { return "\(tokens)" }
        if tokens < 1_000_000 {
            return String(format: "%.1fk", Double(tokens) / 1_000.0)
        }
        return String(format: "%.1fM", Double(tokens) / 1_000_000.0)
    }

    // MARK: - Time formatting

    /// Format a 5h bucket reset time as "HH:mm" in local time.
    /// Returns "—" for nil.
    static func format(resetTime: Date?) -> String {
        guard let resetTime else { return "—" }
        let fmt = DateFormatter()
        fmt.timeZone = .current
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "HH:mm"
        return fmt.string(from: resetTime)
    }

    // MARK: - Time windows

    /// Returns the start (Monday 00:00 UTC) and end (Sunday 00:00 UTC + 6 days) of the
    /// ISO week containing `referenceDate`.
    static func currentISOWeekRange(referenceDate: Date = Date()) -> (start: Date, end: Date) {
        let daysPerWeek = TimeWindow.hoursPerWeek / TimeWindow.hoursPerDay
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .utc
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
        let start = cal.date(from: comps) ?? referenceDate
        let end = cal.date(byAdding: .day, value: daysPerWeek - 1, to: start) ?? start
        return (start, end)
    }

    /// Returns "YYYY-MM-DD" for `referenceDate` in UTC.
    static func todayUTCString(referenceDate: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.timeZone = .utc
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: referenceDate)
    }
}