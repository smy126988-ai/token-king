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
        // nanoGpt representative (gpt-4o): rate(for: .nanoGpt) gives
        // input=16.98, output=67.90, cache=nil. The modelRate switch does
        // not query nanoGpt (only OpenAI-on-Codex), so this path falls
        // through to the provider rate. Sums the same way as testCodexBasic
        // but nanoGpt's rate caches out to nil, so cache contributes 0.
        let tokens = TokenBreakdown(input: 1_000_000, output: 100_000)
        let cost = calc.calculate(provider: "nanogpt", model: "gpt-4o", tokens: tokens)
        // 1 * 16.98 + 0.1 * 67.90 = 23.77 (cache=nil contributes 0).
        XCTAssertEqual(cost ?? -1, 23.77, accuracy: 1e-9)
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

    /// Round 9 follow-up: model-level rate must NOT leak across providers.
    /// An OpenAI-style model name under .kimi must NOT receive OpenAI
    /// list prices — the OpenAI list is bound to .codex.
    func testOpenAIPriceDoesNotLeakToKimiProvider() {
        let tokens = TokenBreakdown(input: 1_000_000, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0)
        // If the modelRate lookup wrongly applied, we'd get 1M * $5 = ¥33.95.
        // Correct behavior: gpt-5.6-sol under .kimi falls through to .kimi
        // representative (kimi-k2.6) rate = 1M input × 6.50 RMB/M = 6.50 RMB.
        let costRMB = calc.calculate(provider: "kimi", model: "gpt-5.6-sol", tokens: tokens)
        XCTAssertNotNil(costRMB)
        XCTAssertEqual(costRMB ?? -1, 6.50, accuracy: 0.05,
                       "OpenAI modelRate must not leak into .kimi provider; kimi representative applies")
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
}
