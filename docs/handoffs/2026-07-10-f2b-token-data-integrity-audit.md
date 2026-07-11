# Handoff: F2b Token Data Integrity Audit & Re-extraction

> **Status**: PR `feat/f1-f3-f4-token-stats` (commit 792ab15) has been merged/closed (or marked stale). Current F2b DB at `~/Library/Application Support/TokenKing/f2b.sqlite` has data integrity issues that the next session must fix.
>
> **Goal of next session**: Audit each token-tracking tool independently. For each, verify: (a) where data lives, (b) what fields it exposes, (c) whether fields are cumulative or per-event, (d) what the correct extraction formula is. Then fix the extractor + re-purge and re-scan.

---

## 1. Why this handoff exists

The F1/F3/F4 implementation went through 13+ commits trying to fix data quality issues. The user reported "全乱了已经" (everything is messed up). Key takeaway: **the F2b data in the local DB is not trustworthy for any provider** — every tool's token data has at least one bug. Each commit fixed one issue but new ones surfaced, and the data is now in an inconsistent state across providers.

A clean audit is needed. The next session's job is to:

1. **For each tool**, verify what fields the source tool produces and whether they're cumulative or per-event.
2. **For each extractor**, validate the extraction logic against the tool's real source data.
3. **Plan a migration**: for each tool, delete the misclassified rows, re-extract with the fixed extractor, validate.
4. **Don't touch the current PR's commits** — they may or may not be salvageable. Start fresh with validated extraction logic.

---

## 2. The 7 token-tracking tools in Token King

Each tool has a corresponding F2b extractor in `CopilotMonitor/CopilotMonitor/Helpers/TokenExtractor/`.

| Tool / Source | Extractor file | Source path | Source format | Per-event or Snapshot | API key source |
|---|---|---|---|---|---|
| OpenCode | `OpenCodeExtractor.swift` | `~/.local/share/opencode/opencode.db` | SQLite, `message` table with JSON `data` blob | **Per-event** (one row per assistant turn) | None (no auth) |
| Claude Code | `ClaudeCodeExtractor.swift` | `~/.claude/projects/**/*.jsonl` | JSONL, `assistant` rows | **Per-event** | None |
| Codex CLI | `CodexExtractor.swift` | `~/.codex/sessions/**/rollout-*.jsonl` | JSONL, `event_msg` with `payload.info.total_token_usage` / `last_token_usage` | **Per-event**, but values are CUMULATIVE inside the session | None |
| Kimi CLI (legacy) | `KimiCLILegacyExtractor.swift` | `~/.kimi/sessions/**/*.jsonl` | JSONL with `_usage` role | **Per-event** (but no timestamp — only token_count) | None |
| Kimi Code (new) | `KimiCodeExtractor.swift` | `~/.kimi-code/sessions/**/wire.jsonl` | JSONL with `inputOther` / `cacheRead` / `output` fields | **Per-event**, but `cacheRead` is CUMULATIVE within a session | None |
| ZAI API | `ZAIExtractor.swift` | `https://api.z.ai/api/coding/paas/v4/usage/list` | HTTP API, returns monthly usage | **Snapshot** (one fetch = one event) | `Z_AI_API_KEY` env / UserDefaults |
| NanoGPT API | `NanoGPTExtractor.swift` | `https://nano-gpt.com/api/subscription/v1/usage` | HTTP API, returns monthly usage | **Snapshot** (one fetch = one event) | `NANOGPT_API_KEY` env / UserDefaults / `~/.nanogpt/token` / `~/.config/nanogpt/token` |

---

## 3. Field-level audit (the heart of this handoff)

For each tool, the audit must verify:

| Field | Cumulative or per-event? | If cumulative, can we compute delta from consecutive events? | Where in source |
|---|---|---|---|
| `input` | (varies by tool — see below) | | |
| `output` | (varies) | | |
| `cacheRead` | (varies — likely cumulative) | | |
| `cacheWrite` | (varies) | | |
| `reasoning` | (varies) | | |

### 3.1 OpenCode — `OpenCodeExtractor.swift`

- **Source**: `~/.local/share/opencode/opencode.db`, table `message` with column `data` (JSON blob)
- **JSON shape varies by version**:
  - **Old schema** (~v1): `data.model.providerID` + `data.model.modelID` on assistant message
  - **New schema** (~v2+): `data.modelID` (top-level camelCase) on assistant message; `data.model.providerID` only on parent user message; `data.parentID` to link them
