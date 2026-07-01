import Foundation

/// Formats USD amounts into the user's selected display currency.
/// USD amounts are the source of truth everywhere; this converts + renders at the edge.
final class CurrencyFormatter {
    static let shared = CurrencyFormatter()

    private let defaults: UserDefaults
    private let rateStore: ExchangeRateStore

    init(defaults: UserDefaults = .standard,
         rateStore: ExchangeRateStore = ExchangeRateStore()) {
        self.defaults = defaults
        self.rateStore = rateStore
    }

    var currency: Currency {
        get {
            guard let raw = defaults.string(forKey: CurrencyPreferences.selectedCurrencyKey),
                  let c = Currency(rawValue: raw) else { return .usd }
            return c
        }
        set { defaults.set(newValue.rawValue, forKey: CurrencyPreferences.selectedCurrencyKey) }
    }

    /// Convert a USD amount into the active currency and render with symbol.
    func format(usd amount: Double, decimals: Int = 2) -> String {
        let converted: Double
        switch currency {
        case .usd: converted = amount
        case .rmb: converted = amount * rateStore.usdToCNY
        }
        return "\(currency.symbol)\(String(format: "%.\(decimals)f", converted))"
    }

    /// Kick a background rate refresh (call on launch). Failures are silently ignored.
    func refreshRateInBackground() {
        Task { try? await rateStore.refresh() }
    }
}
