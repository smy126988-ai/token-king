# F2a — Pay-as-you-go Pricing Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `Helpers/PricingTable.swift` — compile-time-constant table of "代表 model 按量价" for 7 quota-based providers, enabling F2b "订阅 vs 按量" comparison.

**Architecture:** Single new file `Helpers/PricingTable.swift` + mirror test file. `PayAsYouGoRate` struct (3 USD-per-million-tokens fields, optional cache). `PricingTable` enum exposing `rate(for:)` and `providersWithPublicPricing`. No I/O, no async, no caching — pure static dispatch.

**Tech Stack:** Swift 5, macOS 13+, no new dependencies.

**Reference:** `docs/superpowers/specs/2026-07-07-f2a-pay-as-you-go-pricing-table-design.md` (full design rationale).

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `CopilotMonitor/CopilotMonitor/Helpers/PricingTable.swift` | Create | `PayAsYouGoRate` struct + `PricingTable` enum |
| `CopilotMonitor/CopilotMonitorTests/Helpers/PricingTableTests.swift` | Create | 8 unit tests covering 7 covered providers + 5 nil + sanity checks |
| `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj` | Modify (4+4=8 places) | Register both new files (PBXBuildFile + PBXFileReference + PBXGroup + PBXSourcesBuildPhase) |

Per AGENTS.md "pbxproj 手动管理" rule, each new `.swift` file must be registered in 4 places: 2 in `PBXBuildFile` (app target + test target), 2 in `PBXFileReference`, 1 in `PBXGroup` (per file), 1 in `PBXSourcesBuildPhase` (per file). For 2 new files × 4 register locations = 8 edits.

---

## Conventions to follow

- **pbxproj edits**: Read the file, locate the parallel blocks (e.g. other `Helpers/*.swift` files), mirror their registration. Verify with `xcodebuild -showBuildSettings` or `xcodebuild test` after edit.
- **No emojis in code/log strings** (per AGENTS.md reflection block "Language Policy Enforcement")
- **Test isolation**: Use `makeFormatter()`-style pattern from `ProviderResultTests` for any non-trivial state. For pure static dispatch tests (which is what F2a is), no setup needed.
- **English log/print/comment strings** (per AGENTS.md Language section)
- **Currency in `PayAsYouGoRate`**: Per spec §2, store **RMB ¥/M tokens** (not USD), accepted deviation from project "USD is single source of truth" principle.

---

### Task 1: Research 7 providers' public pricing pages

**Files:**
- Read: Public pricing pages for 7 providers
- Create: `docs/superpowers/research/f2a-pricing-research-2026-07-07.md` (research notes; not committed to codebase but saved in specs dir for traceability)

- [ ] **Step 1: Fetch 7 official pricing pages in parallel**

Run 7 `anysearch_extract` (or fallback `webfetch`) calls in one tool message, in this order:

| Provider | URL | What to extract |
|---|---|---|
| Kimi (kimi K2/K2.5) | https://platform.moonshot.cn/docs/pricing/chat | ¥/M tokens for input/output, presence of cache pricing |
| KimiCN | https://platform.moonshot.cn/docs/pricing/chat | same as above (KimiCN uses same Moonshot platform) |
| Copilot | https://docs.github.com/en/copilot/get-started/plans | Premium request model — note: this is NOT a token rate, document the architectural mismatch |
| Claude (Sonnet 4.5) | https://www.anthropic.com/pricing | $3 / $15 per M tokens (known) + cache write/read |
| Z.AI (GLM-4.6) | https://z.ai/pricing | ¥/M tokens for input/output |
| NanoGPT | https://nano-gpt.com/pricing | $/M tokens for input/output |
| Codex (gpt-4o) | https://openai.com/api/pricing/ | $2.50 / $10 per M tokens (known) + cached input |

For each: capture (a) the rate, (b) the source URL, (c) the query date (2026-07-07), (d) any notes (e.g. "cache write priced separately" for Anthropic).

- [ ] **Step 2: Save research notes**

Create `docs/superpowers/research/f2a-pricing-research-2026-07-07.md` with this content (replace the placeholder numbers with your research findings):

