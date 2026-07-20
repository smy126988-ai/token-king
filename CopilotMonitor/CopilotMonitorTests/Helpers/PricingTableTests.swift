import XCTest
@testable import OpenCode_Bar

final class PricingTableTests: XCTestCase {

    // MARK: - Coverage

    func testAll6CoveredProvidersReturnNonNilRate() {
        for provider in PricingTable.providersWithPublicPricing {
            XCTAssertNotNil(
                PricingTable.rate(for: provider),
                "Provider \(provider) is in providersWithPublicPricing but rate(for:) returned nil"
            )
        }
    }

    func testProvidersWithPublicPricingContainsExactly9() {
        // t1.2 (audit/p0-batch-1-t1.2): added 3 new raw-API-rate providers
        // (.minimaxCN, .openCodeGo, .xiaomiTokenPlanCN) on top of the 6
        // pre-existing covered providers. copilot remains intentionally nil
        // (Premium-request model, no per-token pricing).
        XCTAssertEqual(
            PricingTable.providersWithPublicPricing.count, 9,
            "Expected 9 covered providers post-t1.2 (kimi/kimiCN/claude/zai/nanoGpt/codex + minimaxCN/openCodeGo/xiaomiTokenPlanCN)"
        )
        let expected: Set<ProviderIdentifier> = [
            .kimi, .kimiCN, .claude, .zaiCodingPlan, .nanoGpt, .codex,
            .minimaxCN, .openCodeGo, .xiaomiTokenPlanCN
        ]
        XCTAssertEqual(
            Set(PricingTable.providersWithPublicPricing), expected
        )
    }

    // MARK: - Nil cases

    func testCopilotReturnsNil() {
        // Copilot Premium is request-multiplier, not per-token rate.
        XCTAssertNil(PricingTable.rate(for: .copilot))
    }

    func testAntigravityReturnsNil() {
        // Google does not publish per-token pricing for Antigravity.
        XCTAssertNil(PricingTable.rate(for: .antigravity))
    }

    func testOtherUncoveredProvidersReturnNil() {
        // 4 Chinese providers without confirmed public pricing as of 2026-07-07.
        for provider in [ProviderIdentifier.mimo,
                         .volcanoArk, .hunyuan, .zhipuGLM] {
            XCTAssertNil(
                PricingTable.rate(for: provider),
                "Expected nil for \(provider)"
            )
        }
    }

    // MARK: - Sanity

    func testRateValuesArePositive() {
        for provider in PricingTable.providersWithPublicPricing {
            guard let rate = PricingTable.rate(for: provider) else {
                XCTFail("\(provider) returned nil"); continue
            }
            XCTAssertGreaterThan(rate.input, 0, "\(provider).input must be > 0")
            XCTAssertGreaterThan(rate.output, 0, "\(provider).output must be > 0")
            if let cache = rate.cache {
                XCTAssertGreaterThan(cache, 0, "\(provider).cache must be > 0")
            }
        }
    }

    func testOutputRateGreaterOrEqualToInputRate() {
        // Industry-standard: output tokens cost >= input tokens cost.
        // Catches data-entry typos (e.g. swapping input/output columns).
        for provider in PricingTable.providersWithPublicPricing {
            guard let rate = PricingTable.rate(for: provider) else {
                XCTFail("\(provider) returned nil"); continue
            }
            XCTAssertGreaterThanOrEqual(
                rate.output, rate.input,
                "\(provider): output (\(rate.output)) must be >= input (\(rate.input))"
            )
        }
    }

    func testKimiAndKimiCNHaveSameRate() {
        // Both .kimi and .kimiCN use the same Moonshot platform & same
        // representative model. Their rates must be identical.
        XCTAssertEqual(
            PricingTable.rate(for: .kimi),
            PricingTable.rate(for: .kimiCN),
            ".kimi and .kimiCN must return identical rates (same Moonshot platform)"
        )
    }

    // MARK: - Per-model rates (GPT-5.x family)

