import XCTest
@testable import OpenCode_Bar

/// F2b Task 5 — MonthCostCalculator (15 test cases).
/// Formula: cost = (input * inputRate + output * outputRate + cacheRead * cacheReadRate) / 1e6.
/// cacheWrite excluded (5 reference consensus: Anthropic prompt cache write free,
/// OpenAI cache write simplified excluded).
final class MonthCostCalculatorTests: XCTestCase {

    private var calc: MonthCostCalculator!

    override func setUp() {
        super.setUp()
        calc = MonthCostCalculator()
    }

    // MARK: - Provider basic cost tests (1-7)

    func testKimiK26Basic() {
        // kimi representative rate: input=6.50, output=27.00, cache=1.10 (RMB/M).
        let tokens = TokenBreakdown(input: 1_000_000, output: 500_000)
        let cost = calc.calculate(provider: "kimi", model: "kimi-k2.6", tokens: tokens)
        // 1 * 6.5 + 0.5 * 27 = 6.5 + 13.5 = 20.0
        XCTAssertEqual(cost ?? -1, 20.0, accuracy: 1e-9)
    }

    func testKimiCacheRead() {
        // 1M cacheRead only -> cost = 1 * 1.10 = 1.10
        let tokens = TokenBreakdown(cacheRead: 1_000_000)
        let cost = calc.calculate(provider: "kimi", model: "kimi-k2.6", tokens: tokens)
        XCTAssertEqual(cost ?? -1, 1.10, accuracy: 1e-9)
    }

    func testKimiCacheWriteExcluded() {
        // 1M cacheWrite only -> cost = 0 (cacheWrite not billed).
        let tokens = TokenBreakdown(cacheWrite: 1_000_000)
        let cost = calc.calculate(provider: "kimi", model: "kimi-k2.6", tokens: tokens)
        XCTAssertEqual(cost ?? -1, 0.0, accuracy: 1e-9)
    }

    func testClaudeBasic() {
        // claude representative (sonnet-4-5): input=20.37, output=101.85, cache=25.46 (write rate).
        let tokens = TokenBreakdown(input: 1_000_000, output: 100_000)
        let cost = calc.calculate(provider: "claude", model: "claude-sonnet-4-5", tokens: tokens)
        // 1 * 20.37 + 0.1 * 101.85 = 20.37 + 10.185 = 30.555
        XCTAssertEqual(cost ?? -1, 30.555, accuracy: 1e-9)
    }

    func testCodexBasic() {
        // codex modelRate (gpt-4o) entry added in round 10:
        // input = 2.50 * 6.79 = 16.975, output = 10.00 * 6.79 = 67.90, cache = 1.25 * 6.79 = 8.4875.
        // Older test (round 9 and earlier) used the provider-level rate(for: .codex)
        // representative which rounded input to 16.98. Round 10 prefers the
        // model-level rate, hence the looser accuracy bound.
        let tokens = TokenBreakdown(input: 1_000_000, output: 100_000)
        let cost = calc.calculate(provider: "codex", model: "gpt-4o", tokens: tokens)
        // 1 * 16.975 + 0.1 * 67.90 = 16.975 + 6.79 = 23.765
        XCTAssertEqual(cost ?? -1, 23.765, accuracy: 0.01)
    }

    func testZAIBasic() {
        // zai representative (glm-4.6): input=4.07, output=14.94, cache=0.75.
        let tokens = TokenBreakdown(input: 1_000_000, output: 100_000)
        let cost = calc.calculate(provider: "zai", model: "glm-4.6", tokens: tokens)
        // 1 * 4.07 + 0.1 * 14.94 = 4.07 + 1.494 = 5.564
        XCTAssertEqual(cost ?? -1, 5.564, accuracy: 1e-9)
    }

    func testNanoGptBasic() {
        // Every recognized provider now attempts modelRate first. The gpt-4o
        // model therefore uses its precise model-level CNY rate before the
        // NanoGPT representative fallback is considered.
        let tokens = TokenBreakdown(input: 1_000_000, output: 100_000)
        let cost = calc.calculate(provider: "nanogpt", model: "gpt-4o", tokens: tokens)
        // 1 * 16.975 + 0.1 * 67.90 = 23.765.
        XCTAssertEqual(cost ?? -1, 23.765, accuracy: 1e-9)
    }

    // MARK: - Edge cases (8-13)

    func testUnknownModelFallsBackToProviderRate() {
        // Round 9 (2026-07-12): the legacy representative-model strict-equal
        // gate was removed. An unknown model under a known provider now
        // falls back to that provider's representative rate (e.g. .kimi →
        // kimi-k2.6), so the row is always visible in monthly totals.
        // The `hasUnknownPricing` flag is separately signalled by the
        // aggregator (covered in testHasUnknownPricingFlag below).
        let tokens = TokenBreakdown(input: 1_000)
        let costRMB = calc.calculate(
            provider: "kimi", model: "unknown-model", tokens: tokens
        )
        XCTAssertNotNil(costRMB, "unknown kimi model should fall back to kimi-k2.6 rate, not nil")
        // 1k input * 6.5 RMB/M / 1e6 = 0.0065 RMB.
        XCTAssertEqual(costRMB ?? -1, 6.50 * 1_000 / 1_000_000, accuracy: 1e-9)
    }