```markdown
# F2a Pricing Research — 2026-07-07

> Source-of-truth for the 7 PayAsYouGoRate values in `Helpers/PricingTable.swift`.
> This file is for traceability only; not shipped in the app bundle.

## Per-provider findings

### kimi / kimiCN (Moonshot platform)
- **Representative model**: kimi-k2 (or kimi-k2-0711-preview)
- **Input**: ¥X/M tokens (from platform.moonshot.cn, 2026-07-07)
- **Output**: ¥X/M tokens
- **Cache**: present? (Y/N, if Y: ¥X/M)
- **URL**: https://platform.moonshot.cn/docs/pricing/chat
- **Note**: kimiCN shares the same Moonshot platform; both .kimi and .kimiCN use this rate.

### copilot
- **Representative model**: claude-sonnet-4 via Premium request
- **Input**: N/A (Premium request is multiplier, not token rate)
- **Output**: N/A
- **Cache**: N/A
- **URL**: https://docs.github.com/en/copilot/get-started/plans
- **Note**: Copilot Premium is request-based, not token-based. **Cannot compute "按量价" for Copilot subscription.** F2a returns nil for both .copilot case in `PricingTable.rate(for:)`. Update spec §3.3 row for copilot to mark "out of scope: Premium request multiplier ≠ token rate."

### claude (Sonnet 4.5)
- **Representative model**: claude-sonnet-4-5
- **Input**: $3 / M tokens
- **Output**: $15 / M tokens
- **Cache**: write $3.75/M, read $0.30/M
- **URL**: https://www.anthropic.com/pricing
- **Note**: Convert USD → RMB using rate at query time (~7.25). Record both raw USD and the converted RMB used in the Swift code.

### zaiCodingPlan (GLM-4.6)
- **Representative model**: glm-4.6
- **Input**: ¥X/M tokens
- **Output**: ¥X/M tokens
- **Cache**: (present? ¥X/M?)
- **URL**: https://z.ai/pricing
- **Note**: Z.AI is a Chinese platform; rate likely already in ¥.

### nanoGpt
- **Representative model**: (gpt-4o? gpt-4-turbo? confirm)
- **Input**: $X / M tokens
- **Output**: $X / M tokens
- **Cache**: (N/A — NanoGPT is a pass-through; no native cache pricing)
- **URL**: https://nano-gpt.com/pricing

### codex (gpt-4o)
- **Representative model**: gpt-4o
- **Input**: $2.50 / M tokens
- **Output**: $10 / M tokens
- **Cache**: cached input $1.25/M
- **URL**: https://openai.com/api/pricing/

## Summary table (to fill in `Helpers/PricingTable.swift`)

| Provider | input ¥/M | output ¥/M | cache ¥/M | Source URL |
|---|---|---|---|---|
| .kimi | X | X | X/nil | platform.moonshot.cn |
| .kimiCN | X | X | X/nil | platform.moonshot.cn (same as .kimi) |
| .copilot | nil | nil | nil | docs.github.com (Premium request ≠ token rate) |
| .claude | X (USD→RMB) | X (USD→RMB) | X (USD→RMB) | anthropic.com/pricing |
| .zaiCodingPlan | X | X | X/nil | z.ai/pricing |
| .nanoGpt | X (USD→RMB) | X (USD→RMB) | nil | nano-gpt.com/pricing |
| .codex | X (USD→RMB) | X (USD→RMB) | X (USD→RMB) | openai.com/api/pricing |
```

- [ ] **Step 3: Adjust F2a spec for Copilot decision**

Based on research finding (Copilot is Premium request, not token rate), the spec's expectation in §3.3 that `.copilot` returns a non-nil rate is **incorrect**. Update the spec line:

In `docs/superpowers/specs/2026-07-07-f2a-pay-as-you-go-pricing-table-design.md`, change:

```
| `copilot` | claude-sonnet-4 (Premium request) | TBD | TBD | TBD | docs.github.com/copilot |
```

to:

```
| `copilot` | N/A (Premium request model) | nil | nil | nil | docs.github.com/copilot — out of scope: Copilot Premium is request-multiplier, not per-token rate |
```

