import XCTest
@testable import OpenCode_Bar

final class SubscriptionPlanDisplayTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "SubscriptionPlanDisplayTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeFormatter(currency: Currency, rate: Double = 7.2) -> CurrencyFormatter {
        let defaults = makeDefaults()
        let rateDefaults = makeDefaults()
        rateDefaults.set(rate, forKey: ExchangeRateStore.cacheKey)
        let formatter = CurrencyFormatter(defaults: defaults, rateStore: ExchangeRateStore(defaults: rateDefaults))
        formatter.currency = currency
        return formatter
    }

    func testRMBSelectedPresetUsesYuanAndMonthlySuffix() {
        let formatter = makeFormatter(currency: .rmb)
        let presets = ProviderSubscriptionPresets.kimiChina
        let plan = SubscriptionPlan.preset("Moderato", 19)

        let title = plan.displayTitle(formatter: formatter, presets: presets)

        XCTAssertFalse(title.contains("$"), "RMB selected-plan text must not contain '$': \(title)")
        XCTAssertTrue(title.contains("/月"), "RMB selected-plan text should use '月' suffix: \(title)")
        XCTAssertTrue(title.contains("¥99"), "RMB selected-plan text should use native CNY price: \(title)")
    }

    func testRMBCustomPlanUsesYuanAndMonthlySuffix() {
        let formatter = makeFormatter(currency: .rmb)
        let plan = SubscriptionPlan.custom(20)

        let title = plan.displayTitle(formatter: formatter, presets: [])

        XCTAssertFalse(title.contains("$"), "RMB custom-plan text must not contain '$': \(title)")
        XCTAssertTrue(title.contains("/月"), "RMB custom-plan text should use '月' suffix: \(title)")
        XCTAssertTrue(title.contains("¥144"), "RMB custom-plan text should convert USD via rate: \(title)")
    }

    func testRMBNonePlanUsesYuanWithoutDollar() {
        let formatter = makeFormatter(currency: .rmb)
        let plan = SubscriptionPlan.none

        let title = plan.displayTitle(formatter: formatter, presets: [])

        XCTAssertFalse(title.contains("$"), "RMB none-plan text must not contain '$': \(title)")
        XCTAssertTrue(title.contains("¥0"), "RMB none-plan text should show zero yuan: \(title)")
    }

    func testUSDSelectedPresetUsesDollarAndMonthlySuffix() {
        let formatter = makeFormatter(currency: .usd)
        let presets = ProviderSubscriptionPresets.kimiChina
        let plan = SubscriptionPlan.preset("Moderato", 19)

        let title = plan.displayTitle(formatter: formatter, presets: presets)

        XCTAssertTrue(title.contains("$19"), "USD selected-plan text should show dollar price: \(title)")
        XCTAssertFalse(title.contains("/m"), "USD selected-plan text must not use '/m': \(title)")
        XCTAssertTrue(title.contains("/月"), "USD selected-plan text should still use Chinese '月' suffix: \(title)")
    }

    func testUSDCustomPlanUsesDollarAndMonthlySuffix() {
        let formatter = makeFormatter(currency: .usd)
        let plan = SubscriptionPlan.custom(25)

        let title = plan.displayTitle(formatter: formatter, presets: [])

        XCTAssertTrue(title.contains("$25"), "USD custom-plan text should show dollar price: \(title)")
        XCTAssertTrue(title.contains("/月"), "USD custom-plan text should use Chinese '月' suffix: \(title)")
    }

    @MainActor
    func testCodexSubscriptionMenuShowsDistinctPro100AndPro200() {
        UserDefaults.standard.set(true, forKey: "githubStarPromptDismissed")

        let controller = StatusBarController()
        let menu = NSMenu()
        controller.addSubscriptionItems(to: menu, provider: .codex, accountId: nil)

        let titles = menu.items.map(\.title)
        let pro100 = titles.first { $0.contains("Pro $100") }
        let pro200 = titles.first { $0.contains("Pro $200") }

        XCTAssertNotNil(pro100, "Codex subscription menu should contain 'Pro $100' preset: \(titles)")
        XCTAssertNotNil(pro200, "Codex subscription menu should contain 'Pro $200' preset: \(titles)")
        XCTAssertNotEqual(pro100, pro200, "Pro $100 and Pro $200 should be distinct menu items")
    }
}
