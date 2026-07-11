import XCTest

final class F2bE2ETests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    /// Test 1: 启动 app → 等 30s tick → 顶部 header 有 "本月 API 折算" + provider 列表
    func testMenuBarShowsMonthlyCostAfter30s() throws {
        let menuBar = app.statusItems.firstMatch
        XCTAssertTrue(menuBar.waitForExistence(timeout: 5))
        menuBar.click()
        // 等 30s tick + UI render
        sleep(35)
        let monthCostText = app.menuBars.menus.menuItems
            .containing(NSPredicate(format: "label CONTAINS '本月 API 折算'"))
            .firstMatch
        XCTAssertTrue(monthCostText.exists, "顶部应显示 '本月 API 折算 ¥XX'")
    }

    /// Test 2: provider 列表 (5 provider: Kimi/Claude/Codex/Z.AI/NanoGpt) 出现
    func testProviderListShowsAfterTick() throws {
        app.statusItems.firstMatch.click()
        sleep(35)
        for providerName in ["Kimi", "Claude", "Codex", "Z.AI", "NanoGpt"] {
            let item = app.menuBars.menus.menuItems
                .containing(NSPredicate(format: "label CONTAINS[c] %@", providerName))
                .firstMatch
            XCTAssertTrue(item.exists, "\(providerName) 应在 provider 列表")
        }
    }

    /// Test 3: 单 provider 详情有 "按量折算" row
    func testProviderDetailHasMonthlyCost() throws {
        app.statusItems.firstMatch.click()
        sleep(35)
        // 点 Kimi (如果存在)
        let kimi = app.menuBars.menus.menuItems
            .containing(NSPredicate(format: "label BEGINSWITH 'Kimi'"))
            .firstMatch
        if kimi.exists {
            kimi.click()
            sleep(1)
            let monthlyCost = app.menuBars.menus.menuItems
                .containing(NSPredicate(format: "label CONTAINS '按量折算'"))
                .firstMatch
            XCTAssertTrue(monthlyCost.exists, "Kimi 详情应有 '按量折算 ¥XX / 月'")
        } else {
            throw XCTSkip("Kimi 不可见, 跳过 detail 测试")
        }
    }

    /// Test 4: Calendar month reset (skip if time mocking not feasible)
    func testCalendarMonthReset() throws {
        // Time mocking 复杂, F2b v1 跳过, F2c 再加
        throw XCTSkip("Time mocking 复杂, F2b v1 跳过, F2c 增强")
    }
}
