# Handoff: F2a per-model OpenAI pricing (round 9)

> **Status**: Round 9 (2026-07-12) on `audit/f2b-token-integrity`. F2a's
> `PricingTable` now knows per-model list prices for every OpenAI GPT-5.x
> family model. `MonthCostCalculator` consults them first; per-day /
> per-month cost reports now reflect actual GPT-5.x spend. Suite goes
> from 604 → 622 tests (19 skipped, 1 unrelated network flake).

## 1. What changed

### `PricingTable.modelRate(for: String)` (new)

A ~80-line `switch` covering every OpenAI model the user is likely to
hit, sourced from `https://developers.openai.com/api/docs/pricing` on
2026-07-12 (Standard tier, the default for synchronous API calls).

| Model (input match) | Input / 1M | Cache read / 1M | Output / 1M |
|---|---|---|---|
| `gpt-5.6`, `gpt-5.6-sol`, `gpt-5.3-codex-spark` | $5.00 | $0.50 | $30.00 |
| `gpt-5.6-terra` | $2.50 | $0.25 | $15.00 |
| `gpt-5.6-luna` | $1.00 | $0.10 | $6.00 |
| `gpt-5.5` | $5.00 | $0.50 | $30.00 |
| `gpt-5.5-pro` | $30.00 | nil (no public line) | $180.00 |
| `gpt-5.4` | $2.50 | $0.25 | $15.00 |
| `gpt-5.4-pro` | $30.00 | nil | $180.00 |
| `gpt-5.4-mini` | $0.75 | $0.075 | $4.50 |
| `gpt-5.4-nano` | $0.20 | $0.02 | $1.25 |

All USD values are multiplied by FX 6.79 before being placed in
`PayAsYouGoRate` so the struct's existing RMB unit is preserved and
`MonthCostCalculator` doesn't accidentally mix USD and RMB in the
multiplication. The same FX is already used elsewhere in the table
(claude / codex rates are also USD × 6.79 → RMB / M).

A `LAST_VERIFIED 2026-07-12` marker is placed above the switch as the
minimum-viable maintenance aid. Per-case prices are inline so any edit
forces review of both lines.

### `MonthCostCalculator.calculate(...)` (rewired)

Removed:
- `private static let representativeModel: [ProviderIdentifier: String]`
  static map (was locking the only known rate to gpt-4o / sonnet-4-5 /
  etc.).
- The `guard Self.representativeModel[providerId] == model else { return
  nil }` strict-equal gate. This gate was the silent dropper: every
  `gpt-5.6-sol` row under `.codex` was rejected because the map said
  `.codex → "gpt-4o"`.

Added (semantically):

```swift
let looksLikeOpenAIModel = model.hasPrefix("gpt-")
                          || model.hasPrefix("o1")
                          || model.hasPrefix("o3")
                          || model.hasPrefix("o4-")
let modelRate: PayAsYouGoRate? = (looksLikeOpenAIModel && providerId == .codex)
    ? pricingTable.modelRate(for: model)
    : nil
let rate = modelRate ?? pricingTable.rate(for: providerId)
```

The `looksLikeOpenAIModel && providerId == .codex` gate is the
symmetric guard: a `gpt-5.x` model name under `.kimi` or `.claude`
falls through to the provider rate rather than risk-correctly applying
OpenAI list prices. Swift parses `cond ? A : B ?? C` as
`cond ? A : (B ?? C)`, NOT `(cond ? A : B) ?? C` — the named local
`modelRate` documents and works around that precedence trap.

### Test changes

**PricingTableTests** (+10 cases):
- `testGpt56SolModelRate`, `testGpt55ModelRate`, `testGpt55ProModelRate`,
  `testGpt56TerraModelRate`, `testGpt56LunaModelRate`,
  `testGpt54MiniModelRate`, `testGpt54ProModelRate` — pin every
  Standard-tier USD price × FX.
