import XCTest
@testable import OpenCode_Bar

final class ZAIExtractorTests: XCTestCase {

    private class StubURLProtocol: URLProtocol {
        static var stubData: Data?
        static var stubStatus: Int = 200
        static var stubError: Error?

        private override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: URLProtocolClient?) {
            super.init(request: request, cachedResponse: cachedResponse, client: client)
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            if let error = StubURLProtocol.stubError {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            let status = StubURLProtocol.stubStatus
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response,
                                cacheStoragePolicy: .notAllowed)
            if let data = StubURLProtocol.stubData {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private var session: URLSession!

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubURLProtocol.self)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        super.tearDown()
        URLProtocol.unregisterClass(StubURLProtocol.self)
        StubURLProtocol.stubData = nil
        StubURLProtocol.stubError = nil
        StubURLProtocol.stubStatus = 200
    }

    func testExtractFromSampleData() async {
        let body = """
        {"model":"glm-4.6","input_tokens":1000,"output_tokens":500,"cached_input_tokens":200,"cache_creation_tokens":50,"reasoning_tokens":30}
        """
        StubURLProtocol.stubData = body.data(using: .utf8)
        StubURLProtocol.stubStatus = 200

        let extractor = ZAIExtractor(
            session: session,
            bearerTokenProvider: { "test-token" }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertNotNil(events)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, .zaiApi)
        XCTAssertEqual(events.first?.model, "glm-4.6")
        XCTAssertEqual(events.first?.provider, .zai)
    }

    func testMissingBearerTokenReturnsEmpty() async {
        let extractor = ZAIExtractor(
            session: session,
            bearerTokenProvider: { nil }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testNetworkErrorReturnsEmpty() async {
        StubURLProtocol.stubError = NSError(
            domain: NSURLErrorDomain, code: NSURLErrorTimedOut
        )

        let extractor = ZAIExtractor(
            session: session,
            bearerTokenProvider: { "test-token" }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testBrokenJSONReturnsEmpty() async {
        StubURLProtocol.stubData = "this is not json".data(using: .utf8)
        StubURLProtocol.stubStatus = 200

        let extractor = ZAIExtractor(
            session: session,
            bearerTokenProvider: { "test-token" }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testProviderNormalizationApplied() async {
        let body = """
        {"model":"glm-5p","input_tokens":100,"output_tokens":50}
        """
        StubURLProtocol.stubData = body.data(using: .utf8)
        StubURLProtocol.stubStatus = 200

        let extractor = ZAIExtractor(
            session: session,
            bearerTokenProvider: { "test-token" }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.first?.provider, .zai)
    }

    func testTokenBreakdownExtraction() async {
        let body = """
        {"model":"glm-4.6","input_tokens":1000,"output_tokens":500,"cached_input_tokens":200,"cache_creation_tokens":50,"reasoning_tokens":30}
        """
        StubURLProtocol.stubData = body.data(using: .utf8)

        let extractor = ZAIExtractor(
            session: session,
            bearerTokenProvider: { "test-token" }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.first?.tokens.input, 1000)
        XCTAssertEqual(events.first?.tokens.output, 500)
        XCTAssertEqual(events.first?.tokens.cacheRead, 200)
        XCTAssertEqual(events.first?.tokens.cacheWrite, 50)
        XCTAssertEqual(events.first?.tokens.reasoning, 30)
    }
}
