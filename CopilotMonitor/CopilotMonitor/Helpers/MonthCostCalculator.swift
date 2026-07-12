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

    /// Compute the cost-equivalent for a single month_aggregate.
    ///
    /// Rate precedence (round 9, 2026-07-12):
    ///   1. **If the model name is an OpenAI GPT-* family string AND the
    ///      provider is `.codex`**, use `pricingTable.modelRate(for: model)`
    ///      — exact model pricing sourced from OpenAI's public list page
    ///      (covers gpt-5.6-sol/terra/luna, gpt-5.5/pro, gpt-5.4/pro/mini/nano,
    ///      the `gpt-5.6` plain alias, and the Codex-CLI preview alias
    ///      `gpt-5.3-codex-spark`).
    ///   2. **Otherwise** (non-OpenAI providers, or non-OpenAI model names
    ///      under any provider), use `pricingTable.rate(for: providerId)` —
    ///      the provider-level representative rate (e.g. .kimi → kimi-k2.6,
    ///      .claude → sonnet-4-5, .codex → gpt-4o).
    ///   3. `nil` when the provider is itself unknown to F2a (e.g. .copilot
    ///      Premium request model), or when the lookup returns a rate
    ///      whose input + output are both 0 (degenerate rate).
    ///
    /// The previous `representativeModel: [.codex: "gpt-4o"]` strict-equal
    /// gate was removed in round 9: it incorrectly filtered every GPT-5.x
    /// row to nil, hiding the model-level rate that PricingTable already
    /// resolved. Restricting model-level overrides to OpenAI-on-Codex
    /// prevents the symmetric bug — applying OpenAI list prices to e.g.
    /// a Kimi or Claude model name.
    func calculate(provider: String, model: String, tokens: TokenBreakdown) -> Double? {
        guard let providerId = providerStringToIdentifier(provider) else { return nil }

        // Model-level rate applies ONLY to OpenAI model names under .codex.
        // This is the only family PricingTable's `modelRate(for:)` switch
        // covers today; expanding it is round-10+ work.
        //
        // The ?: vs ?? precedence: Swift parses `cond ? A : B ?? C` as
        // `cond ? A : (B ?? C)`, NOT `(cond ? A : B) ?? C`. Wrap the
        // ternary in parens so modelRate(nil-fallback) chains with the
        // provider-rate ?? as intended.
        let looksLikeOpenAIModel = model.hasPrefix("gpt-")
                                  || model.hasPrefix("o1")
                                  || model.hasPrefix("o3")
                                  || model.hasPrefix("o4-")
        let modelRate: PayAsYouGoRate? = (looksLikeOpenAIModel && providerId == .codex)
            ? pricingTable.modelRate(for: model)
            : nil
        let rate = modelRate ?? pricingTable.rate(for: providerId)

        guard let rate = rate, rate.input > 0 || rate.output > 0 else { return nil }

        let inputCost = Double(tokens.input) * rate.input / 1_000_000
        let outputCost = Double(tokens.output) * rate.output / 1_000_000
        // rate.cache is the cache-READ rate; cache-write is intentionally
        // excluded (F2a consensus: cache-write cost is simplified away).
        let cacheReadCost = Double(tokens.cacheRead) * (rate.cache ?? 0) / 1_000_000
        return inputCost + outputCost + cacheReadCost
    }

    /// Aggregate `month_aggregates` into a per-provider `MonthlyTotal`.
    /// Aggregates with unknown pricing are still preserved in `modelBreakdown`
    /// (with `costRMB == nil`) and `hasUnknownPricing` is set to `true`
    /// on the provider total when at least one aggregate is unknown.
    func calculateMonthlyTotals(_ aggregates: [MonthAggregate]) -> [MonthlyTotal] {
        var totals: [String: MonthlyTotal] = [:]
        for agg in aggregates {
            let cost = calculate(provider: agg.provider, model: agg.model, tokens: agg.tokens)
            let existing = totals[agg.provider]
            totals[agg.provider] = MonthlyTotal(
                provider: agg.provider,
                modelBreakdown: (existing?.modelBreakdown ?? []) + [
                    ModelCost(model: agg.model, tokens: agg.tokens, costRMB: cost)
                ],
                totalTokens: (existing?.totalTokens ?? TokenBreakdown())
                    .adding(agg.tokens),
                totalCostRMB: (existing?.totalCostRMB ?? 0) + (cost ?? 0),
                hasUnknownPricing: (existing?.hasUnknownPricing ?? false) || (cost == nil)
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