    /// Test-driven surface for model-level public list prices. The current
    /// `rate(for: ProviderIdentifier)` fall-back to a single representative
    /// model (e.g. gpt-4o for .codex) — under-bills real GPT-5.x spend.
    /// Each model below was sourced from
    /// https://developers.openai.com/api/docs/pricing (2026-07-12).
    func testGpt56SolModelRate() {
        // Source: https://developers.openai.com/api/docs/models/gpt-5.6
        // USD per 1M tokens: input $5.00 / cached input $0.50 / output $30.00.
        // PayAsYouGoRate stores the unified RMB figure (USD * FX 6.79) so
        // downstream MonthCostCalculator treats every provider's rate in a
        // single currency without ad-hoc per-call conversions.
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.6-sol") else {
            return XCTFail("gpt-5.6-sol should resolve to an explicit rate")
        }
        XCTAssertEqual(rate.input, 5.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 30.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.50 * fx, accuracy: 0.01,
                       "cache field stores cache-read rate on PayAsYouGoRate")
    }

    func testGpt55ModelRate() {
        // Source: https://developers.openai.com/api/docs/pricing (Standard tier, <272K).
        // USD per 1M tokens: input $5.00 / cached input $0.50 / output $30.00.
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.5") else {
            return XCTFail("gpt-5.5 should resolve")
        }
        XCTAssertEqual(rate.input, 5.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 30.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.50 * fx, accuracy: 0.01)
    }

    func testGpt55ProModelRate() {
        // Standard tier, 6× input / output of plain gpt-5.5; no cache page line.
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.5-pro") else {
            return XCTFail("gpt-5.5-pro should resolve")
        }
        XCTAssertEqual(rate.input, 30.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 180.00 * fx, accuracy: 0.01)
        XCTAssertNil(rate.cache, "gpt-5.5-pro has no public cache-read rate")
    }

    func testGpt56TerraModelRate() {
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.6-terra") else {
            return XCTFail("gpt-5.6-terra should resolve")
        }
        XCTAssertEqual(rate.input, 2.50 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 15.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.25 * fx, accuracy: 0.01)
    }

    func testGpt56LunaModelRate() {
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.6-luna") else {
            return XCTFail("gpt-5.6-luna should resolve")
        }
        XCTAssertEqual(rate.input, 1.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 6.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.10 * fx, accuracy: 0.01)
    }

    func testGpt54MiniModelRate() {
        // Standard tier: USD $0.75 / $0.075 / $4.50.
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.4-mini") else {
            return XCTFail("gpt-5.4-mini should resolve")
        }
        XCTAssertEqual(rate.input, 0.75 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 4.50 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.075 * fx, accuracy: 0.01)
    }

    func testGpt54ProModelRate() {
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.4-pro") else {
            return XCTFail("gpt-5.4-pro should resolve")
        }
        XCTAssertEqual(rate.input, 30.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 180.00 * fx, accuracy: 0.01)
        XCTAssertNil(rate.cache, "gpt-5.4-pro has no public cache-read rate")
    }

    /// Aliases for the same model must resolve identically (OpenAI alias
    /// `gpt-5.6` routes to `gpt-5.6-sol` per
    /// https://openai.com/index/gpt-5-6/).
    func testGpt56AliasResolvesToSolRate() {
        XCTAssertEqual(
            PricingTable.modelRate(for: "gpt-5.6"),
            PricingTable.modelRate(for: "gpt-5.6-sol"),
            "gpt-5.6 plain alias must map to gpt-5.6-sol"
        )
    }

    /// Previously-broken: pre-5.6 Codex CLI sometimes emitted `gpt-5.3-codex-spark`
    /// as an alias for `gpt-5.6-sol` (preview). Verify it's mapped.
    func testGpt53CodexSparkAliasResolvesToSolRate() {
        guard let sol = PricingTable.modelRate(for: "gpt-5.6-sol"),
              let spark = PricingTable.modelRate(for: "gpt-5.3-codex-spark")
        else {
            return XCTFail("both aliases should resolve")
        }
        XCTAssertEqual(spark.input, sol.input, accuracy: 0.001)
        XCTAssertEqual(spark.output, sol.output, accuracy: 0.001)
    }

    func testUnknownModelReturnsNil() {
        XCTAssertNil(PricingTable.modelRate(for: "gpt-future-99-ultra"))
        XCTAssertNil(PricingTable.modelRate(for: ""))
        XCTAssertNil(PricingTable.modelRate(for: "some/random/path"))
    }

    func testModelRateOutputNotLowerThanInput() {
        // Industry-standard invariant: output ≥ input. Catches data-entry
        // typos (e.g. swapping input/output columns). Exceptions: Pro
        // variants listed below are excluded since their input rate
        // ($30) still satisfies the invariant ($180 ≥ $30), keep them in.
        let covered: [String] = [
            "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna",
            "gpt-5.5", "gpt-5.5-pro",
            "gpt-5.4", "gpt-5.4-pro", "gpt-5.4-mini", "gpt-5.4-nano"
        ]
        for m in covered {
            guard let rate = PricingTable.modelRate(for: m) else {
                XCTFail("\(m) returned nil"); continue
            }
            XCTAssertGreaterThanOrEqual(
                rate.output, rate.input,
                "\(m): output (\(rate.output)) must be >= input (\(rate.input))"
            )
            if let cache = rate.cache {
                XCTAssertGreaterThan(cache, 0, "\(m): cache must be > 0")
            }
        }
    }

    // MARK: - Anthropic Claude model-level rates (round 12, 2026-07-13)
    //
    // Source: https://www.anthropic.com/pricing (captured 2026-07-13).
    // FX: 1 USD = 6.79 CNY (consistent with all other modelRate entries).

    /// Opus 4.8 (current head revision of the Opus 4.x line).
    /// USD list: $5.00 / $25.00; cache write $6.25, cache read $0.50.
    /// Pre-12 behaviour: under-billed via Sonnet representative fallback
    /// (rate(for: .claude)). 7月 real-data drift on Opus input was ~5%
    /// under; this entry closes the gap.
    func testClaudeOpus48ModelRate() {
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "claude-opus-4.8") else {
            return XCTFail("claude-opus-4.8 should resolve to an explicit rate")
        }
        XCTAssertEqual(rate.input, 5.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 25.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.50 * fx, accuracy: 0.01,
                       "cache field stores cache-read rate (matches all other modelRate entries)")
    }

    /// Haiku 4.5 (current head revision of the Haiku 4.x line).
    /// USD list: $1.00 / $5.00; cache write $1.25, cache read $0.10.
    /// Pre-12 behaviour: also under-billed via Sonnet representative.
    func testClaudeHaiku45ModelRate() {
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "claude-haiku-4.5") else {
            return XCTFail("claude-haiku-4.5 should resolve")
        }
        XCTAssertEqual(rate.input, 1.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 5.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.10 * fx, accuracy: 0.01)
    }

    /// Alias `claude-opus-4` (no .8) must map to the head revision (Opus 4.8).
    /// Forward-compat: future Claude SDKs may emit the family alias
    /// without a minor number. Old-session data with sub-version strings
    /// (e.g. `claude-opus-4-7`) is intentionally NOT aliased and falls
    /// back to the Sonnet representative.
    func testClaudeOpus4AliasResolvesToOpus48Rate() {
        guard let head = PricingTable.modelRate(for: "claude-opus-4.8"),
              let alias = PricingTable.modelRate(for: "claude-opus-4")
        else {
            return XCTFail("both should resolve")
        }
        XCTAssertEqual(alias.input, head.input, accuracy: 0.001)
        XCTAssertEqual(alias.output, head.output, accuracy: 0.001)
        XCTAssertEqual(alias.cache ?? 0, head.cache ?? 0, accuracy: 0.001)
    }

    /// Alias `claude-haiku-4` (no .5) must map to the head revision (Haiku 4.5).
    func testClaudeHaiku4AliasResolvesToHaiku45Rate() {
        guard let head = PricingTable.modelRate(for: "claude-haiku-4.5"),
              let alias = PricingTable.modelRate(for: "claude-haiku-4")
        else {
            return XCTFail("both should resolve")
        }
        XCTAssertEqual(alias.input, head.input, accuracy: 0.001)
        XCTAssertEqual(alias.output, head.output, accuracy: 0.001)
        XCTAssertEqual(alias.cache ?? 0, head.cache ?? 0, accuracy: 0.001)
    }

    /// Pre-round-12 strings (e.g. `claude-opus-4-7`) must NOT silently
    /// resolve to Opus 4.8; they should fall back to Sonnet representative
    /// via the provider-level `rate(for: .claude)`. This guards against
    /// accidentally mis-pricing deprecated-model data with current prices.
    func testClaudeLegacyModelStringFallsBackToRepresentative() {
        XCTAssertNil(PricingTable.modelRate(for: "claude-opus-4-7"),
                     "legacy model strings must not be silently aliased; they fall through to Sonnet representative")
        XCTAssertNil(PricingTable.modelRate(for: "claude-sonnet-4-5"),
                     "sonnet representative is provider-level, not model-level")
        XCTAssertNotNil(PricingTable.rate(for: .claude),
                        "Sonnet representative rate(for: .claude) must remain available for the fallback")
    }

    func testKnownModelsSetMembership() {
        // Lock down which models the audit branch claims to know about.
        // Adding a new model: add to PricingTable.modelRate(for:) AND below.
        let known: Set<String> = [
            // GPT-5.6 family.
            "gpt-5.6", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna",
            "gpt-5.3-codex-spark",
            // GPT-5.5 family.
            "gpt-5.5", "gpt-5.5-pro",
            // GPT-5.4 family.
            "gpt-5.4", "gpt-5.4-pro", "gpt-5.4-mini", "gpt-5.4-nano",
            // gpt-4o legacy canonical model.
            "gpt-4o",
            // Kimi Code subscription alias.
            "kimi-code/kimi-for-coding", "kimi-for-coding", "kimi-k2-7-code",
            // OpenCode Go (opencode-go tier) deepseek routes.
            "deepseek-v4-pro", "deepseek-v4-flash", "deepseek-v4-flash-free",
            // MiniMax direct API (user's own key).
            "MiniMax-M3", "minimax-m3",
            // t1.2 (audit/p0-batch-1-t1.2) — opencode-go additions.
            "qwen3.7-max", "mimo-v2.5-pro", "mimo-v2.5",
            // Anthropic Claude family (round 12, 2026-07-13, t1.3). Aliases
            // `claude-opus-4` / `claude-haiku-4` resolve to the current
            // 4.x head revision (Opus 4.8 / Haiku 4.5); pre-4.x strings
            // like `claude-opus-4-7` would fall through to the Sonnet
            // representative and are intentionally NOT aliased.
            "claude-opus-4.8", "claude-opus-4",
            "claude-haiku-4.5", "claude-haiku-4"
        ]
        for m in known {
            XCTAssertNotNil(PricingTable.modelRate(for: m), "\(m) should resolve")
        }
    }

    // MARK: - t1.1 — Kimi K2.7 Code native CNY, no FX

    func testKimiK27CodeNoFX() {
        guard let rate = PricingTable.modelRate(for: "kimi-k2-7-code") else {
            return XCTFail("kimi-k2-7-code should resolve")
        }
        XCTAssertEqual(rate.input, 6.50, accuracy: 1e-9)
        XCTAssertEqual(rate.output, 27.00, accuracy: 1e-9)
        XCTAssertEqual(rate.cache ?? -1, 1.30, accuracy: 1e-9)
        XCTAssertEqual(rate.currency, "CNY")
    }

    // MARK: - t1.2 — provider-aware modelRate override for mimo-v2.5-pro

    /// Same model name (`mimo-v2.5-pro`) has different list prices depending
    /// on which provider routed the call:
    /// - opencode-go: USD $1.74 / $3.48 / $0.0145 → ¥11.8146 / ¥23.6292 / ¥0.0984555
    /// - Xiaomi Token Plan CN: native CNY ¥3.00 / ¥6.00 / ¥0.025
    /// Using the wrong rate inflates the xiaomiTokenPlanCN cost ~4×.
    func testMimoV25ProOpencodeGoRate() {
        let fx = 6.79
        guard let rate = PricingTable.modelRate(
            for: "mimo-v2.5-pro", provider: .openCodeGo
        ) else { return XCTFail("mimo-v2.5-pro under opencodeGo must resolve") }
        XCTAssertEqual(rate.input, 1.74 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 3.48 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.0145 * fx, accuracy: 0.001)
    }

    func testMimoV25ProXiaomiTokenPlanCNRate() {
        // Xiaomi domestic CNY per 1M (no FX conversion).
        guard let rate = PricingTable.modelRate(
            for: "mimo-v2.5-pro", provider: .xiaomiTokenPlanCN
        ) else { return XCTFail("mimo-v2.5-pro under xiaomiTokenPlanCN must resolve") }
        XCTAssertEqual(rate.input, 3.00, accuracy: 1e-9)
        XCTAssertEqual(rate.output, 6.00, accuracy: 1e-9)
        XCTAssertEqual(rate.cache!, 0.025, accuracy: 1e-9)
    }

    /// Provider-agnostic `modelRate(for:)` defaults to opencode-go USD*fx
    /// for `mimo-v2.5-pro`. The provider-aware overload is the explicit
    /// path when the caller knows the provider.
    func testMimoV25ProProviderAgnosticDefaultsToOpencodeGoRate() {
        let fx = 6.79
        guard let agnostic = PricingTable.modelRate(for: "mimo-v2.5-pro"),
              let viaProvider = PricingTable.modelRate(
                for: "mimo-v2.5-pro", provider: .openCodeGo
              )
        else { return XCTFail("both lookups should resolve") }
        XCTAssertEqual(agnostic.input, viaProvider.input, accuracy: 1e-9)
        XCTAssertEqual(agnostic.output, viaProvider.output, accuracy: 1e-9)
        XCTAssertEqual(agnostic.cache!, viaProvider.cache!, accuracy: 1e-9)
        XCTAssertEqual(agnostic.input, 1.74 * fx, accuracy: 0.01)
    }

    // MARK: - t1.2 — provider-level representative rates

    func testMinimaxCNRate() {
        // Source: https://platform.minimaxi.com/docs/guides/pricing-paygo (2026-07-13)
        // Native CNY: input ¥2.10 / cache_read ¥0.42 / output ¥8.40.
        guard let rate = PricingTable.rate(for: .minimaxCN) else {
            return XCTFail(".minimaxCN must resolve to a representative rate")
        }
        XCTAssertEqual(rate.input, 2.10, accuracy: 1e-9)
        XCTAssertEqual(rate.output, 8.40, accuracy: 1e-9)
        XCTAssertEqual(rate.cache!, 0.42, accuracy: 1e-9)
    }

    func testOpenCodeGoRate() {
        // Pre-t1.2: returned nil. Post-t1.2: deepseek-v4-pro USD*fx.
        let fx = 6.79
        guard let rate = PricingTable.rate(for: .openCodeGo) else {
            return XCTFail(".openCodeGo must resolve post-t1.2 (was nil pre-t1.2)")
        }
        XCTAssertEqual(rate.input, 1.74 * fx, accuracy: 1e-6)
        XCTAssertEqual(rate.output, 3.48 * fx, accuracy: 1e-6)
        XCTAssertEqual(rate.cache!, 0.0145 * fx, accuracy: 1e-6)
    }

    func testXiaomiTokenPlanCNRate() {
        // Source: https://mimo.mi.com/docs/en-US/price/pay-as-you-go (2026-07-13)
        // Native CNY: input ¥3.00 / cache_read ¥0.025 / output ¥6.00.
        guard let rate = PricingTable.rate(for: .xiaomiTokenPlanCN) else {
            return XCTFail(".xiaomiTokenPlanCN must resolve")
        }
        XCTAssertEqual(rate.input, 3.00, accuracy: 1e-9)
        XCTAssertEqual(rate.output, 6.00, accuracy: 1e-9)
        XCTAssertEqual(rate.cache!, 0.025, accuracy: 1e-9)
    }

    /// Round 10 module 2: every rate in this table must carry a
    /// `currency: String` that signals the unit of `input / output /
    /// cache`. The round-9 contract is "CNY per 1M tokens" (USD public
    /// prices are converted via FX 6.79 inside `modelRate(for:)`). The
    /// default is "CNY" and the regression lock below is a guardrail
    /// against an explicit non-CNY call slipping in (round-10 follow-up
    /// if we ever need raw USD is to add a new string + `convertTo(_:)`).
    func testAllRatesHaveCNYCurrency() {
        for provider in PricingTable.providersWithPublicPricing {
            guard let rate = PricingTable.rate(for: provider) else { continue }
            XCTAssertEqual(rate.currency, "CNY",
                           "\(provider) rate.currency must be CNY; got \(rate.currency)")
        }
        let knownModels: [String] = [
            "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna",
            "gpt-5.5", "gpt-5.5-pro",
            "gpt-5.4", "gpt-5.4-pro", "gpt-5.4-mini", "gpt-5.4-nano",
            "gpt-4o",
            // Round 12 (2026-07-13): Anthropic Claude model-level rates.
            "claude-opus-4.8", "claude-haiku-4.5"
        ]
        for m in knownModels {
            guard let rate = PricingTable.modelRate(for: m) else {
                XCTFail("\(m) should resolve to assert currency"); continue
            }
            XCTAssertEqual(rate.currency, "CNY",
                           "\(m) rate.currency must be CNY; got \(rate.currency)")
        }
    }
}
