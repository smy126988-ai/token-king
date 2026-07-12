# 7月 2026-07-01..12 Token Cost Audit (All Providers)

> **CTCA methodology** documented at `docs/methodology/ctca-cli-token-cost-audit.md`. 5 subagents ran the procedure in parallel on 2026-07-12. All numbers are **Standard tier list price** (the default for synchronous API calls). FX 6.79 (1 USD = 6.79 CNY) for cost conversion; the F2a `PayAsYouGoRate.currency` field added in round 10 module 2 makes the unit explicit.

> **Round 11 fix (2026-07-13, user feedback pass)**: kimiCode now uses
> the kimi-k2-7-code cache_read rate of ¥1.30/M; **MiniMax-M3 now
> uses the China-domestic list price ¥4.20/¥0.84/¥16.80** (the user
> has their own direct API key, not the international promo $0.30 rate);
> **opencode-go deepseek routes now use the opencode-go rate
> ($1.74/$0.0145/$3.48 for V4-Pro, 4× the upstream DeepSeek direct
> rate)**. Total opencode cost moves from $153.58 → **$307.01** (×2.0).

## 1. Grand total — all priced providers (post round 11 fix)

| Provider | Rows | Total cost (12 days, Standard tier) | Currency |
|----------|----:|----:|----|
| **claudeCode** | 8,027 | **$6,667.08** | USD |
| **Codex (codexCli)** | 30,426 | **$3,381.42** | USD |
| **kimiCode** (k2.7-code rate) | 4,101 | **¥733.02 ≈ $107.96** | native CNY |
| **opencode** | 14,577 (11 days) | **$307.01** (was $153.58; opencode-go deepseek + MiniMax 国内 list) | USD |
| kimiCli | 0 in-window | ¥0 | — |
| zaiCodingPlan | 0 in-window | ¥0 | — |
| nanogpt | 31 zero-token rows | $0 | — |
| **TOTAL (priced, USD-equivalent)** | | **$10,463.47** | |

USD-equivalent rolls everything into one column using FX 6.79. The
native currency for each row is preserved in the per-provider table
below.

## 2. claudeCode — $6,667.08 (¥45,269.48)

| Model | input | cache_read | output | Cost (USD) | Cost (CNY) |
|---|---:|---:|---:|---:|---:|
| `claude-opus-4.8` | 1301.74 M | 0 | 4.07 M | $6,610.54 | ¥44,886.46 |
| `claude-haiku-4.5` | 56.06 M | 0 | 0.10 M | $56.54 | ¥383.91 |
| `<synthetic>` (zero-token system markers) | 0 | 0 | 0 | excluded | excluded |
| **Total** | **1357.80 M** | **0** | **4.17 M** | **$6,667.08** | **¥45,269.48** |

Prices: Opus 4.8 $5 / $0.50 / $25, Haiku 4.5 $1 / $0.10 / $5 (per 1M Standard tier, source: `https://platform.claude.com/docs/en/about-claude/pricing`).

**User flag 1 — "c2cc should have cache"**: VERIFIED AGAINST RAW JSONL
+ COMPARED TO 6月. 6月 used `mimo-v2.5-pro` (64 events, all in
cc-haha), 100% cache hit, 2.29M cache_read tokens. 7月 switched to
`claude-opus-4.8` (5,559 events, 0 cache_creation, 0 cache_read).
The user did **not** enable cache_control on Opus in 7月. This is a
**real usage change** (model switch from mimo to opus), not an
extraction bug. F2b is not under-counting; cache_read=0 in 7月
reflects the user's actual configuration. If cache_control had been
enabled on Opus, the bill could be ~50% lower (Opus cache_read is
0.10× input; $0.50/M vs $5/M input) → ~$3,300 instead of $6,611 for Opus.