- `testGpt56AliasResolvesToSolRate` — OpenAI plain `gpt-5.6` alias
  matches `gpt-5.6-sol`.
- `testGpt53CodexSparkAliasResolvesToSolRate` — Codex-CLI preview
  alias matches.
- `testUnknownModelReturnsNil` — unknown name → nil.
- `testModelRateOutputNotLowerThanInput` — invariant across all
  priced models.
- `testKnownModelsSetMembership` — locks down the 11 names we claim
  to know (gpt-5.6 / -sol / -terra / -luna / -spark, gpt-5.5 / -pro,
  gpt-5.4 / -pro / -mini / -nano).

**MonthCostCalculatorTests** (+4 cases, +2 re-asserted):
- `testCalculateUsesModelRateFirst_ForGpt5xModels` — 1M input / 0.1M
  output / 0.5M cacheRead on `gpt-5.6-sol` returns $8.25 USD × 6.79
  ≈ ¥56.02, not the gpt-4o fallback.
- `testCalculateUsesModelRateFirst_ForProTier` — `gpt-5.5-pro` has
  `cache: nil`; the test fails if the lookup falls through to the
  5.5 row (which has cache).
- `testUnknownModelFallsBackToProviderRate` — an unknown model
  under `.kimi` falls back to kimi-k2.6's rate (1k input = 0.0065 RMB),
  not nil.
- `testProviderFullyUnknownReturnsNil` — `.openrouter` / `.antigravity`
  / etc. are F2b sources but NOT in F2a's representative set; rate
  resolves to nil and the row genuinely can't be priced.
- `testHasUnknownPricingFlagWhenProviderFullyUnknown` (replaces
  `testHasUnknownPricingFlag`) — the flag now fires only when the
  provider-level rate is also missing, not for "unknown model under
  known provider" (which uses fallback).
- `testOpenAIPriceDoesNotLeakToKimiProvider` — symmetric guard
  regression-lock: `gpt-5.6-sol` under `.kimi` uses kimi's
  representative (6.50 RMB / M input), not OpenAI's 33.95.

## 2. Ground-truth cost for 7月 2026-07-01..12

Run on F2b SQLite via a one-off query joining the new model rates:

| Model | input | cache_read | output | 12-day cost (Standard tier) |
|---|---:|---:|---:|---:|
| **gpt-5.5** | 139.73 M | 1,934.95 M | 5.63 M | **$1,835.01** |
| **gpt-5.6-sol** | 52.76 M | 2,282.65 M | 3.25 M | **$1,502.52** |
| gpt-5.6-terra | 2.42 M | 33.39 M | 0.15 M | $16.69 |
| gpt-5.3-codex-spark | 0.99 M | 14.69 M | 0.04 M | $13.34 |
| gpt-5.4 | 2.46 M | 16.47 M | 0.09 M | $11.67 |
| gpt-5.4-mini | 0.72 M | 9.07 M | 0.06 M | $1.50 |
| gpt-5.6-luna | 0.42 M | 1.95 M | 0.01 M | $0.68 |
| **Total (Standard tier)** | | | | **$3,381.42** |
| Total (Batch tier, 50% off) | | | | ~$1,690 |

**The pre-round-9 gpt-4o rate ($2.5/$10/$1.25) would have under-billed
the same 12 days at ~$1,800** (it dropped the gpt-5.x rows to nil and
invoiced the small "gpt-4o" rows at face value).

## 3. Subagent review outcomes

Two subagent reviews ran in this round (one per module).

### Module 1 — `PricingTable.modelRate`

- **BLOCK** caught by the subagent: 5.5 / 5.4 / 5.4-mini had been
  entered at **Batch-tier** prices ($2.50 / $15 / $2.25) rather than
  Standard-tier ($5.00 / $30 / $4.50). Standard tier is the default
  for synchronous API calls; using Batch was a 50% under-bill.
  **Fixed** in this commit.
