# Codex Quota Widget Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a polished, account-configurable Codex quota widget whose content follows ordered quota priority instead of fixed window names.

**Architecture:** Extend the additive snapshot contract with per-account Codex data, build ordered metrics in the main app, and render a new family-adaptive SwiftUI QuotaCard. Keep legacy generic provider snapshots intact while exposing only the new Codex widget in the WidgetBundle.

**Tech Stack:** Swift 6, SwiftUI, WidgetKit, AppIntents, CryptoKit, XCTest

---

## File map

- Modify `CopilotMonitor/CopilotMonitor/Shared/WidgetSnapshot.swift`: additive account and metric metadata.
- Create `CopilotMonitor/CopilotMonitor/Services/CodexWidgetSnapshotBuilder.swift`: pure account mapping, opaque ids, masking, metric ordering.
- Modify `CopilotMonitor/CopilotMonitor/Services/WidgetSnapshotMapper.swift`: attach Codex accounts without changing other providers.
- Modify `CopilotMonitor/TokenKingWidget/Intent/ProviderEntity.swift`: replace provider picker types with Codex account entity/query.
- Modify `CopilotMonitor/TokenKingWidget/Intent/ProviderSelectionIntent.swift`: account configuration intent.
- Create `CopilotMonitor/TokenKingWidget/CodexQuotaCardView.swift`: family-adaptive QuotaCard and focused subviews.
- Modify `CopilotMonitor/TokenKingWidget/TokenKingWidget.swift`: expose one Codex widget and pass account selection/freshness.
- Modify `CopilotMonitor/TokenKingWidget/WidgetDesignToken.swift`: traceable Codex card tokens and quota-float thresholds.
- Modify `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`: register the two new Swift files in the correct targets.
- Modify `CopilotMonitor/CopilotMonitorTests/Shared/WidgetSnapshotMapperTests.swift`: Codex account mapping regression cases.
- Create `CopilotMonitor/CopilotMonitorTests/Services/CodexWidgetSnapshotBuilderTests.swift`: ordering, fallback, masking, and Spark exclusion tests.

### Task 1: Lock the additive snapshot contract

- [ ] Add optional `accounts` to `ProviderSnapshot`, plus `ProviderAccountSnapshot`, `ProviderAccountStatus`, `windowSeconds`, and `priority`.
- [ ] Update semantic content equality so account changes trigger a widget refresh.
- [ ] Add decoding coverage proving snapshots without `accounts` remain valid.

### Task 2: Build Codex account presentations

- [ ] Write failing tests for two-window ordering, weekly-only promotion, duplicate suppression, invalid percent filtering, masked account labels, and Spark exclusion.
- [ ] Implement `CodexWidgetSnapshotBuilder` as a pure mapper over `ProviderResult.accounts` with aggregate fallback.
- [ ] Derive opaque ids with SHA-256 from stable account identity and use index only as the final fallback.
- [ ] Run the focused builder tests and confirm they pass.

### Task 3: Attach accounts to the widget snapshot

- [ ] Write mapper assertions for Codex accounts and unchanged non-Codex behavior.
- [ ] Call the builder only for `.codex`; leave aggregate provider fields intact for compatibility.
- [ ] Run `WidgetSnapshotMapperTests` and confirm all existing cases still pass.

### Task 4: Replace provider selection with account selection

- [ ] Change the AppIntent parameter to `CodexAccountEntity?` with localized account-focused labels.
- [ ] Query only the Codex provider's account snapshots.
- [ ] Use stable account ids, masked labels, and plan subtitles in picker representations.
- [ ] Preserve zero-configuration behavior by resolving the only account at timeline/view selection time.

### Task 5: Implement the polished QuotaCard

- [ ] Add a thin family dispatcher that prepares primary and secondary metrics once.
- [ ] Implement separate `CodexCardHeader`, `CodexQuotaHero`, `CodexSecondaryMetric`, and `CodexWidgetStateView` structs with narrow inputs.
- [ ] Keep remaining percentage as both hero value and bar width; use used percentage only to select the tier palette.
- [ ] Give Small, Medium, and Large distinct spacing/typography while retaining one hierarchy.
- [ ] Render account/freshness failures without fabricated values or silent fallback.
- [ ] Use the data status for the status light and the primary metric for aurora/progress risk.

### Task 6: Consolidate the gallery entry

- [ ] Expose one `Token King Codex` `AppIntentConfiguration` supporting all three system families.
- [ ] Stamp entries with selected account id and keep HTTP-first/file-fallback reads.
- [ ] Drive `QuotaCardBackground` from the resolved account's first metric.
- [ ] Leave deferred widget implementations compiled but remove them from the public bundle.

### Task 7: Verify the bounded change

- [ ] Run focused mapper/builder tests.
- [ ] Build the `TokenKingWidget` target.
- [ ] Run SwiftLint on changed Swift files.
- [ ] Confirm no Spark field is referenced by the builder or new view.
- [ ] Confirm the new view contains no hard-coded `5h`, `7d`, `primary`, or `secondary` lookup.
- [ ] Review the diff to ensure menu/provider code outside the snapshot bridge is untouched.