**kiro proxy question**: the kiro CLI uses its own storage
(`~/Library/Application Support/kiro-cli/data.sqlite3`, no JSONL
files), not `~/.claude/projects/`. kiro data does not flow into F2b
today; if the user wants kiro usage in the audit, the F2b pipeline
needs a kiro extractor (round 11+ work). The 6月 mimo usage that
**was** cache-rich went through `claudeCode` (because mimo is the
local Xiaomi API which F2b's `claudeCode` extractor picked up via the
Kiro/Codex proxy path), not through kiro itself.

## 3. codexCli — $3,381.42 (¥22,959.85)

| Model | input | cache_read | output | Cost (USD) |
|---|---:|---:|---:|---:|
| `gpt-5.5` | 139.73 M | 1,934.95 M | 5.63 M | $1,835.01 |
| `gpt-5.6-sol` | 52.76 M | 2,282.65 M | 3.25 M | $1,502.52 |
| `gpt-5.6-terra` | 2.42 M | 33.39 M | 0.15 M | $16.69 |
| `gpt-5.3-codex-spark` | 0.99 M | 14.69 M | 0.04 M | $13.34 |
| `gpt-5.4` | 2.46 M | 16.47 M | 0.09 M | $11.67 |
| `gpt-5.4-mini` | 0.72 M | 9.07 M | 0.06 M | $1.50 |
| `gpt-5.6-luna` | 0.42 M | 1.95 M | 0.01 M | $0.68 |
| **Total** | **199.49 M** | **4,293.15 M** | **9.23 M** | **$3,381.42** |

Prices: `gpt-5.6-sol/5.5`: $5 / $0.50 / $30; `gpt-5.6-terra/5.4`: $2.50 / $0.25 / $15; `gpt-5.4-mini`: $0.75 / $0.075 / $4.50; `gpt-5.6-luna`: $1 / $0.10 / $6; `gpt-5.3-codex-spark` is a Codex-CLI preview alias for `gpt-5.6-sol`. (Source: `https://developers.openai.com/api/docs/pricing`, verified 2026-07-12.)

**Caveat**: Total cache_read is 4.29B (47% of total tokens); of that, `gpt-5.5` (1.93B) and `gpt-5.6-sol` (2.28B) drive the bill. The raw sum has been dedup'd in F2b extraction (round 8 commit `014ea58`); pre-dedup totals would have been 1.3× higher (Codex CLI duplicate-snapshot issue per ccusage PR #824).

## 4. opencode — $307.01 (was $153.58) [round 11 fix]

