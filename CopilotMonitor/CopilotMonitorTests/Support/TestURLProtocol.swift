import Foundation

final class TestURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var handler: Handler?
        var requests: [URLRequest] = []
    }

    private static let state = State()

    static var handler: Handler? {
        get {
            state.lock.lock()
            defer { state.lock.unlock() }
            return state.handler
        }
        set {
            state.lock.lock()
            state.handler = newValue
            state.lock.unlock()
        }
    }

    static var recordedRequests: [URLRequest] {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.requests
    }

    static func reset() {
        state.lock.lock()
        state.handler = nil
        state.requests = []
        state.lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.state.lock.lock()
        Self.state.requests.append(request)
        let handler = Self.state.handler
        Self.state.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
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
