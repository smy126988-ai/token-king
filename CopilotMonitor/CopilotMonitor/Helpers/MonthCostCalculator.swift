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
    /// `usedFallback` is set ONLY when:
    ///   - the model name matches an OpenAI `gpt-*` / `o1` / `o3` / `o4-*`
    ///     prefix AND
    ///   - the provider is `.codex` AND
    ///   - `pricingTable.modelRate(for: model)` returned nil.
    ///
    /// Other providers (kimi / claude / zai / nanogpt) don't have a
    /// `modelRate(for:)` switch entry today, so their rows always
    /// resolve via `rate(for: providerId)`. That's the canonical path
    /// for that provider, not a fallback. `usedFallback` is false in
    /// those cases so we don't spam the UI with false "estimated" badges
    /// for non-OpenAI providers.
    func calculateWithSource(provider: String, model: String, tokens: TokenBreakdown) -> CostEstimate? {
        guard let providerId = providerStringToIdentifier(provider) else { return nil }

        let looksLikeOpenAIModel = model.hasPrefix("gpt-")
                                  || model.hasPrefix("o1")
                                  || model.hasPrefix("o3")
                                  || model.hasPrefix("o4-")
        let queriedModelRate: Bool = (looksLikeOpenAIModel && providerId == .codex)
        let modelRate: PayAsYouGoRate? = queriedModelRate
            ? pricingTable.modelRate(for: model)
            : nil
        let rate = modelRate ?? pricingTable.rate(for: providerId)
        guard let rate = rate, rate.input > 0 || rate.output > 0 else { return nil }

        let inputCost = Double(tokens.input) * rate.input / 1_000_000
        let outputCost = Double(tokens.output) * rate.output / 1_000_000
        let cacheReadCost = Double(tokens.cacheRead) * (rate.cache ?? 0) / 1_000_000
        return CostEstimate(
            costRMB: inputCost + outputCost + cacheReadCost,
            usedFallback: queriedModelRate && modelRate == nil
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

    /// F2a `PricingTable.rate(for:)` accepts `ProviderIdentifier`
    /// (`.kimi / .kimiCN / .claude / .zaiCodingPlan / .nanoGpt / .codex`).
    /// `MonthAggregate.provider` is a `String` (read from SQLite via `TokenUsageStore`).
    ///
    /// The "zai" string is F2b `Provider.zai.rawValue`; it must bridge to F2a's
    /// `ProviderIdentifier.zaiCodingPlan` — they are distinct enums.
    private func providerStringToIdentifier(_ s: String) -> ProviderIdentifier? {
        switch s.lowercased() {
        case "kimi":    return .kimi
        case "kimicn":  return .kimiCN
        case "claude":  return .claude
        case "codex":   return .codex
        case "zai":     return .zaiCodingPlan
        case "nanogpt": return .nanoGpt
        default:        return nil
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