- **Token fields** in `data.tokens`:
  - `input` — fresh input (non-cached) for this turn
  - `output` — output tokens for this turn
  - `cache.read` — **CUMULATIVE** size of cached context at end of this turn (grows over session)
  - `cache.write` — **CUMULATIVE** size of cache writes
  - `reasoning` — reasoning tokens for this turn
- **Delta computation**: per session, track previous `cache.read` and `cache.write`, compute `delta = max(0, current - previous)`. For first event, treat full value as delta (entire cache was created this turn).
- **Real-world issue seen**: when new schema `data.model.providerID` is NULL on assistant messages, the old SQL `json_extract(data, '$.model.providerID')` returns NULL → `TokenNormalizer.matchProvider` defaults to `.nanoGpt` (fallback). Fix: use LEFT JOIN to parent message and read `u.data.model.providerID` instead.
- **Test data to validate against**: use the user's actual `~/.local/share/opencode/opencode.db` (~16,693 events across multiple sessions). Sample 3-4 sessions, verify that the extracted events have:
  - non-empty `providerID` matching the user's actual OpenCode provider config (e.g., `kimi`, `minimax-cn`, `xiaomi-token-plan-cn`, `opencode-go`, `opencode`)
  - per-event `cache.read` deltas (not cumulative)
  - correct `model` matching what the user typed

### 3.2 Claude Code — `ClaudeCodeExtractor.swift`

- **Source**: `~/.claude/projects/**/*.jsonl`
- **Format**: each line is a JSON object with `role: "assistant"`, `usage: {input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens}` (Anthropic API format)
- **Field semantics**:
  - `input_tokens` — fresh input for this turn
  - `output_tokens` — output for this turn
  - `cache_creation_input_tokens` — cache writes (cumulative session)
  - `cache_read_input_tokens` — cache reads (cumulative session)
- **Critical**: `cache_creation_input_tokens` and `cache_read_input_tokens` are CUMULATIVE. Need per-session delta.
- **Test data**: use the user's `~/.claude/projects/*/*.jsonl` files. Each file is one session. Verify per-session `cache_read_input_tokens` grows monotonically, `cache_creation_input_tokens` grows (or stays).
- **Known bug**: was parsing ISO 8601 wrong (using `Double(s)` which only works for epoch seconds). Fixed in commit `4cf1f24`. Need to verify the fix produces correct timestamps.

### 3.3 Codex CLI — `CodexExtractor.swift`

- **Source**: `~/.codex/sessions/**/rollout-*.jsonl`
- **Format**: each line is a JSON object. `event_msg` with `payload.info.total_token_usage` (CUMULATIVE session total) and `payload.info.last_token_usage` (per-event delta from previous call).
- **Field semantics**:
  - `total_token_usage.input_tokens` — **CUMULATIVE** session input
  - `total_token_usage.cached_input_tokens` — **CUMULATIVE** cache size
  - `total_token_usage.output_tokens` — cumulative output
  - `total_token_usage.reasoning_output_tokens` — cumulative reasoning
  - `last_token_usage.*` — per-event delta (new tokens billed in this call). Use these.
- **Critical**: Use `last_token_usage` for per-event values, NOT `total_token_usage`. The previous bug was reading `total_token_usage` (cumulative) and storing as per-event.
- **Test data**: use the user's `~/.codex/sessions/2026/07/10/rollout-*.jsonl` (or any recent). Look for a long session with `last_token_usage` non-zero values. Each should be 1-10K tokens (real per-event cost), NOT 200K (cumulative cache size).
- **ISO 8601 timestamps**: commit `4cf1f24` added `ISO8601DateFormatter` with fractional seconds. Verify on user's data.

### 3.4 Kimi CLI legacy — `KimiCLILegacyExtractor.swift`

- **Source**: `~/.kimi/sessions/<workspace-hash>/<sessionId>/context.jsonl`
- **Format**: each line is a JSON object with `role: "_usage"`, `token_count` (single field — no breakdown)
- **Field semantics**:
  - `token_count` — single number, no input/output/cache split
