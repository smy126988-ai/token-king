import XCTest
@testable import OpenCode_Bar

final class WidgetSnapshotMapperTests: XCTestCase {

    // MARK: - Multi-window quotaBased (Claude-style)

    /// Claude-style quotaBased with 5h + 7d windows. Verifies:
    /// - Three windows total (`primary` + `5h` + `7d`)
    /// - `kind == .quota`
    /// - `primaryWindowId` picks the highest `usedPercent` (7d = 80%)
    /// - `used` and `limit` are populated on the primary window
    func testMapProviderWithMultipleWindows() {
        let details = DetailedUsage(
            fiveHourUsage: 30.0,
            fiveHourReset: Date(timeIntervalSinceNow: 18000),
            sevenDayUsage: 80.0,
            sevenDayReset: Date(timeIntervalSinceNow: 604800)
        )
        let result = ProviderResult(
            usage: .quotaBased(remaining: 25, entitlement: 100, overagePermitted: false),
            details: details
        )

        let snapshot = WidgetSnapshotMapper.makeSnapshot(
            providerResults: [.claude: result],
            monthlyCost: nil
        )

        XCTAssertEqual(snapshot.providers.count, 1)
        XCTAssertEqual(snapshot.version, 1)

        let p = snapshot.providers[0]
        XCTAssertEqual(p.id, "claude")
        XCTAssertEqual(p.kind, .quota)
        XCTAssertEqual(p.windows.count, 3) // primary + 5h + 7d
        XCTAssertEqual(p.primaryWindowId, "7d") // 7d has highest usedPercent

        // Verify primary window carries the absolute used/limit derived from the
        // remaining/entitlement pair (100 - 25 = 75 used, 100 limit).
        let primary = p.windows.first(where: { $0.id == "primary" })
        XCTAssertEqual(primary?.used, 75)
        XCTAssertEqual(primary?.limit, 100)
    }

    // MARK: - Pay-as-you-go

    /// Pay-as-you-go provider (usage kind). Verifies:
    /// - `kind == .usage`
    /// - Single window with `id = "primary"`
    /// - `spendUSD` is round-tripped from cost
    func testMapUsageProvider() {
        let reset = Date(timeIntervalSinceNow: 86400)
        let result = ProviderResult(
            usage: .payAsYouGo(utilization: 42.5, cost: 12.34, resetsAt: reset),
            details: nil
        )

        let snapshot = WidgetSnapshotMapper.makeSnapshot(
            providerResults: [.openRouter: result],
            monthlyCost: nil
        )

        XCTAssertEqual(snapshot.providers.count, 1)
        let p = snapshot.providers[0]
        XCTAssertEqual(p.id, "openrouter")
        XCTAssertEqual(p.kind, .usage)
        XCTAssertEqual(p.spendUSD, 12.34)
        XCTAssertEqual(p.primaryWindowId, "primary")
        XCTAssertEqual(p.windows.count, 1)
        XCTAssertEqual(p.windows[0].usedPercent, 42.5)
        XCTAssertEqual(p.windows[0].resetsAt, reset)
    }

    // MARK: - Empty results

    /// Empty provider dictionary produces a valid but empty snapshot.
    func testEmptyResults() {
        let snapshot = WidgetSnapshotMapper.makeSnapshot(
            providerResults: [:],
            monthlyCost: nil
        )
        XCTAssertEqual(snapshot.providers.count, 0)
        XCTAssertEqual(snapshot.version, 1)
    }
}
