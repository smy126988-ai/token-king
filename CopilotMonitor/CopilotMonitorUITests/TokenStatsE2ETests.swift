import XCTest

/// F1 / F3 / F4 e2e test: launches the app, opens the menu, verifies the
/// new top-level "全局统计" item and its submenu contents.
///
/// Note: these tests require a real macOS desktop session with a menu bar.
/// They may be skipped in headless CI environments.
final class TokenStatsE2ETests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// F4: "全局统计" submenu is visible from the top menu and contains
    /// the expected headers + rows.
    func testF4GlobalStatsSubmenuExists() throws {
        let menuBar = app.statusItems.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5), "Status bar item should appear within 5s")
        menuBar.click()

        // Top-level "全局统计" item (Chinese label)
        let globalStats = app.menuItems["全局统计"]
        XCTAssertTrue(globalStats.waitForExistence(timeout: 3), "全局统计 menu item should exist")
        globalStats.hover()

        // Submenu header
        let tokenHeader = app.staticTexts["Token 用量汇总"]
        XCTAssertTrue(tokenHeader.waitForExistence(timeout: 2), "Token 用量汇总 header should appear in submenu")

        // Three token rows (each starts with "  " + label + "：")
        let todayRow = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '  今日：'")).firstMatch
        let weekRow = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '  本周：'")).firstMatch
        let monthRow = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH '  本月：'")).firstMatch
        XCTAssertTrue(todayRow.exists, "今日 row missing")
        XCTAssertTrue(weekRow.exists, "本周 row missing")
        XCTAssertTrue(monthRow.exists, "本月 row missing")

        // Quota section
        let quotaHeader = app.staticTexts["额度状态"]
        XCTAssertTrue(quotaHeader.exists, "额度状态 header should appear")
    }

    /// F1: a per-provider submenu should contain the "Token 用量 (本月)" header
    /// when F2b has data. Skipped when no provider has F2b data (no real session files).
    func testF1ProviderDetailHasMonthlyTokenBlock() throws {
        let menuBar = app.statusItems.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5))
        menuBar.click()
        sleep(35)  // wait for 30s tick + UI render

        // Click Kimi (if present) and check for F1 monthly header.
        let kimi = app.menuBars.menus.menuItems
            .containing(NSPredicate(format: "label BEGINSWITH 'Kimi'"))
            .firstMatch
        if !kimi.exists {
            throw XCTSkip("Kimi not visible (no F2b data on this machine)")
        }
        kimi.click()
        sleep(1)
        let monthlyHeader = app.staticTexts["Token 用量 (本月)"]
        XCTAssertTrue(monthlyHeader.exists, "Provider detail should show 'Token 用量 (本月)' header when F2b data exists")
    }

    /// F3: provider detail should contain the "使用记录" section when
    /// DetailedUsage has both fiveHourUsage and sevenDayUsage.
    /// Skipped when no provider has quota windows.
    func testF3ProviderDetailHasUsageRecord() throws {
        let menuBar = app.statusItems.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5))
        menuBar.click()
        sleep(35)

        let kimi = app.menuBars.menus.menuItems
            .containing(NSPredicate(format: "label BEGINSWITH 'Kimi'"))
            .firstMatch
        if !kimi.exists {
            throw XCTSkip("Kimi not visible (no providers on this machine)")
        }
        kimi.click()
        sleep(1)
        let usageRecord = app.staticTexts["使用记录"]
        XCTAssertTrue(usageRecord.exists, "Provider detail should show '使用记录' header when DetailedUsage has 5h/7d data")
    }
}