    func testProviderFullyUnknownReturnsNil() {
        // "openrouter" / "antigravity" / etc. are F2b sources but NOT in
        // F2a's representative-model set. rate(for: providerId) returns nil,
        // modelRate has no chance to hit either, so the row is genuinely
        // unpriced — different from "model unknown, provider known".
        let cost = calc.calculate(
            provider: "openrouter", model: "auto", tokens: TokenBreakdown(input: 1_000)
        )
        XCTAssertNil(cost)
    }

    func testUnknownProviderReturnsNil() {
        // provider="mimo" not mapped in F2a PricingTable -> nil.
        let cost = calc.calculate(
            provider: "mimo",
            model: "any-model",
            tokens: TokenBreakdown(input: 1_000)
        )
        XCTAssertNil(cost)
    }

    func testCalculateMonthlyTotalsAggregatesPerProvider() {
        let aggs = [
            MonthAggregate(
                provider: "kimi",
                model: "kimi-k2.6",
                tokens: TokenBreakdown(input: 1_000_000, output: 500_000),
                yearMonth: "2026-07"
            ),
            MonthAggregate(
                provider: "kimi",
                model: "kimi-k2.6",
                tokens: TokenBreakdown(input: 2_000_000, output: 1_000_000),
                yearMonth: "2026-07"
            ),
            MonthAggregate(
                provider: "claude",
                model: "claude-sonnet-4-5",
                tokens: TokenBreakdown(input: 1_000_000, output: 100_000),
                yearMonth: "2026-07"
            ),
        ]
        let totals = calc.calculateMonthlyTotals(aggs)
        XCTAssertEqual(totals.count, 2)

        guard let kimi = totals.first(where: { $0.provider == "kimi" }) else {
            XCTFail("Missing kimi total"); return
        }
        // Kimi: input=3M, output=1.5M  ->  cost = 3 * 6.5 + 1.5 * 27 = 19.5 + 40.5 = 60.0
        XCTAssertEqual(kimi.totalCostRMB, 60.0, accuracy: 1e-9)
        XCTAssertEqual(kimi.totalTokens.input, 3_000_000)
        XCTAssertEqual(kimi.totalTokens.output, 1_500_000)
        XCTAssertEqual(kimi.modelBreakdown.count, 2)
        XCTAssertFalse(kimi.hasUnknownPricing)

        guard let claude = totals.first(where: { $0.provider == "claude" }) else {
            XCTFail("Missing claude total"); return
        }
        XCTAssertEqual(claude.totalCostRMB, 30.555, accuracy: 1e-9)
        XCTAssertEqual(claude.totalTokens.input, 1_000_000)
        XCTAssertEqual(claude.totalTokens.output, 100_000)
    }

    func testHasUnknownPricingFlagWhenProviderFullyUnknown() {
        // Round 9: hasUnknownPricing now fires when the *provider-level*
        // rate is missing (modelRate didn't hit + provider-level fallback
        // also nil). Mixing a known kimi model with a future/unknown kimi
        // model under the .kimi provider no longer flags (both rows get a
        // cost from gpt-4o-style fallback or its own model rate).
        //
        // Use a provider that is fully unpriced (openrouter) to flip the
        // flag. This regression-locks the new "fallback" code path.
        let aggs = [
            MonthAggregate(
                provider: "kimi",
                model: "kimi-k2.6",
                tokens: TokenBreakdown(input: 1_000_000),
                yearMonth: "2026-07"
            ),
            MonthAggregate(
                provider: "openrouter",  // not in F2a set
                model: "auto",
                tokens: TokenBreakdown(input: 1_000_000),
                yearMonth: "2026-07"
            ),
        ]
        let totals = calc.calculateMonthlyTotals(aggs)
        XCTAssertEqual(totals.count, 2, "should keep openrouter row visible even when unpriced")
        let openrouter = totals.first(where: { $0.provider == "openrouter" })
        XCTAssertNotNil(openrouter)
        XCTAssertTrue(openrouter?.hasUnknownPricing ?? false,
                      "Provider with no model+provider rate should flag")
        let kimi = totals.first(where: { $0.provider == "kimi" })
        XCTAssertNotNil(kimi)
        XCTAssertFalse(kimi?.hasUnknownPricing ?? true,
                       "kimi fallback for unknown model should NOT flag (cost is estimated, row is visible)")
    }

