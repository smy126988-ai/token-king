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

    func testKimiModelAnthropicProvider() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "kimi-special", providerID: "anthropic"), .kimi)
    }

    func testZaiModelOpenAIProvider() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "glm-4.5", providerID: "openai"), .zai)
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

    func testRealOpenCodeKimiProvider() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "kimi-k2", providerID: "opencode-kimi"), .kimi)
    }

    func testRealCodexGpt54Mini() {
        XCTAssertEqual(TokenNormalizer.matchProvider(model: "gpt-5.4-mini", providerID: "openai"), .codex)
    }
}