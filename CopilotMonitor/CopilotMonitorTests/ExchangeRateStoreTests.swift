import XCTest
@testable import OpenCode_Bar

final class ExchangeRateStoreTests: XCTestCase {
    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: type(of: self))
        let url = bundle.url(forResource: name, withExtension: "json")!
        return try Data(contentsOf: url)
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ExchangeRateStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testParsesCNYRateFromSuccessResponse() throws {
        let rate = try ExchangeRateStore.parseUSDToCNY(from: fixtureData("exchange_rate_success"))
        XCTAssertEqual(rate, 7.2531, accuracy: 0.0001)
    }

    func testParseThrowsOnErrorResponse() throws {
        XCTAssertThrowsError(try ExchangeRateStore.parseUSDToCNY(from: fixtureData("exchange_rate_error")))
    }

    func testRateReturnsDefaultWhenNoCache() {
        let store = ExchangeRateStore(defaults: makeDefaults())
        XCTAssertEqual(store.usdToCNY, ExchangeRateStore.defaultUSDToCNY, accuracy: 0.0001)
    }

    func testRefreshWritesBackCacheAndReadsIt() async throws {
        let defaults = makeDefaults()
        let data = try fixtureData("exchange_rate_success")
        let store = ExchangeRateStore(defaults: defaults, fetcher: { data })
        try await store.refresh()
        XCTAssertEqual(store.usdToCNY, 7.2531, accuracy: 0.0001)
        let reopened = ExchangeRateStore(defaults: defaults)
        XCTAssertEqual(reopened.usdToCNY, 7.2531, accuracy: 0.0001)
    }

    func testRefreshFailureKeepsLastKnownRate() async throws {
        let defaults = makeDefaults()
        let ok = try fixtureData("exchange_rate_success")
        let store = ExchangeRateStore(defaults: defaults, fetcher: { ok })
        try await store.refresh()
        store.fetcher = { throw ProviderError.networkError("boom") }
        _ = try? await store.refresh()
        XCTAssertEqual(store.usdToCNY, 7.2531, accuracy: 0.0001)
    }
}
