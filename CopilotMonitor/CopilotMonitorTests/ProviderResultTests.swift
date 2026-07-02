import XCTest
@testable import OpenCode_Bar

final class ProviderResultTests: XCTestCase {
    private let currencyKey = CurrencyPreferences.selectedCurrencyKey
    private let rateKey = ExchangeRateStore.cacheKey

    private func setCurrency(_ currency: Currency, rate: Double) {
        UserDefaults.standard.set(currency.rawValue, forKey: currencyKey)
        UserDefaults.standard.set(rate, forKey: rateKey)
    }

    private func restoreCurrencyState(currency: String?, rate: Double?) {
        if let currency = currency {
            UserDefaults.standard.set(currency, forKey: currencyKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currencyKey)
        }
        if let rate = rate {
            UserDefaults.standard.set(rate, forKey: rateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: rateKey)
        }
    }

    // MARK: - TableFormatter currency awareness

    func testSingleProviderPayAsYouGoUsesRMBSymbol() {
        let previousCurrency = UserDefaults.standard.string(forKey: currencyKey)
        let previousRate = UserDefaults.standard.object(forKey: rateKey) as? Double
        addTeardownBlock { [weak self] in
            self?.restoreCurrencyState(currency: previousCurrency, rate: previousRate)
        }

        setCurrency(.rmb, rate: 7.0)

        let usage = ProviderUsage.payAsYouGo(utilization: 0, cost: 10.0, resetsAt: nil)
        let result = ProviderResult(usage: usage, details: nil)
        let output = TableFormatter.format([.claude: result])

        XCTAssertTrue(output.contains("¥70.00 spent"),
                      "Expected RMB formatted cost in single-provider row, got:\n\(output)")
        XCTAssertFalse(output.contains("$"),
                       "Output should not contain hardcoded USD symbol in RMB mode, got:\n\(output)")
    }

    func testMultiAccountPayAsYouGoUsesRMBSymbol() {
        let previousCurrency = UserDefaults.standard.string(forKey: currencyKey)
        let previousRate = UserDefaults.standard.object(forKey: rateKey) as? Double
        addTeardownBlock { [weak self] in
            self?.restoreCurrencyState(currency: previousCurrency, rate: previousRate)
        }

        setCurrency(.rmb, rate: 7.0)

        let account = ProviderAccountResult(
            accountIndex: 0,
            accountId: "alice",
            usage: .payAsYouGo(utilization: 0, cost: 5.0, resetsAt: nil),
            details: nil
        )
        let aggregate = ProviderUsage.payAsYouGo(utilization: 0, cost: 5.0, resetsAt: nil)
        let result = ProviderResult(usage: aggregate, details: nil, accounts: [account])

        let output = TableFormatter.format([.openRouter: result])

        XCTAssertTrue(output.contains("¥35.00 spent"),
                      "Expected RMB formatted cost in multi-account row, got:\n\(output)")
        XCTAssertFalse(output.contains("$"),
                       "Output should not contain hardcoded USD symbol in RMB mode, got:\n\(output)")
    }

    func testSingleProviderPayAsYouGoStillSupportsUSD() {
        let previousCurrency = UserDefaults.standard.string(forKey: currencyKey)
        let previousRate = UserDefaults.standard.object(forKey: rateKey) as? Double
        addTeardownBlock { [weak self] in
            self?.restoreCurrencyState(currency: previousCurrency, rate: previousRate)
        }

        setCurrency(.usd, rate: 7.0)

        let usage = ProviderUsage.payAsYouGo(utilization: 0, cost: 10.0, resetsAt: nil)
        let result = ProviderResult(usage: usage, details: nil)
        let output = TableFormatter.format([.claude: result])

        XCTAssertTrue(output.contains("$10.00 spent"),
                      "Expected USD formatted cost in USD mode, got:\n\(output)")
    }
}
