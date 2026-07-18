import XCTest
@testable import OpenCode_Bar

final class SyntheticProviderTests: XCTestCase {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeCredentials(
        authPath: URL? = URL(fileURLWithPath: "/tmp/test-opencode-auth.json")
    ) -> FakeProviderCredentialStore {
        let credentials = FakeProviderCredentialStore()
        credentials.syntheticAPIKey = "test-synthetic-key"
        credentials.lastFoundAuthPath = authPath
        return credentials
    }

    private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
        let url = URL(string: "https://api.synthetic.new/v2/quotas")!
        return HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    override func tearDown() {
        TestURLProtocol.reset()
        super.tearDown()
    }

    func testProviderIdentifier() {
        let provider = SyntheticProvider()
        XCTAssertEqual(provider.identifier, .synthetic)
    }

    func testProviderType() {
        let provider = SyntheticProvider()
        XCTAssertEqual(provider.type, .quotaBased)
    }

    func testFetchUsesInjectedKeyWithoutTokenManager() async throws {
        let credentials = FakeProviderCredentialStore()
        credentials.syntheticAPIKey = "injected-synthetic-key"

        TestURLProtocol.handler = { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer injected-synthetic-key"
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let json = #"{"subscription":{"limit":100,"requests":25,"renewsAt":null}}"#
            return (response, Data(json.utf8))
        }

        let provider = SyntheticProvider(tokenManager: credentials, session: makeSession())
        _ = try await provider.fetch()
    }

    func testFetchSuccessCreatesProviderResult() async throws {
        let credentials = makeCredentials()
        let expectedAuthPath = credentials.lastFoundAuthPath?.path
        let session = makeSession()
        let provider = SyntheticProvider(tokenManager: credentials, session: session)

        let json = """
        {
          "subscription": {
            "limit": 200,
            "requests": 50.5,
            "renewsAt": "2026-02-05T14:59:30.123Z"
          }
        }
        """
        let data = json.data(using: .utf8)!
        TestURLProtocol.handler = { _ in
            (self.makeHTTPResponse(statusCode: 200), data)
        }

        let result = try await provider.fetch()

        switch result.usage {
        case .quotaBased(let remaining, let entitlement, let overagePermitted):
            XCTAssertEqual(remaining, 149)
            XCTAssertEqual(entitlement, 200)
            XCTAssertFalse(overagePermitted)
        default:
            XCTFail("Expected quota-based usage")
        }

        XCTAssertEqual(result.details?.limit, 200)
        XCTAssertEqual(result.details?.limitRemaining, 149)
        if let fiveHourUsage = result.details?.fiveHourUsage {
            XCTAssertEqual(fiveHourUsage, 25.25, accuracy: 0.01)
        } else {
            XCTFail("Expected fiveHourUsage")
        }
        XCTAssertNotNil(result.details?.fiveHourReset)
        XCTAssertEqual(result.details?.authSource, expectedAuthPath)
    }

    func testFetchReturnsAuthenticationErrorOn401() async throws {
        let session = makeSession()
        let provider = SyntheticProvider(tokenManager: makeCredentials(), session: session)

        let data = Data("{}".utf8)
        TestURLProtocol.handler = { _ in
            (self.makeHTTPResponse(statusCode: 401), data)
        }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected authentication failure")
        } catch let error as ProviderError {
            switch error {
            case .authenticationFailed:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchReturnsNetworkErrorOnNon200() async throws {
        let session = makeSession()
        let provider = SyntheticProvider(tokenManager: makeCredentials(), session: session)

        let data = Data("{}".utf8)
        TestURLProtocol.handler = { _ in
            (self.makeHTTPResponse(statusCode: 500), data)
        }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected network error")
        } catch let error as ProviderError {
            switch error {
            case .networkError(let message):
                XCTAssertTrue(message.contains("HTTP 500"))
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchReturnsAuthenticationErrorOnMalformedJSON() async throws {
        let session = makeSession()
        let provider = SyntheticProvider(tokenManager: makeCredentials(), session: session)

        let data = Data("{".utf8)
        TestURLProtocol.handler = { _ in
            (self.makeHTTPResponse(statusCode: 200), data)
        }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected authentication failure")
        } catch let error as ProviderError {
            switch error {
            case .authenticationFailed(let message):
                XCTAssertTrue(message.contains("No active Synthetic subscription"))
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchParsesDateWithoutFractionalSeconds() async throws {
        let session = makeSession()
        let provider = SyntheticProvider(tokenManager: makeCredentials(), session: session)

        let json = """
        {
          "subscription": {
            "limit": 100,
            "requests": 20,
            "renewsAt": "2026-02-05T14:59:30Z"
          }
        }
        """
        let data = json.data(using: .utf8)!
        TestURLProtocol.handler = { _ in
            (self.makeHTTPResponse(statusCode: 200), data)
        }

        let result = try await provider.fetch()
        XCTAssertNotNil(result.details?.fiveHourReset)
    }

    func testDecodingWithFractionalRequests() throws {
        let json = """
        {
          "subscription": {
            "limit": 135,
            "requests": 35.6,
            "renewsAt": "2025-09-21T14:36:14.288Z"
          }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(SyntheticQuotasResponse.self, from: data)

        XCTAssertEqual(response.subscription.limit, 135)
        XCTAssertEqual(response.subscription.requests, 35.6, accuracy: 0.01)
        XCTAssertEqual(response.subscription.renewsAt, "2025-09-21T14:36:14.288Z")
    }

    func testDecodingWithoutFractionalSeconds() throws {
        let json = """
        {
          "subscription": {
            "limit": 100,
            "requests": 0,
            "renewsAt": "2025-12-31T23:59:59Z"
          }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(SyntheticQuotasResponse.self, from: data)

        XCTAssertEqual(response.subscription.limit, 100)
        XCTAssertEqual(response.subscription.requests, 0)
    }
}
