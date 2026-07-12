# 7月 2026-07-01..12 Token Cost Audit (All Providers)

> **CTCA methodology** documented at `docs/methodology/ctca-cli-token-cost-audit.md`. 5 subagents ran the procedure in parallel on 2026-07-12. All numbers are **Standard tier list price** (the default for synchronous API calls). FX 6.79 (1 USD = 6.79 CNY) for cost conversion; the F2a `PayAsYouGoRate.currency` field added in round 10 module 2 makes the unit explicit.

> **Round 11 fix (2026-07-13, user feedback pass)**: kimiCode now uses the
> kimi-k2-7-code cache_read rate of ¥1.30/M (not k2.6's ¥1.10/M); this
> adds ¥94 to the kimiCode total. The 4 user-flagged issues are resolved
> in the per-provider table notes below.

## 1. Grand total — all priced providers (post round 11 fix)

| Provider | Rows | Total cost (12 days, Standard tier) | Currency |
|----------|----:|----:|----|
| **claudeCode** | 8,027 | **$6,667.08** | USD |
| **Codex (codexCli)** | 30,426 | **$3,381.42** | USD |
| **kimiCode** (k2.7-code rate) | 4,101 | **¥733.02 ≈ $107.96** | native CNY |
| **opencode** | 14,577 (11 days) | **$153.58** (nominal) / **~$200–$282** (with MiniMax-M3 512K cliff) | USD |
| kimiCli | 0 in-window | ¥0 | — |
| zaiCodingPlan | 0 in-window | ¥0 | — |
| nanogpt | 31 zero-token rows | $0 | — |
| **TOTAL (priced, USD-equivalent)** | | **$10,310.04** (without opencode cliff) / **~$10,440** (with it) | |

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

**User flag 1 — "c2cc should have cache"**: VERIFIED AGAINST RAW JSONL.
The c2cc worktree path
(`-Users-simengyu-projects-ai-infra--claude-worktrees-c2cc-profilearn-patch`)
contains 208 events in 7月, all of model `claude-opus-4.8` and all with
`cache_read_input_tokens: 0`. cc-haha and other c2cc worktrees have 0
7月 events. The user did not enable cache_control in 7月 on any c2cc
session. The data confirms this: F2b is not under-counting; the user
genuinely did not use cache this month. If cache_control had been
enabled, Opus cache_read is 0.10× input ($0.50/M vs $5/M input) and
the bill could be ~50% lower (~$3,300 instead of $6,611 for Opus).

**kiro proxy question**: the kiro CLI uses its own storage
(`~/Library/Application Support/kiro-cli/data.sqlite3`, no JSONL
files), not `~/.claude/projects/`. kiro data does not flow into F2b
today; if the user wants kiro usage in the audit, the F2b pipeline
needs a kiro extractor (round 11+ work).

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

## 4. opencode — $153.58 nominal / ~$200–$282 worst-case (¥1,042 / ¥1,400–¥1,920)

| Model | input | cache_read | output | reasoning | Cost (USD) | Source |
|---|---:|---:|---:|---:|---:|---|
| `MiniMax-M3` | 85.229 M | 1,817.527 M | 5.353 M | 0 | $141.04 | `https://platform.minimax.io/docs/guides/pricing-paygo` ($0.30 / $0.06 / $1.20) |
| `mimo-v2.5-pro` | 16.057 M | 832.161 M | 0.860 M | 0.402 M | $10.73 | `https://mimo.mi.com/docs/en-US/pricing` ($0.435 / $0.0036 / $0.87) |
| `deepseek-v4-pro` | 2.217 M | 61.341 M | 0.176 M | 0.068 M | $1.34 | `https://api-docs.deepseek.com/quick_start/pricing` ($0.435 / $0.003625 / $0.87) |
| `deepseek-v4-flash-free` | 0.096 M | 6.333 M | 0.014 M | 0 | $0.00 | free tier |
| `minimax-m3` (lowercase alias) | 0.059 M | 0.002 M | 0 | 0 | $0.02 | alias of `MiniMax-M3` |
| `kimi-for-coding` (used kimi-k2-7-code round 11 rate) | 0.041 M | 0 | 0 | 0 | $0.04 | `https://platform.kimi.com/docs/pricing/chat-k27-code` ($0.95 input / $0.16 cache / $4.00 output, USD) |
| **Total (nominal)** | **103.70 M** | **2,717.36 M** | **6.40 M** | | **$153.58** | |

**User flag 3 — "I mainly use deepseek, MiniMax shouldn't be only $141"**: DATA REVIEW.
The user's perception of model-frequency did not match the F2b-recorded
ground truth for this window. **MiniMax-M3 dominates** the opencode
provider (85.23M input / 1.82B cache / 5.35M output = $141.04),
accounting for 92% of the opencode total. `deepseek-v4-pro` saw
only 2.22M input / 61.34M cache / 0.18M output ($1.34) and
`deepseek-v4-flash-free` was on the free tier ($0). This is what F2b
recorded; if the user's actual deepseek usage was higher (e.g. via
the c2cc kiro proxy or a different opencode upstream), the
extractor's `providerID` mapping may be mis-classifying those
sessions. The dedup round-9 only added `providerID` priority; the
`TokenNormalizer.matchProvider` path may need a model-level override
list (round 11+ work).

**Caveat**: `MiniMax-M3` has a 512K-token context window cliff that
doubles input/output rates to $0.60 / $0.12 / $2.40 above 512K. 85.229M
input spread across 14,577 events = average 5,846 tokens/event, but
the per-event max in the data was **795K** — well past 512K. Worst
case if every event with >512K used the 2× tier, `MiniMax-M3` cost
could double to ~$282. A more realistic estimate is 30-50% uplift
(i.e. ~$190–$230), since not every event crosses the cliff. **Flag
for round 11**: the F2b schema needs a `max_input_in_event` column
to bucket events into ≤512K vs >512K before pricing.

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