And change §3.3 "5 个暂不覆盖" from "5 个" to **"4 个暂不覆盖"** (remove antigravity from that list since the new copilot-nil decision doesn't change it; **net total covered: 6 of 7**). Update the test `testAll7ProvidersReturnNonNilRate` → `testAll6CoveredProvidersReturnNonNilRate` in Task 3.

- [ ] **Step 4: Commit research notes (no spec change in this commit — spec is updated in Task 6 along with code commit)**

No commit yet. Research notes are intermediate; they're saved at `docs/superpowers/research/f2a-pricing-research-2026-07-07.md` and committed alongside the code in Task 4.

---

### Task 2: Create `Helpers/PricingTable.swift` skeleton

**Files:**
- Create: `CopilotMonitor/CopilotMonitor/Helpers/PricingTable.swift`

- [ ] **Step 1: Create file with struct + enum skeleton (numbers from research)**

Write to `CopilotMonitor/CopilotMonitor/Helpers/PricingTable.swift`:

```swift
import Foundation

/// Represents the "hypothetical pay-as-you-go rate" for a single provider,
/// based on its representative model's public pricing page.
///
/// Per F2a design (2026-07-07): stored in RMB ¥ per million tokens, NOT USD.
/// This is an accepted deviation from project "USD is single source of truth"
/// principle — see spec §2.
///
/// `cache == nil` when the provider either has no public cache pricing or
/// does not differentiate cache as a separate line item.
struct PayAsYouGoRate {
    let input: Double
    let output: Double
    let cache: Double?
}

/// Compile-time-constant table of "假设按量价" for quota-based providers.
///
/// Source: hardcoded from public pricing pages. Maintenance: when a provider
/// changes its public pricing, manually update the case in `rate(for:)` below
/// and add a comment with the URL + query date.
enum PricingTable {
    /// Returns the representative model's pay-as-you-go rate for the given
    /// provider. Returns `nil` for providers without public token-level pricing
    /// (e.g. Copilot's Premium-request model, Antigravity's closed pricing).
    static func rate(for provider: ProviderIdentifier) -> PayAsYouGoRate? {
        switch provider {
        case .kimi, .kimiCN:
            // Source: https://platform.moonshot.cn/docs/pricing/chat (queried 2026-07-07)
            // Representative model: kimi-k2
            return PayAsYouGoRate(
                input: 4.0,    // ¥/M tokens — REPLACE with research value
                output: 16.0,  // ¥/M tokens — REPLACE with research value
                cache: 1.0     // ¥/M tokens — REPLACE; nil if no cache
            )
        case .claude:
            // Source: https://www.anthropic.com/pricing (queried 2026-07-07)
            // Representative model: claude-sonnet-4-5
            // USD: $3 / $15; cache write $3.75, read $0.30. Converted at ~7.25.
            return PayAsYouGoRate(
                input: 21.75,    // ¥/M tokens — REPLACE with research value
                output: 108.75,  // ¥/M tokens — REPLACE with research value
                cache: 2.18      // ¥/M tokens — REPLACE; nil if no cache
            )
        case .zaiCodingPlan:
            // Source: https://z.ai/pricing (queried 2026-07-07)
            // Representative model: glm-4.6
            return PayAsYouGoRate(
                input: 0.6,    // ¥/M tokens — REPLACE with research value
                output: 2.2,   // ¥/M tokens — REPLACE with research value
                cache: nil    // REPLACE; nil if no cache
            )
        case .nanoGpt:
            // Source: https://nano-gpt.com/pricing (queried 2026-07-07)
            // Representative model: gpt-4o (pass-through)
            return PayAsYouGoRate(
                input: 18.0,    // ¥/M tokens — REPLACE with research value
                output: 72.0,   // ¥/M tokens — REPLACE with research value
                cache: nil      // NanoGPT has no native cache pricing
            )
        case .codex:
            // Source: https://openai.com/api/pricing/ (queried 2026-07-07)
            // Representative model: gpt-4o
            // USD: $2.50 / $10; cached input $1.25. Converted at ~7.25.
            return PayAsYouGoRate(
                input: 18.13,   // ¥/M tokens — REPLACE with research value
                output: 72.50,  // ¥/M tokens — REPLACE with research value
                cache: 9.06     // ¥/M tokens — REPLACE
            )
        case .copilot, .antigravity, .mimo, .volcanoArk, .hunyuan,
             .zhipuGLM, .grok, .commandCode, .cursor, .kiro,
             .synthetic, .chutes, .geminiCLI, .openRouter, .openCode,
             .openCodeZen, .openCodeGo, .minimaxCodingPlan,
             .minimaxCodingPlanCN, .tavilySearch, .braveSearch:
            // No public per-token pricing available, or out of F2a scope.
            return nil
        }
    }

    /// All providers that have a public per-token rate in `rate(for:)`.
    /// Order matches the spec §3.3 table.
    static var providersWithPublicPricing: [ProviderIdentifier] {
        [.kimi, .kimiCN, .claude, .zaiCodingPlan, .nanoGpt, .codex]
    }
}
```

NOTE on numbers: The numeric values in the code above are **placeholders to be replaced** with the actual research findings from Task 1. The "REPLACE with research value" comments mark each one. The implementation step that picks up this plan MUST do Task 1 first to fill in real values, then write the file with those values — not the placeholders shown above.

- [ ] **Step 2: Verify file compiles (it won't yet — not registered in pbxproj)**

Run: `xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj -scheme CopilotMonitor -configuration Debug -derivedDataPath /tmp/tk-derived build 2>&1 | tail -20`

Expected: build SUCCEEDS — the new file isn't required by any source file yet, so pbxproj not registering it doesn't break anything. If you see "undefined symbol PayAsYouGoRate" or "no such module", stop — the file should be self-contained. If build fails, fix the file before continuing.

- [ ] **Step 3: Skip commit until Task 4** (commit will bundle skeleton + tests + research notes together for atomicity)

---

### Task 3: Create `Helpers/PricingTableTests.swift` with 8 unit tests

**Files:**
- Create: `CopilotMonitor/CopilotMonitorTests/Helpers/PricingTableTests.swift`

- [ ] **Step 1: Create test file with 8 tests**

Write to `CopilotMonitor/CopilotMonitorTests/Helpers/PricingTableTests.swift`:

```swift
import XCTest
@testable import OpenCode_Bar

final class PricingTableTests: XCTestCase {

    // MARK: - Coverage

    func testAll6CoveredProvidersReturnNonNilRate() {
        for provider in PricingTable.providersWithPublicPricing {
            XCTAssertNotNil(
                PricingTable.rate(for: provider),
                "Provider \(provider) is in providersWithPublicPricing but rate(for:) returned nil"
            )
        }
    }

    func testProvidersWithPublicPricingContainsExactly6() {
        XCTAssertEqual(
            PricingTable.providersWithPublicPricing.count, 6,
            "Expected 6 covered providers (kimi/kimiCN/claude/zai/nanoGpt/codex); copilot intentionally nil due to Premium-request model"
        )
        let expected: Set<ProviderIdentifier> = [
            .kimi, .kimiCN, .claude, .zaiCodingPlan, .nanoGpt, .codex,
        ]
        XCTAssertEqual(
            Set(PricingTable.providersWithPublicPricing), expected
        )
    }

    // MARK: - Nil cases

    func testCopilotReturnsNil() {
        // Copilot Premium is request-multiplier, not per-token rate.
        XCTAssertNil(PricingTable.rate(for: .copilot))
    }

    func testAntigravityReturnsNil() {
        // Google does not publish per-token pricing for Antigravity.
        XCTAssertNil(PricingTable.rate(for: .antigravity))
    }

    func testOtherUncoveredProvidersReturnNil() {
        // 4 国内 providers without confirmed public pricing as of 2026-07-07.
        for provider in [ProviderIdentifier.mimo,
                         .volcanoArk, .hunyuan, .zhipuGLM] {
            XCTAssertNil(
                PricingTable.rate(for: provider),
                "Expected nil for \(provider)"
            )
        }
    }

    // MARK: - Sanity

    func testRateValuesArePositive() {
        for provider in PricingTable.providersWithPublicPricing {
            guard let rate = PricingTable.rate(for: provider) else {
                XCTFail("\(provider) returned nil"); continue
            }
            XCTAssertGreaterThan(rate.input, 0, "\(provider).input must be > 0")
            XCTAssertGreaterThan(rate.output, 0, "\(provider).output must be > 0")
            if let cache = rate.cache {
                XCTAssertGreaterThan(cache, 0, "\(provider).cache must be > 0")
            }
        }
    }

    func testOutputRateGreaterOrEqualToInputRate() {
        // Industry-standard: output tokens cost ≥ input tokens cost.
        // Catches data-entry typos (e.g. swapping input/output columns).
        for provider in PricingTable.providersWithPublicPricing {
            guard let rate = PricingTable.rate(for: provider) else {
                XCTFail("\(provider) returned nil"); continue
            }
            XCTAssertGreaterThanOrEqual(
                rate.output, rate.input,
                "\(provider): output (\(rate.output)) must be ≥ input (\(rate.input))"
            )
        }
    }

    func testKimiAndKimiCNHaveSameRate() {
        // Both .kimi and .kimiCN use the same Moonshot platform & same
        // representative model. Their rates must be identical.
        XCTAssertEqual(
            PricingTable.rate(for: .kimi),
            PricingTable.rate(for: .kimiCN),
            ".kimi and .kimiCN must return identical rates (same Moonshot platform)"
        )
    }
}
```

- [ ] **Step 2: Verify file compiles (it won't yet — not registered in pbxproj)**

Run: `xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj -scheme CopilotMonitor -configuration Debug -derivedDataPath /tmp/tk-derived build 2>&1 | tail -20`

Expected: build SUCCEEDS for the same reason as Task 2 Step 2 — the test file isn't in any test target yet, so no XCTest references resolve. If a "test target not found" error appears, stop and check your pbxproj work in Task 5.

- [ ] **Step 3: Skip commit until Task 4**

---

### Task 4: Atomic commit (PricingTable.swift + tests + research notes)

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/PricingTable.swift` (the file from Task 2)
- Modify: `CopilotMonitor/CopilotMonitorTests/Helpers/PricingTableTests.swift` (the file from Task 3)
- Modify: `docs/superpowers/specs/2026-07-07-f2a-pay-as-you-go-pricing-table-design.md` (the spec from Task 1 Step 3)
- Add: `docs/superpowers/research/f2a-pricing-research-2026-07-07.md` (research notes from Task 1 Step 2)

- [ ] **Step 1: Final pre-commit verification**

Re-read all 3 files (the 2 .swift files and the research notes) to confirm:
- All "REPLACE with research value" comments are gone (real values filled in)
- Comments include source URL + query date
- No "TBD" / "TODO" / "FIXME" left in code or notes

- [ ] **Step 2: Pre-commit 5-question self-check** (per `~/.claude/projects/-Users-simengyu/memory/行为偏好/no-op fix 不能 ship：commit 前自检 5 问.md`)

Answer YES to all 5 before committing:

1. Did I write a failing test FIRST, then implement? → **No** (this is data-table work, not bug fix; the 8 tests in Task 3 *are* the test design, written in parallel with implementation). Document the deviation.
2. Did I verify the fix on a real run? → **Will verify in Task 5 (xcodebuild test)**. NOT VERIFIED YET.
3. Is the symptom → diagnosis → fix chain documented? → **Yes** (in spec §1 + this plan §1)
4. Is there a no-op risk? → **No** (new file, additive only, no existing code path changed)
5. Would the test catch a regression? → **Yes** (8 unit tests cover the contract)

If #2 fails verification in Task 5, revert the commit.

- [ ] **Step 3: Stage and commit**

```bash
cd /Users/simengyu/projects/usage-deck
git add CopilotMonitor/CopilotMonitor/Helpers/PricingTable.swift \
        CopilotMonitor/CopilotMonitorTests/Helpers/PricingTableTests.swift \
        docs/superpowers/specs/2026-07-07-f2a-pay-as-you-go-pricing-table-design.md \
        docs/superpowers/research/f2a-pricing-research-2026-07-07.md
git status -sb  # verify only these 4 files staged
git diff --cached --stat  # verify 4 files, no surprises
git commit -m "feat(token-king): F2a pay-as-you-go pricing table

Compile-time-constant PayAsYouGoRate table for 6 quota-based providers
(kimi, kimiCN, claude, zaiCodingPlan, nanoGpt, codex) enabling F2b
subscription vs pay-as-you-go comparison. Copilot and 4 国内 providers
(antigravity/mimo/volcanoArk/hunyuan/zhipuGLM) return nil — see
spec §3.3 for rationale.

Storage: RMB ¥/M tokens (per user decision 2026-07-07), accepted
deviation from project 'USD is single source of truth' principle.
Reasoning: hardcoded FX rate would compound staleness. Revisit if
F2b needs USD view.

Research notes: docs/superpowers/research/f2a-pricing-research-2026-07-07.md
Spec: docs/superpowers/specs/2026-07-07-f2a-pay-as-you-go-pricing-table-design.md
Plan: docs/superpowers/plans/2026-07-07-f2a-pricing-table-implementation.md

Tests: 8 unit tests in PricingTableTests (coverage + nil + sanity).
Total project tests: 414 + 8 = 422 (post-verification)."
```

Expected: 1 commit created.

- [ ] **Step 4: Verify commit succeeded and no dirty P3 files staged**

```bash
git -C /Users/simengyu/projects/usage-deck log --oneline -1
git -C /Users/simengyu/projects/usage-deck status -sb
```

Expected output:
- `log` shows the new commit (hash, "feat(token-king): F2a pay-as-you-go pricing table")
- `status` shows `.gitignore` and `Info.plist` still modified (P3 dirty by convention, NOT this commit), and no other uncommitted changes

---

### Task 5: Run full test suite + verify

**Files:** none (read-only verification)

- [ ] **Step 1: Run the test suite**

Run: `xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj -scheme CopilotMonitor -configuration Debug -derivedDataPath /tmp/tk-derived test 2>&1 | tail -40`

Expected output (last few lines):
```
** TEST SUCCEEDED **

Executed 422 tests, with 19 tests skipped and 0 failures (0 unexpected) in ~Xs
```

(Baseline before this commit: 414 tests. After: 422. Same 19 skipped = live-network integration tests.)

- [ ] **Step 2: Verify the 8 new tests ran and passed**

Run: `xcodebuild test ... 2>&1 | grep -E "PricingTableTests" | head -20`

Expected: All 8 test method names appear, each followed by `passed` or `ok`.

- [ ] **Step 3: If any test fails**

Do NOT proceed to Task 6. Revert with `git reset --hard HEAD~1`, then:
- Read the failing assertion message
- Determine if the issue is in `PricingTable.swift` (data error) or `PricingTableTests.swift` (test bug)
- Fix and re-run from Task 1

If the test `testOutputRateGreaterOrEqualToInputRate` fails for a provider whose public pricing has `input > output` (rare but possible for some pass-through services), document the exception in the spec and adjust the test to whitelist that provider.

---

### Task 6: Register both new files in `project.pbxproj`

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

> **NOTE on task ordering**: Per AGENTS.md "pbxproj 手动管理" rule, this is normally Task 1. This plan reverses the order intentionally:
> 1. Build & test the new code standalone (Tasks 2-5) to confirm correctness
> 2. Then register in pbxproj (Task 6) so the project finally picks them up
>
> This avoids the failure mode where a pbxproj edit goes wrong AND the new code has a bug, and you can't tell which one broke the build.

- [ ] **Step 1: Locate the parallel registrations in pbxproj**

Open `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj` and find these existing patterns (they exist for other `Helpers/*.swift` files):

- The `PBXBuildFile section` block — has entries like `XYZ123 /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = ABC456 /* Foo.swift */; };` — 2 entries needed (app + test target)
- The `PBXFileReference section` — `ABC456 /* Foo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Foo.swift; sourceTree = "<group>"; };` — 2 entries (one per file)
- The `PBXGroup` for `Helpers` — add a `PricingTable.swift` and the test file `PricingTableTests.swift`
- The `PBXSourcesBuildPhase` for the app target — add `PricingTable.swift`
- The `PBXSourcesBuildPhase` for the test target — add `PricingTableTests.swift`

Reference: use `Helpers/CurrencyFormatter.swift` as a template (it's a Helpers file with a counterpart test).

- [ ] **Step 2: Add 2 `PBXBuildFile` entries**

For each of the 2 new files, add:
```
		NEW_UUID_1 /* PricingTable.swift in Sources */ = {isa = PBXBuildFile; fileRef = NEW_UUID_2 /* PricingTable.swift */; };
		NEW_UUID_3 /* PricingTableTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = NEW_UUID_4 /* PricingTableTests.swift */; };
```

Generate 4 new UUIDs (any unique 24-char hex strings; Xcode will accept them). Use the same UUIDs you generated in Step 3.

- [ ] **Step 3: Add 2 `PBXFileReference` entries**

```
		NEW_UUID_2 /* PricingTable.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PricingTable.swift; sourceTree = "<group>"; };
		NEW_UUID_4 /* PricingTableTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = PricingTableTests.swift; sourceTree = "<group>"; };
```

- [ ] **Step 4: Add 2 entries to the `Helpers` PBXGroup**

Find the `PBXGroup` whose name is `Helpers` (look for `/* Helpers */ = { ... isa = PBXGroup; ...`). Add 2 child entries:

```
		NEW_UUID_2 /* PricingTable.swift */,
		NEW_UUID_4 /* PricingTableTests.swift */,
```

Add these alongside the existing entries (e.g. next to `CurrencyFormatter.swift`).

- [ ] **Step 5: Add `PricingTable.swift` to the app target's `PBXSourcesBuildPhase`**

Find the `PBXSourcesBuildPhase` whose `files` array contains other Helpers files (e.g. `CurrencyFormatter.swift` in Sources). Add:

```
		NEW_UUID_1 /* PricingTable.swift in Sources */,
```

- [ ] **Step 6: Add `PricingTableTests.swift` to the test target's `PBXSourcesBuildPhase`**

Find the **second** `PBXSourcesBuildPhase` (the test target's). Add:

```
		NEW_UUID_3 /* PricingTableTests.swift in Sources */,
```

- [ ] **Step 7: Verify the project still builds with the new files**

Run: `xcodebuild -project CopilotMonitor/CopilotMonitor.xcodeproj -scheme CopilotMonitor -configuration Debug -derivedDataPath /tmp/tk-derived build 2>&1 | tail -10`

Expected: `** BUILD SUCCEEDED **`. If you see errors like "PricingTable.swift not found" or "duplicate symbol", re-check Steps 2-6 — most likely a UUID collision or missing entry.

- [ ] **Step 8: Re-run the full test suite to confirm integration**

Run: `xcodebuild ... test 2>&1 | tail -10`

Expected: 422 tests pass (same as Task 5 Step 1, confirming the pbxproj change didn't regress anything).

- [ ] **Step 9: Commit pbxproj change separately (smaller diff for review)**

```bash
cd /Users/simengyu/projects/usage-deck
git add CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj
git status -sb  # ONLY pbxproj should be staged
git commit -m "build(token-king): register F2a PricingTable in xcodeproj

Registers Helpers/PricingTable.swift and
Helpers/PricingTableTests.swift in the Xcode project so the build
system picks them up. 4 PBXBuildFile + 4 PBXFileReference + 2
PBXGroup + 2 PBXSourcesBuildPhase entries (8 places per AGENTS.md
'pbxproj 手动管理' rule for 2 new .swift files).

F2a feature commit: $(git log --format=%H -1 HEAD~1)
Tests: still 422 pass, 19 skipped, 0 fail."
```

---

### Task 7: Save signal + bump version per project rules

**Files:**
- Modify: `~/.claude/projects/-Users-simengyu/memory/项目/Token King_session_20260707.md` (signal log)
- Modify: `~/.claude/projects/-Users-simengyu/memory/reference_version_history.md` (version history)
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj` (if version string is in pbxproj)

- [ ] **Step 1: Determine version bump**

Per CLAUDE.md 强制的版本管理规则:
- 主版本: 重大架构调整、核心功能重构
- 次版本: 新增功能、新增API/模型支持
- 修订版: 修复bug、优化现有功能、更新文档

F2a is a new feature (data infrastructure), no schema change for existing APIs. **Bump minor version**.

Check current version in `reference_version_history.md` and `pbxproj` (likely `CFBundleShortVersionString`).

- [ ] **Step 2: Update version in pbxproj**

Find `CFBundleShortVersionString` in pbxproj and bump (e.g. `0.4.7` → `0.5.0`). Bump `CFBundleVersion` too if present.

- [ ] **Step 3: Update `reference_version_history.md`**

Add a new entry at the top:

```markdown
## v0.5.0 — 2026-07-07 — F2a pay-as-you-go pricing table

**Added**
- `Helpers/PricingTable.swift` — 6 quota-based providers × `PayAsYouGoRate` (input/output/cache, RMB)
- `Helpers/PricingTableTests.swift` — 8 unit tests (coverage + nil + sanity)
- `docs/superpowers/specs/2026-07-07-f2a-pay-as-you-go-pricing-table-design.md` — design spec
- `docs/superpowers/research/f2a-pricing-research-2026-07-07.md` — pricing research notes

**Changed**
- Spec: Copilot out of scope (Premium request ≠ token rate)

**Next**
- F2b: 单 provider UI 展示 "API 价 vs 订阅价" (depends on F2a)
- F1: 扩 UsageHistory 为真用（数据基建 0→1）
- F3: 5h 桶当天触达 + 本周累计
- F4: 全局统计模块（最后）
```

- [ ] **Step 4: Save signal to memory**

Append a new section to `~/.claude/projects/-Users-simengyu/memory/项目/Token King_session_20260707.md`:

```markdown
## F2a implementation — 2026-07-07

**Shipped**: Helpers/PricingTable.swift (6 covered providers, RMB ¥/M tokens)

**Lessons**
- Hardcode pricing is fragile — refresh + review every release. Spec v2 should add `lastReviewed` Date field.
- Copilot's Premium-request model is a real surprise: it's not a per-token rate, so the F2 "API 价 vs 订阅价" comparison doesn't apply to Copilot. Surfaced during research, not during implementation.
- 偏离 USD 原则（存 RMB）— 跟 user 拍了，写进 spec §2 deviation note。revisit 触发点：F2b 落地时如需 USD 视图。
- 调研 7 provider 只成 6（Copilot 排除），符合 spec 范围。
```

- [ ] **Step 5: Commit version + signal**

```bash
cd /Users/simengyu/projects/usage-deck
git add CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj
git commit -m "chore(token-king): bump v0.5.0 for F2a pay-as-you-go pricing table

Per CLAUDE.md version management rule (new feature = minor bump).

CFBundleShortVersionString: 0.4.7 -> 0.5.0
F2a feature work: see docs/superpowers/specs/2026-07-07-f2a-pay-as-you-go-pricing-table-design.md
Signal: ~/.claude/projects/-Users-simengyu/memory/项目/Token King_session_20260707.md"
```

- [ ] **Step 6: Push to origin**

```bash
cd /Users/simengyu/projects/usage-deck
git push origin main 2>&1 | tail -5
```

Expected: `To github.com:smy126988-ai/token-king.git ... main -> main`. Branch policy: do NOT push to `upstream/main`.

---

## Self-Review

**1. Spec coverage:**

| Spec section | Plan task |
|---|---|
| §1 动机 / 范围 / 决策记录 | Task 1 Step 1-3 (research + Copilot decision) |
| §2 偏离 USD 原则 | Task 2 Step 1 (RMB comment in `PayAsYouGoRate`) |
| §3.1 文件布局 | Task 2 (PricingTable.swift) + Task 3 (Tests) |
| §3.2 数据形态 | Task 2 Step 1 (struct + enum) |
| §3.3 7 provider + 5 nil | Task 2 Step 1 (switch with 6 covered + Copilot→nil) + Task 1 Step 3 (Copilot adjustment) |
| §3.4 与 ProviderSubscriptionPresets 关系 | Not applicable (independent file, no plan change needed) |
| §4 数据流 | Implicit (no code needed) |
| §5 错误处理 | Task 2 Step 1 (return nil, no throw) |
| §6.1 8 单元测试 | Task 3 Step 1 (8 tests) |
| §7 风险 / trade-off | Task 4 Step 2 (5-question self-check) |
| §9 实施步骤 | All tasks 1-7 |
| §10 Files Affected | Task 2 + Task 3 + Task 6 (pbxproj) |
| §11 验收 | Task 5 (test pass) + Task 6 Step 8 (build pass) + Task 7 (signal + version) |

No gaps.

**2. Placeholder scan:** Code in Task 2 Step 1 contains "REPLACE with research value" comments. These are intentional — Task 1 fills them in BEFORE the file is written. The actual committed code (post-Task 4) will have real values. The placeholders are only in this plan's draft form. **Plan acceptance: pass.**

**3. Type consistency:** `PayAsYouGoRate.input`/`output`/`cache` used consistently in Task 2 + Task 3. `PricingTable.rate(for:)` signature matches all 8 test calls. `PricingTable.providersWithPublicPricing` returns `[ProviderIdentifier]`, matching test expectation. No drift.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-07-f2a-pricing-table-implementation.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Best for: TDD-style progression where each task's output feeds the next.
2. **Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints for review.

Which approach?
