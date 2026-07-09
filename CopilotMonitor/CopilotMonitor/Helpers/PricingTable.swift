import Foundation

/// Represents the "hypothetical pay-as-you-go rate" for a single provider,
/// based on its representative model's public pricing page.
///
/// Per F2a design (2026-07-07): stored in RMB ¥ per million tokens, NOT USD.
/// This is an accepted deviation from project "USD is single source of truth"
/// principle - see spec section 2 in
/// `docs/superpowers/specs/2026-07-07-f2a-pay-as-you-go-pricing-table-design.md`.
///
/// `cache == nil` when the provider either has no public cache pricing or
/// does not differentiate cache as a separate line item.
struct PayAsYouGoRate: Equatable {
    let input: Double
    let output: Double
    let cache: Double?
}

/// Compile-time-constant table of "hypothetical pay-as-you-go rates" for
/// quota-based providers, used by the F2a cross-provider cost comparison UI.
///
/// Source: hardcoded from public pricing pages (see
/// `docs/superpowers/research/f2a-pricing-research-2026-07-07.md`).
/// Maintenance: when a provider changes its public pricing, manually update
/// the case in `rate(for:)` below and re-record the URL + query date in
/// the research notes file.
enum PricingTable {

    /// Returns the representative model's pay-as-you-go rate for the given
    /// provider. Returns `nil` for providers without public token-level pricing
    /// (e.g. Copilot's Premium-request model, providers with no public
    /// per-token pricing page).
    static func rate(for provider: ProviderIdentifier) -> PayAsYouGoRate? {
        switch provider {
        case .kimi, .kimiCN:
            // Source: https://platform.moonshot.cn/docs/pricing/chat-k26 (2026-07-07)
            // Representative model: kimi-k2.6
            // FX: N/A (native RMB)
            // .kimi and .kimiCN share the same Moonshot platform; both use this rate.
            return PayAsYouGoRate(
                input: 6.50,
                output: 27.00,
                cache: 1.10
            )

        case .claude:
            // Source: https://www.anthropic.com/pricing (2026-07-07)
            // Representative model: claude-sonnet-4-5
            // USD: $3.00 / $15.00; cache write $3.75, cache read $0.30.
            // FX: 1 USD = 6.79 CNY (2026-07-07).
            // Cache field stores the WRITE rate (¥25.46) instead of the READ rate
            // (¥2.04). Write is the "cache is more expensive than input" side;
            // read is cheaper than input. Storing write makes `cache > input`
            // for this provider, which is the conservative upper-bound
            // assumption when comparing cache hits vs misses.
            return PayAsYouGoRate(
                input: 20.37,
                output: 101.85,
                cache: 25.46
            )

        case .zaiCodingPlan:
            // Source: https://docs.z.ai/guides/overview/pricing (2026-07-07)
            // Representative model: glm-4.6
            // USD: $0.60 / $2.20; cache read $0.11; cache storage limited-time free.
            // FX: 1 USD = 6.79 CNY (2026-07-07).
            return PayAsYouGoRate(
                input: 4.07,
                output: 14.94,
                cache: 0.75
            )

        case .nanoGpt:
            // Source: https://nano-gpt.com/pricing (2026-07-07, best-effort)
            // Representative model: gpt-4o (per NanoGPT's pass-through claim:
            // "API pricing - no markup: Text model API usage is billed at list prices")
            // USD: $2.50 / $10.00 (= OpenAI list for gpt-4o).
            // FX: 1 USD = 6.79 CNY (2026-07-07).
            // NOTE: best-effort; NanoGPT's JS-rendered table couldn't be machine-read.
            // NanoGPT does not publish its own cache line; cache == nil.
            return PayAsYouGoRate(
                input: 16.98,
                output: 67.90,
                cache: nil
            )

        case .codex:
            // Source: https://platform.openai.com/docs/pricing (2026-07-07)
            // Representative model: gpt-4o
            // USD: $2.50 / $10.00; cached input $1.25 (50% discount, automatic).
            // FX: 1 USD = 6.79 CNY (2026-07-07).
            return PayAsYouGoRate(
                input: 16.98,
                output: 67.90,
                cache: 8.49
            )

        case .copilot, .antigravity, .mimo, .volcanoArk, .hunyuan,
             .zhipuGLM, .grok, .commandCode, .cursor, .kiro,
             .synthetic, .chutes, .geminiCLI, .openRouter, .openCode,
             .openCodeZen, .openCodeGo, .minimaxCodingPlan,
             .minimaxCodingPlanCN, .minimax, .minimaxCN,
             .xiaomi, .xiaomiTokenPlanCN,
             .tavilySearch, .braveSearch:
            // No public per-token pricing available, or out of F2a scope.
            return nil
        }
    }

    /// All providers that have a public per-token rate in `rate(for:)`.
    /// Order matches the spec section 3.3 table.
    static var providersWithPublicPricing: [ProviderIdentifier] {
        [.kimi, .kimiCN, .claude, .zaiCodingPlan, .nanoGpt, .codex]
    }
}