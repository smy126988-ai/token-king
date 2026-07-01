import Foundation
import os

private let rateLogger = Logger(subsystem: "com.opencodeproviders", category: "ExchangeRateStore")

/// Holds the USD→CNY exchange rate with scheme C behaviour:
/// local default → on launch fetch live rate → on success write back to cache →
/// on failure keep the last cached value (stale-while-revalidate).
final class ExchangeRateStore {
    /// Reasonable fallback used only until the first successful fetch writes a real value.
    static let defaultUSDToCNY: Double = 7.2
    static let cacheKey = "currency.usdToCNY.cached"
    static let cacheUpdatedAtKey = "currency.usdToCNY.updatedAt"

    private let defaults: UserDefaults
    /// Injectable fetcher returning raw response Data. Real impl hits open.er-api.com.
    /// Mutable so tests can swap behaviour mid-lifecycle (e.g. success then failure).
    var fetcher: () async throws -> Data

    init(defaults: UserDefaults = .standard,
         fetcher: (() async throws -> Data)? = nil) {
        self.defaults = defaults
        self.fetcher = fetcher ?? ExchangeRateStore.liveFetch
    }

    /// Current rate: cached value if present, otherwise the default.
    var usdToCNY: Double {
        let cached = defaults.double(forKey: Self.cacheKey)
        return cached > 0 ? cached : Self.defaultUSDToCNY
    }

    /// Fetch live rate; on success write back to cache. Throws on failure (caller may ignore).
    func refresh() async throws {
        let data = try await fetcher()
        let rate = try Self.parseUSDToCNY(from: data)
        defaults.set(rate, forKey: Self.cacheKey)
        defaults.set(Date().timeIntervalSince1970, forKey: Self.cacheUpdatedAtKey)
        rateLogger.info("USD→CNY refreshed: \(rate)")
    }

    static func parseUSDToCNY(from data: Data) throws -> Double {
        struct Response: Decodable {
            let result: String
            let rates: [String: Double]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard decoded.result == "success", let cny = decoded.rates["CNY"], cny > 0 else {
            throw ProviderError.decodingError("Exchange rate response missing CNY")
        }
        return cny
    }

    private static func liveFetch() async throws -> Data {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/USD") else {
            throw ProviderError.networkError("Invalid exchange rate URL")
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ProviderError.networkError("Exchange rate HTTP error")
        }
        return data
    }
}