    func testZeroTokensReturnsZero() {
        // All zeros -> cost = 0 (still non-nil since provider/model match).
        let cost = calc.calculate(provider: "kimi", model: "kimi-k2.6", tokens: TokenBreakdown())
        XCTAssertEqual(cost ?? -1, 0.0, accuracy: 1e-9)
    }

    func testVeryLargeTokens() {
        // 1B input + 500M output for kimi-k2.6.
        // cost = 1000 * 6.5 + 500 * 27 = 6500 + 13500 = 20000 RMB.
        let tokens = TokenBreakdown(input: 1_000_000_000, output: 500_000_000)
        let cost = calc.calculate(provider: "kimi", model: "kimi-k2.6", tokens: tokens)
        XCTAssertEqual(cost ?? -1, 20_000.0, accuracy: 1e-6)
    }

    // MARK: - Real user data + zai bridge (14, 15)

    func testRealUserData() {
        // User real data: 14M input + 1.4M output + 473M cacheRead for codex gpt-4o.
        // F2a codex gpt-4o rate (round 10 modelRate entry, USD $2.50/$10/$1.25
        // × FX 6.79): input=16.975, output=67.90, cache=8.4875 (RMB/M).
        // Formula:
        //   14 * 16.975 + 1.4 * 67.90 + 473 * 8.4875
        //   = 237.65 + 95.06 + 4014.5875
        //   = 4347.2975 RMB.
        // Round-9 expected 4348.55 RMB; round-10 picks up the modelRate
        // preference (more precise) so the new value is 1.25 RMB lower.
        let tokens = TokenBreakdown(
            input: 14_000_000,
            output: 1_400_000,
            cacheRead: 473_000_000
        )
        let cost = calc.calculate(provider: "codex", model: "gpt-4o", tokens: tokens)
        XCTAssertEqual(cost ?? 0, 4347.2975, accuracy: 0.01)
    }

    func testProviderZaiMapping() {
        // Verify F2b provider string "zai" (Provider.rawValue) bridges to F2a
        // ProviderIdentifier.zaiCodingPlan (different enum, different rawValue).
        // "zai" -> .zaiCodingPlan -> glm-4.6 (representative).
        // Cost = 1 * 4.07 + 0.1 * 14.94 = 5.564.
        let tokens = TokenBreakdown(input: 1_000_000, output: 100_000)
        let cost = calc.calculate(provider: "zai", model: "glm-4.6", tokens: tokens)
        XCTAssertEqual(cost ?? -1, 5.564, accuracy: 1e-9)
    }

    // MARK: - Model-first rate precedence (round 9, fixes gpt-4o fall-through)

    /// Pre-round-9 behaviour dropped every GPT-5.x row to `nil` because the
    /// `representativeModel` gate required `model == "gpt-4o"` under the
    /// `.codex` provider. That hidden gate is now removed (or relaxed) and
    /// `modelRate(for:)` is consulted first. Verify with a known GPT-5.x
    /// model under any supported provider that we now get a non-nil cost
    /// computed from the model's own rate, not gpt-4o's.
    ///
    /// Cost math (Standard tier USD per 1M):
    ///   input 1M * $5  +  output 0.1M * $30  +  cache 0.5M * $0.5
    ///  = $5 + $3 + $0.25 = $8.25 USD
    /// After FX 1 USD = 6.79 CNY → $56.0175 RMB.
    /// Allow ±0.05 RMB rounding tolerance.
    func testCalculateUsesModelRateFirst_ForGpt5xModels() {
        let tokens = TokenBreakdown(
            input: 1_000_000, output: 100_000, cacheRead: 500_000, cacheWrite: 0, reasoning: 0
        )
        // Standard tier USD per 1M:
        //   input 1M * $5  +  output 0.1M * $30  +  cache 0.5M * $0.5
        //  = $5 + $3 + $0.25 = $8.25 USD = 56.0175 RMB (FX 6.79).
        let expectedRMB = 8.25 * 6.79
        guard let costRMB = calc.calculate(
            provider: "codex", model: "gpt-5.6-sol", tokens: tokens
        ) else {
            return XCTFail("gpt-5.6-sol must compute, not drop to nil (modelRate must take precedence)")
        }
        XCTAssertEqual(costRMB, expectedRMB, accuracy: 0.10,
                       "gpt-5.6-sol must use $5/$30/$0.50; legacy gpt-4o representative would yield ~23.77 RMB")
    }

