import XCTest
@testable import OpenCode_Bar

final class TavilyLiveIntegrationTests: XCTestCase {
    func testRealMultiKeyFetchReturnsMultipleAccounts() async throws {
        try LiveProviderTestGate.requireEnabled()
        let yamlURL = AIInfraYamlKeySource.defaultURL()
        guard FileManager.default.fileExists(atPath: yamlURL.path) else {
            throw XCTSkip("ai-infra keys.local.yaml not present; skipping live test")
        }

        let provider = TavilySearchProvider()
        let result = try await provider.fetch()

        guard let accounts = result.accounts else {
            XCTFail("Expected accounts to be populated for multi-key Tavily")
            return
        }

        XCTAssertGreaterThan(accounts.count, 1, "Expected multiple Tavily keys from ai-infra")
        for account in accounts {
            XCTAssertNotNil(account.accountId)
        }
    }
}
