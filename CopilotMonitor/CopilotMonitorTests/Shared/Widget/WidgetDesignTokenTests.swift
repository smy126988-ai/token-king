import XCTest
@testable import OpenCode_Bar

final class WidgetDesignTokenTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testRelativeResetFormatterReturnsEmptyForMissingDate() {
        XCTAssertEqual(RelativeResetFormatter.string(from: nil, relativeTo: now), "")
    }

    func testRelativeResetFormatterReturnsResettingForElapsedDate() {
        XCTAssertEqual(
            RelativeResetFormatter.string(from: now.addingTimeInterval(-1), relativeTo: now),
            "resetting"
        )
    }

    func testRelativeResetFormatterFormatsMinutes() {
        XCTAssertEqual(
            RelativeResetFormatter.string(from: now.addingTimeInterval(59 * 60), relativeTo: now),
            "59m left"
        )
    }

    func testRelativeResetFormatterFormatsHoursAndMinutes() {
        XCTAssertEqual(
            RelativeResetFormatter.string(from: now.addingTimeInterval((3 * 3_600) + (17 * 60)), relativeTo: now),
            "3h 17m left"
        )
    }

    func testRelativeResetFormatterFormatsWholeDays() {
        XCTAssertEqual(
            RelativeResetFormatter.string(from: now.addingTimeInterval((49 * 3_600) + (30 * 60)), relativeTo: now),
            "2d left"
        )
    }

    func testUSDFormatterDefaultsMissingValueToZero() {
        XCTAssertEqual(USDFormatter.string(from: nil), "$0.00")
    }

    func testUSDFormatterRoundsToTwoDecimalPlaces() {
        XCTAssertEqual(USDFormatter.string(from: 12.345), "$12.35")
    }

    func testAuroraTierUsesInclusiveSeverityBoundaries() {
        XCTAssertEqual(
            WidgetDesignToken.Aurora.tier(forUsedPercent: WidgetDesignToken.Severity.amberAt).opacity,
            WidgetDesignToken.Aurora.caution.opacity
        )
        XCTAssertEqual(
            WidgetDesignToken.Aurora.tier(forUsedPercent: WidgetDesignToken.Severity.redAt).opacity,
            WidgetDesignToken.Aurora.critical.opacity
        )
    }

    func testCodexTierUsesStrictQuotaBoundaries() {
        XCTAssertEqual(
            WidgetDesignToken.CodexQuota.tier(
                forUsedPercent: WidgetDesignToken.CodexQuota.cautionUsedAbove
            ).opacity,
            WidgetDesignToken.Aurora.healthy.opacity
        )
        XCTAssertEqual(
            WidgetDesignToken.CodexQuota.tier(
                forUsedPercent: WidgetDesignToken.CodexQuota.criticalUsedAbove
            ).opacity,
            WidgetDesignToken.Aurora.caution.opacity
        )
    }
}