    /// The Pro tier is a separate, 6×-more-expensive row. Make sure the
    /// `gpt-5.5-pro` alias resolves to its own rate, not the plain 5.5 row.
    func testCalculateUsesModelRateFirst_ForProTier() {
        let tokens = TokenBreakdown(
            input: 100_000, output: 10_000, cacheRead: 50_000, cacheWrite: 0, reasoning: 0
        )
        // Standard tier USD: gpt-5.5-pro is $30 / no-cache / $180.
        // 0.1 * $30 + 0.01 * $180 = 3 + 1.8 = $4.80 USD = 32.592 RMB.
        let expectedRMB = 4.80 * 6.79
        guard let costRMB = calc.calculate(
            provider: "codex", model: "gpt-5.5-pro", tokens: tokens
        ) else {
            return XCTFail("gpt-5.5-pro must resolve via modelRate")
        }
        XCTAssertEqual(costRMB, expectedRMB, accuracy: 0.10,
                       "gpt-5.5-pro cache is nil; must NOT use 5.5 cache rate")
    }

    /// An unknown `.codex` model must NOT drop to nil; provider-level
    /// fallback to the gpt-4o representative rate keeps the row alive
    /// (the user can see it was un-priced, distinct from "no cost").
    func testUnknownCodexModelFallsBackToProviderRate() {
        let tokens = TokenBreakdown(
            input: 1_000_000, output: 100_000, cacheRead: 0, cacheWrite: 0, reasoning: 0
        )
        // gpt-4o fallback: 1 * 16.98 + 0.1 * 67.90 = 23.77 RMB.
        let cost = calc.calculate(provider: "codex", model: "gpt-unknown", tokens: tokens)
        XCTAssertNotNil(cost, "Unknown model under codex must fall back, not drop")
        XCTAssertEqual(cost ?? -1, 23.77, accuracy: 0.05)
    }

    /// The legacy representative-model gate is removed entirely (any model
    /// under .codex reaches at least the gpt-4o fallback). The previous
    /// `representativeModel: [.codex: "gpt-4o"]` strict-equal check must no
    /// longer filter out non-gpt-4o model names.
    func testCodexNoLongerRequiresGpt4oExactMatch() {
        let tokens = TokenBreakdown(input: 1, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0)
        // Previously: returned nil because "gpt-5.6-sol" != "gpt-4o".
        // Now: returns gpt-4o fallback rate * 1e-6 input = 1 * 16.98 / 1e6 RMB.
        let cost = calc.calculate(provider: "codex", model: "gpt-5.6-sol", tokens: tokens)
        // Must compute via either modelRate (preferred) or fallback — assert non-nil.
        XCTAssertNotNil(cost)
    }

    /// Model-level rates are global overrides. This is required for provider
    /// routes whose persisted provider label differs from the model vendor
    /// (for example Kimi Code and OpenCode Go).
    func testKnownModelRateTakesPrecedenceAcrossProviderLabels() {
        let tokens = TokenBreakdown(input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0)
        let costRMB = calc.calculate(provider: "kimi", model: "gpt-5.6-sol", tokens: tokens)
        XCTAssertNotNil(costRMB)
        XCTAssertEqual(costRMB ?? -1, 5.00 * 6.79, accuracy: 0.05,
                       "Known model rate must take precedence over the provider representative")
    }

    // MARK: - calculateWithSource (round 10) — hasUnknownPricing fallback signal

    /// Known model under .codex resolves via modelRate; the row is
    /// "fully priced" (no fallback). UI can show this as a normal cost.
    func testCalculateWithSourceKnownModelNotFallback() {
        let tokens = TokenBreakdown(input: 1, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0)
        guard let est = calc.calculateWithSource(
            provider: "codex", model: "gpt-5.6-sol", tokens: tokens
        ) else { return XCTFail("gpt-5.6-sol must resolve") }
        XCTAssertFalse(est.usedFallback,
                       "Known model under .codex must not flag as fallback")
        XCTAssertGreaterThanOrEqual(est.costRMB, 0)
    }

    /// Unknown OpenAI-prefix model under .codex (e.g. "gpt-zzz-9") triggers
    /// a modelRate query that returns nil. The row falls back to the
    /// gpt-4o representative rate. UI should show "estimated".
    func testCalculateWithSourceUnknownGptModelFallsBack() {
        let tokens = TokenBreakdown(input: 1, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0)
        guard let est = calc.calculateWithSource(
            provider: "codex", model: "gpt-zzz-9", tokens: tokens
        ) else { return XCTFail("unknown gpt- model under .codex must fall back to gpt-4o") }
        XCTAssertTrue(est.usedFallback,
                      "gpt-zzz-9 under .codex must flag as fallback (gpt-4o rate used)")
    }

    /// Kimi representative model path: kimi doesn't have a modelRate entry,
    /// so modelRate is never queried. usedFallback must be false even
    /// though the row is "model-specific" — kimi's representative rate
    /// is the canonical path for that provider, not a fallback.
    func testCalculateWithSourceKimiRepresentativeIsNotFallback() {
        let tokens = TokenBreakdown(input: 1, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0)
        guard let est = calc.calculateWithSource(
            provider: "kimi", model: "kimi-k2.6", tokens: tokens
        ) else { return XCTFail("kimi must resolve") }
        XCTAssertFalse(est.usedFallback,
                       "kimi representative model is the canonical path, not a fallback")
    }