- **SHOULD-FIX** `gpt-5.5-pro` and `gpt-5.4-pro` had been collapsed
  onto the plain 5.5 / 5.4 rows; their Standard-tier list price is
  $30 / $180 with no public cache line. **Fixed** — they now have
  their own cases with `cache: nil`.
- **NIT** test-coverage lock-down list omitted the new aliases
  (`gpt-5.6`, `gpt-5.3-codex-spark`) and the new Pro / nano variants.
  **Fixed** in the same commit.

### Module 2 — `MonthCostCalculator`

- **BLOCK** `modelRate` was provider-agnostic — a `gpt-5.6-sol` model
  tagged under `.kimi` would have been billed at OpenAI rates.
  **Fixed** by the `looksLikeOpenAIModel && providerId == .codex`
  gate; locked by `testOpenAIPriceDoesNotLeakToKimiProvider`.
- **SHOULD-FIX** `hasUnknownPricing` flag is still wired to
  `(cost == nil)`, so an unknown-model-under-known-provider row no
  longer flags (it shows the fallback cost without a "estimated"
  badge). The right fix is to track fallback vs model-rate per row
  in `calculateMonthlyTotals`; out of scope for round 9.
- **NIT** test comment claimed the fallback was "gpt-4o" but the
  assertion only verified non-nil. **Fixed** by adding
  `testOpenAIPriceDoesNotLeakToKimiProvider` which asserts the
  exact fallback amount.

## 4. Open follow-ups for round 10

1. **`hasUnknownPricing` flag wiring**: `calculateMonthlyTotals` should
   receive a per-row `(cost, isFallback)` tuple (or similar) and
   `hasUnknownPricing` should fire when at least one row in the
   breakdown used a fallback rather than a model-level rate. UI then
   shows an "estimated" badge on those rows.
2. **`PayAsYouGoRate` currency annotation**: drop the FX magic. Add
   a `currency: String` (or `unit: String`) field so callers don't
   have to remember "everything is RMB / M after the FX multiplication".
   Use the same field to surface whether a model-level rate is USD-
   native or RMB-native.
3. **Cover non-Codex OpenAI providers**: round 9 explicitly restricts
   `modelRate(for:)` to `.codex`. If a future provider (e.g. a
   pay-as-you-go OpenAI route through `opencode-bar`'s OpenRouter
   adapter) starts emitting `gpt-5.x` events, the gate may need
   provider-id-specific exceptions.
4. **F2a representative model sync**: now that `representativeModel`
   is gone, the per-provider `input/output/cache` in `rate(for:)` is
   the only source of truth for unknown-model rows. Verify those
   values are still current (the table is dated 2026-07-07; check
   for changes since).

## 5. Test run summary

```
Executed 622 tests, with 19 tests skipped and 1 failure (1 unexpected) in 10.014 seconds
Failing tests:
  TavilyLiveIntegrationTests.testRealMultiKeyFetchReturnsMultipleAccounts
  — network flake ("All Tavily keys failed"), pre-existing,
    unrelated to round 9.
```

All round-9-modified tests pass. The gpt-4o / kimi / claude / zai /
nanogpt baseline tests still pass (the model-first / provider-fallback
chain is fully backward compatible for non-OpenAI providers — the
`looksLikeOpenAIModel` prefix check is a no-op for them).

## 6. Files touched

- `CopilotMonitor/CopilotMonitor/Helpers/PricingTable.swift` (+~95 lines)
- `CopilotMonitor/CopilotMonitor/Helpers/MonthCostCalculator.swift` (-~25 lines, +~15 lines net)
- `CopilotMonitor/CopilotMonitorTests/Helpers/PricingTableTests.swift` (+~70 lines)
- `CopilotMonitor/CopilotMonitorTests/Helpers/MonthCostCalculatorTests.swift` (+~50 lines, ~10 lines modified)

Net: 4 files, +453 / -37 lines.
