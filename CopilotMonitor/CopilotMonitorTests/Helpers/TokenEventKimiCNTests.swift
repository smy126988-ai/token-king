import XCTest
@testable import OpenCode_Bar

/// F1 Phase 0: Kimi Global / CN split coverage. Verifies that the
/// `Provider` enum has the new `.kimiCN` case, that `TokenNormalizer`
/// correctly classifies providers with a "cn" providerID as `.kimiCN`,
/// and that `MonthCostCalculator` accepts the `kimicn` string.
final class TokenEventKimiCNTests: XCTestCase {

    // MARK: - Provider enum

    func testProviderHasKimiCNCase() {
        let provider = Provider.kimiCN
        XCTAssertEqual(provider.rawValue, "kimiCN")
    }

    func testProviderDisplayNameShowsKimiCN() {
        XCTAssertEqual(Provider.kimiCN.displayName, "Kimi CN")
        XCTAssertEqual(Provider.kimi.displayName, "Kimi Global")
    }

    // MARK: - TokenNormalizer (model field)

    func testModelKimiWithCNProviderIDReturnsKimiCN() {
        let p = TokenNormalizer.matchProvider(model: "kimi-k2.5", providerID: "kimi-cn")
        XCTAssertEqual(p, .kimiCN)
    }

    func testModelKimiWithGlobalProviderIDReturnsKimi() {
        let p = TokenNormalizer.matchProvider(model: "kimi-for-coding", providerID: "kimi")
        XCTAssertEqual(p, .kimi)
    }

    // MARK: - TokenNormalizer (providerID fallback)

    func testProviderIDAloneKimiCNReturnsKimiCN() {
        let p = TokenNormalizer.matchProvider(model: "kimi-for-coding", providerID: "kimi-cn-api")
        XCTAssertEqual(p, .kimiCN)
    }

    func testProviderIDAloneMoonshotReturnsKimi() {
        let p = TokenNormalizer.matchProvider(model: "kimi-k2.5", providerID: "moonshot")
        XCTAssertEqual(p, .kimi)
    }

    // MARK: - MonthCostCalculator

    func testMonthCostCalculatorAcceptsKimicnString() throws {
        let cost = MonthCostCalculator().calculate(
            provider: "kimiCN",
            model: "kimi-k2.6",
            tokens: TokenBreakdown(input: 1_000_000, output: 0)
        )
        XCTAssertNotNil(cost, "kimiCN should resolve to .kimiCN representative model and return a cost")
    }
}
