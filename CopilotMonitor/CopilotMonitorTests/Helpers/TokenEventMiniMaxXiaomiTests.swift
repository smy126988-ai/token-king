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

    // MARK: - providerID priority over model (ordering bug fix)

    /// Regression for bug 2: the old model-first routing checked `mimo-` prefix
    /// BEFORE the providerID-based xiaomi family, so
    /// `("mimo-v2.5-pro", "xiaomi-token-plan-cn")` returned `.minimaxCN`.
    /// After the rewrite, providerID is the primary signal — xiaomi-token-plan-cn
    /// matches first, so the event correctly classifies as .xiaomiTokenPlanCN.
    func testMimoV25ProWithXiaomiTokenPlanCNRoutesCorrectly() {
        let p = TokenNormalizer.matchProvider(model: "mimo-v2.5-pro", providerID: "xiaomi-token-plan-cn")
        XCTAssertEqual(p, .xiaomiTokenPlanCN,
                       "mimo-v2.5-pro + xiaomi-token-plan-cn should be .xiaomiTokenPlanCN, not .minimaxCN")
    }

    /// providerID priority must win even when the model name would otherwise
    /// hint at a different family. `mimo-v2.5-pro` historically was a MiniMax
    /// model name, but the user's actual provider is xiaomi-global here.
    func testMimoV25ProWithXiaomiGlobalProviderRoutesToXiaomi() {
        let p = TokenNormalizer.matchProvider(model: "mimo-v2.5-pro", providerID: "xiaomi")
        XCTAssertEqual(p, .xiaomi,
                       "providerID=xiaomi must override model=mimo- prefix")
    }

    // MARK: - opencode-go providerID (bug 1 fix)

    /// The pre-fix function had no rule matching `opencode-go`. Every event
    /// with that providerID fell through to `.nanoGpt`. New routing treats
    /// `opencode-go` as a gateway and disambiguates by model name. When the
    /// model is unknown the safe default is `.kimi` (most common CN-side use).
    func testOpencodeGoProviderIDDefaultsToKimi() {
        let p = TokenNormalizer.matchProvider(model: "some-misc", providerID: "opencode-go")
        XCTAssertEqual(p, .kimi,
                       "opencode-go without known model should default to .kimi")
    }

    /// Model-disambiguation inside the opencode-go branch: gpt-* → codex,
    /// claude-* → claude, kimi → kimi, mimo-v2.5-pro → minimaxCN.
    func testOpencodeGoWithKnownModel() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-5", providerID: "opencode-go"), .codex)
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-4o", providerID: "opencode-go"), .codex)
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "claude-opus-4-8", providerID: "opencode-go"), .claude)
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "mimo-v2.5-pro", providerID: "opencode-go"), .minimaxCN)
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "kimi-k2", providerID: "opencode-go"), .kimi)
    }

    /// Bare `opencode` providerID (no `-go` suffix) defaults to kimi for the
    /// kimi-family models. The model disambiguator fires before the default.
    func testPlainOpencodeProviderIDRoutesToKimi() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "mimo-v2.5-pro", providerID: "opencode"), .kimi,
                       "Bare opencode + mimo- prefix should default to kimi (not minimaxCN)")
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "kimi-k2", providerID: "opencode"), .kimi)
    }

    /// `opencode` + `qwen3.7-max` (xiaomi token plan model) → xiaomiTokenPlanCN.
    func testOpencodeWithQwen37MaxRoutesToXiaomiTokenPlanCN() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "qwen3.7-max", providerID: "opencode"), .xiaomiTokenPlanCN)
    }

    // MARK: - empty providerID falls back to model name (regression guard)

    /// When providerID is missing/empty, model-name routing takes over. This
    /// must still work — the rewrite only reorders priority, it does not
    /// remove the model-based fallback.
    func testEmptyProviderIDFallsBackToModelName() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "claude-opus-4-8", providerID: ""), .claude)
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-5", providerID: ""), .codex)
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "qwen3.7-max", providerID: ""), .xiaomiTokenPlanCN)
    }
}
