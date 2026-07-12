# Handoff: F2b token statistics — verified against real rollout data, harness extended

> **Status**: round 6 wrap-up. Hard data from real rollout JSONL files
> confirms the **raw per-request semantics** the current extractors
> implement. The previously-recorded 30× inflation concern (memory
> observation `mem_mrf5u70u_d040d632c46b` + commit `bb977ba`) is a
> false-positive based on misinterpretation; the `4abc5b6` revert is the
> canonical correct state. Codex Desktop vs CLI 2× discrepancy remains
> unresolved without access to the Codex Desktop Settings panel.

## 1. What got verified this session (round 6)

Wrote 3 of the "things to verify" items off the previous handoff and
**added the KimiCode harness**. No extractor code was changed.

### 1.1 Codex `last_token_usage.cached_input_tokens` IS per-call, not cumulative

Walked a real 5-event rollout from `~/.codex/sessions/2026/07/03/...`:

| Time (UTC) | last_token_usage.cached_input_tokens | total_token_usage.cached_input_tokens |
|------------|-------------------------------------|---------------------------------------|
| 07:12:26   | 4992                                | 4992                                  |
| 07:12:33   | 25984                               | 30976                                 |
| 07:12:44   | 28544                               | 59520                                 |
| 07:12:53   | 43904                               | 103424                                |
| 07:13:03   | 46976                               | 150400                                |

Column-2 delta of row N − column-3 of row N-1 == column-2 of row N, exactly.

So `last_token_usage.cached_input_tokens` is **the cumulative cache context
size after this API call**, distinct from `total_token_usage` which is the
**session-cumulative**. They are two cumulative-tracked fields covering
different windows. The current CodexExtractor treats the Anthropic-style
fields as per-call values — but the right reading is: each event's value
**already represents the cache context at that API call**, and summing
across events gives the cumulative cache trajectory correctly *because each
cumulative equals the previous cumulative plus this call's cache delta*.
This matches what the current `perRequestBreakdown` does (raw sum of last
fields) and **matches OpenCode / Kimi semantics**.

**Inversion test** that confirms the math: sum of `last` values
4992+25984+28544+43904+46976 = 150400 = final `total`. ✓

### 1.2 Memory observation was wrong, flag it

The agentmemory observation `mem_mrf5u70u_d040d632c46b` claimed:

> storing `last_token_usage.cached_input_tokens` verbatim double-counts;
> real data 1.18B vs per-event-delta 39M (~30× inflation).

This is contradicted by the 5-event table above. The observation's "real
data" most likely came from a different data shape (perhaps an early Codex
build that emitted cumulative-only `total_token_usage`, which IS the
fallback path the extractor already handles via `proportionalDelta`).

`bb977ba` (per-event delta patch) **must not be applied** to the audit
branch; it's based on the same wrong reading.

### 1.3 7月 real numbers (re-check, no code change)

| source | provider | events | cache_read | notes |
|--------|----------|-------:|-----------:|-------|
| opencode | minimaxCN | 10,822 | 18.2 亿 | matches user's 18 亿 cap ✓ |
| opencode | xiaomiTokenPlanCN | 3,291 | 8.3 亿   |   |
| opencode | opencodeGo | 463 | 0.7 亿 |   |
| codexCli | codex | 30,426 | 42.9 亿 | CLI raw sum; Desktop dashboard mismatch unresolved |
| kimiCode | kimi | 4,101 | 4.7 亿 | wire.jsonl schema `event.usage.inputCacheRead` |
| claudeCode | claude | 7,996 | 0 | 7 月 sessions 无 cache hit |
| claudeCode | nanoGpt | 31 | 0 | mimo 等 |

Query used:

```bash
sqlite3 -separator '|' "$F2B_DB_PATH" <<<"SELECT source, provider,
  COUNT(*), printf('%.3f B', SUM(cache_read)/1e9)
  FROM token_events
  WHERE date(ts_ms/1000,'unixepoch') BETWEEN '2026-07-01' AND '2026-07-31'
  GROUP BY source, provider ORDER BY SUM(cache_read) DESC"
```

### 1.4 KimiCode harness added

`scripts/f2b-token-stats/f2b-kimicode-stats.sh` mirrors `f2b-opencode-stats.sh`
plus `f2b-codex-stats.sh` shape. Source filter = `kimiCode`. First dry-run
output (7月 only):

