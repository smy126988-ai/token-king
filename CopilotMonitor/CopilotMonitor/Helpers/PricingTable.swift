import Foundation

/// Represents the "hypothetical pay-as-you-go rate" for a single provider
/// or model, based on the public pricing page.
///
/// Per F2a design (2026-07-07) and round-9 alignment: `input / output /
/// cache` fields are stored in **RMB per million tokens** (CNY × 1e-6
/// per token). OpenAI public list prices (USD) are converted to RMB
/// internally by `modelRate(for:)` via FX 6.79, so callers never have
/// to do per-call currency math. The `currency` field is the explicit
/// surface for that contract: a value of `"CNY"` is the only valid
/// string in this table as of round 10 — see `testAllRatesHaveCNYCurrency`
/// for the regression lock. Future revisions that need a different
/// unit (e.g. raw USD for a new panel) should add a new string and a
/// `convertTo(_:)` method rather than mutating existing call sites.
///
/// `cache == nil` when the provider either has no public cache pricing or
/// does not differentiate cache as a separate line item.
struct PayAsYouGoRate: Equatable {
    let input: Double
    let output: Double
    let cache: Double?
    let currency: String

    init(input: Double, output: Double, cache: Double?, currency: String = "CNY") {
        self.input = input
        self.output = output
        self.cache = cache
        self.currency = currency
    }
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
             .minimaxCodingPlanCN, .tavilySearch, .braveSearch:
            // No public per-token pricing available, or out of F2a scope.
            return nil
        }
    }

    /// All providers that have a public per-token rate in `rate(for:)`.
    /// Order matches the spec section 3.3 table.
    static var providersWithPublicPricing: [ProviderIdentifier] {
        [.kimi, .kimiCN, .claude, .zaiCodingPlan, .nanoGpt, .codex]
    }

    /// Per-model pay-as-you-go rate override. Returns the model's own
    /// list price when known; falls back to `nil` to let the caller use
    /// `rate(for: ProviderIdentifier)` as a fallback.
    ///
    /// The provider-level rate uses a single "representative" model per
    /// provider (e.g. `.codex` → gpt-4o). Real GPT-5.x spend diverges by
    /// 2-6× because the family spans $0.20-$180 per 1M tokens. This
    /// switch gives every model its own public list price so per-day /
    /// per-month cost reports can show "gpt-5.6-sol $1,502 / gpt-5.5
    /// $1,835" instead of "codex $1,800 (using gpt-4o rates)".
    ///
    /// All USD figures are per 1M tokens, sourced from OpenAI's
    /// **Standard** tier (the default for synchronous API calls) at
    /// `https://developers.openai.com/api/docs/pricing` on **2026-07-12**.
    /// Batch/Flex are 50% off and live in their own tier; users on those
    /// tiers should adjust externally before computing spend against
    /// these rates.
    ///
    /// `cache` stores the *cache-read* rate (cache-write is gated by
    /// OpenAI per request and not stored in F2b's `token_events`).
    ///
    /// LAST_VERIFIED 2026-07-12 — re-verify quarterly; OpenAI does not
    /// promise version-stamped pricing pages.
    ///
    /// Aliases registered:
    /// - `gpt-5.6` → routes to `gpt-5.6-sol` per OpenAI's official guidance
    /// - `gpt-5.3-codex-spark` → sold as a preview alias for `gpt-5.6-sol`
    static func modelRate(for model: String) -> PayAsYouGoRate? {
        // The rest of the F2a PricingTable (rate(for: ProviderIdentifier)) uses
        // RMB per 1M tokens. We mirror that unit here: USD public prices
        // (sourced from OpenAI's pricing page) are multiplied by the FX rate
        // the table already uses elsewhere (1 USD = 6.79 CNY).
        //
        // Rationale: keeping the struct unit-less and pinning it to a
        // single currency across all providers avoids the recurring bug
        // of mixing USD * RMB in the calculator (cost math for Claude on
        // RMB vs OpenAI on USD would silently diverge by ~7×).
        let fx: Double = 6.79

        switch model {
        // OpenCode Go (opencode-go tier) routes the user's deepseek-v4-pro
        // and deepseek-v4-flash calls through OpenCode's own product tier,
        // not DeepSeek's direct API. OpenCode Go prices are higher than
        // upstream DeepSeek by ~4× on V4-Pro (verified 2026-07-13 from
        // https://opencode.ai/docs/go/). opencode-go uses automatic prefix
        // caching (not explicit / per-message). Cache-read factor is
        // V4-Pro 1/120 of Go input, V4-Flash 1/50 of Go input.
        case "deepseek-v4-pro":
            return PayAsYouGoRate(
                input:  1.74 * fx,
                output: 3.48 * fx,
                cache:   0.0145 * fx
            )
        case "deepseek-v4-flash", "deepseek-v4-flash-free":
            // opencode-go names the model "deepseek-v4-flash"; the
            // "deepseek-v4-flash-free" alias from older opencode-go
            // builds resolves to the same model+rate. (Direct DeepSeek
            // API's "deepseek-v4-flash-free" is a separate free tier
            // that does NOT apply through opencode-go.)
            return PayAsYouGoRate(
                input:  0.14 * fx,
                output: 0.28 * fx,
                cache:  0.0028 * fx
            )

        // MiniMax-M3 direct API via the user's own key. China-domestic
        // list price (CNY per 1M); standard tier, ≤512K context. Above
        // 512K input the request is billed at the long-context tier
        // (2× the standard rate; ¥8.40 / ¥1.68 / ¥33.60). International
        // `minimax.io` publishes the same model at $0.30/$0.06/$1.20
        // after a permanent 50% off promo — that's a different
        // product. Capture the China-domestic rate because the user
        // pays in CNY via their direct key.
        //   input ¥4.20 / cache_read ¥0.84 / output ¥16.80
        // Source: https://platform.minimaxi.com/docs/guides/pricing-paygo
        // (captured 2026-07-13).
        case "MiniMax-M3", "minimax-m3":
            return PayAsYouGoRate(
                input:   4.20,
                output: 16.80,
                cache:   0.84
            )

        // GPT-5.6 family (released GA 2026-07-09). Headline routes:
        case "gpt-5.6", "gpt-5.6-sol", "gpt-5.3-codex-spark":
            // Standard short-context; >272K ctx is 2x input / 1.5x output
            // (rarely hit in practice; F2b does not currently distinguish
            // context-size tiers). USD list price $5.00 / $0.50 / $30.00.
            return PayAsYouGoRate(
                input:  5.00 * fx,
                output: 30.00 * fx,
                cache:   0.50 * fx
            )

        // gpt-4o: legacy canonical model. Lives both in
        // `rate(for: .codex)` (representative) AND here so the model-level
        // lookup returns non-nil for it. Without this entry, a Codex row
        // tagged `gpt-4o` would be mis-marked as `usedFallback` because the
        // modelRate query returns nil. Public list $2.50 / $10.00 / $1.25.
        case "gpt-4o":
            return PayAsYouGoRate(
                input:   2.50 * fx,
                output: 10.00 * fx,
                cache:   1.25 * fx
            )

        // Kimi Code subscription alias. The model name reported by
        // `kimi-code` CLI sessions is `kimi-code/kimi-for-coding`,
        // which auto-resolves to `kimi-k2-7-code` since 2026-06-12.
        // Standard-tier list (CNY per 1M):
        //   input  ¥6.50  /  cache read  ¥1.30  /  output  ¥27.00
        // Source: https://platform.kimi.com/docs/pricing/chat-k27-code
        // (captured 2026-07-13). Distinct from plain kimi-k2.6, which
        // is the F2a `rate(for: .kimi)` representative; the k2.6 cache
        // rate is ¥1.10/M. Mixing them was a known source of ¥94 (15%)
        // under-cost on kimiCode 7月 totals.
        case "kimi-code/kimi-for-coding", "kimi-for-coding", "kimi-k2-7-code":
            return PayAsYouGoRate(
                input:   6.50 * fx,
                output: 27.00 * fx,
                cache:   1.30 * fx
            )

        case "gpt-5.6-terra":
            // USD list: $2.50 / $0.25 / $15.00.
            return PayAsYouGoRate(
                input:  2.50 * fx,
                output: 15.00 * fx,
                cache:   0.25 * fx
            )

        case "gpt-5.6-luna":
            // USD list: $1.00 / $0.10 / $6.00.
            return PayAsYouGoRate(
                input:  1.00 * fx,
                output:  6.00 * fx,
                cache:   0.10 * fx
            )

        // GPT-5.5 family (Standard tier, synchronous API). >272K ctx
        // doubles input, 1.5× output; F2b does not currently distinguish
        // context-size tiers, so the Standard <272K rate is the approximation.
        case "gpt-5.5":
            // USD list: $5.00 / $0.50 / $30.00.
            return PayAsYouGoRate(
                input:  5.00 * fx,
                output: 30.00 * fx,
                cache:   0.50 * fx
            )
        case "gpt-5.5-pro":
            // Pro variant is 6× input / output of plain 5.5; no public
            // cache-read line on the Standard page.
            // USD list: $30.00 / no-cache / $180.00.
            return PayAsYouGoRate(
                input:  30.00 * fx,
                output: 180.00 * fx,
                cache:  nil
            )

        // GPT-5.4 family. Standard tier.
        case "gpt-5.4":
            // USD list: $2.50 / $0.25 / $15.00.
            return PayAsYouGoRate(
                input:  2.50 * fx,
                output: 15.00 * fx,
                cache:   0.25 * fx
            )
        case "gpt-5.4-pro":
            // USD list: $30.00 / no-cache / $180.00.
            return PayAsYouGoRate(
                input:  30.00 * fx,
                output: 180.00 * fx,
                cache:  nil
            )
        case "gpt-5.4-mini":
            // USD list: $0.75 / $0.075 / $4.50.
            return PayAsYouGoRate(
                input:  0.75 * fx,
                output:  4.50 * fx,
                cache:   0.075 * fx
            )
        case "gpt-5.4-nano":
            // USD list: $0.20 / $0.02 / $1.25.
            return PayAsYouGoRate(
                input:  0.20 * fx,
                output:  1.25 * fx,
                cache:   0.02 * fx
            )

        // Unknown model — caller falls back to provider-level rate.
        default:
            return nil
        }
    }
}