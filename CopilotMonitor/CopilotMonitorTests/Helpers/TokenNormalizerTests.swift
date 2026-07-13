import XCTest
@testable import OpenCode_Bar

/// F2b Task 2 — TokenNormalizer.matchProvider 测试.
/// 30 test cases (5 Provider × 6 case + 真实 user 本机数据).
final class TokenNormalizerTests: XCTestCase {

    // MARK: - Kimi (6 tests)

    func testKimiModel() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "kimi-k2", providerID: "kimi"), .kimi)
    }

    func testKimiModelK2p() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "k2p-7b", providerID: "moonshot"), .kimi)
    }

    func testKimiModelK2_5() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "kimi-k2-5", providerID: "kimi"), .kimi)
    }

    func testKimiModelCaseInsensitive() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "KIMI-SOMETHING", providerID: "KIMI"), .kimi)
    }

    func testKimiProviderIDFallback() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "unknown-model", providerID: "kimi-coding"), .kimi)
    }

    func testKimiMoonshotProviderID() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "unknown-model", providerID: "moonshot-v1"), .kimi)
    }

    // MARK: - Claude (5 tests)

    func testClaudeModel() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "claude-sonnet-4-5", providerID: "anthropic"), .claude)
    }

    func testClaudeModelHaiku() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "claude-haiku-4", providerID: "anthropic"), .claude)
    }

    func testClaudeModelCaseInsensitive() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "CLAUDE-OPUS-4", providerID: "ANTHROPIC"), .claude)
    }

    func testClaudeProviderIDFallback() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "unknown-model", providerID: "anthropic-prod"), .claude)
    }

    func testClaudePA() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "claude-pa", providerID: "anthropic"), .claude)
    }

    // MARK: - Codex (5 tests)

    func testCodexModelGPT() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-4o", providerID: "openai"), .codex)
    }

    func testCodexModelGPT5() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-5", providerID: "openai"), .codex)
    }

    func testCodexModelO3() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "o3-mini", providerID: "openai"), .codex)
    }

    func testCodexProviderIDFallback() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "unknown-model", providerID: "openai-responses"), .codex)
    }

    func testCodexModelNanoGPT() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-nano-gpt", providerID: "openai"), .codex)
    }

    // MARK: - Z.AI (5 tests)

    func testZAIModel() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "glm-4.6", providerID: "z-ai"), .zai)
    }

    func testZAIModel5p() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "glm-5p", providerID: "z-ai"), .zai)
    }

    func testZAICaseInsensitive() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "GLM-4.5", providerID: "Z-AI"), .zai)
    }

    func testZAIProviderIDZ() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "unknown-model", providerID: "z-ai-coding"), .zai)
    }

    func testZAIProviderIDZai() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "unknown-model", providerID: "zai-prod"), .zai)
    }

    // MARK: - NanoGpt 兜底 (5 tests)

    func testUnknownModelUnknownProvider() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "foo-bar", providerID: "bar-baz"), .nanoGpt)
    }

    func testEmptyModelEmptyProvider() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "", providerID: ""), .nanoGpt)
    }

    func testUnknownModelOpenAIProvider() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "unknown", providerID: "openai"), .codex)
    }

    // providerID-first resolution: when the providerID directly identifies a
    // specific provider (e.g. "anthropic"), the model name is irrelevant.
    // This guarantees cost attribution always lands on the subscription plan
    // the user actually invoked, not on the model brand.
    func testKimiModelAnthropicProviderUsesProviderID() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "kimi-special", providerID: "anthropic"), .claude)
    }

    func testZaiModelOpenAIProviderUsesProviderID() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "glm-4.5", providerID: "openai"), .codex)
    }

    // MARK: - 真实 user 本机数据 (5 tests)

    func testRealKimiMimo() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "kimi-mimo", providerID: "kimi"), .kimi)
    }

    func testRealKimiForCoding() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "kimi-for-coding", providerID: "moonshot"), .kimi)
    }

    func testRealKimiCodeNew() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "kimi-code-new", providerID: "kimi"), .kimi)
    }

    // opencode-kimi routes via the "opencode" parent match to the OpenCode Go
    // subscription, NOT to Moonshot Kimi. This is intentional: the user paid
    // for the OpenCode Go subscription, so the cost must attribute there.
    func testRealOpenCodeKimiProviderUsesProviderID() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "kimi-k2", providerID: "opencode-kimi"), .opencodeGo)
    }

    func testRealCodexGpt54Mini() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-5.4-mini", providerID: "openai"), .codex)
    }

    // MARK: - P0-3 NanoGPT providerID precedence (providerID wins over model prefix)

    /// P0-3 regression: NanoGPT API responses carrying OpenAI-style models
    /// (e.g. `gpt-4o`) must route to `.nanoGpt`, not `.codex`. The providerID
    /// is the strongest signal — when it identifies NanoGPT, we trust it.
    func testNanoGptGpt4oRoutesToNanoGpt() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-4o", providerID: "nanogpt"), .nanoGpt)
    }

    /// Same regression, different model: any gpt-* model served via NanoGPT
    /// stays NanoGPT-attributed.
    func testNanoGptGpt4oMiniRoutesToNanoGpt() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-4o-mini", providerID: "nanogpt"), .nanoGpt)
    }

    /// NanoGPT providerID with non-OpenAI-style model — the providerID is the
    /// only signal, so the result is still `.nanoGpt`.
    func testNanoGptUnknownModelRoutesToNanoGpt() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "some-nano-only-model", providerID: "nanogpt"), .nanoGpt)
    }

    /// Match common alternative spellings of the NanoGPT providerID (dashes
    /// and underscores) — same routing decision.
    func testNanoGptProviderIDVariantsRouteToNanoGpt() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-4o", providerID: "nano-gpt"), .nanoGpt)
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-4o", providerID: "nano_gpt"), .nanoGpt)
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-4o", providerID: "NanoGPT"), .nanoGpt)
    }

    /// Regression guard: providerID `openai` (Codex/ChatGPT) MUST still route
    /// `gpt-4o` to `.codex`. The fix must not break the original Codex path.
    func testCodexGpt4oStillRoutesToCodex() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-4o", providerID: "openai"), .codex)
    }

    /// Regression guard: when providerID is empty (raw CLI stream), the
    /// model-based fallback still routes `gpt-4o` to `.codex` — i.e. we did
    /// not accidentally delete the model-prefix branch.
    func testEmptyProviderIDGpt4oFallsToModelCodex() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-4o", providerID: ""), .codex)
    }
}
