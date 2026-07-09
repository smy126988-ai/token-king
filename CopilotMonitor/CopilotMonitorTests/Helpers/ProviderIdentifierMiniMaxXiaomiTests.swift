import XCTest
@testable import OpenCode_Bar

/// F2b-routing UI gap: the UI `ProviderIdentifier` enum (separate from
/// F2b's `Provider` enum in TokenEvent.swift) needs MiniMax + Xiaomi
/// cases so `StatusBarController.f2bTokenProviderRaw` / `f2bProviderRaw`
/// can bridge the F2b rows now living in `day_aggregates` after the
/// OpenCode providerID migration in commit da2b3cb.
///
/// These tests verify the new enum cases exist with the right rawValues,
/// displayName, family, region, and helper-method outputs.
@MainActor
final class ProviderIdentifierMiniMaxXiaomiTests: XCTestCase {

    // MARK: - Enum cases

    func testProviderIdentifierHasMiniMaxCases() {
        XCTAssertEqual(ProviderIdentifier.minimax.rawValue, "minimax")
        XCTAssertEqual(ProviderIdentifier.minimaxCN.rawValue, "minimax_cn")
        XCTAssertEqual(ProviderIdentifier.xiaomi.rawValue, "xiaomi")
        XCTAssertEqual(ProviderIdentifier.xiaomiTokenPlanCN.rawValue, "xiaomi_token_plan_cn")
    }

    func testProviderIdentifierDisplayName() {
        XCTAssertEqual(ProviderIdentifier.minimax.displayName, "MiniMax Global")
        XCTAssertEqual(ProviderIdentifier.minimaxCN.displayName, "MiniMax CN")
        XCTAssertEqual(ProviderIdentifier.xiaomi.displayName, "Xiaomi Global")
        XCTAssertEqual(ProviderIdentifier.xiaomiTokenPlanCN.displayName, "Xiaomi Token Plan CN")
    }

    func testProviderIdentifierShortDisplayName() {
        XCTAssertEqual(ProviderIdentifier.minimax.shortDisplayName, "MiniMax")
        XCTAssertEqual(ProviderIdentifier.minimaxCN.shortDisplayName, "MiniMax")
        XCTAssertEqual(ProviderIdentifier.xiaomi.shortDisplayName, "Xiaomi")
        XCTAssertEqual(ProviderIdentifier.xiaomiTokenPlanCN.shortDisplayName, "Xiaomi")
    }

    func testProviderIdentifierRegion() {
        // ProviderRegion has only 2 cases and no Equatable conformance today,
        // so compare via `==` (Bool) instead of XCTAssertEqual on the raw enum.
        XCTAssertTrue(ProviderIdentifier.minimax.region == .global)
        XCTAssertTrue(ProviderIdentifier.minimaxCN.region == .china)
        XCTAssertTrue(ProviderIdentifier.xiaomi.region == .global)
        XCTAssertTrue(ProviderIdentifier.xiaomiTokenPlanCN.region == .china)
    }

    func testProviderIdentifierIconNameIsNonEmpty() {
        // SF Symbols check: every provider should resolve to a non-empty
        // icon name. The actual resolution to a real SF Symbol is verified
        // by the menu render, not by this unit test — here we just guard
        // against accidental empty strings which would silently break the
        // menu bar identity icon layer.
        for identifier: ProviderIdentifier in [.minimax, .minimaxCN, .xiaomi, .xiaomiTokenPlanCN] {
            XCTAssertFalse(identifier.iconName.isEmpty, "iconName for \(identifier) is empty")
        }
    }

    // MARK: - StatusBarController bridging helpers

    func testF2bTokenProviderRawForMiniMaxXiaomi() {
        let suite = "pi-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Cannot create test UserDefaults suite")
            return
        }
        let controller = StatusBarController(options: .testing(userDefaults: defaults))
        XCTAssertEqual(controller.f2bTokenProviderRaw(for: .minimax), "minimax")
        XCTAssertEqual(controller.f2bTokenProviderRaw(for: .minimaxCN), "minimaxCN")
        XCTAssertEqual(controller.f2bTokenProviderRaw(for: .xiaomi), "xiaomi")
        XCTAssertEqual(controller.f2bTokenProviderRaw(for: .xiaomiTokenPlanCN), "xiaomiTokenPlanCN")
    }

    func testF2bProviderRawForMiniMaxXiaomiCollapsed() {
        let suite = "pi-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            XCTFail("Cannot create test UserDefaults suite")
            return
        }
        let controller = StatusBarController(options: .testing(userDefaults: defaults))
        // .minimax and .minimaxCN collapse to "minimax" for the cost path
        // (PricingTable treats them the same). Same collapse for Xiaomi.
        // The split happens via f2bTokenProviderRaw above for the token
        // aggregation path; for cost-equivalent RMB rating the family only
        // has one representative rate.
        XCTAssertEqual(controller.f2bProviderRaw(for: .minimax), "minimax")
        XCTAssertEqual(controller.f2bProviderRaw(for: .minimaxCN), "minimax")
        XCTAssertEqual(controller.f2bProviderRaw(for: .xiaomi), "xiaomi")
        XCTAssertEqual(controller.f2bProviderRaw(for: .xiaomiTokenPlanCN), "xiaomi")
    }

    // MARK: - PricingTable nil-bridging

    func testPricingTableHasNoRateForMiniMaxXiaomi() {
        // PricingTable has no public per-token rate for MiniMax / Xiaomi.
        // All four new identifiers should return nil — the cost column
        // for these rows is intentionally absent (UI shows "unknown" badge).
        XCTAssertNil(PricingTable.rate(for: .minimax))
        XCTAssertNil(PricingTable.rate(for: .minimaxCN))
        XCTAssertNil(PricingTable.rate(for: .xiaomi))
        XCTAssertNil(PricingTable.rate(for: .xiaomiTokenPlanCN))
    }
}
