import Foundation

/// Abstraction for `CurrencyFormatter` introduced as part of the L1-M1
/// singleton-decoupling refactor (plan §3.2 / D.1). The concrete class
/// conforms; future implementations (e.g. deterministic test doubles) can
/// substitute via InitOptions.
protocol CurrencyFormatting: AnyObject {
    var currency: Currency { get set }
    var currentRate: Double { get }
    func format(usd amount: Double, decimals: Int) -> String
    func format(amount: Double, as currency: Currency?, decimals: Int) -> String
    func refreshRateInBackground()
}

/// Formats USD amounts into the user's selected display currency.
/// USD amounts are the source of truth everywhere; this converts + renders at the edge.
final class CurrencyFormatter: CurrencyFormatting {
    @available(*, deprecated, message: "Use InitOptions.testing or inject CurrencyFormatting")
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
                  let c = Currency(rawValue: raw) else { return .rmb }
            return c
        }
        set { defaults.set(newValue.rawValue, forKey: CurrencyPreferences.selectedCurrencyKey) }
    }

    /// Current USD→CNY rate exposed for callers that need to convert themselves.
    var currentRate: Double { rateStore.usdToCNY }

    /// Convert a USD amount into the active currency and render with symbol.
    func format(usd amount: Double, decimals: Int = 2) -> String {
        let converted: Double
        switch currency {
        case .usd: converted = amount
        case .rmb: converted = amount * rateStore.usdToCNY
        }
        return format(amount: converted, as: currency, decimals: decimals)
    }

    /// Render an amount that has already been converted into the target currency.
    /// Pass `currency` to override the active currency; defaults to the user's selection.
    func format(amount: Double, as currency: Currency? = nil, decimals: Int = 2) -> String {
        let targetCurrency = currency ?? self.currency
        return "\(targetCurrency.symbol)\(String(format: "%.\(decimals)f", amount))"
    }

    /// Kick a background rate refresh (call on launch). Failures are silently ignored.
    func refreshRateInBackground() {
        Task { try? await rateStore.refresh() }
    }
}
