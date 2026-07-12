# CTCA — CLI Token Cost Audit (v1.0, 2026-07-12)

> **Source-of-truth methodology** for computing "what did I actually spend
> on `<provider>` this month" against the local Token King `f2b.sqlite`
> + the canonical public list prices for each model.
>
> Verified end-to-end against the user's 7月 2026-07-01..12 Codex
> data: **$3,381.42 USD Standard tier** (raw sum, before dedup), as
> reproduced by `ccusage` to ±2%.

## When to use

- Audit-monthly cost reports for any provider wired into Token King
  F2b (Codex / OpenCode / Claude / Kimi / Z.AI / NanoGPT).
- Cross-check Token King's F2a monthly cost column against the real
  token_events aggregate.
- Settle "X Desktop says 20 亿, F2b says 42 亿, who's right" type
  disputes by pinning the right public-list price to each event.

## When NOT to use

- Subscription / quota-based providers (Copilot Premium-request,
  Antigravity, Kiro, etc.) — those don't bill per-token. Use the
  provider's own dashboard.
- Real-time per-call spend (e.g. for a per-user billing dashboard) —
  CTCA is offline audit, not real-time.
- Pre-release OpenAI / Anthropic models whose list price isn't on the
  public pricing page yet (wait for GA, add to `modelRate(for:)` then).

## The 7-step procedure

### 1. Pin the data source

F2b SQLite at `$HOME/Library/Application Support/TokenKing/f2b.sqlite`,
table `token_events`. Each row has a `source TEXT` column mapping to one
of: `codexCli`, `opencode`, `claudeCode`, `kimiCode`, `kimiCli`,
`nanoGpt`, `zaiCodingPlan`. `ts_ms` is epoch milliseconds. The
`provider` column (in the newer schema) is the same as the F2a Provider
enum (e.g. `codex`, `kimi`, `claude`).

Verify the row count for the month:
```sql
SELECT source, COUNT(*) FROM token_events
WHERE date(ts_ms/1000, 'unixepoch') BETWEEN 'YYYY-MM-01'
  AND 'YYYY-MM-DD' GROUP BY source;
```

If a source is missing, the user's local CLI tool wasn't used that
month — say so in the report, don't fabricate a number.

### 2. Pull the per-model breakdown

```sql
SELECT model,
       SUM(input) / 1e6         AS input_M,
       SUM(output) / 1e6        AS output_M,
       SUM(cache_read) / 1e6     AS cache_read_M,
       SUM(cache_write) / 1e6    AS cache_write_M,
       SUM(reasoning) / 1e6      AS reasoning_M
FROM token_events
WHERE source = '<source>'
  AND date(ts_ms/1000, 'unixepoch') BETWEEN 'YYYY-MM-01' AND 'YYYY-MM-DD'
GROUP BY model
ORDER BY SUM(input + output + cache_read + cache_write + reasoning) DESC;
```

The output is the raw token-count matrix per model. Save it verbatim;
don't try to compute cost yet.

### 3. Look up each model's public list price

**Source of truth (anysearch):**
- OpenAI: `https://developers.openai.com/api/docs/pricing` and
  per-model pages at `https://developers.openai.com/api/docs/models/<model>`
- Anthropic: `https://www.anthropic.com/pricing` and per-model docs
- Google: `https://ai.google.dev/pricing`
- xAI: `https://docs.x.ai/docs/models`
- DeepSeek / Moonshot / Z.AI: their respective pricing pages

**Tier trap**: every vendor has multiple tiers. Always state which
you're using. Defaults:
- OpenAI: **Standard** (the default for synchronous API calls)
- OpenAI: **Batch** = 50% off, async, 24h SLA. **Priority** = 2× input,
  faster latency.
- Anthropic: list price × tier (build a per-tier table)
- Google: pay-as-you-go vs. batch vs. cache

**Cache field naming is per-vendor** (and CTCA-v1 unifies only the
denominators, not the names):
- OpenAI: `cached_input_tokens` (5x → 0.5/1M for 5.6-sol) +
  `cache_creation_input_tokens` (1.25x input)
- Anthropic: `cache_creation_input_tokens` (1.25x input) +
  `cache_read_input_tokens` (0.1x input)
- Google: `cached_content_token_count`

F2b's `cache_read` column maps to the per-vendor "cache READ" (the
discounted, not the cache WRITE / creation) side. Cache-write / cache-
creation is intentionally excluded from CTCA by default (F2a's PricingTable
also excludes it; flag as a future enhancement if you want to include).

### 4. Currency unit (the unit-mixup trap)

`PayAsYouGoRate` in PricingTable.swift stores **CNY per 1M tokens** for
every priced rate. OpenAI public list prices (USD) are converted to
CNY via FX 6.79 inside `modelRate(for:)` (round 9). When you compute
cost in raw SQL, the formula is:

```
cost_USD = (input / 1e6) * price_in
        + (cache_read / 1e6) * price_cache
        + (output / 1e6) * price_out
cost_CNY = cost_USD * 6.79
```