- **No timestamp in the data** — must fall back to file mtime. Commit `1a1d458` added this fallback.
- **All token_count stored as `output`** in `TokenBreakdown` (legacy schema can't split). Document this limitation.
- **Test data**: use the user's `~/.kimi/sessions/*/context.jsonl`. Verify file mtime is reasonable (corresponds to last write time of file).

### 3.5 Kimi Code (new) — `KimiCodeExtractor.swift`

- **Source**: `~/.kimi-code/sessions/<workspace-hash>/<sessionId>/agents/main/wire.jsonl`
- **Format**: each line is a JSON object with `inputOther`, `output`, `cacheRead`, `cacheWrite`, `cacheRead`, etc.
- **Field semantics**:
  - `inputOther` — fresh input (non-cached)
  - `output` — output tokens
  - `cacheRead` — **CUMULATIVE** cache size (grows)
  - `cacheWrite` — **CUMULATIVE** cache writes
- **Need per-session delta**: track previous `cacheRead` and `cacheWrite`, compute delta.
- **Test data**: use the user's `~/.kimi-code/sessions/*/wire.jsonl`. Verify per-session `cacheRead` grows monotonically.

### 3.6 ZAI API — `ZAIExtractor.swift`

- **Source**: HTTP API
- **Format**: returns monthly usage snapshot (not per-event)
- **Stores one event per fetch** with `sourceId="zai:api:snapshot:month"`. The F2b design intent: snapshot data, not events.
- **Test data**: hit the API, verify the response shape matches what ZAIExtractor reads.

### 3.7 NanoGPT API — `NanoGPTExtractor.swift`

- **Source**: HTTP API
- **Format**: returns monthly usage snapshot
- **Same pattern as ZAI** — one event per fetch.
- **Known bug**: writes a new event every fetch (due to `INSERT OR IGNORE` + unique sourceId). Should be `INSERT OR REPLACE` (upsert). The current 16,693 rows in F2b (where `provider='nanoGpt'` was the misclassification result from OpenCode) are unrelated to this extractor — they're OpenCode events that landed in the wrong bucket.
- **Test data**: hit the API with a known key, verify snapshot behavior.

---

## 4. Current data state (in `~/Library/Application Support/TokenKing/f2b.sqlite`)

Quick stats from recent audit (approximate, will change as user uses more):

| Provider | Events | Notes |
|---|---|---|
| codex | ~30,000 | Likely still has cumulative bug for cacheRead (depends on whether user re-scanned after `bb977ba`) |
| claude | ~5,000 | OK after `4cf1f24` |
| opencode (raw count) | ~16,000 | All mis-classified to `provider='nanoGpt'` due to SQL bug — should be split into `kimi` / `minimaxCN` / `xiaomiTokenPlanCN` / `codex` / `claude` per the user's actual OpenCode config |
| nanoGpt (stale rows) | ~16,000 | Will disappear after purge — never reappear (re-scan with `TokenNormalizer` rules will route to correct providers) |
| kimi | ~10,000 | Possibly mis-routed from old `mimo-` shadowing xiaomi (some events with model=`mimo-v2.5-pro` may have gone to `.minimaxCN` when should be `.xiaomiTokenPlanCN`) |
| minimaxCN | ~13,000 | Includes some events that should be `.xiaomiTokenPlanCN` per the mimo bug |
| minimax | 1 | Edge case |
| kimiCli | ~0-200 | Stale, file-mtime fix applied |

The 7月 53.76亿 number is unreliable — it includes many opencode/nanoGpt mis-classified rows.

---

## 5. Migration plan (the concrete next-session tasks)

### Task A: For each tool, write a test fixture extractor

For each of the 7 extractors, write a unit test that:
1. Creates a temp source file/db with 3-5 hand-crafted events matching the real source format
2. Includes a "cumulative cache" pattern (e.g., 100K → 150K → 220K) to verify the extractor computes deltas correctly
3. Asserts the per-event `TokenBreakdown` is correct
4. Asserts the `provider` (F2b `Provider` enum case) is correct per the user's actual config

Use the **user's actual config** as ground truth. The user uses:
- OpenCode with providers: `kimi`, `minimax-cn` (probably `xiaomi-token-plan-cn` too), maybe `opencode-go`, `claude`, `minimax` (global)
- Codex CLI (OpenAI)
- Claude Code (Anthropic)
- Kimi CLI (Moonshot) and Kimi Code

### Task B: For each tool, validate against real source data

For each tool, pick 1-2 real sessions from the user's local data and:
1. Run the extractor
2. Compare output to expected values (manually compute from raw source for at least 3 events)
3. Document the correct extraction formula in code comments
4. Fix any bugs found

### Task C: Purge all data and re-scan

After all extractors are validated:

```sql
-- Wipe token_events and re-scan from scratch
DELETE FROM token_events;
DELETE FROM day_aggregates;
DELETE FROM month_aggregates;
```

Then re-launch the app. RefreshActor will re-extract from each source with the fixed logic. Resulting `day_aggregates` / `month_aggregates` should match the user's actual usage per provider per model.

### Task D: Validate the final numbers

After re-scan:
1. Compare against the user's mental model ("I used ~X GPT tokens today", "I used ~Y MiniMax tokens this week")
2. Check that cache sums make sense (cumulative context size, not per-event cache hits)
3. Verify no provider has suspiciously high totals (which would indicate double-counting)

### Task E: Build a verification test

Add an end-to-end test that loads a snapshot of the user's actual data and asserts the F2b aggregate totals match expected (within tolerance for newly-written events between the snapshot and the test run). This guards against regressions.

---

## 6. Out of scope (do NOT touch)

- The F1/F3/F4 UI changes (Top-level "今日 Token" menu, "按量付费" section, etc.) are FINE — the issue is the data, not the UI
- The general ProviderIdentifier enum (kimi, kimiCN, claude, codex, zai, minimax, minimaxCN, nanoGpt, xiaomi, xiaomiTokenPlanCN) is FINE — the cases are correct, just the routing logic was wrong
- The displayName strings (MiniMax, Kimi, etc.) are FINE
- The SubscriptionsSettings, MenuDesignToken subsystem, etc. are FINE
- The billing calculation (¥/token) is FINE
- The current `feat/f1-f3-f4-token-stats` PR commits may be salvageable as a base, but DO NOT push more commits there until the audit is complete. Consider opening a new branch like `audit/f2b-token-integrity` from the latest stable main.

---

## 7. Useful files to read first (in the next session)

- `CopilotMonitor/CopilotMonitor/Helpers/TokenEvent.swift` — `TokenBreakdown` struct (the 5 fields)
- `CopilotMonitor/CopilotMonitor/Helpers/TokenNormalizer.swift` — `matchProvider` (routing rules)
- `CopilotMonitor/CopilotMonitor/Helpers/TokenUsageStore.swift` — schema + queries
- `CopilotMonitor/CopilotMonitor/Helpers/TokenExtractor/*.swift` — 7 extractors
- `CopilotMonitor/CopilotMonitorTests/Helpers/TokenExtractor/*Tests.swift` — existing test patterns
- The user's actual data: `~/.local/share/opencode/opencode.db`, `~/.claude/projects/*/*.jsonl`, `~/.codex/sessions/**/rollout-*.jsonl`, `~/.kimi/sessions/*/context.jsonl`, `~/.kimi-code/sessions/*/wire.jsonl`

---

## 8. Open questions for the user (ask before starting)

1. The user uses 5-6 OpenCode providers per session. Which ones? (This determines what the routing logic must support.)
2. Does the user actually pay for nanoGPT / zAI? If not, those extractors can be disabled by default (similar to `.kiro`).
3. The user wants a single F2b that aggregates all sources per session (a session in OpenCode = a session in Codex = same user activity). Do we need cross-tool session correlation, or just per-tool session-level aggregation? (The current design is per-tool; cross-tool would be a v2.)

---

## 9. Recommended starting order for the next session

1. Read this handoff fully (you're doing it now)
2. Run `sqlite3 ~/Library/Application\ Support/TokenKing/f2b.sqlite ".schema token_events"` to see the schema
3. Run `sqlite3 ~/Library/Application\ Support/TokenKing/f2b.sqlite "SELECT provider, source, COUNT(*), SUM(input+output+cache_read+cache_write+reasoning) FROM token_events GROUP BY provider, source"` to see the current distribution
4. Open the user's 5-6 real OpenCode sessions from `~/.local/share/opencode/opencode.db` and pick 3 events to manually compute expected values (input, output, cache, model, provider). This gives the ground truth.
5. Write a focused test for ONE extractor (suggest `KimiCodeExtractor` — clear schema, well-bounded), validate against real data, fix any bugs
6. Repeat for the other 6 extractors
7. Once all extractors produce correct per-event values, do a single migration: `DELETE FROM token_events;` + re-launch app + verify aggregated totals match user's mental model
8. Commit each fix on a clean branch (don't pile onto the messy `feat/f1-f3-f4-token-stats`)

---

## 10. Final state for the user to confirm

Before starting the next session, the user should:
- Decide whether to revert `feat/f1-f3-f4-token-stats` PR's commits OR keep them as a base
- Decide whether to close that PR and start fresh
- Verify the 28+ uncommitted files in the working tree are either committed separately or discarded (they are NOT related to this audit; they're from other in-flight work like B39, F2b init error fixes, etc.)

When ready, the next session should read this handoff first, then start with Task A (write a focused test for one extractor).