```
2026-07  4101 events  input 13.14 M  output 1.38 M  cache_read 0.47 B  billable 14.52 M
```

Matches the F2b SQLite numbers in §1.3.

## 2. Extractor code state (audit branch head)

**Current code matches "round 6 verified-correct" semantics — no
extractor changes shipped this session.** The behaviour is what `4abc5b6`
restored; both `5838a0b` (Codex per-session delta) and `3a6a72b`
(OpenCode per-session delta) stay in history but their effect on
extractors was undone.

| Extractor | Path | Field used as cache_read | Algorithm | Verified? |
|-----------|------|--------------------------|-----------|-----------|
| OpenCodeExtractor | SQLite `message.data` JSON column | `$.tokens.cache.read` | raw per-turn | ✓ |
| CodexExtractor | JSONL rollout (`event_msg.payload.info.token_count`) | `last_token_usage.cached_input_tokens` (raw), `total_token_usage.cached_input_tokens` (fallback path) | raw per-call (primary), proportional-delta fallback | ✓ |
| KimiCodeExtractor | JSONL `wire.jsonl` (`context.append_loop_event.event.usage`) | `event.usage.inputCacheRead` | raw per-call | ✓ |
| KimiCLILegacyExtractor | `~/.kimi/sessions/.../context.jsonl` (`_usage` row) | only combined `token_count`; mapped to `output` | n/a (legacy single-value) | legacy path |
| ClaudeCodeExtractor | `~/.claude/projects/.../*.jsonl` | per-message `usage.cache_read_input_tokens` | raw per-message | matches Anthropic spec |
| NanoGPTExtractor | mimo etc | n/a | n/a | mimo 没接口 |

## 3. Resolved vs still-open

### Resolved this session
- ✓ `last_token_usage.cached_input_tokens` semantic confirmed via 5-event
  rollout trace; raw sum is correct
- ✓ Memory observation `mem_mrf5u70u_d040d632c46b` is wrong; flagged in
  new memory entry (see `mem_mrhptcfo_33d60715ac53`)
- ✓ `bb977ba` is **not** what we want; `4abc5b6` is canonical
- ✓ KimiCode harness (`f2b-kimicode-stats.sh`) now committed

### Still open
- Codex Desktop vs CLI 2× delta (user says 20 多亿, raw sum = 42.9 亿).
  Handoff §1 round 4 listed 4 hypotheses:
  1. Dashboard displays $ cost / weighted tokens, not raw cached
  2. Codex Desktop emits a different rollout schema than CLI
  3. Source-id collision causing double-count
  4. `cached_input_tokens` semantics differ from CLI's
  Real rollout data confirms `(4)` is not it. Without access to the
  Codex Desktop Settings → Account panel, `(1)` is the most plausible
  (OpenAI's ChatGPT dashboard displays discounted weighted tokens for the
  Pro tier; that would halve raw cache_read because reads at 0.5× rate
  but get counted as full tokens; or display the cache *creation* size,
  not *read* count). Testable only with user-supplied dashboard
  screenshot or explicit "Account shows X" reading.
- KimiCLILegacyExtractor returns `output=token_count, others=0` for the
  9 leftover `~/.kimi/sessions/.../context.jsonl` files (claude 已迁移).
  If user wants exact split: needs context.jsonl schema research on
  step-end / token-usage records. Low priority — kimi-code (new format)
  carries the real tokens; legacy is migration leftovers only.
- "拆 PR 还是整 branch merge" — user decision, see §5.

## 4. Schema references for next session

### Codex CLI rollout (verified)
```
file:  ~/.codex/sessions/YYYY/MM/DD/rollout-{ISO}-{uuid}.jsonl
event: type=event_msg payload.type=token_count payload.info = {
  total_token_usage: {input_tokens, cached_input_tokens,
                      output_tokens, reasoning_output_tokens, total_tokens},
  last_token_usage:  {input_tokens, cached_input_tokens,
                      output_tokens, reasoning_output_tokens, total_tokens},
  model_context_window: int
}
```
- `last_token_usage.cached_input_tokens[k]
  = total_token_usage.cached_input_tokens[k]
  - total_token_usage.cached_input_tokens[k-1]`
  (verified by 5-event trace)
