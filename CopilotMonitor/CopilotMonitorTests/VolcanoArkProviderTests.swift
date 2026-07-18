import XCTest
@testable import OpenCode_Bar

final class VolcanoArkProviderTests: XCTestCase {
    private final class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override static func canInit(with request: URLRequest) -> Bool { true }
        override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard let handler = MockURLProtocol.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testProviderIdentifierAndType() {
        let provider = VolcanoArkProvider()
        XCTAssertEqual(provider.identifier, .volcanoArk)
        XCTAssertEqual(provider.type, .quotaBased)
    }

    func testSignerProducesExpectedHeaderShape() {
        let url = URL(string: "https://ark.cn-beijing.volces.com/?Action=GetAFPUsage&Version=2024-01-01")!
        let request = VolcanoArkSigner.signedRequest(
            url: url,
            accessKey: "AKLTTest",
            secretKey: "SecretTest"
        )
        XCTAssertNotNil(request)
        let auth = request?.value(forHTTPHeaderField: "Authorization")
        XCTAssertNotNil(auth)
        XCTAssertTrue(auth?.hasPrefix("HMAC-SHA256 Credential=") ?? false)
        XCTAssertTrue(auth?.contains("SignedHeaders=content-type;host;x-content-sha256;x-date") ?? false)
    }

    func testFetchParsesFiveHourAndWeeklyWindows() async throws {
        let json = """
        {
          "Result": {
            "AFPFiveHour": { "Quota": 2000, "Used": 500, "ResetTime": 1778806800000 },
            "AFPWeekly": { "Quota": 7000, "Used": 1500, "ResetTime": 1779062400000 }
          }
        }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue((request.value(forHTTPHeaderField: "Authorization") ?? "").hasPrefix("HMAC-SHA256"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let provider = VolcanoArkProvider(accessKey: "AKLTTest", secretKey: "SecretTest", session: makeSession())
        let result = try await provider.fetch()

        switch result.usage {
        case .quotaBased(let remaining, let entitlement, let overagePermitted):
            XCTAssertEqual(remaining, 75) // 100 - max(25, 21.4)
            XCTAssertEqual(entitlement, 100)
            XCTAssertFalse(overagePermitted)
        default:
            XCTFail("Expected quota-based usage")
        }

        XCTAssertEqual(result.details?.fiveHourUsage ?? -1, 25.0, accuracy: 0.001)
        XCTAssertEqual(result.details?.sevenDayUsage ?? -1, (1500.0 / 7000.0) * 100.0, accuracy: 0.001)
        XCTAssertNotNil(result.details?.fiveHourReset)
        XCTAssertNotNil(result.details?.sevenDayReset)
    }

    func testFetchReturnsAuthenticationErrorOn401() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let provider = VolcanoArkProvider(accessKey: "AKLTTest", secretKey: "SecretTest", session: makeSession())
        do {
            _ = try await provider.fetch()
            XCTFail("Expected authentication failure")
        } catch let error as ProviderError {
            switch error {
            case .authenticationFailed: break
            default: XCTFail("Unexpected error: \(error)")
            }
        }
    }

}