Don't mix — if you set `cost_USD` but multiply by FX in another column,
you've doubled the FX. The round-9 unit-mixup bug caused a 0.5×
under-bill in the original 5.5 / 5.4 rates.

### 5. Run the cost query

For each model, run:

```sql
WITH model_pricing(m, pi, pc, po) AS (VALUES
  ('gpt-5.6-sol', 5.00, 0.50, 30.00),
  ('gpt-5.5',     5.00, 0.50, 30.00),
  -- ... one row per model, in USD per 1M tokens ...
)
SELECT t.model,
       SUM(t.input)/1e6         * p.pi +
       SUM(t.cache_read)/1e6    * p.pc +
       SUM(t.output)/1e6        * p.po AS cost_USD
FROM token_events t
LEFT JOIN model_pricing p ON t.model = p.m
WHERE source = '<source>'
  AND date(ts_ms/1000, 'unixepoch') BETWEEN 'YYYY-MM-01' AND 'YYYY-MM-DD'
GROUP BY t.model
ORDER BY cost_USD DESC;
```

Sum the per-model rows for the provider total. **Caveat**: `LEFT JOIN`
to `model_pricing` will include rows where `m` is unknown — their cost
is 0. Sanity-check the join by listing `t.model` distinct values and
matching against the priced set; report any unpriced models in the
output ("12M tokens of gpt-future-99 unpriced").

### 6. Subagent review (the safety net)

Spawn a `general-purpose` subagent with the full per-model breakdown,
the per-model cost row, and the public pricing page URL. Ask it to:

- Spot-check 1-2 prices against the source-of-truth URL.
- Verify tier (Standard / Batch / Priority) and the cache discount
  factor (0.1x for OpenAI cache read).
- Check that the lookup chain does not double-apply FX (USD vs CNY
  unit).
- Flag any model where the per-model cost is suspicious (e.g. cache_read
  < 10% of total would be unusual for a long session).

The subagent has caught real bugs in the F2a round 9 work (Batch-tier
rates used for Standard-tier expectations; gpt-4o missing from the
modelRate switch causing false `usedFallback` flag). Skipping this
step is the single highest-risk shortcut in the procedure.

### 7. Write the report + memory

For the user-facing report, structure as:

```
# 7月 2026 <provider> cost (Standard tier, USD)

| Model | input | cache_read | output | cost |
| --- | ---: | ---: | ---: | ---: |
| gpt-5.5 | 1.4M | 19.3M | 56k | $1,835.01 |
| gpt-5.6-sol | 53k | 22.8M | 3.3k | $1,502.52 |
| ... |
| **Total** | | | | **$3,381.42** |

## Caveats

- 12 days of July (2026-07-01..12). For a full-month number, multiply
  the daily rate by 30. Don't extrapolate linear — usage is typically
  uneven across a month.
- Dedup fingerprint (round 8) was applied to F2b extraction at the
  Codex layer, so cache_read raw sum is now ~ccusage value. Older data
  may have a 30%+ inflation from Codex CLI duplicate snapshots; rerun
  the F2b extraction post-round-8 to get a clean baseline.
- The `modelRate(for:)` switch covers only OpenAI-on-Codex today. For
  Anthropic / Google / xAI / DeepSeek / Z.AI you need a separate
  per-vendor rate table; F2a PricingTable's `rate(for: providerId)`
  is the representative-model fallback (e.g. .claude → sonnet-4-5
  Standard price). Round 10 module 2 makes the unit explicit; future
  work expands the switch to non-OpenAI vendors.

## Worked example (Codex 7月 2026-07-01..12, the audit that produced this)

| Step | Output |
|------|-------|
| 1. Row count by source | `codexCli`: 30,426 events |
| 2. Per-model breakdown | 7 distinct models, gpt-5.5 + gpt-5.6-sol dominate |
| 3. Public list price | OpenAI Standard, $5/$0.5/$30 for 5.6-sol and 5.5 |
| 4. Unit | USD per 1M × FX 6.79 = CNY per 1M |
| 5. Cost query | 7 rows summed to $3,381.42 |
| 6. Subagent review | Caught Batch-vs-Standard tier mixup, fixed in commit `54d9c5e` |
| 7. Report | "7月 12天 Codex = $3,381.42 USD Standard tier, 47% from 5.6-sol cache_read" |

## Provenance

This procedure was developed and verified in audit/f2b-token-integrity
branch, commits 36b7c7c through 73c707e (round 6 through round 10).
The full diff trail and handoffs are at:
- `docs/handoffs/2026-07-12-f2b-cache-semantics-final.md` (round 1-5)
- `docs/handoffs/2026-07-12-f2b-real-data-verification.md` (round 6)
- `docs/handoffs/2026-07-12-f2b-ccusage-bench-handoff.md` (round 7)
- `docs/handoffs/2026-07-12-f2b-ccusage-bench-7mo.txt` (baseline)
- `docs/handoffs/2026-07-12-f2b-f2a-model-pricing-round9.md` (round 9)
- This file (round 10 methodology)

When you add a new step, append a row to the provenance table.
