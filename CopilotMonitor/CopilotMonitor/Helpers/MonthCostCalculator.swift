import Foundation

/// Monthly cost-equivalent calculation (F2b Layer 4).
///
/// Formula:
///     costRMB = (input * inputRate + output * outputRate + cacheRead * cacheReadRate) / 1e6
/// where `*Rate` is the F2a `PayAsYouGoRate` value in RMB per million tokens.
///
/// `cacheWrite` is intentionally excluded (5 reference consensus:
/// Anthropic prompt cache writes are free; OpenAI cache-write cost is simplified away).
///
/// Lookup is by `(provider, model)`. Only representative models (the same models
/// PricingTable documents in its source comments) return a cost. Unknown models
/// return `nil` so the UI can display "Unknown" without blocking other fields.
struct MonthCostCalculator {

    /// `PricingTable.Type`: passes the metatype so the static call site
    /// `pricingTable.rate(for: providerId)` resolves to F2a's static method,
    /// even though PricingTable is a no-cases enum and cannot be instantiated
    /// as a value. Default keeps call sites terse; tests can override.
    let pricingTable: PricingTable.Type

    init(pricingTable: PricingTable.Type = PricingTable.self) {
        self.pricingTable = pricingTable
    }

    /// Compute the cost-equivalent for a single month_aggregate. Thin
    /// wrapper over `calculateWithSource(...)` that drops the
    /// `usedFallback` flag. Existing call sites that only need the
    /// cost number (TokenEventKimiCNTests, 11 legacy test cases) keep
    /// using this entry point; new code that needs to flag
    /// "estimated" rows uses `calculateWithSource(...)` directly.
    func calculate(provider: String, model: String, tokens: TokenBreakdown) -> Double? {
        calculateWithSource(provider: provider, model: model, tokens: tokens)?.costRMB
    }

    /// Source-resolved cost (round 10, 2026-07-12). Returns both the
    /// computed RMB cost AND whether the row was priced via the
    /// provider-level fallback (i.e. modelRate(for:) was queried but
    /// returned nil). The `usedFallback` flag is the signal that
    /// `calculateMonthlyTotals` aggregates into `MonthlyTotal.hasUnknownPricing`
    /// so the UI can show an "estimated" badge on those rows.
    ///
    /// Returned nil when the provider is itself unknown to F2a, or the
    /// rate lookup returns a degenerate (input + output both 0) value.
    ///
    /// `usedFallback` is set only when:
    ///   - the provider has a public provider-level rate AND
    ///   - `pricingTable.modelRate(for: model)` returned nil.
    ///
    /// Every recognized provider attempts the model-level lookup first. This
    /// allows non-OpenAI routes such as Kimi Code, MiniMax, and OpenCode Go to
    /// use their explicit model prices. Providers without public fallback
    /// pricing do not receive an "estimated" marker solely because their model
    /// is absent from the model table.
    func calculateWithSource(provider: String, model: String, tokens: TokenBreakdown) -> CostEstimate? {
        guard let providerId = providerStringToIdentifier(provider) else { return nil }

        let modelRate = pricingTable.modelRate(for: model)
        let rate = modelRate ?? pricingTable.rate(for: providerId)
        guard let rate = rate, rate.input > 0 || rate.output > 0 else { return nil }

        let inputCost = Double(tokens.input) * rate.input / 1_000_000
        let outputCost = Double(tokens.output) * rate.output / 1_000_000
        let cacheReadCost = Double(tokens.cacheRead) * (rate.cache ?? 0) / 1_000_000
        let providerHasFallbackRate = PricingTable.providersWithPublicPricing.contains(providerId)
        let usedProviderFallback = providerHasFallbackRate
            && modelRate == nil
            && !isRepresentativeModel(model, for: providerId)
        return CostEstimate(
            costRMB: inputCost + outputCost + cacheReadCost,
            usedFallback: usedProviderFallback
        )
    }

