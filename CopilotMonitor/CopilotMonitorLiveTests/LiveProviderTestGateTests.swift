import XCTest
@testable import OpenCode_Bar

final class LiveProviderTestGateTests: XCTestCase {
    func testOnlyExactOneEnablesLiveProviderTests() {
        XCTAssertFalse(LiveProviderTestGate.isEnabled(environment: [:]))
        XCTAssertFalse(LiveProviderTestGate.isEnabled(environment: ["RUN_LIVE_PROVIDER_TESTS": "0"]))
        XCTAssertFalse(LiveProviderTestGate.isEnabled(environment: ["RUN_LIVE_PROVIDER_TESTS": "true"]))
        XCTAssertTrue(LiveProviderTestGate.isEnabled(environment: ["RUN_LIVE_PROVIDER_TESTS": "1"]))
    }
}
