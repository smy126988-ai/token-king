import XCTest
@testable import OpenCode_Bar

final class CurrencyFormatterTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "CurrencyFormatterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testDefaultsToUSD() {
        let f = CurrencyFormatter(defaults: makeDefaults(), rateStore: ExchangeRateStore(defaults: makeDefaults()))
        XCTAssertEqual(f.currency, .usd)
    }

    func testFormatsUSDUnchanged() {
        let f = CurrencyFormatter(defaults: makeDefaults(), rateStore: ExchangeRateStore(defaults: makeDefaults()))
        f.currency = .usd
        XCTAssertEqual(f.format(usd: 12.5), "$12.50")
    }

    func testFormatsRMBUsingRate() {
        let defaults = makeDefaults()
        let rateDefaults = makeDefaults()
        rateDefaults.set(7.0, forKey: ExchangeRateStore.cacheKey)
        let f = CurrencyFormatter(defaults: defaults, rateStore: ExchangeRateStore(defaults: rateDefaults))
        f.currency = .rmb
        XCTAssertEqual(f.format(usd: 10.0), "¥70.00")
    }

    func testCurrencyPreferencePersists() {
        let defaults = makeDefaults()
        let f = CurrencyFormatter(defaults: defaults, rateStore: ExchangeRateStore(defaults: makeDefaults()))
        f.currency = .rmb
        let reopened = CurrencyFormatter(defaults: defaults, rateStore: ExchangeRateStore(defaults: makeDefaults()))
        XCTAssertEqual(reopened.currency, .rmb)
    }

    func testFormatWithDecimalsZero() {
        let f = CurrencyFormatter(defaults: makeDefaults(), rateStore: ExchangeRateStore(defaults: makeDefaults()))
        f.currency = .usd
        XCTAssertEqual(f.format(usd: 42.0, decimals: 0), "$42")
    }
}
