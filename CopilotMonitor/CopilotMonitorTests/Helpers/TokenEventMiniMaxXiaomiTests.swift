import XCTest
@testable import OpenCode_Bar

/// F2b extension: MiniMax + Xiaomi provider detection.
///
/// Adds four Provider enum cases (minimax / minimaxCN / xiaomi / xiaomiTokenPlanCN)
/// that the old TokenNormalizer could not detect — so OpenCode events with
/// providerID `minimax-cn` / `xiaomi-token-plan-cn` were silently falling through
/// to `.nanoGpt`.
final class TokenEventMiniMaxXiaomiTests: XCTestCase {

    // MARK: - Provider enum

    func testProviderHasMiniMaxCases() {
        XCTAssertEqual(Provider.minimax.rawValue, "minimax")
        XCTAssertEqual(Provider.minimaxCN.rawValue, "minimaxCN")
        XCTAssertEqual(Provider.xiaomi.rawValue, "xiaomi")
        XCTAssertEqual(Provider.xiaomiTokenPlanCN.rawValue, "xiaomiTokenPlanCN")
    }

    func testProviderDisplayName() {
        XCTAssertEqual(Provider.minimax.displayName, "MiniMax Global")
        XCTAssertEqual(Provider.minimaxCN.displayName, "MiniMax CN")
        XCTAssertEqual(Provider.xiaomi.displayName, "Xiaomi Global")
        XCTAssertEqual(Provider.xiaomiTokenPlanCN.displayName, "Xiaomi Token Plan CN")
    }

    // MARK: - TokenNormalizer (model field)

    func testModelWithMiniMaxCNProviderID() {
        let p = TokenNormalizer.matchProvider(model: "minimax-m3", providerID: "minimax-cn")
        XCTAssertEqual(p, .minimaxCN)
    }

    func testModelWithMiniMaxGlobalProviderID() {
        let p = TokenNormalizer.matchProvider(model: "minimax-m3", providerID: "minimax")
        XCTAssertEqual(p, .minimax)
    }

    func testModelWithXiaomiTokenPlanCN() {
        let p = TokenNormalizer.matchProvider(model: "qwen3.7-max", providerID: "xiaomi-token-plan-cn")
        XCTAssertEqual(p, .xiaomiTokenPlanCN)
    }

    func testModelWithXiaomiGlobal() {
        let p = TokenNormalizer.matchProvider(model: "qwen3.7-max", providerID: "xiaomi")
        XCTAssertEqual(p, .xiaomi)
    }

    func testModelWithMimoPrefixMiniMaxCN() {
        // Older MiniMax model name pattern.
        let p = TokenNormalizer.matchProvider(model: "mimo-v2.5-pro", providerID: "minimax-cn-api")
        XCTAssertEqual(p, .minimaxCN)
    }

    func testModelMiniMaxM3CapitalizedWithCNProviderID() {
        // F2b: New schema events use camelCase "MiniMax-M3" model name.
        // Lowercased coercion already matches, but explicit check is defense-in-depth.
        let p = TokenNormalizer.matchProvider(model: "MiniMax-M3", providerID: "minimax-cn")
        XCTAssertEqual(p, .minimaxCN)
    }

    func testModelMiniMaxM3CapitalizedWithGlobalProviderID() {
        // Global variant of the capitalized MiniMax model.
        let p = TokenNormalizer.matchProvider(model: "MiniMax-M3", providerID: "minimax")
        XCTAssertEqual(p, .minimax)
    }

    // MARK: - TokenNormalizer (providerID-only fallback)

    func testProviderIDAloneMiniMaxCN() {
        let p = TokenNormalizer.matchProvider(model: "minimax-m3", providerID: "minimax-cn-api")
        XCTAssertEqual(p, .minimaxCN)
    }

    func testProviderIDAloneMiniMaxGlobal() {
        let p = TokenNormalizer.matchProvider(model: "unknown", providerID: "minimax")
        XCTAssertEqual(p, .minimax)
    }

    func testProviderIDAloneXiaomiTokenPlanCN() {
        let p = TokenNormalizer.matchProvider(model: "unknown", providerID: "xiaomi-token-plan")
        XCTAssertEqual(p, .xiaomiTokenPlanCN)
    }

    func testProviderIDAloneXiaomiGlobal() {
        let p = TokenNormalizer.matchProvider(model: "unknown", providerID: "xiaomi")
        XCTAssertEqual(p, .xiaomi)
    }
}
