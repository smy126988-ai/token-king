# Handoff: F2b cache semantics — final state, Codex unresolved

> **Status**: session cleanup. MiniMax/MiMax bug fixed end-to-end and
> validated against user's 18亿 cap expectation. Codex 42亿 vs user's
> "20多亿" expected is **NOT** fully resolved. Other tools (Claude, Kimi)
> are partial fixes. This document records what is known, what is fixed, and
> what the next session should still verify.

## 1. What changed this session (5 audit rounds)

Round 1 — OpenCode schema research:
Found authoritative source code in `anomalyco/opencode`
(`packages/opencode/src/session/session.ts#getUsage`):
- `cache.read = Anthropic cacheReadInputTokens per-request` (NOT cumulative
  session state)
- `cache.write = tokens newly added to cache this request`
- `input = total - cache_read - cache_write` (fresh non-cached)
- `output - reasoning` (output net of reasoning tokens)
- `last_token_usage` REPLACES per step-finish; `total_token_usage` accumulates
  (OpenCode stores only the per-message value).

Round 2 — Codex schema research:
Found authoritative source code in `openai/codex`
(`codex-rs/protocol/src/protocol.rs`):

  pub struct TokenUsage {
      pub input_tokens: i64,
      pub cached_input_tokens: i64,    // OpenAI cache hits per call
      pub output_tokens: i64,
      pub reasoning_output_tokens: i64,
      pub total_tokens: i64,
  }

`last_token_usage` is REPLACED per event (per-request semantics). Sum across
messages = total cache hits billed. Same model as OpenCode.

