# F2b Token Audit — New Chat Bootstrap Prompt

> **Purpose**: paste everything below the `--- BOOTSTRAP ---` line into
> a fresh chat to get back up to speed in one shot. The pre-context
> this file gives the assistant: who you are, what you worked on,
> where the artifacts live, and what to do first.

---

## BOOTSTRAP — paste below here into a fresh chat

You are picking up the F2b token-stats audit on the Token King
macOS app (a Swift fork of `opgginc/opencode-bar` maintained by the
user at `smy126988-ai/token-king`). Round 1 through 11 closed at
commit `88cef97` on `main` and `audit/f2b-token-integrity`. The full
methodology + 4-issue user-feedback resolution + final 7月 12-day
cost rollup is at:

  - `docs/handoffs/2026-07-13-f2b-round11-final.md` (status snapshot)
  - `docs/methodology/ctca-cli-token-cost-audit.md` (7-step procedure)
  - `docs/handoffs/2026-07-12-f2b-7mo-cost-audit-all-providers.md` (master audit)
  - `docs/handoffs/2026-07-12-f2b-f2a-model-pricing-round9.md` (round 9)
  - `docs/handoffs/2026-07-12-f2b-ccusage-bench-handoff.md` (round 7)
  - `docs/handoffs/2026-07-12-f2b-cache-semantics-final.md` (rounds 1-5)

Read those first; they cover what was done, why, what's open, and
the F2a/F2b cost flow.

### User profile — how to work with this user

- **Personal developer, not a team.** Workflow is direct commits to
  `main` (no PR). The `audit/f2b-token-integrity` branch exists for
  isolation during deep work, but is fast-forward-merged to `main`
  at the end of each round.
- **Repository boundaries**: push to `origin` (`smy126988-ai/token-king`)
  only. **Do NOT push to `upstream`** (`opgginc/opencode-bar`) — that
  is the upstream public repo, out of scope. Always confirm the
  remote before pushing.
- **Language preference**: Chinese for chat / handoffs / commit
  messages in 中文 context, English for code comments / commit body
  on the audit branch. The handoffs on disk are in 中文 with English
  code identifiers.
- **Style**: direct, terse, no preamble. Lead with findings, then
  evidence. Use real data (`jq`, `sqlite3`, raw JSONL) — not
  assumptions — to back every claim. When in doubt, the user wants
  you to look it up rather than ask.
- **Per-module workflow**: the user asked for TDD + subagent review +
  context7 per module. Each round is shipped as one or more commits
  on `audit/f2b-token-integrity` and merged to `main` at the end.
- **Subagent template**: spawn `general-purpose` (NOT `general-purpose`
  — the correct type name is `general`) for QA reviews. The review
  prompt should include: file:line, severity, one-sentence
  justification, ≤30 lines. Subagents caught real bugs (Batch-vs-
  Standard tier mixup, gpt-4o missing from modelRate switch, MiniMax
  international-vs-China price confusion).

### Project state at handoff (commit 88cef97)

- **Branch**: `main` (and `audit/f2b-token-integrity` are at the same
  commit). Origin: `smy126988-ai/token-king`. Upstream: do NOT push.
- **Tests**: 629 pass, 19 skipped, 0 failures. (1 unrelated Tavily
  network flake.) Run: `xcodebuild -project
  CopilotMonitor/CopilotMonitor.xcodeproj -scheme CopilotMonitor
  -destination 'platform=macOS' test`.
- **F2b SQLite**: `$HOME/Library/Application Support/TokenKing/f2b.sqlite`.
  Schema in `CopilotMonitor/Copilot/Helpers/TokenUsageStore.swift:17-45`.

### 7月 12-day (2026-07-01..12) ground-truth cost rollup

| Provider | USD-equivalent | Key note |
|----------|----------------:|-------|
| **claudeCode** | **$6,667.08** | Opus 4.8 1.3B input / 0 cache. User did not enable cache_control in 7月 (6月 mimo had 100% cache). |
| **codexCli** | **$3,381.42** | GPT-5.5 ($1,835) + GPT-5.6-sol ($1,503) dominate. Round-8 dedup applied. |
| **opencode** | **$307.01** | MiniMax-M3 95% at China-domestic list (¥4.20/¥0.84/¥16.80) = $290.66. deepseek-v4-pro 4× upstream rate via opencode-go = $5.36. mimo direct = $10.73. |
| **kimiCode** | **$107.96** | kimi-k2-7-code (¥6.50/¥1.30/¥27) — round 11 fix. |
| **TOTAL (priced)** | **$10,463.47** | |

### The 4 critical user-flagged issues, all resolved

1. **claudeCode cache_read=0**: real. User switched from mimo (6月, 100%
   cache hit) to opus-4.8 (7月, 0 cache) without enabling cache_control
   on the new model. F2b is not under-counting.
2. **MiniMax-M3 at $141 was wrong**: international minimax.io publishes
   a permanent 50% promo ($0.30/$0.06/$1.20); the user has a direct
   China-domestic key, so the China list applies (¥4.20/¥0.84/¥16.80,
   ≈ $0.62/$0.12/$2.47 per 1M after FX). MiniMax 7月: $141 → $290.66.
3. **kimiCode was using kimi-k2.6, should be kimi-k2-7-code**:
   kimiCode 7月 cost moves ¥639.12 → ¥733.02 (¥94 / 15% upward
   correction, because the k2-7-code cache rate is ¥1.30/M vs k2-6's
   ¥1.10/M).
