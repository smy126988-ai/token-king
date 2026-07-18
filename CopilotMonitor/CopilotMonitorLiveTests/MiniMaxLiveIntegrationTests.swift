import XCTest
@testable import OpenCode_Bar

final class MiniMaxLiveIntegrationTests: XCTestCase {
    func testCNFetchReturnsUsageWithRealKey() async throws {
        try LiveProviderTestGate.requireEnabled()
        guard TokenManager.shared.getMiniMaxCodingPlanCNAPIKey() != nil else {
            throw XCTSkip("MiniMax Coding Plan CN API key not available; skipping live fetch test.")
        }

        let provider = MiniMaxCNProvider(tokenManager: TokenManager.shared, session: .shared)
        let result = try await provider.fetch()

        switch result.usage {
        case .quotaBased(let remaining, let entitlement, let overagePermitted):
            XCTAssertGreaterThanOrEqual(remaining, 0)
            XCTAssertEqual(entitlement, 100)
            XCTAssertFalse(overagePermitted)
        default:
            XCTFail("Expected quota-based usage")
        }

        XCTAssertNotNil(result.details)
    }

    func testGlobalFetchReturnsUsageWithRealKey() async throws {
        try LiveProviderTestGate.requireEnabled()
        guard TokenManager.shared.getMiniMaxCodingPlanAPIKey() != nil else {
            throw XCTSkip("MiniMax Coding Plan API key not available; skipping live fetch test.")
        }

        let provider = MiniMaxGlobalProvider(tokenManager: TokenManager.shared, session: .shared)
        let result = try await provider.fetch()

        switch result.usage {
        case .quotaBased(let remaining, let entitlement, let overagePermitted):
            XCTAssertGreaterThanOrEqual(remaining, 0)
            XCTAssertEqual(entitlement, 100)
            XCTAssertFalse(overagePermitted)
        default:
            XCTFail("Expected quota-based usage")
        }

        XCTAssertNotNil(result.details)
    }
}