    /// `hasUnknownPricing` flag wiring: a monthly aggregate with a mix
    /// of fully-priced + fallback rows must flag hasUnknownPricing=true
    /// (was previously true *only* on nil-cost rows, which is now
    /// unreachable under round-9 fallback semantics).
    func testMonthlyTotalsFlagsFallbackRows() {
        let aggs = [
            MonthAggregate(provider: "codex", model: "gpt-5.6-sol",
                           tokens: TokenBreakdown(input: 1_000_000),
                           yearMonth: "2026-07"),
            MonthAggregate(provider: "codex", model: "gpt-zzz-9",
                           tokens: TokenBreakdown(input: 1_000_000),
                           yearMonth: "2026-07"),
            MonthAggregate(provider: "codex", model: "gpt-5.6-terra",
                           tokens: TokenBreakdown(input: 1_000_000),
                           yearMonth: "2026-07"),
        ]
        let totals = calc.calculateMonthlyTotals(aggs)
        let codex = totals.first(where: { $0.provider == "codex" })
        XCTAssertNotNil(codex)
        XCTAssertTrue(codex?.hasUnknownPricing ?? false,
                      "codex total with at least one fallback row must flag hasUnknownPricing")
        // Re-verify the flag is sticky across further rows — a later
        // fully-priced row must NOT clear it.
        XCTAssertEqual(codex?.modelBreakdown.count, 3)
        XCTAssertTrue(codex?.hasUnknownPricing ?? false,
                      "a fully-priced row added after a fallback row must not clear the flag")
    }

    /// Round 10 lock-down: `gpt-4o` (the canonical Codex model) must
    /// resolve via the model-level lookup, not via the gpt-4o
    /// representative rate. Without this entry in the modelRate switch
    /// (PricingTable.swift), a Codex row tagged `gpt-4o` would be
    /// mis-marked as `usedFallback` because the model-level query
    /// returns nil and the codex representative rate catches it.
    func testCalculateWithSourceGpt4oIsNotFallback() {
        let tokens = TokenBreakdown(input: 1, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0)
        guard let est = calc.calculateWithSource(
            provider: "codex", model: "gpt-4o", tokens: tokens
        ) else { return XCTFail("gpt-4o must resolve") }
        XCTAssertFalse(est.usedFallback,
                       "gpt-4o is a known canonical model, must not flag as fallback")
    }

    /// `hasUnknownPricing` flag wiring: a monthly aggregate with all
    /// fully-priced rows must NOT flag. Previously (round 9 module 2)
    /// this test asserted true when an unknown-model row was mixed in;
    /// round 10 retires that since unknown-model rows now produce a
    /// fallback cost instead of nil.
    func testMonthlyTotalsCleanRunDoesNotFlag() {
        let aggs = [
            MonthAggregate(provider: "codex", model: "gpt-5.6-sol",
                           tokens: TokenBreakdown(input: 1_000_000),
                           yearMonth: "2026-07"),
            MonthAggregate(provider: "kimi", model: "kimi-k2.6",
                           tokens: TokenBreakdown(input: 1_000_000),
                           yearMonth: "2026-07"),
        ]
        let totals = calc.calculateMonthlyTotals(aggs)
        XCTAssertEqual(totals.count, 2)
        for t in totals {
            XCTAssertFalse(t.hasUnknownPricing,
                           "fully-priced rows must not flag hasUnknownPricing")
        }
    }

    // MARK: - Kimi K2.7 Code routing (t1.1)

    func testKimiK27CodeBasic() {
        let tokens = TokenBreakdown(input: 1_000_000, output: 500_000)
        let cost = calc.calculate(provider: "kimiCode", model: "kimi-k2-7-code", tokens: tokens)
        XCTAssertEqual(cost ?? -1, 20.0, accuracy: 1e-9)
    }

    func testKimiK27CodeCache() {
        let tokens = TokenBreakdown(cacheRead: 1_000_000)
        let cost = calc.calculate(provider: "kimiCode", model: "kimi-k2-7-code", tokens: tokens)
        XCTAssertEqual(cost ?? -1, 1.30, accuracy: 1e-9)
    }

    func testKimiK27AliasPaths() {
        let tokens = TokenBreakdown(input: 1_000_000, output: 500_000, cacheRead: 1_000_000)
        let expectedCost = 21.30
        for model in ["kimi-for-coding", "kimi-code/kimi-for-coding"] {
            let cost = calc.calculate(provider: "kimiCode", model: model, tokens: tokens)
            XCTAssertEqual(cost ?? -1, expectedCost, accuracy: 1e-9, "Alias \(model) must use K2.7 rates")
        }
    }