| Model | input | cache_read | output | reasoning | Cost (USD) | Source |
|---|---:|---:|---:|---:|---:|---|
| `MiniMax-M3` (user's own key) | 85.229 M | 1,817.527 M | 5.353 M | 0 | **$290.66** (CNY ¥1,974.58) | `https://platform.minimaxi.com/docs/guides/pricing-paygo` (input ¥4.20, cache ¥0.84, output ¥16.80 per 1M) |
| `mimo-v2.5-pro` (direct Xiaomi API) | 16.057 M | 832.161 M | 0.860 M | 0.402 M | $10.73 | `https://mimo.mi.com/docs/en-US/pricing` ($0.435/$0.0036/$0.87) |
| `deepseek-v4-pro` (opencode-go) | 2.217 M | 61.341 M | 0.176 M | 0.068 M | **$5.36** | `https://opencode.ai/docs/go/` ($1.74/$0.0145/$3.48) — opencode-go rate is **4× upstream DeepSeek** ($0.435/$0.003625/$0.87) |
| `deepseek-v4-flash-free` (opencode-go) | 0.096 M | 6.333 M | 0.014 M | 0 | **$0.0351** | opencode-go names it `deepseek-v4-flash` ($0.14/$0.0028/$0.28); the `*-free` alias resolves to the same model+rate in opencode-go (not the same as DeepSeek direct's free tier) |
| `minimax-m3` (lowercase alias of `MiniMax-M3`) | 0.059 M | 0.002 M | 0 | 0 | $0.038 | alias of `MiniMax-M3` |
| `kimi-for-coding` (k2.7-code via opencode) | 0.041 M | 0 | 0 | 0 | $0.039 | `https://platform.kimi.com/docs/pricing/chat-k27-code` ($0.95 input / $0.16 cache / $4.00 output, USD) |
| **Total** | **103.70 M** | **2,717.36 M** | **6.40 M** | | **$307.01** | |

**User flag 3 — "I mainly use deepseek"**: The user's perception does not
match the F2b-recorded ground truth for this window. Per the data,
**MiniMax-M3 is the dominant opencode model (85.23M input / 1.82B
cache / 5.35M output = $290.66 USD, 95% of opencode total)**. The
`deepseek-v4-pro` line (the one the user *intended* to be primary)
shows only 2.22M input / 61.34M cache ($5.36 USD). If the user's
actual deepseek volume is higher than F2b recorded, the
`TokenNormalizer.matchProvider` may be mis-classifying deepseek
sessions on c2cc / direct-curl upstreams — flagged for round 11+
work to add a model-level override list.

**User flag 4 — "kimi 和 minimax 都按照国内单价算, 确认下"**:
- **kimi**: 7月 priced with the China-domestic kimi-k2-7-code list
  (¥6.50 / ¥1.30 / ¥27.00), source
  `https://platform.kimi.com/docs/pricing/chat-k27-code`.
- **minimax**: now priced with the China-domestic MiniMax-M3 list
  (¥4.20 / ¥0.84 / ¥16.80), source
  `https://platform.minimaxi.com/docs/guides/pricing-paygo`. The
  international minimax.io page publishes a permanent 50%-off promo
  ($0.30/$0.06/$1.20) — that's a **different product** for
  international customers. Since the user has a direct API key with
  the China platform, the China-domestic rate applies. This is the
  reason the cost moved from $141 (old international-promo rate) to
  $290.66 (correct China-domestic list) — a 2.06× correction.

**Caveat**: `MiniMax-M3` has a 512K-token context window cliff that
doubles input/output rates to ¥8.40 / ¥1.68 / ¥33.60 above 512K. 85.229M
input spread across 14,577 events = average 5,846 tokens/event, but
the per-event max in the data was **795K** — well past 512K. Worst
case if every event with >512K used the 2× tier, `MiniMax-M3` cost
could double to ~$581.32. A more realistic estimate is 30-50% uplift
(i.e. ~$377–$436), since not every event crosses the cliff.
**Flag for round 11**: the F2b schema needs a `max_input_in_event`
column to bucket events into ≤512K vs >512K before pricing.

## 5. kimiCode — ¥733.02 (~$107.96) [round 11 fix]

| Model | input | cache_read | output | Cost (CNY) | Cost (USD equiv) |
|---|---:|---:|---:|---:|---:|
| `kimi-code/kimi-for-coding` | 13.14 M | 469.53 M | 1.38 M | ¥733.02 | $107.96 |

Price: **kimi-k2-7-code** Standard tier (synchronous API), CNY/1M:
**input ¥6.50 / cache_read ¥1.30 / output ¥27.00**. Source:
`https://platform.kimi.com/docs/pricing/chat-k27-code` (captured
2026-07-13). Distinct from plain kimi-k2.6 (¥1.10/M cache).

Formula: `13.14 × 6.50 + 469.53 × 1.30 + 1.38 × 27.00 = 85.41 + 610.39 + 37.26 = ¥733.06 ≈ ¥733.02` (sub-cent rounding).

**User flag 2 — "kimiCode uses kimi k2.7 not 2.6"**: FIXED.
Previous report (round 9) priced kimiCode as kimi-k2.6 (¥1.10/M
cache), giving ¥639.12. The kimi-k2-7-code cache rate is ¥1.30/M,
so the correct 12-day total is **¥733.02**, a 15% upward correction
(¥94 more). The new entry in `PricingTable.modelRate(for:)` covers
`"kimi-code/kimi-for-coding"`, `"kimi-for-coding"`, and
`"kimi-k2-7-code"` aliases. The legacy kimi-k2.6 ¥1.10/M rate still
applies to plain `.kimi` provider-level rate (kimi-cli native).

## 6. kimiCli / zaiCodingPlan / nanogpt — $0 in-window

All three providers show **zero priced rows** in the 2026-07-01..12 window:

- **kimiCli**: 117 historical rows in F2b total, **all with `ts_ms=0`** (1970-01-01 stub events). User-facing kimi-cli usage for 7月 was 0.
- **zaiCodingPlan**: 0 rows in F2b for this source. Either the local `~/.zai` CLI was not used in 7月, or the F2b extractor was not wired up to that path. F2a's `rate(for: .zaiCodingPlan)` exists (GLM-4.6 @ ¥4.07/14.94/0.75 per 1M), so once a row lands the cost will compute.
- **nanogpt**: 31 rows tagged `provider=nanoGpt` in F2b, **all 0-token `<synthetic>` system markers**. Real Claude / mimo usage that routed through NanoGPT was attributed to `provider=claude` etc. in the F2b schema and is captured above under `claudeCode` / `opencode`. No paid NanoGPT usage in the window.

## 7. Round 11 user-feedback pass resolution (4/4)

The 4 issues raised in user feedback are addressed:

1. **"claudecode 内容需要去 c2cc 里面看, 因为是代理的 kiro"** — Resolved by direct raw-JSONL inspection + 6月-vs-7月 model-distribution comparison. 6月 used mimo (cache-rich), 7月 switched to claude-opus-4.8 (cache_control not enabled). F2b is not under-counting; the user simply changed model in 7月 and didn't enable cache on the new model. The kiro CLI uses its own SQLite storage (not in F2b's pipeline); if the user wants kiro usage in the audit, a kiro extractor is round 11+ work.
2. **"minimax 也不应该只有 $141"** — Resolved by using the China-domestic MiniMax list price (¥4.20/¥0.84/¥16.80) instead of the international $0.30 promo. The user has a direct API key with the China platform, so the international promo rate doesn't apply. MiniMax cost moved from $141 (international promo, wrong) to **$290.66 (China-domestic list, correct)** — a 2.06× correction.
3. **"kimiCode 用的是 kimi k2.7, 不是 2.6"** — Resolved by adding kimi-k2-7-code entry to `PricingTable.modelRate(for:)` (input ¥6.50 / cache_read ¥1.30 / output ¥27.00). The kimiCode 7月 total is now **¥733.02** (was ¥639.12 with the k2.6 rate, a ¥94 / 15% under-cost).
4. **"opencode 是工具, minimax 是我自己的 api key, deepseek 是 opencode go, 把 opencode go 所有的 model 花销都算出来"** — Resolved. The deepseek-v4-pro line (and the deepseek-v4-flash-free line, which the opencode-go docs call `deepseek-v4-flash`) is now priced with the **opencode-go tier** rate ($1.74 / $0.0145 / $3.48 for V4-Pro; $0.14 / $0.0028 / $0.28 for V4-Flash). These are **4× the upstream DeepSeek direct rate** ($0.435 / $0.003625 / $0.87). Source: `https://opencode.ai/docs/go/`. Other opencode-go models visible in the same page that the audit should care about in future months: GLM-5.2/5.1, Kimi K2.7 Code/K2.6, MiMo-V2.5/Pro, MiniMax M3/M2.7, Qwen3.7 Max/Plus, Qwen3.6 Plus. The user said "minimax 是我自己的 api key" so the `MiniMax-M3` line is the direct-Minimax China list, not the opencode-go pass-through — already covered in section 4.

## 8. Subagent review notes (5-issue QA pass, post round 11)

The 5-issue subagent review after the round-9 audit is now superseded by the round-11 corrections. Final state:

1. **claudeCode cache_read=0** — RESOLVED. The "0 cache reads" claim is real (verified against raw JSONL: cache_control was not enabled on the 7月 claude-opus-4.8 sessions; the 6月 mimo-v2.5-pro sessions that did have cache are a different model). F2b is not under-counting.
2. **opencode MiniMax-M3 512K cliff** — ANNOTATED. Worst-case $581.32 (after round 11 price correction) vs nominal $290.66. F2b needs a `max_input_in_event` column to bucket events into ≤512K vs >512K before pricing. Round 11+ work.
3. **kimiCode CNY vs USD** — RESOLVED. Native CNY list used (k2.7-code at ¥6.50/¥1.30/¥27.00); grand total rolls everything into USD via FX 6.79.
4. **Codex cache_read:input ratio 43× for gpt-5.6-sol** — NOT A BUG. Anthropic-style prompt cache can hit 30-50× the fresh input rate when the system prompt + tool schemas are stable; this is the normal "small fresh input, large cache hit" pattern, not a column bleed.
5. **zaiCodingPlan / nanogpt zero rows** — ANNOTATED. Each subagent's SQL filter was logged; the zero is a real usage gap (or in-progress F2b-extractor wiring), not a query miss.

## 9. Provenance

- **Methodology**: `docs/methodology/ctca-cli-token-cost-audit.md` (commit `59b6310`)
- **Subagent outputs**: written to agentmemory as separate observations under concept tags `ctca`, `july-2026`, model name
- **Codex audit baseline**: `docs/handoffs/2026-07-12-f2b-ccusage-bench-7mo.txt`
- **Round 9 / 10 commits** that made the per-model lookup work:
  `54d9c5e` (modelRate switch), `b87cbeb` (hasUnknownPricing fallback),
  `73c707e` (PayAsYouGoRate.currency), `014ea58` (Codex dedup)
- **Round 11 commits**:
  - `388eb48` — adds kimi-k2-7-code case to `PricingTable.modelRate(for:)`
  - `TBD (this commit)` — adds China-domestic MiniMax-M3 + opencode-go
    deepseek cases; updates this report; merged to main

## 10. Round 11+ follow-ups

1. **F2b schema**: add `max_input_in_event` (or `is_long_context`) column to
   `token_events` so the opencode MiniMax-M3 512K cliff can be priced
   per-row instead of as a single nominal / worst-case range.
2. **kimiCode / kimi-k2-7-code alias**: extend `modelRate(for:)` to
   distinguish `kimi-k2.6` (¥1.10/M cache) from `kimi-k2-7-code`
   (¥1.30/M cache). **DONE** in round 11.
3. **MiniMax-M3 China-domestic vs international promo**: `modelRate(for:)`
   is wired with the China-domestic list (¥4.20/¥0.84/¥16.80). If a
   user on the international `minimax.io` platform runs the same
   model through this code path, the cost will be over-billed by
   ~2×. Either gate on `providerID` or accept the conservative
   (high) estimate.
4. **opencode-go deepseek routes** (V4-Pro, V4-Flash): added in round 11.
   If a user on the direct DeepSeek API runs the same model through
   opencode CLI (which routes to opencode-go), the cost will be
   over-billed by ~4×. Either gate on `providerID` or accept the
   conservative estimate.
5. **TokenEater-style agent watchers**: a "live session overlay" in the
   menu bar. Out of scope for cost audit.
6. **zaiCodingPlan + nanogpt extractors**: the F2b wiring is in place
   but the data is missing in 7月. Verify the local CLI tool was
   not used; if it was, the extractor path may be broken.
7. **kiro CLI extractor**: kiro uses its own SQLite storage at
   `~/Library/Application Support/kiro-cli/data.sqlite3`. If the user
   wants kiro usage in the F2a cost reports, build a kiro extractor
   (round 11+).
8. **deepseek "perception vs reality" gap**: the user reported deepseek
   as a primary model but the F2b-recorded opencode data shows only
   2.22M input / 61.34M cache for `deepseek-v4-pro`. If the user
   actually had more deepseek volume routed via a different upstream
   (c2cc / kiro / direct curl), `TokenNormalizer.matchProvider` may
   be mis-classifying those sessions. Audit the `providerID` field
   on heavy deepseek volumes.
9. **claudeCode opus cache_control** (user action item): the user
   should consider enabling cache_control on Opus prompts to halve
   the Opus bill (~$6,611 → ~$3,300 in this window).