    /// Aggregate `month_aggregates` into a per-provider `MonthlyTotal`.
    /// Aggregates with unknown pricing are still preserved in `modelBreakdown`
    /// (with `costRMB == nil`) and `hasUnknownPricing` is set to `true`
    /// on the provider total when at least one aggregate is unknown.
    func calculateMonthlyTotals(_ aggregates: [MonthAggregate]) -> [MonthlyTotal] {
        var totals: [String: MonthlyTotal] = [:]
        for agg in aggregates {
            let estimate = calculateWithSource(provider: agg.provider, model: agg.model, tokens: agg.tokens)
            let cost = estimate?.costRMB
            let existing = totals[agg.provider]
            totals[agg.provider] = MonthlyTotal(
                provider: agg.provider,
                modelBreakdown: (existing?.modelBreakdown ?? []) + [
                    ModelCost(model: agg.model, tokens: agg.tokens, costRMB: cost)
                ],
                totalTokens: (existing?.totalTokens ?? TokenBreakdown())
                    .adding(agg.tokens),
                totalCostRMB: (existing?.totalCostRMB ?? 0) + (cost ?? 0),
                hasUnknownPricing: (existing?.hasUnknownPricing ?? false)
                    || (estimate == nil || estimate?.usedFallback == true)
            )
        }
        return Array(totals.values)
    }

    private func isRepresentativeModel(_ model: String, for provider: ProviderIdentifier) -> Bool {
        switch provider {
        case .kimi, .kimiCN:
            return model == "kimi-k2.6"
        case .claude:
            return model == "claude-sonnet-4-5"
        case .zaiCodingPlan:
            return model == "glm-4.6"
        case .nanoGpt, .codex:
            return model == "gpt-4o"
        default:
            return false
        }
    }

    /// F2a `PricingTable.rate(for:)` accepts `ProviderIdentifier`
    /// (`.kimi / .kimiCN / .claude / .zaiCodingPlan / .nanoGpt / .codex`).
    /// `MonthAggregate.provider` is a `String` (read from SQLite via `TokenUsageStore`).
    ///
    /// `TokenSource.kimiCode.rawValue` is `"kimiCode"` (camelCase).
    /// `providerStringToIdentifier` lowercases before matching, so the case
    /// is irrelevant at this layer. The alias maps `"kimicode"` -> `.kimi`
    /// to share pricing with the main kimi provider (current F2b schema
    /// writes `provider='kimi' AND source='kimiCode'`, so the alias is
    /// forward-compat for a future schema where kimiCode becomes its own
    /// provider enum).
    ///
    /// The "zai" string is F2b `Provider.zai.rawValue`; it must bridge to F2a's
    /// `ProviderIdentifier.zaiCodingPlan` — they are distinct enums.
    private func providerStringToIdentifier(_ s: String) -> ProviderIdentifier? {
        switch s.lowercased() {
        case "kimi", "kimicode": return .kimi
        case "kimicn":           return .kimiCN
        case "claude":           return .claude
        case "codex":            return .codex
        case "zai":              return .zaiCodingPlan
        case "nanogpt":          return .nanoGpt
        default:                  return nil
        }
    }
}

/// Per-provider monthly rollup. One entry per `Provider` raw value seen in
/// `month_aggregates`. `modelBreakdown` preserves every (model, tokens, costRMB)
/// triple for UI display; `hasUnknownPricing` is true iff any single model
/// in the breakdown had no F2a PricingTable rate.
struct MonthlyTotal {
    let provider: String
    let modelBreakdown: [ModelCost]
    let totalTokens: TokenBreakdown
    let totalCostRMB: Double
    let hasUnknownPricing: Bool
}

/// Per-model rollup row inside a `MonthlyTotal.modelBreakdown`.
/// `costRMB == nil` signals that the model had no representative rate in
/// PricingTable, so the row contributes to `hasUnknownPricing` but not to
/// `totalCostRMB`.
struct ModelCost {
    let model: String
    let tokens: TokenBreakdown
    let costRMB: Double?
}

/// Per-row pricing result from `MonthCostCalculator.calculateWithSource(...)`.
/// `usedFallback` is true when the row was priced via the provider-level
/// representative rate because `modelRate(for: model)` was queried
/// (model name matches an OpenAI prefix AND provider is `.codex`) but
/// returned nil. UI surfaces this as an "estimated" badge.
struct CostEstimate {
    let costRMB: Double
    let usedFallback: Bool
}

extension TokenBreakdown {
    /// Component-wise add. Used by `MonthCostCalculator.calculateMonthlyTotals`
    /// to roll up per-(provider, model) tokens into the per-provider total.
    func adding(_ other: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(
            input: input + other.input,
            output: output + other.output,
            cacheRead: cacheRead + other.cacheRead,
            cacheWrite: cacheWrite + other.cacheWrite,
            reasoning: reasoning + other.reasoning
        )
    }
}
