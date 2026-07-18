import XCTest
@testable import OpenCode_Bar

final class VolcanoArkLiveIntegrationTests: XCTestCase {
    func testFetchReturnsUsageWithRealCredentials() async throws {
        try LiveProviderTestGate.requireEnabled()
        guard TokenManager.shared.getVolcanoArkCredentials() != nil else {
            throw XCTSkip("Volcano Ark credentials not available; skipping live fetch test.")
        }

        let provider = VolcanoArkProvider(tokenManager: .shared, session: .shared)
        let result = try await provider.fetch()

        switch result.usage {
        case .quotaBased(let remaining, let entitlement, _):
            XCTAssertGreaterThanOrEqual(remaining, 0)
            XCTAssertEqual(entitlement, 100)
        default:
            XCTFail("Expected quota-based usage")
        }

        XCTAssertNotNil(result.details)
    }
}