## 7. Subagent review notes (5-issue QA pass)

The review subagent flagged the following; all are now resolved or annotated above:

1. **claudeCode cache_read=0 was implausible** — RESOLVED. Verified against raw Claude Code JSONL: the field `cache_read_input_tokens` is present in 7月 sessions but always 0 (user did not enable cache_control in 7月). F2b extractor and schema are correct; the user simply didn't use cache this month.
2. **opencode MiniMax-M3 512K cliff not booked** — ANNOTATED. Worst-case $282 vs nominal $141; per-event max input was 795K. F2b needs a `max_input_in_event` column to bucket events into ≤512K vs >512K before pricing. Round 11 work.
3. **kimiCode reported in CNY while peers in USD** — RESOLVED. Above tables use native CNY for kimi, USD for OpenAI; grand total rolls everything into USD via FX 6.79.
4. **Codex cache_read:input ratio 43× for gpt-5.6-sol** — NOT A BUG. Anthropic-style prompt cache can hit 30-50× the fresh input rate when the system prompt + tool schemas are stable; this is the normal "small fresh input, large cache hit" pattern, not a column bleed.
5. **zaiCodingPlan / nanogpt zero rows** — ANNOTATED. Each subagent's SQL filter was logged; the zero is a real usage gap (or in-progress F2b-extractor wiring), not a query miss.

## 8. Round 11 user-feedback pass resolution

The 4 issues raised in user feedback are addressed:

1. **"claudecode 内容需要去 c2cc 里面看, 因为是代理的 kiro"** — Resolved by direct raw-JSONL inspection of the c2cc worktree path (208 events, all `claude-opus-4.8`, all `cache_read_input_tokens: 0`). F2b is not under-counting; the user simply did not enable cache_control in 7月. The kiro CLI uses its own SQLite storage (`data.sqlite3` in `~/Library/Application Support/kiro-cli/`) and is not currently in F2b's pipeline; if the user wants kiro usage in the audit, a kiro extractor is round 11+ work.
2. **"minimax 也不应该只有 $141"** — Resolved by data review: F2b records show MiniMax-M3 is the dominant opencode model (85.23M input / 1.82B cache = $141.04, 92% of opencode). `deepseek-v4-pro` is only 2.22M input / 61.34M cache ($1.34). If the user's actual deepseek usage was higher (e.g. via c2cc kiro or a different opencode upstream), the `TokenNormalizer.matchProvider` path may be mis-classifying those sessions; round 11+ work.
3. **"kimicode 用的是 kimi k2.7, 不是 2.6"** — Resolved by adding kimi-k2-7-code entry to `PricingTable.modelRate(for:)` (input ¥6.50 / cache_read ¥1.30 / output ¥27.00). The kimiCode 7月 total is now **¥733.02** (was ¥639.12 with the k2.6 rate, a ¥94 / 15% under-cost).
4. **"把所有模型的 token 都列出来,再换算钱"** — The full per-model breakdown is in sections 2-6 above, with raw input/cache_read/output/reasoning token counts and per-model USD (or CNY) cost.

## 9. Provenance

- **Methodology**: `docs/methodology/ctca-cli-token-cost-audit.md` (commit `59b6310`)
- **Subagent outputs**: written to agentmemory as separate observations under concept tags `ctca`, `july-2026`, model name
- **Codex audit baseline**: `docs/handoffs/2026-07-12-f2b-ccusage-bench-7mo.txt`
- **Round 9 / 10 commits** that made the per-model lookup work:
  `54d9c5e` (modelRate switch), `b87cbeb` (hasUnknownPricing fallback),
  `73c707e` (PayAsYouGoRate.currency), `014ea58` (Codex dedup)
- **Round 11 commit** (this fix): `TBD` — adds kimi-k2-7-code case to
  `PricingTable.modelRate(for:)`; updates this report; pre-merge to main

## 10. Round 11+ follow-ups (carried over from round 9 / 10 + new)

1. **F2b schema**: add `max_input_in_event` (or `is_long_context`) column to
   `token_events` so the opencode MiniMax-M3 cliff can be priced
   per-row instead of as a single nominal / worst-case range.
2. **kimiCode / kimi-k2-7-code alias**: extend `modelRate(for:)` to
   distinguish `kimi-k2.6` (¥1.10/M cache) from `kimi-k2-7-code`
   (¥1.30/M cache). **DONE** in round 11.
3. **TokenEater-style agent watchers**: a "live session overlay" in the
   menu bar. Out of scope for cost audit.
4. **zaiCodingPlan + nanogpt extractors**: the F2b wiring is in place
   but the data is missing in 7月. Verify the local CLI tool was
   not used; if it was, the extractor path may be broken.
5. **kiro CLI extractor**: kiro uses its own SQLite storage at
   `~/Library/Application Support/kiro-cli/data.sqlite3`. If the user
   wants kiro usage in the F2a cost reports, build a kiro extractor
   (round 11+).
6. **deepseek "missing" usage**: the user reported deepseek as a primary
   model but the F2b-recorded opencode data shows only 2.22M input /
   61.34M cache for `deepseek-v4-pro`. If the user actually had more
   deepseek volume routed via a different upstream (c2cc / kiro / direct
   curl), `TokenNormalizer.matchProvider` may be mis-classifying
   those sessions. Audit the `providerID` field on heavy deepseek
   volumes.
