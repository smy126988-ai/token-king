# Handoff: F2b Token Audit (Round 1-11, 2026-07-06..13)

> **Status**: Audit closed at Round 11 with user feedback 2 passes. All
> 4 critical issues from the final user review resolved. Main branch on
> `origin` at `88cef97`; audit branch `audit/f2b-token-integrity` also
> at `88cef97` (merged forward). 17 commits lead upstream. **629/629
> tests pass, 0 failures** (1 unrelated Tavily live-network flake).

## 1. What's in `main` (round 1 → 11)

| Round | Commits | What shipped |
|-------|----------|---------|
| **R1-5** | pre-audit (`36b7c7c` and earlier) | KimiCode harness, ccusage benchmark harness, 7月 all-providers cost audit rollup, F2b CodexExtractor dedup fingerprint (PR #824 algorithm) |
| **R9**  | `54d9c5e` | `PricingTable.modelRate(for:)` switch covering GPT-5.6-sol/terra/luna, GPT-5.5/pro, GPT-5.4/pro/mini/nano, gpt-4o. `MonthCostCalculator.calculate` now prefers model-level rate over provider-level. |
| **R9**  | `2e0acc5` | handoff: round 9 — per-model OpenAI list price for GPT-5.x |
| **R10 M1** | `b87cbeb` | `CostEstimate { costRMB, usedFallback }` struct + `calculateWithSource` method. `hasUnknownPricing` flag tracks fallback rows correctly. |
| **R10 M2** | `73c707e` | `PayAsYouGoRate.currency: String` field makes the unit (CNY) explicit; default = "CNY" so existing call sites compile unchanged. |
| **R11**  | `388eb48` | `modelRate(for:)` adds kimi-k2-7-code entry. kimiCode 7月 cost moves from ¥639.12 (k2.6) to ¥733.02 (k2.7) — a ¥94 / 15% upward correction. |
| **R11 P2** | `88cef97` | Adds `MiniMax-M3` China-domestic list (¥4.20/¥0.84/¥16.80) and opencode-go deepseek routes ($1.74/$0.0145/$3.48 for V4-Pro, $0.14/$0.0028/$0.28 for V4-Flash). opencode 7月 cost moves from $153.58 to $307.01. |
| **R11 P2** | `88cef97` | Master report at `docs/handoffs/2026-07-12-f2b-7mo-cost-audit-all-providers.md` reflects the corrected numbers. |

## 2. Ground-truth 7月 12-day (2026-07-01..12) cost rollup

| Provider | USD-equivalent | Notes |
|----------|----------------:|-------|
| **claudeCode** | **$6,667.08** | Opus 4.8 1.3B input / 0 cache. User did not enable cache_control in 7月; 6月 mimo had 100% cache. |
| **Codex (codexCli)** | **$3,381.42** | GPT-5.5 ($1,835) + GPT-5.6-sol ($1,503) dominate; total cache_read 4.29B (47% of total). Round-8 dedup applied. |
| **opencode** | **$307.01** | MiniMax-M3 95% of total at China-domestic list (¥4.20/¥0.84/¥16.80) = $290.66. deepseek-v4-pro 4× the upstream rate via opencode-go = $5.36. mimo direct Xiaomi = $10.73. |
| **kimiCode** | **$107.96** | kimi-k2-7-code (¥6.50/¥1.30/¥27) — round 11 fix. ¥733.02. |
| kimiCli / zai / nanogpt | $0 | No in-window data. |
| **TOTAL (priced, USD-equivalent)** | **$10,463.47** | |

## 3. Schema gap surfaced (round 11 follow-up)

F2b `token_events` table has no `project_path` or `cwd` column. `ClaudeCodeExtractor` stores `sessionId` (UUID only), so we cannot break claudeCode spend down by project without re-extracting. This is the most expensive missing column. Round 11+ work.

## 4. Open follow-ups (round 11+)

1. **F2b schema**: add `max_input_in_event` (or `is_long_context`) column so the opencode MiniMax-M3 512K cliff can be priced per-row (currently a $290 nominal / $581 worst-case range).
2. **kiro CLI extractor**: `~/Library/Application Support/kiro-cli/data.sqlite3` — kiro uses its own SQLite, not `~/.claude/projects/`. Build a kiro extractor if kiro usage is to flow into F2a.
3. **zaiCodingPlan + nanogpt extractors**: F2b wiring in place but 7月 data is missing. Verify the local CLI tool was not used; if it was, the extractor path may be broken.
4. **deepseek "perception vs reality" gap**: the user reported deepseek as a primary model but F2b-recorded opencode data shows only 2.22M input for `deepseek-v4-pro`. If the user actually had more deepseek volume routed via a different upstream (c2cc / kiro / direct curl), `TokenNormalizer.matchProvider` may be mis-classifying those sessions. Add a model-level override list.
5. **claudeCode cache_control** (user action item): user should consider enabling cache_control on Opus prompts to halve the Opus bill ($6,611 → ~$3,300 in this window).
6. **MiniMax-M3 over-bill risk** (international users): the modelRate switch is wired with the China-domestic list (¥4.20/¥0.84/¥16.80). A user on the international `minimax.io` platform (with the permanent 50% promo) would be over-billed by ~2×. Either gate on `providerID` or accept the conservative estimate.

## 5. Methodology for next month (CTCA v1.0)

`docs/methodology/ctca-cli-token-cost-audit.md` (commit `59b6310`) is the source-of-truth procedure. 7-step:

1. **Pin the data source** — `F2b SQLite` at `$HOME/Library/Application Support/TokenKing/f2b.sqlite`, `token_events` table.
2. **Pull per-model breakdown** — `SELECT model, SUM(input/output/cache_read/...)` grouped by `model`.
3. **Look up each model's public list price** — `https://developers.openai.com/api/docs/pricing`, `https://www.anthropic.com/pricing`, `https://platform.minimaxi.com/docs/guides/pricing-paygo` (CNY), `https://platform.kimi.com/docs/pricing/chat-k27-code` (CNY), `https://opencode.ai/docs/go/`, etc.
4. **Currency unit** — every `PayAsYouGoRate` value is CNY per 1M tokens. USD public prices × FX 6.79 inside `modelRate(for:)`. **Tier trap**: Standard / Batch / Priority are 1× / 0.5× / 1.5–2× of each other.
5. **Run the cost query** — `LEFT JOIN` model_pricing to events; cost = (input/1M)*price_in + (cache_read/1M)*price_cache + (output/1M)*price_out.
6. **Subagent review** — spawn a `general-purpose` subagent to spot-check prices and tier against the public URL. Caught the Batch-vs-Standard tier mixup and the gpt-4o missing-from-modelRate bug.
7. **Write the report + memory** — `docs/handoffs/YYYY-MM-DD-f2b-<provider>-cost-audit.md`; cross-link to the round-11 master report at `docs/handoffs/2026-07-12-f2b-7mo-cost-audit-all-providers.md`.

## 6. Provenance chain (every doc committed this session)

| Path | Commit | What |
|------|--------|------|
| `docs/handoffs/2026-07-12-f2b-cache-semantics-final.md` | pre-audit | Round 1-5 (Cache semantics, MiniMax fix) |
| `docs/handoffs/2026-07-12-f2b-real-data-verification.md` | pre-audit | Round 6 (JSONL walk, KimiCode harness) |
| `docs/handoffs/2026-07-12-f2b-ccusage-bench-handoff.md` | pre-audit | Round 7 (ccusage benchmark harness) |
| `docs/handoffs/2026-07-12-f2b-ccusage-bench-7mo.txt` | pre-audit | 7月 baseline raw data |
| `docs/methodology/ctca-cli-token-cost-audit.md` | `59b6310` | CTCA v1.0 (7-step procedure) |
| `docs/handoffs/2026-07-12-f2b-f2a-model-pricing-round9.md` | `2e0acc5` | Round 9 handoff |
| `docs/handoffs/2026-07-12-f2b-7mo-cost-audit-all-providers.md` | `abde7ce`, `88cef97` | Master cost rollup (round 11 corrected) |
| `docs/methodology/ctca-cli-token-cost-audit.md` | `59b6310` | (above) |

## 7. Test state

- **629 tests, 19 skipped, 0 failures** (1 unrelated `TavilyLiveIntegrationTests` network flake).
- The `TavilyLiveIntegrationTests` flake is pre-existing and depends on
  Tavily API keys; not a regression from this work.
- New tests added in this work: 12+ in `PricingTableTests` (modelRate
  cases, alias tests, k2.7-code case, MiniMax/M3 case, opencode-go
  deepseek cases, lock-down list), 5 in `MonthCostCalculatorTests`
  (round-10 module-1 fallback contract), 2 in `CodexExtractorTests`
  (round-8 dedup fingerprint).

## 8. Working environment

- **Repo**: `git@github.com:smy126988-ai/token-king.git` (origin), `https://github.com/opgginc/opencode-bar.git` (upstream, do NOT push here).
- **Branch**: `main` and `audit/f2b-token-integrity` are at the same commit (`88cef97`). User's personal-dev workflow: direct commits to `main`, no PR.
- **Build**: `xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj -scheme CopilotMonitor -destination 'platform=macOS' test` (629 tests, ~12s).
- **Run app from source**: open `CopilotMonitor.xcodeproj` in Xcode 16+; the TokenExtractor tests run via `xcodebuild test` or the Xcode test navigator.
- **F2b SQLite** path: `$HOME/Library/Application Support/TokenKing/f2b.sqlite` (~41MB as of 2026-07-12). Tables: `token_events`, `day_aggregates`, `month_aggregates`, `model_pricing_cache`, `quota_snapshots`. Schema documented in `CopilotMonitor/Copilot/Helpers/TokenUsageStore.swift:17-45`.
- **SQL helper snippets** (copy-paste ready): see `docs/methodology/ctca-cli-token-cost-audit.md` section 5 for the per-model breakdown and cost query templates.

## 9. Where to start next session

The `f2b-token-integrity-next-chat-bootstrap.md` file in the same
directory is the prompt to paste when opening a new chat. It points
back here for context, but is self-contained.