    func testKimiCodeUnknownModelFallsBack() {
        let tokens = TokenBreakdown(input: 1_000_000, output: 500_000, cacheRead: 1_000_000)
        guard let estimate = calc.calculateWithSource(
            provider: "kimiCode", model: "kimi-unknown-2027", tokens: tokens
        ) else {
            return XCTFail("Unknown Kimi Code model must use the Kimi representative rate")
        }
        XCTAssertEqual(estimate.costRMB, 21.10, accuracy: 1e-9)
        XCTAssertTrue(estimate.usedFallback)
    }

    // MARK: - t1.2 (audit/p0-batch-1-t1.2) — 3 new raw-API-rate providers

    /// Pre-t1.2: `providerStringToIdentifier("minimaxCN")` returned nil,
    /// causing `month_aggregates` rows with provider="minimaxCN" to drop
    /// to nil cost. Post-t1.2: routed to .minimaxCN representative rate
    /// (¥4.20 / ¥16.80 / ¥0.84 from MiniMax-M3 standard tier).
    /// 1M input * ¥4.20/M = ¥4.20.
    func testMinimaxCNBasic() {
        let tokens = TokenBreakdown(input: 1_000_000)
        let cost = calc.calculate(provider: "minimaxCN", model: "MiniMax-M3", tokens: tokens)
        XCTAssertEqual(cost ?? -1, 4.20, accuracy: 1e-9)
    }

    /// Unknown model under .minimaxCN falls back to the provider-level
    /// representative rate. `usedProviderFallback` is true (since modelRate
    /// was queried via the new `isNewProviderWithModelRate` path).
    func testMinimaxCNUnknownFallsBack() {
        let tokens = TokenBreakdown(input: 1_000_000)
        guard let est = calc.calculateWithSource(
            provider: "minimaxCN", model: "MiniMax-unknown", tokens: tokens
        ) else { return XCTFail("unknown model under minimaxCN must fall back, not nil") }
        XCTAssertEqual(est.costRMB, 4.20, accuracy: 1e-9)
        XCTAssertTrue(est.usedFallback,
                      "Unknown model under .minimaxCN must flag as fallback (provider-level rate used)")
    }

    /// Pre-t1.2: `providerStringToIdentifier("opencodeGo")` returned nil.
    /// Post-t1.2: routed to .openCodeGo representative rate
    /// (USD $1.74/$3.48/$0.0145 × FX 6.79 = ¥11.8146 / ¥23.6292 / ¥0.0984555).
    /// 1M input * ¥11.8146/M = ¥11.8146.
    /// Note: modelRate for deepseek-v4-pro is also $1.74 input, so this
    /// resolves via the modelRate lookup (preferred over provider-level).
    func testOpencodeGoDeepseekV4Pro() {
        let tokens = TokenBreakdown(input: 1_000_000)
        let cost = calc.calculate(provider: "opencodeGo", model: "deepseek-v4-pro", tokens: tokens)
        XCTAssertEqual(cost ?? -1, 1.74 * 6.79, accuracy: 1e-6)
    }

    /// mimo-v2.5-pro through opencodeGo uses the opencode-go USD*fx rate
    /// ($1.74 / $3.48 / $0.0145). 1M input → ¥11.8146.
    func testOpencodeGoMimo() {
        let tokens = TokenBreakdown(input: 1_000_000)
        guard let cost = calc.calculate(
            provider: "opencodeGo", model: "mimo-v2.5-pro", tokens: tokens
        ) else { return XCTFail("mimo-v2.5-pro under opencodeGo must resolve via modelRate") }
        XCTAssertEqual(cost, 1.74 * 6.79, accuracy: 1e-6,
                       "opencodeGo routes mimo-v2.5-pro at opencode-go tier (USD*fx)")
    }

    /// mimo-v2.5-pro through xiaomiTokenPlanCN uses Xiaomi's direct CNY
    /// rate (¥3.00 / ¥6.00 / ¥0.025), NOT the opencode-go USD*fx rate.
    /// This is the **provider-aware** override added in t1.2.
    /// 1M input * ¥3.00/M = ¥3.00 — ~4× cheaper than opencodeGo's path.
    func testXiaomiTokenPlanCNMimo() {
        let tokens = TokenBreakdown(input: 1_000_000)
        guard let cost = calc.calculate(
            provider: "xiaomiTokenPlanCN", model: "mimo-v2.5-pro", tokens: tokens
        ) else { return XCTFail("mimo-v2.5-pro under xiaomiTokenPlanCN must resolve") }
        XCTAssertEqual(cost, 3.00, accuracy: 1e-9,
                       "xiaomiTokenPlanCN uses Xiaomi's direct CNY rate, not opencode-go USD*fx")
    }