4. **opencode-go deepseek**: opencode-go prices deepseek-v4-pro at
   $1.74/$0.0145/$3.48 — **4× the upstream DeepSeek direct rate**
   ($0.435/$0.003625/$0.87). F2b was using the direct rate; round
   11 fix replaced with opencode-go rate.

### Open follow-ups (round 11+)

1. **F2b schema**: add `max_input_in_event` (or `is_long_context`) column
   so the opencode MiniMax-M3 512K cliff can be priced per-row
   (currently a $290 nominal / $581 worst-case range).
2. **kiro CLI extractor**: kiro uses its own SQLite storage at
   `~/Library/Application Support/kiro-cli/data.sqlite3`, not
   `~/.claude/projects/`. If the user wants kiro in F2a, build an
   extractor.
3. **zaiCodingPlan + nanogpt extractors**: F2b wiring in place but
   7月 data missing. Verify the local CLI tools were not used; if
   they were, the extractor path may be broken.
4. **deepseek perception vs reality gap**: user reported deepseek as
   a primary model, but F2b-recorded opencode data shows only
   2.22M input for `deepseek-v4-pro`. Likely TokenNormalizer is
   mis-classifying deepseek-on-c2cc / deepseek-on-direct-curl
   sessions. Add a model-level override list.
5. **claudeCode cache_control** (user action item): user should
   consider enabling cache_control on Opus prompts to halve the
   Opus bill ($6,611 → ~$3,300 in this window).
6. **MiniMax over-bill risk** (international users): the modelRate
   switch is wired with the China-domestic list. A user on the
   international `minimax.io` platform would be over-billed by
   ~2×. Either gate on `providerID` or accept the conservative
   estimate.

### What to do first

1. **Confirm you have the same `F2b` SQLite** at
   `$HOME/Library/Application Support/TokenKing/f2b.sqlite`. If the
   user is on a different machine, the data is local; you can't
   re-run the audit without it.
2. **Re-read `docs/handoffs/2026-07-13-f2b-round11-final.md`** for
   the full state.
3. **Ask the user what they want to work on next**:
   - Round 12 follow-ups (schema migration, kiro extractor, etc.)?
   - New provider audit (8月 cost with corrected prices)?
   - Different repo? (TokenEater / sylearn AIUsage / etc. as inspiration
     for Token King UI work.)
   - A specific bug or feature in F2a / F2b?
4. The default workflow for any new round: TDD (red → green → refactor)
   + subagent review per module + commit on the audit branch + merge
   to main at the end. Methodology doc `ctca-cli-token-cost-audit.md`
   is the source of truth for cost-audit work; follow it verbatim.

### Quick recon commands

```bash
# Confirm the repo and branch
cd ~/projects/usage-deck
git remote -v
git log --oneline -5
git status

# Run the test suite
xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj \
  -scheme CopilotMonitor -destination 'platform=macOS' test 2>&1 \
  | grep -E "Executed.*tests|FAIL|error: -" | tail -5

# Confirm F2b SQLite is there
ls -la "$HOME/Library/Application Support/TokenKing/f2b.sqlite"

# Re-run the master CTCA audit on a fresh month
./scripts/f2b-token-stats/f2b-codex-stats.sh
./scripts/f2b-token-stats/f2b-opencode-stats.sh
./scripts/f2b-token-stats/f2b-kimicode-stats.sh
```

### Files most likely to need editing

- `CopilotMonitor/CopilotMonitor/Helpers/PricingTable.swift` — add new
  model prices, add alias cases, change `currency` default
- `CopilotMonitor/CopilotMonitor/Helpers/MonthCostCalculator.swift` — refine
  the `looksLikeOpenAIModel && providerId == .codex` guard
- `CopilotMonitor/CopilotMonitor/Helpers/TokenExtractor/*.swift` — add
  new extractors, fix dedup, handle new schema fields
- `CopilotMonitor/CopilotMonitor/Helpers/TokenUsageStore.swift` — schema
  changes (e.g. add `max_input_in_event` column)
- `docs/methodology/ctca-cli-token-cost-audit.md` — update the procedure
  when a step's contract changes
- `docs/handoffs/` — write a per-round handoff at the end of each
  round, and update the master rollup at `2026-07-12-f2b-7mo-cost-audit-all-providers.md`

### Hard rules (inherited from the user)

- **Don't push to upstream.** Always `git remote -v` first.
- **Use real data, not assumptions.** If a claim can be checked, check
  it with `jq`, `sqlite3`, or a raw JSONL peek. If a claim can't be
  checked, say so and propose the check.
- **Subagent review per module.** Don't ship a non-trivial change
  without it; the reviews have caught real bugs every round.
- **When in doubt, follow the existing pattern.** Look at how
  `modelRate(for:)` is wired, look at how
  `calculateMonthlyTotals` aggregates, look at how the extractor's
  `parseFile` walks the input. Match the style.
- **No "we should also..." in the report.** Open follow-ups go to a
  numbered "Round 11+ follow-ups" list at the end of the handoff
  doc, not in the body.
- **Big-picture question ("how do I know my numbers are right?")**:
  compare F2b totals against `ccusage` (industry reference) and the
  raw JSONL. If they disagree, the discrepancy is either
  (a) dup-snapshot inflation in raw data (round 8 fix),
  (b) per-provider timezone misalignment (use `--timezone UTC` on
  ccusage), or
  (c) tier or model mis-classification (subagent review).