Round 3 — revert wrong cache delta:
Both OpenCode and Codex extractors previously applied an incorrect
"per-session cumulative → delta" conversion to cache.read / cache.write /
cached_input_tokens. The conversion was based on a misinterpretation of the
naturally-growing per-request cache footprint. Reverted to raw per-request
semantics. Verified by:

  before revert (minimaxCN 7月 cache_read):  80 M  (delta'd)
  after  revert (minimaxCN 7月 cache_read):  1.82 B = 18.2亿
  user-reported cap expectation:                18亿
  → matches user mental model. ✓

Round 4 — Codex user reported discrepancy:
User states actual Codex 7月 usage is "20多亿" tokens. Two independent
verifications of rollout files both report:

  raw rollout files summed:  3.887 B = 38.9亿 cached_input_tokens
  F2b extractor sum:        4.293 B = 42.9亿 cached_input_tokens
  user-stated expected:     ~20多亿

**Discrepancy: 22亿 (2× my number).** Root cause still unknown. Possibilities:

  (a) Codex Desktop's dashboard displays $ cost or weighted tokens rather
      than raw `cached_input_tokens`. User is reading $ or weighted value.
  (b) Codex Desktop emits a different rollout schema than CLI. The files I
      read might be a superset of what Desktop actually bills.
  (c) Some rollout events are double-counted in F2b (source_id collision I
      haven't found).
  (d) OpenAI's `cached_input_tokens` is not what I think it is (per-request
      cache hits). Could be cumulative session state cached_tokens at time
      of request, which would inflate by the same ~2× as we saw in OpenCode
      earlier.

Round 5 — install Codex CLI:
User asked me to install Codex CLI to verify quota locally. Installed
`@openai/codex` via `npm install -g` to `~/.npm-global/bin/codex`. **No
built-in /quota or /status command** (slashes are session-only inside the
REPL). User will need to check https://chatgpt.com/codex/usage or the
Desktop Settings → Account panel manually.

## 2. Final 7月 (11天) data — round 3 fix applied

F2b 7月 after raw-per-request fix (output rounded):

| source | provider | events | input | cache_read | output |
|---|---|---|---|---|---|
| opencode | minimaxCN | 10,822 | 85 M | **18.2亿** | 5.3 M |
| opencode | xiaomiTokenPlanCN | 3,291 | 16 M | 8.3亿 | 0.9 M |
| opencode | opencodeGo | 463 | 2.4 M | 0.7亿 | 0.2 M |
| codexCli | codex | 30,426 | 199 M | **42.9亿** ⚠ | 9.2 M |
| kimiCode | kimi | 4,101 | 13 M | 4.7亿 ⚠ | 1.4 M |
| claudeCode | claude | 7,996 | 1357 M = 13.6亿 | 0 | 4.2 M |
| claudeCode | nanoGpt (mimo etc) | 31 | 0 | 0 | 0 |

⚠ — codexCli / kimiCode cache_read semantics unverified against ground
truth. See §3.

## 3. Open questions for the next session

1. **Codex 42亿 vs user 20亿** — needs verification against the actual
   Codex Desktop Usage panel. Determine whether `cached_input_tokens` is
   per-request (Anthropic semantic) or cumulative (OpenCode's old
   interpretation that I just reverted). If per-request, my number is
   right and the user is reading a different field. If cumulative, the
   CodexExtractor needs the same per-session-delta revert that the
   pre-fix-3 version had (but only for Codex, not OpenCode).

2. **KimiCode cache_read 4.7亿** — Kimi Code CLI stores tokens in
   `wire.jsonl` with `inputOther/output/inputCacheRead/inputCacheCreation`
   fields. The `inputCacheRead` field semantic needs verification
   against Kimi's Rust source (`kimi-code` repo). If per-request, current
   F2b storage is right. If cumulative, KimiCodeExtractor needs the
   same fix as OpenCode had.

3. **ClaudeCode 7月 cache_read = 0** — this matches the raw data
   (Claude 7月 sessions had 0 cache hits, while 6月 had 12.86亿). Not a
   bug, but the asymmetry between months is worth a sanity check.

4. **Harness scripts** (`scripts/f2b-token-stats/*.sh`) need a final
   pass to confirm the output format still works after the schema change.
   OpenCode harness prints "B" for cache_read (e.g., `1.82 B = 18.2亿`)
   which is correct. Codex harness was not built. KimiCode harness
   not built. Should be added in a follow-up if other tools stay on
   raw per-request semantics.

## 4. Reference: what is fixed in this branch

`audit/f2b-token-integrity` (5 commits + handoff doc):

- `f60cdef` Build infra (TimeZone+UTC, TimeWindow, test files)
- `556d4af` OpenCode: top-level providerID/modelID + session_id from SQL
- `3a6a72b` OpenCode: cache fields converted to per-session delta  *(LATER REVERTED)*
- `2213d6a` OpenCode harness
- `7fa268f` Handoff doc + dead mimo code removed + SQL injection guard
- `5838a0b` Codex: per-session delta for cumulative cache + ISO 8601  *(LATER REVERTED)*
- `ea54cb9` Claude: line-index sourceId + model-based routing + ISO 8601
- `4abc5b6` OpenCode + Codex: REVERT cumulative-to-delta cache conversion
        (the 1-line fix that realigned MiniMax with the 18亿 cap)

The two "convert to delta" commits (3a6a72b, 5838a0b) are kept in history
for traceability but their EFFECT on extractor code was undone in
4abc5b6. The 4abc5b6 commit is the canonical "right answer".

## 5. Tasks for the next session

- Verify Codex cache_read against actual Codex Desktop Usage panel
- Verify KimiCode cache_read against Kimi Rust source
- Add `f2b-codex-stats.sh` and `f2b-kimicode-stats.sh` harnesses
- Decide whether to merge `audit/f2b-token-integrity` to main as-is or
  split into "OpenCode+ClaudeCode+Codex route fixes" (the high-confidence
  fixes) vs "Codex cache semantics fix" (the uncertain one) for review

## 6. User's intent going forward

Per the last message: "写handoff，我们要clear" — write handoff, we should
clear (wrap up). This document is the wrap-up. Do not start new extractor
work in this session; remaining items go to the next session.