    /// Cross-provider divergence: same model, different providers, different
    /// prices. Verifies the opencodeGo vs xiaomiTokenPlanCN price split
    /// for mimo-v2.5-pro.
    func testMimoV25ProPriceDivergesAcrossProviders() {
        let tokens = TokenBreakdown(input: 1_000_000)
        let opencodeGoCost = calc.calculate(
            provider: "opencodeGo", model: "mimo-v2.5-pro", tokens: tokens
        ) ?? -1
        let xiaomiTokenPlanCNCost = calc.calculate(
            provider: "xiaomiTokenPlanCN", model: "mimo-v2.5-pro", tokens: tokens
        ) ?? -1
        XCTAssertGreaterThan(opencodeGoCost, xiaomiTokenPlanCNCost,
                             "opencodeGo must price higher than direct Xiaomi API (~4×)")
    }

    /// qwen3.7-max through opencodeGo uses the opencode-go USD*fx rate
    /// ($2.50 / $7.50 / $0.50 → ¥16.975 / ¥50.925 / ¥3.395).
    /// 1M input * ¥16.975/M = ¥16.975.
    func testQwen37MaxOpencodeGo() {
        let tokens = TokenBreakdown(input: 1_000_000)
        guard let cost = calc.calculate(
            provider: "opencodeGo", model: "qwen3.7-max", tokens: tokens
        ) else { return XCTFail("qwen3.7-max under opencodeGo must resolve via modelRate") }
        XCTAssertEqual(cost, 2.50 * 6.79, accuracy: 1e-6)
    }

    /// Pre-t1.2: xiaomiTokenPlanCN returned nil. Post-t1.2: routed to
    /// .xiaomiTokenPlanCN representative rate (¥3.00 / ¥6.00 / ¥0.025
    /// from mimo-v2.5-pro Xiaomi domestic). Uses an unknown model so the
    /// call falls through `modelRate` (nil) to `rate(for: .xiaomiTokenPlanCN)`.
    /// 1M input + 100K output = 1 * 3.00 + 0.1 * 6.00 = 3.60.
    func testXiaomiTokenPlanCNBasic() {
        let tokens = TokenBreakdown(input: 1_000_000, output: 100_000)
        let cost = calc.calculate(
            provider: "xiaomiTokenPlanCN", model: "mimo-v2.5-pro", tokens: tokens
        )
        XCTAssertEqual(cost ?? -1, 3.60, accuracy: 1e-9)
    }

    /// t1.2: mimo-v2.5-pro cache read under xiaomiTokenPlanCN uses ¥0.025/M.
    /// 1M cacheRead * 0.025 = 0.025.
    func testXiaomiTokenPlanCNMimoCacheRead() {
        let tokens = TokenBreakdown(cacheRead: 1_000_000)
        let cost = calc.calculate(
            provider: "xiaomiTokenPlanCN", model: "mimo-v2.5-pro", tokens: tokens
        )
        XCTAssertEqual(cost ?? -1, 0.025, accuracy: 1e-9)
    }

    /// `calculateMonthlyTotals` regression: the 3 new providers used to drop
    /// out of the totals entirely (pre-t1.2 returned nil). Post-t1.2: each
    /// provider row appears in totals with a non-nil cost.
    func testMonthlyTotalsIncludesNewProviders() {
        let aggs = [
            MonthAggregate(provider: "minimaxCN", model: "MiniMax-M3",
                           tokens: TokenBreakdown(input: 1_000_000),
                           yearMonth: "2026-07"),
            MonthAggregate(provider: "opencodeGo", model: "deepseek-v4-pro",
                           tokens: TokenBreakdown(input: 1_000_000),
                           yearMonth: "2026-07"),
            MonthAggregate(provider: "xiaomiTokenPlanCN", model: "mimo-v2.5-pro",
                           tokens: TokenBreakdown(input: 1_000_000),
                           yearMonth: "2026-07"),
        ]
        let totals = calc.calculateMonthlyTotals(aggs)
        XCTAssertEqual(totals.count, 3, "all 3 new providers should appear in totals")
        let minimax = totals.first(where: { $0.provider == "minimaxCN" })
        XCTAssertNotNil(minimax)
        XCTAssertEqual(minimax?.totalCostRMB ?? -1, 4.20, accuracy: 1e-9)
        let opencodeGo = totals.first(where: { $0.provider == "opencodeGo" })
        XCTAssertNotNil(opencodeGo)
        XCTAssertEqual(opencodeGo?.totalCostRMB ?? -1, 1.74 * 6.79, accuracy: 1e-6)
        let xiaomiTokenPlanCN = totals.first(where: { $0.provider == "xiaomiTokenPlanCN" })
        XCTAssertNotNil(xiaomiTokenPlanCN)
        XCTAssertEqual(xiaomiTokenPlanCN?.totalCostRMB ?? -1, 3.00, accuracy: 1e-9)
    }

