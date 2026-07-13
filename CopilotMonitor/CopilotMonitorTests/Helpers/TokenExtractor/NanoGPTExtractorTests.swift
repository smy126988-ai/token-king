import XCTest
@testable import OpenCode_Bar

final class NanoGPTExtractorTests: XCTestCase {

    private final class StubURLProtocol: URLProtocol {
        static var stubData: Data?
        static var stubStatus: Int = 200
        static var stubError: Error?

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
        {"model":"gpt-4o","input_tokens":500,"output_tokens":250,"cached_input_tokens":100,"cache_creation_tokens":20}
        """
        StubURLProtocol.stubData = body.data(using: .utf8)
        StubURLProtocol.stubStatus = 200

        let extractor = NanoGPTExtractor(
            session: session,
            bearerTokenProvider: { "test-key" }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertNotNil(events)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.source, .nanoGptApi)
        XCTAssertEqual(events.first?.model, "gpt-4o")
    }

    func testMissingBearerTokenReturnsEmpty() async {
        let extractor = NanoGPTExtractor(
            session: session,
            bearerTokenProvider: { nil }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testNetworkErrorReturnsEmpty() async {
        StubURLProtocol.stubError = NSError(
            domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost
        )

        let extractor = NanoGPTExtractor(
            session: session,
            bearerTokenProvider: { "test-key" }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testBrokenJSONReturnsEmpty() async {
        StubURLProtocol.stubData = "garbled response".data(using: .utf8)
        StubURLProtocol.stubStatus = 200

        let extractor = NanoGPTExtractor(
            session: session,
            bearerTokenProvider: { "test-key" }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testProviderNormalizationApplied() async {
        // P0-3 fix: NanoGPT API responses must route to `.nanoGpt`, not `.codex`,
        // even when the model name is OpenAI-style (e.g. `gpt-4o-mini`). The
        // providerID signal wins over the model prefix in TokenNormalizer.
        let body = """
        {"model":"gpt-4o-mini","input_tokens":100,"output_tokens":50}
        """
        StubURLProtocol.stubData = body.data(using: .utf8)

        let extractor = NanoGPTExtractor(
            session: session,
            bearerTokenProvider: { "test-key" }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.first?.provider, .nanoGpt)
    }

    func testTokenBreakdownExtraction() async {
        let body = """
        {"model":"gpt-4o","input_tokens":500,"output_tokens":250,"cached_input_tokens":100,"cache_creation_tokens":20}
        """
        StubURLProtocol.stubData = body.data(using: .utf8)

        let extractor = NanoGPTExtractor(
            session: session,
            bearerTokenProvider: { "test-key" }
        )
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.first?.tokens.input, 500)
        XCTAssertEqual(events.first?.tokens.output, 250)
        XCTAssertEqual(events.first?.tokens.cacheRead, 100)
        XCTAssertEqual(events.first?.tokens.cacheWrite, 20)
    }

    func testInjectedDefaultsProvidesBearerToken() {
        let suiteName = "test.NanoGPT.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        defaults.set("injected-key", forKey: "nanogpt.apiKey")

        let extractor = NanoGPTExtractor(session: session, defaults: defaults)
        XCTAssertEqual(extractor.bearerTokenProvider(), "injected-key")
    }

    func testInjectedDefaultsPreventsReadingStandard() {
        UserDefaults.standard.set("standard-key", forKey: "nanogpt.apiKey")
        defer { UserDefaults.standard.removeObject(forKey: "nanogpt.apiKey") }

        let suiteName = "test.NanoGPT.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        defaults.removeObject(forKey: "nanogpt.apiKey")

        let extractor = NanoGPTExtractor(session: session, defaults: defaults)
        XCTAssertNotEqual(extractor.bearerTokenProvider(), "standard-key")
        XCTAssertNil(extractor.bearerTokenProvider())
    }
}