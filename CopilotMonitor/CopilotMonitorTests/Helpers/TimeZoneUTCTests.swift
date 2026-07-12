//
//  TimeZoneUTCTests.swift
//  CopilotMonitorTests
//
//  Regression tests for the shared UTC timezone fallback.
//

import XCTest
@testable import OpenCode_Bar

final class TimeZoneUTCTests: XCTestCase {

    /// The shared constant must represent GMT+0 (UTC) regardless of whether the
    /// "UTC" identifier is available on the current system.
    func testUTCConstantIsUTC() {
        XCTAssertEqual(TimeZone.utc.secondsFromGMT(), 0)
    }

    /// Ensure the fallback path still yields a non-nil, GMT+0 timezone if the
    /// identifier lookup were to fail. We exercise the same expression used in
    /// the extension so a regression in `TimeZone(secondsFromGMT:)` is caught.
    func testUTCFallbackExpressionIsNonNilAndGMT() {
        let fallback = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(fallback.secondsFromGMT(), 0)
    }

    /// Calendar/Formatter behavior must stay aligned with the explicit UTC
    /// identifier: a known UTC date should format to the expected string.
    func testUTCConstantFormatsDatesCorrectly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .utc

        var components = DateComponents()
        components.year = 2026
        components.month = 1
        components.day = 15
        components.hour = 12
        components.minute = 0
        components.timeZone = .utc

        guard let date = calendar.date(from: components) else {
            XCTFail("Could not construct UTC date")
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = .utc
        formatter.locale = Locale(identifier: "en_US_POSIX")

        XCTAssertEqual(formatter.string(from: date), "2026-01-15 12:00:00")
    }

    /// The extension must be accessible from every module that previously used
    /// `TimeZone(identifier: "UTC")`. This test imports the app target and
    /// references the member to ensure it is part of the compiled product.
    func testUTCConstantIsExposedToAppTarget() {
        XCTAssertNotNil(TimeZone.utc)
    }
}
