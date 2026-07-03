import XCTest
@testable import OpenCode_Bar

final class ProviderRegionTests: XCTestCase {

    // MARK: - Provider Order

    @MainActor
    func testStatusBarQuotaOrderHasCNBeforeGlobal() {
        let controller = StatusBarController()
        let order = controller.providerQuotaOrderForTesting

        let kimiCNIndex = order.firstIndex(of: .kimiCN)
        let kimiGlobalIndex = order.firstIndex(of: .kimi)
        let minimaxCNIndex = order.firstIndex(of: .minimaxCodingPlanCN)
        let minimaxGlobalIndex = order.firstIndex(of: .minimaxCodingPlan)

        XCTAssertNotNil(kimiCNIndex)
        XCTAssertNotNil(kimiGlobalIndex)
        XCTAssertLessThan(kimiCNIndex!, kimiGlobalIndex!, "Kimi CN must appear before Kimi Global in the menu")

        XCTAssertNotNil(minimaxCNIndex)
        XCTAssertNotNil(minimaxGlobalIndex)
        XCTAssertLessThan(minimaxCNIndex!, minimaxGlobalIndex!, "MiniMax CN must appear before MiniMax Global in the menu")
    }

    // MARK: - Family / Region mapping

    func testKimiIdentifiersShareFamily() {
        XCTAssertEqual(ProviderIdentifier.kimi.family, .kimi)
        XCTAssertEqual(ProviderIdentifier.kimiCN.family, .kimi)
        XCTAssertEqual(ProviderIdentifier.kimi.region, .global)
        XCTAssertEqual(ProviderIdentifier.kimiCN.region, .china)
    }

    func testMiniMaxIdentifiersShareFamily() {
        XCTAssertEqual(ProviderIdentifier.minimaxCodingPlan.family, .minimax)
        XCTAssertEqual(ProviderIdentifier.minimaxCodingPlanCN.family, .minimax)
        XCTAssertEqual(ProviderIdentifier.minimaxCodingPlan.region, .global)
        XCTAssertEqual(ProviderIdentifier.minimaxCodingPlanCN.region, .china)
    }

    // MARK: - RMB filtering by current region

    func testRMBModeShowsKimiGlobalTiersWithUSDConversion() {
        let presets = ProviderSubscriptionPresets.presets(for: .kimi)
        CurrencyFormatter.shared.currency = .rmb
        defer { CurrencyFormatter.shared.currency = .usd }

        // 当前 region 没有 cnyCost，所以不过滤，所有 global tier 都显示 USD 折算价
        XCTAssertTrue(presets.contains { $0.name == "Vivace" })
        let vivace = presets.first { $0.name == "Vivace" }!
        XCTAssertTrue(vivace.formattedPrice(decimals: 0).contains("¥"))
    }

    func testRMBModeHidesKimiVivaceInChinaRegion() {
        let presets = ProviderSubscriptionPresets.presets(for: .kimiCN)
        XCTAssertFalse(presets.contains { $0.name == "Vivace" })
    }

    func testRMBModeShowsMiniMaxGlobalTiersWithUSDConversion() {
        let presets = ProviderSubscriptionPresets.presets(for: .minimaxCodingPlan)
        CurrencyFormatter.shared.currency = .rmb
        defer { CurrencyFormatter.shared.currency = .usd }

        XCTAssertFalse(presets.isEmpty)
        XCTAssertTrue(presets.allSatisfy { $0.cnyCost == nil })
        XCTAssertTrue(presets.first!.formattedPrice(decimals: 0).contains("¥"))
    }

    func testRMBModeShowsAllMiniMaxCNTiers() {
        let presets = ProviderSubscriptionPresets.presets(for: .minimaxCodingPlanCN)
        CurrencyFormatter.shared.currency = .rmb
        defer { CurrencyFormatter.shared.currency = .usd }

        XCTAssertTrue(presets.allSatisfy { $0.cnyCost != nil })
    }

    func testCNPresetFormattedPriceUsesNativeCNYInRMBMode() {
        let preset = ProviderSubscriptionPresets.presets(for: .kimiCN).first { $0.name == "Moderato" }
        XCTAssertNotNil(preset)

        CurrencyFormatter.shared.currency = .rmb
        defer { CurrencyFormatter.shared.currency = .usd }

        let price = preset!.formattedPrice(decimals: 0)
        XCTAssertEqual(price, "¥99")
    }

    func testMiniMaxCNPresetFormattedPriceUsesNativeCNYInRMBMode() {
        let preset = ProviderSubscriptionPresets.presets(for: .minimaxCodingPlanCN).first { $0.name == "Plus" }
        XCTAssertNotNil(preset)

        CurrencyFormatter.shared.currency = .rmb
        defer { CurrencyFormatter.shared.currency = .usd }

        let price = preset!.formattedPrice(decimals: 0)
        XCTAssertEqual(price, "¥49")
    }

    // MARK: - Migration / Config Preservation

    func testOldMiniMaxGlobalSubscriptionKeyIsStillReadable() {
        let manager = SubscriptionSettingsManager.shared
        let key = "minimax_coding_plan.migration-test@example.com"
        defer { manager.removePlan(forKey: key) }

        manager.setPlan(.preset("Max", 50), forKey: key)

        let plan = manager.getPlan(forKey: key)
        XCTAssertEqual(plan, .preset("Max", 50))
    }

    func testOldKimiGlobalSubscriptionKeyIsStillReadable() {
        let manager = SubscriptionSettingsManager.shared
        let key = "kimi.migration-test@example.com"
        defer { manager.removePlan(forKey: key) }

        manager.setPlan(.preset("Vivace", 199), forKey: key)

        let plan = manager.getPlan(forKey: key)
        XCTAssertEqual(plan, .preset("Vivace", 199))
    }
}