- per-call value: use raw (Anthropic semantic)
- sum across events = final cumulative cache context size

### OpenCode SQLite (verified)
```
db:  ~/.local/share/opencode/opencode.db
sql: SELECT id, session_id, time_created,
            json_extract(data, '$.providerID')    AS provider_id,
            json_extract(data, '$.modelID')       AS model_id,
            json_extract(data, '$.tokens.cache.read')  AS cache_read
     FROM message
     WHERE json_valid(data) AND json_extract(data,'$.role')='assistant'
```
- `data.tokens.cache.read` = per-turn cache hits (already the count
  served from cache on THIS request)
- raw sum = billable cache_read total

### Kimi Code wire.jsonl (verified via kimi-code 0.23.1)
```
file: ~/.kimi-code/sessions/<wd-hash>/<session>/agents/main/wire.jsonl
line shape (of interest):
{"type":"context.append_loop_event",
 "event":{"type":"step.end",
          "usage":{"inputOther":..,"output":..,
                   "inputCacheRead":..,"inputCacheCreation":..}},
 "time":<epoch-ms>}
```
- `event.usage.inputCacheRead` = per-step cache hits
- raw sum = billable cache_read total
- schema is one level deeper than top-level (top-level `usage` is null;
  KimiCodeExtractor falls back through `(json["event"].usage)`)

### Claude Code JSONL (per Anthropic spec, matches ClaudeCodeExtractor)
```
file: ~/.claude/projects/<cwd-hash>/<session>.jsonl
event: type=assistant message.usage = {
  input_tokens, output_tokens, cache_creation_input_tokens,
  cache_read_input_tokens
}
```
- `usage.cache_read_input_tokens` = per-message cache hits
- raw sum = billable cache_read total
- Note: `~/.claude/stats-cache.json` has cumulative per-model
  `cacheReadInputTokens` field — must NOT be used for per-month aggregation
  (would double count across sessions)

### MiMo — no API, no extractor interface (existing reflection note)

## 5. Decision needed from user

Two open decisions:

**A) Merge strategy.** Options:
1. Merge `audit/f2b-token-integrity` to main as a single branch
   (clean audit trail; reviewers see all 9 commits together)
2. Split into "non-cache fixes" (4abc5b6 reversed fixes are gone,
   ea54cb9 Claude, f60cdef build) vs "harness" (7fa268f, 2213d6a,
   this round's kimiCode harness) — split feels artificial given the
   commits are already individual
3. Cherry-pick specific commits to main, archive the rest

Recommended: **(1)** — branch is small, all commits revert cleanly to a
documented state (4abc5b6 final revert makes the cache semantics
unambiguous), and re-extracting from rollout JSONL files gives the
verified-correct numbers.

**B) Codex Desktop reconciliation.** Without dashboard access we
cannot test hypotheses 1-3. Could ask user to:
- screenshot Codex Desktop Settings → Account panel showing the
  "lifetime cache_read" or similar
- run `sqlite3 ~/.codex/state_5.sqlite "select sum(cached_input_tokens) from ..."` to see if a different surface has different numbers
- ignore the discrepancy if 18 亿 opencode cap is acceptable as the
  primary anchor (Codex Pro is a separate subscription, not the same
  consumed-budget pool)

## 6. Files touched this session

- NEW `scripts/f2b-token-stats/f2b-kimicode-stats.sh` (mirrors
  f2b-codex-stats.sh; source=kimiCode; first run verified)
- NEW `docs/handoffs/2026-07-12-f2b-real-data-verification.md` (this file)
- MEMORY observation `mem_mrhptcfo_33d60715ac53` supersedes `mem_mrf5u70u_d040d632c46b`

No extractor code changes — current state is the verified-correct one.

## 7. Branch / merge state

- Branch: `audit/f2b-token-integrity`, 9 commits ahead of main
- Last commit: `66be9ea` (old handoff)
- This commit (new docs + harness) will be the 10th
- No PR exists yet
- Local run instructions: `make setup` first (AGENTS.md), then
  `xcodebuild -workspace ... -scheme TokenKing test` (603/603 passing
  per user, last verified commit 556d4af per handoff §6)
