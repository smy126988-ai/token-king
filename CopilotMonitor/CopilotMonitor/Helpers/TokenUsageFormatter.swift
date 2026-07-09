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

    /// Format a token count using Chinese number units (万 / 亿).
    /// - 0..999: plain integer ("0" / "999")
    /// - 1_000..9_999: 1 decimal + k ("1.0k" / "9.9k")
    /// - 10_000..99_999_999: 1 decimal + 万 ("1.0万" / "9900.0万")
    /// - ≥100_000_000: 2 decimal + 亿 ("1.00亿" / "4.17亿")
    static func format(tokens: Int) -> String {
        if tokens < 1_000 { return "\(tokens)" }
        if tokens < 10_000 {
            return String(format: "%.1fk", Double(tokens) / 1_000.0)
        }
        if tokens < 100_000_000 {
            return String(format: "%.1f万", Double(tokens) / 10_000.0)
        }
        return String(format: "%.2f亿", Double(tokens) / 100_000_000.0)
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