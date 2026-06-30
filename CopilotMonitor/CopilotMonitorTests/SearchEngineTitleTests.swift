import XCTest
@testable import OpenCode_Bar

final class SearchEngineTitleTests: XCTestCase {
    func testTitleWithAccountId() {
        let title = StatusBarController.searchEngineAccountTitle(
            base: "Tavily", accountId: "apple", accountIndex: 0)
        XCTAssertEqual(title, "Tavily (apple)")
    }

    func testTitleFallsBackToIndexWhenAccountIdNil() {
        let title = StatusBarController.searchEngineAccountTitle(
            base: "Tavily", accountId: nil, accountIndex: 2)
        XCTAssertEqual(title, "Tavily (#3)")
    }

    func testTitleFallsBackToIndexWhenAccountIdEmpty() {
        let title = StatusBarController.searchEngineAccountTitle(
            base: "Tavily", accountId: "", accountIndex: 0)
        XCTAssertEqual(title, "Tavily (#1)")
    }
}
