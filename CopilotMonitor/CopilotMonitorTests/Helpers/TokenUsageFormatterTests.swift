//
//  TokenUsageFormatterTests.swift
//  CopilotMonitorTests
//
//  F1/F4 unit tests for token formatting and time-window helpers.
//

import XCTest
@testable import OpenCode_Bar

/// F1/F4 unit tests for token formatting and time-window helpers.
final class TokenUsageFormatterTests: XCTestCase {

    // MARK: - formatTokens (Chinese units: 万 / 亿, no "M" no 千万)

    func testFormatTokensUnderThousandShowsPlainNumber() {
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 0), "0")
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 999), "999")
    }

    func testFormatTokensThousandToTenThousandShowsKWithDecimals() {
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 1_000), "1.0k")
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 9_999), "10.0k")
    }

    func testFormatTokensTenThousandToHundredMillionShowsWan() {
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 10_000), "1.0万")
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 12_345), "1.2万")
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 1_000_000), "100.0万")
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 25_700_000), "2570.0万")
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 99_999_999), "10000.0万")
    }

    func testFormatTokensAboveHundredMillionShowsYi() {
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 100_000_000), "1.00亿")
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 417_200_000), "4.17亿")
        XCTAssertEqual(TokenUsageFormatter.format(tokens: 1_234_567_890), "12.35亿")
    }

    // MARK: - formatResetTime

    func testFormatResetTimeReturnsLocalizedString() {
        // format(resetTime:) renders in local time per its docstring.
        // Build the input in .current so the assertion holds on any timezone.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 8; comps.hour = 14; comps.minute = 30
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let date = cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
        let s = TokenUsageFormatter.format(resetTime: date)
        XCTAssertTrue(s.contains("14:30"), "Expected '14:30' in '\(s)'")
    }

    func testFormatResetTimeNilReturnsDash() {
        XCTAssertEqual(TokenUsageFormatter.format(resetTime: nil), "—")
    }

    // MARK: - currentISOWeekRange

    func testCurrentISOWeekRangeOnMondayStartsAtMonday() {
        let monday = Self.makeDate(year: 2026, month: 7, day: 6)  // 2026-07-06 is Monday
        let (start, end) = TokenUsageFormatter.currentISOWeekRange(referenceDate: monday)
        XCTAssertEqual(Self.dayString(start), "2026-07-06")
        XCTAssertEqual(Self.dayString(end), "2026-07-12")
    }

    func testCurrentISOWeekRangeOnWednesdaySpansMonToSun() {
        let wednesday = Self.makeDate(year: 2026, month: 7, day: 8)
        let (start, end) = TokenUsageFormatter.currentISOWeekRange(referenceDate: wednesday)
        XCTAssertEqual(Self.dayString(start), "2026-07-06")
        XCTAssertEqual(Self.dayString(end), "2026-07-12")
    }

    func testCurrentISOWeekRangeOnSundayStaysInSameWeek() {
        let sunday = Self.makeDate(year: 2026, month: 7, day: 12)  // 2026-07-12 is Sunday
        let (start, end) = TokenUsageFormatter.currentISOWeekRange(referenceDate: sunday)
        XCTAssertEqual(Self.dayString(start), "2026-07-06")
        XCTAssertEqual(Self.dayString(end), "2026-07-12")
    }

    // MARK: - todayUTCString

    func testTodayUTCStringFormat() {
        let date = Self.makeDate(year: 2026, month: 7, day: 8)
        XCTAssertEqual(TokenUsageFormatter.todayUTCString(referenceDate: date), "2026-07-08")
    }

    // MARK: - Helpers

    private static func makeDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = hour; comps.minute = minute
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.utc
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    private static func dayString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone.utc
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}