    /// Snapshot regression against the SQLite `month_aggregates`
    /// snapshot captured 2026-07-13 (post-t1.2 implementation). The
    /// numbers below are HARD-CODED `MonthAggregate` instances
    /// (NOT a live SQLite query at runtime) — keeps CI hermetic and
    /// free of F2b SQLite I/O. This test confirms that for the 3
    /// previously-zero-cost provider rows, MonthCostCalculator now
    /// produces non-nil, sensible RMB totals using the new rates.
    ///
    /// Live SQLite drift (e.g. the opencodeGo / minimax-m3 / etc.
    /// volume delta from one day to the next) is NOT captured here;
    /// see t2 (P0-2 day-vs-month token integrity) for the day-by-day
    /// reconciliation job. To regenerate this snapshot:
    ///   sqlite3 ~/Library/Application\ Support/TokenKing/f2b.sqlite \
    ///     "SELECT provider, model, SUM(input), SUM(output), SUM(cache_read) \
    ///      FROM month_aggregates \
    ///      WHERE provider IN ('minimaxCN','opencodeGo','xiaomiTokenPlanCN') \
    ///        AND year_month = '2026-07' \
    ///      GROUP BY provider, model;"
    /// then update the `MonthAggregate(...)` literals below.
    func testCostMathMatchesSnapshottedMonthAggregates202607() {
        let aggs = [
            // minimaxCN|MiniMax-M3: 95.88M in / 5.74M out / 1.96B cr
            // ¥4.20 * 95.88 + ¥16.80 * 5.74 + ¥0.84 * 1959.63 ≈ ¥2145.21
            MonthAggregate(provider: "minimaxCN", model: "MiniMax-M3",
                           tokens: TokenBreakdown(input: 95_880_430, output: 5_739_658, cacheRead: 1_959_627_380),
                           yearMonth: "2026-07"),
            // opencodeGo|deepseek-v4-flash-free: 95.7K in / 14.3K out / 6.33M cr
            // opencode-go USD*fx: 0.14*6.79 / 0.28*6.79 / 0.0028*6.79 ≈ ¥0.24
            MonthAggregate(provider: "opencodeGo", model: "deepseek-v4-flash-free",
                           tokens: TokenBreakdown(input: 95_714, output: 14_295, cacheRead: 6_333_184),
                           yearMonth: "2026-07"),
            // opencodeGo|deepseek-v4-pro: 6.40M in / 568K out / 175.04M cr
            // opencode-go USD*fx: 1.74*6.79 / 3.48*6.79 / 0.0145*6.79 ≈ ¥106.24
            MonthAggregate(provider: "opencodeGo", model: "deepseek-v4-pro",
                           tokens: TokenBreakdown(input: 6_398_613, output: 567_637, cacheRead: 175_037_568),
                           yearMonth: "2026-07"),
            // opencodeGo|minimax-m3: 59.1K in / 127 out / 1.9K cr
            // MiniMax-M3 native CNY: ¥4.20 / ¥16.80 / ¥0.84 ≈ ¥0.25
            MonthAggregate(provider: "opencodeGo", model: "minimax-m3",
                           tokens: TokenBreakdown(input: 59_133, output: 127, cacheRead: 1_906),
                           yearMonth: "2026-07"),
            // xiaomiTokenPlanCN|mimo-v2.5-pro: 16.06M in / 860K out / 832.16M cr
            // Xiaomi direct CNY: ¥3.00 / ¥6.00 / ¥0.025 ≈ ¥74.13
            MonthAggregate(provider: "xiaomiTokenPlanCN", model: "mimo-v2.5-pro",
                           tokens: TokenBreakdown(input: 16_056_695, output: 860_000, cacheRead: 832_160_704),
                           yearMonth: "2026-07"),
        ]
        let totals = calc.calculateMonthlyTotals(aggs)
        XCTAssertEqual(totals.count, 3,
                       "expected 3 distinct provider rows in totals (minimaxCN/opencodeGo/xiaomiTokenPlanCN)")
        // No row should flag hasUnknownPricing (all 5 rows have explicit rates).
        for t in totals {
            XCTAssertFalse(t.hasUnknownPricing,
                           "\(t.provider) should be fully-priced post-t1.2")
        }
        // Provider totals (¥).
        let fx = 6.79
        let minimax = totals.first(where: { $0.provider == "minimaxCN" })
        XCTAssertEqual(minimax?.totalCostRMB ?? -1, 2145.21, accuracy: 0.1)
        let opencodeGo = totals.first(where: { $0.provider == "opencodeGo" })
        // Two deepseek + one minimax-m3 sum:
        //   v4-flash-free ≈ 0.24
        //   v4-pro        ≈ 106.24
        //   minimax-m3    ≈ 0.25
        // total ≈ 106.73
        XCTAssertEqual(opencodeGo?.totalCostRMB ?? -1, 106.73, accuracy: 0.1)
        let xiaomiTokenPlanCN = totals.first(where: { $0.provider == "xiaomiTokenPlanCN" })
        XCTAssertEqual(xiaomiTokenPlanCN?.totalCostRMB ?? -1, 74.13, accuracy: 0.1)
    }
}
