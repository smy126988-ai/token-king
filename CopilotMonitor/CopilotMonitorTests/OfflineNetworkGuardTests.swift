import XCTest
@testable import OpenCode_Bar

final class OfflineNetworkGuardTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TestURLProtocol.reset()
    }

    override func tearDown() {
        TestURLProtocol.reset()
        super.tearDown()
    }

    func testUnstubbedHTTPSRequestIsRejectedByTestURLProtocol() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let url = try XCTUnwrap(URL(string: "https://example.invalid/unstubbed"))

        do {
            _ = try await session.data(from: url)
            XCTFail("Expected an unstubbed request to fail")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        }

        XCTAssertEqual(TestURLProtocol.recordedRequests.map(\.url), [url])
    }
}
