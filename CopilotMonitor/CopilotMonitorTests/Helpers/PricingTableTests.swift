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

    /// t1.2 (predecessor of feat(pricing): route 3 raw-API providers):
    /// the `.openCodeGo` representative rate used to return nil because
    /// the case was bundled into the multi-case "no public pricing"
    /// list. MonthCostCalculator therefore computed nil cost for any
    /// SQLite `month_aggregates` row whose `modelRate` lookup missed.
    /// Verifying `.openCodeGo` itself resolves to deepseek-v4-pro USD*fx
    /// locks the regression.
    func testOpenCodeGoRateResolves() {
        let fx = 6.79
        guard let rate = PricingTable.rate(for: .openCodeGo) else {
            return XCTFail(".openCodeGo must resolve post-Commit A; was nil pre-t1.2")
        }
        XCTAssertEqual(rate.input,  1.74 * fx, accuracy: 1e-6)
        XCTAssertEqual(rate.output, 3.48 * fx, accuracy: 1e-6)
        XCTAssertEqual(rate.cache!, 0.0145 * fx, accuracy: 1e-6)
    }

    func testProvidersWithPublicPricingContainsExactly6() {
        XCTAssertEqual(
            PricingTable.providersWithPublicPricing.count, 6,
            "Expected 6 covered providers (kimi/kimiCN/claude/zai/nanoGpt/codex); copilot intentionally nil due to Premium-request model"
        )
        let expected: Set<ProviderIdentifier> = [
            .kimi, .kimiCN, .claude, .zaiCodingPlan, .nanoGpt, .codex,
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
        XCTAssertEqual(rate.input,  5.00 * fx, accuracy: 0.01)
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
        XCTAssertEqual(rate.input,  5.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 30.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.50 * fx, accuracy: 0.01)
    }

    func testGpt55ProModelRate() {
        // Standard tier, 6× input / output of plain gpt-5.5; no cache page line.
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.5-pro") else {
            return XCTFail("gpt-5.5-pro should resolve")
        }
        XCTAssertEqual(rate.input,  30.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 180.00 * fx, accuracy: 0.01)
        XCTAssertNil(rate.cache, "gpt-5.5-pro has no public cache-read rate")
    }

    func testGpt56TerraModelRate() {
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.6-terra") else {
            return XCTFail("gpt-5.6-terra should resolve")
        }
        XCTAssertEqual(rate.input,  2.50 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 15.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.25 * fx, accuracy: 0.01)
    }

    func testGpt56LunaModelRate() {
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.6-luna") else {
            return XCTFail("gpt-5.6-luna should resolve")
        }
        XCTAssertEqual(rate.input,  1.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output,  6.00 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.10 * fx, accuracy: 0.01)
    }

    func testGpt54MiniModelRate() {
        // Standard tier: USD $0.75 / $0.075 / $4.50.
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.4-mini") else {
            return XCTFail("gpt-5.4-mini should resolve")
        }
        XCTAssertEqual(rate.input,  0.75 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.output, 4.50 * fx, accuracy: 0.01)
        XCTAssertEqual(rate.cache!, 0.075 * fx, accuracy: 0.01)
    }

    func testGpt54ProModelRate() {
        let fx = 6.79
        guard let rate = PricingTable.modelRate(for: "gpt-5.4-pro") else {
            return XCTFail("gpt-5.4-pro should resolve")
        }
        XCTAssertEqual(rate.input,  30.00 * fx, accuracy: 0.01)
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
            "gpt-5.4", "gpt-5.4-pro", "gpt-5.4-mini", "gpt-5.4-nano",
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
        ]
        for m in known {
            XCTAssertNotNil(PricingTable.modelRate(for: m), "\(m) should resolve")
        }
    }

    func testKimiK27CodeNoFX() {
        guard let rate = PricingTable.modelRate(for: "kimi-k2-7-code") else {
            return XCTFail("kimi-k2-7-code should resolve")
        }
        XCTAssertEqual(rate.input, 6.50, accuracy: 1e-9)
        XCTAssertEqual(rate.output, 27.00, accuracy: 1e-9)
        XCTAssertEqual(rate.cache ?? -1, 1.30, accuracy: 1e-9)
        XCTAssertEqual(rate.currency, "CNY")
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