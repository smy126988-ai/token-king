import XCTest
@testable import OpenCode_Bar

final class KimiProviderTests: XCTestCase {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeCredentials(
        cnKey: String? = "cn-kimi-key",
        globalKey: String? = "global-kimi-key"
    ) -> FakeProviderCredentialStore {
        let credentials = FakeProviderCredentialStore()
        credentials.kimiCNAPIKey = cnKey
        credentials.kimiAPIKey = globalKey
        return credentials
    }

    override func tearDown() {
        TestURLProtocol.reset()
        super.tearDown()
    }

    func testWeeklyUsedUsesDirectUsedFieldWhenPresent() async throws {
        let json = """
        {
          "user": {"userId": "u1", "membership": {"level": "LEVEL_VIVACE"}},
          "usage": {"limit": "100", "used": "25", "remaining": "80", "resetTime": "2026-07-08T02:32:44Z"},
          "limits": [{"window": {"duration": 5, "timeUnit": "HOUR"},
                      "detail": {"limit": "50", "used": "0", "remaining": "46", "resetTime": "2026-07-01T08:00:00Z"}}]
        }
        """.data(using: .utf8)!

        TestURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let provider = KimiCNProvider(tokenManager: makeCredentials(), session: makeSession())
        let result = try await provider.fetch()

        XCTAssertEqual(result.details?.sevenDayUsage ?? -1, 25.0, accuracy: 0.01)
        XCTAssertEqual(result.details?.fiveHourUsage ?? -1, 0.0, accuracy: 0.01)
    }

    func testFetchUsesInjectedCNKeyWithoutTokenManager() async throws {
        let credentials = FakeProviderCredentialStore()
        credentials.kimiCNAPIKey = "injected-kimi-cn-key"
        let json = """
        {
          "usage": {"limit": "100", "used": "25", "remaining": "75"},
          "limits": []
        }
        """.data(using: .utf8)!

        TestURLProtocol.handler = { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer injected-kimi-cn-key"
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, json)
        }

        let provider = KimiCNProvider(tokenManager: credentials, session: makeSession())
        _ = try await provider.fetch()
    }

    func testWeeklyUsedFallsBackToLimitMinusRemainingWhenUsedMissing() async throws {
        let json = """
        {
          "user": {"userId": "u1", "membership": {"level": "LEVEL_VIVACE"}},
          "usage": {"limit": "100", "remaining": "40", "resetTime": "2026-07-08T02:32:44Z"},
          "limits": [{"window": {"duration": 5, "timeUnit": "HOUR"},
                      "detail": {"limit": "50", "remaining": "45", "resetTime": "2026-07-01T08:00:00Z"}}]
        }
        """.data(using: .utf8)!

        TestURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let provider = KimiCNProvider(tokenManager: makeCredentials(), session: makeSession())
        let result = try await provider.fetch()

        XCTAssertEqual(result.details?.sevenDayUsage ?? -1, 60.0, accuracy: 0.01)
    }

    func testIntermediateLevelMapsToModeratoInProviderResult() async throws {
        let json = """
        {
          "user": {"userId": "u1", "region": "REGION_CN", "membership": {"level": "LEVEL_INTERMEDIATE"}},
          "usage": {"limit": "100", "remaining": "88", "resetTime": "2026-07-08T02:32:44Z"},
          "limits": [{"window": {"duration": 5, "timeUnit": "HOUR"},
                      "detail": {"limit": "100", "remaining": "64", "resetTime": "2026-07-01T08:00:00Z"}}]
        }
        """

        TestURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(json.utf8))
        }

        let provider = KimiCNProvider(tokenManager: makeCredentials(), session: makeSession())
        let result = try await provider.fetch()

        XCTAssertEqual(result.details?.planType, "Moderato")
    }

    func testKimiCNProviderIdentifierAndType() {
        let provider = KimiCNProvider()
        XCTAssertEqual(provider.identifier, .kimiCN)
        XCTAssertEqual(provider.type, .quotaBased)
    }

    func testKimiGlobalProviderIdentifierAndType() {
        let provider = KimiGlobalProvider()
        XCTAssertEqual(provider.identifier, .kimi)
        XCTAssertEqual(provider.type, .quotaBased)
    }

    func testKimiProvidersUseSameEndpointAndDifferentKeys() async throws {
        let responseJSON = """
        {
          "user": {"userId": "u1", "membership": {"level": "LEVEL_VIVACE"}},
          "usage": {"limit": "100", "remaining": "40", "resetTime": "2026-07-08T02:32:44Z"},
          "limits": [{"window": {"duration": 5, "timeUnit": "HOUR"},
                      "detail": {"limit": "50", "remaining": "45", "resetTime": "2026-07-01T08:00:00Z"}}]
        }
        """

        TestURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }

        let session = makeSession()

        let cnProvider = KimiCNProvider(tokenManager: makeCredentials(), session: session)
        let globalProvider = KimiGlobalProvider(tokenManager: makeCredentials(), session: session)

        _ = try await cnProvider.fetch()
        _ = try await globalProvider.fetch()

        let capturedRequests = TestURLProtocol.recordedRequests
        XCTAssertEqual(capturedRequests.count, 2)
        for request in capturedRequests {
            XCTAssertEqual(request.url?.absoluteString, "https://api.kimi.com/coding/v1/usages")
            XCTAssertEqual(request.httpMethod, "GET")
        }

        let cnAuthorization = capturedRequests[0].value(forHTTPHeaderField: "Authorization")
        let globalAuthorization = capturedRequests[1].value(forHTTPHeaderField: "Authorization")

        XCTAssertEqual(cnAuthorization, "Bearer cn-kimi-key")
        XCTAssertEqual(globalAuthorization, "Bearer global-kimi-key")
    }
}
