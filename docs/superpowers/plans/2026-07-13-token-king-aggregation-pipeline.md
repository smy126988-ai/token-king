# Token King Aggregation Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** 修复历史日聚合和累计 API 语义，用原子 batch/checkpoint 增量刷新替代 30 秒全量重扫，并保证每 tick 最多一次完整菜单刷新。

**Architecture:** Extractor 产出 `ExtractionBatch(events, snapshots, checkpoints, metrics)`；Store 在一个事务内提交数据、受影响聚合和 checkpoint；RefreshActor 最后生成一个 `RefreshSnapshot`，UI 只对变化的内容重建。

**Tech Stack:** Swift 6 actors, SQLite C API, XCTest fixtures, AppKit menu integration, shell runtime sampling.

---

## Task 1: 建立增量抽取类型契约

**Files:**
- Create: `CopilotMonitor/CopilotMonitor/Helpers/TokenIngestionModels.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenExtractor/TokenExtractorProtocol.swift`
- Modify: all seven extractor implementations under `Helpers/TokenExtractor/`
- Create: `CopilotMonitor/CopilotMonitorTests/Helpers/TokenIngestionModelsTests.swift`
- Modify: corresponding extractor tests and `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先写 `YearMonth` validation、events/snapshots 分离、JSONL checkpoint parserState round-trip 测试；运行定向测试，预期因类型/新协议不存在而 RED。
- [ ] 定义 `APIUsageSnapshot`、SQLite/JSONL/API `IngestionCheckpoint`、`ExtractionMetrics`、`ExtractionBatch` 和 `extract(checkpoints:)`；七个 extractor 先以 full-scan batch 兼容。
- [ ] GREEN 命令：`xcodebuild test -project CopilotMonitor/CopilotMonitor.xcodeproj -scheme CopilotMonitor -destination 'platform=macOS' -derivedDataPath /tmp/tk95-pipeline-contracts CODE_SIGNING_ALLOWED=NO -only-testing:CopilotMonitorTests/TokenIngestionModelsTests`。
- [ ] 提交 `refactor: define incremental ingestion contracts`。

## Task 2: 原子迁移到 source-aware schema v3

**Files:**
- Create: `CopilotMonitor/CopilotMonitor/Helpers/TokenUsageSchema.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenUsageStore.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/Helpers/TokenUsageSchemaMigrationTests.swift`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先写 legacy versions 1+2→single v3、source-aware PK、preserve events/drop dead cache、idempotency、invalid schema rollback 测试，确认 RED。
- [ ] 在单个 `BEGIN IMMEDIATE` 中创建 single-row schema_version、source-aware month/day aggregates、`api_snapshots`、`ingestion_checkpoints` 和 source index；旧 aggregates 不猜 source，由 Task 4 从 raw repair。
- [ ] migration 任一步失败 ROLLBACK 且不提升 current_version；删除未使用 `model_pricing_cache`。
- [ ] 运行 `xcodebuild test -project CopilotMonitor/CopilotMonitor.xcodeproj -scheme CopilotMonitor -destination 'platform=macOS' -derivedDataPath /tmp/tk95-pipeline-schema CODE_SIGNING_ALLOWED=NO -only-testing:CopilotMonitorTests/TokenUsageSchemaMigrationTests`，提交 `feat: add transactional usage schema migration`。

## Task 3: 正确存储累计 API 快照

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenExtractor/NanoGPTExtractor.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenExtractor/ZAIExtractor.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenUsageStore.swift`
- Modify: NanoGPT/ZAI extractor tests
- Create: `CopilotMonitor/CopilotMonitorTests/Helpers/TokenUsageStoreBatchTests.swift`

- [ ] 先写 NanoGPT gpt 模型仍归 `.nanoGpt`、100→150 等于150、新月份独立、401/非法 JSON 不更新、旧 fetchedAt 不覆盖新快照等测试，确认 RED。
- [ ] ZAI/NanoGPT 只返回 snapshots；非 2xx、认证失败、非法字段直接 throw，不生成零值或 checkpoint。
- [ ] 用 `ON CONFLICT(provider, source, period, model) DO UPDATE` 且只允许更新为同新或更新 fetchedAt；month aggregate 合并 raw events 与 snapshot，但保留 source。
- [ ] 定向 GREEN 后提交 `fix: store cumulative API usage as replaceable snapshots`。

## Task 4: 原子 repair 全月日聚合

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenUsageStore.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/Helpers/TokenUsageStoreAggregateRepairTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/Helpers/TokenUsageStoreDayAggregatesTests.swift`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先写 12 天五字段、重启补洞、抵消差值仍能发现、repair 中途失败完整回滚、增量只碰 affected days 测试，确认 RED。
- [ ] 实现 `checkDayAggregateConsistency`、`repairDayAggregates`、`ensureDayAggregatesHealthy`；按 provider/source/model/day 逐字段比较。
- [ ] repair 在一个事务里只重建指定月份；首 tick/schema upgrade/health mismatch 自动触发。
- [ ] 定向 GREEN 后提交 `fix: repair historical day aggregates atomically`。

## Task 5: batch 事务和 checkpoint 原子推进

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenUsageStore.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/Helpers/TokenUsageStoreBatchTests.swift`

- [ ] 先写 1000 events 单事务、duplicates metrics、event 500 failure rollback、checkpoint only-after-commit、snapshot+aggregate atomic、busy bounded retry 测试，确认 RED。
- [ ] `commit(_ batch:)` 固定顺序：BEGIN IMMEDIATE → 复用 prepared statements → records → affected days/months → checkpoints → COMMIT。
- [ ] 用 sqlite changes 区分 inserted/duplicate；busy timeout 最多三次有界重试，失败返回 controlled error 和 rollback metrics。
- [ ] 定向 GREEN 后提交 `perf: commit ingestion batches transactionally`。

## Task 6: 为本地源实现真实增量 checkpoint

**Files:**
- Modify: OpenCode/ClaudeCode/Codex/KimiCLILegacy/KimiCode extractor implementations and tests
- Modify: NanoGPT/ZAI extractor API checkpoint tests

- [ ] 先写 SQLite rowid 增量/替换重扫、JSONL 只读完整新行、Codex parserState 恢复、truncate reset、unchanged zero records、ETag/304 测试，确认 RED。
- [ ] SQLite 使用 inode+stable row id；JSONL 使用 canonical key+inode+mtime+byteOffset+lineNumber，只推进到最后完整换行。
- [ ] Codex checkpoint 保存当前 model 与 delta/dedup state；文件替换或缩短时安全重扫，旧记录由 Store source_id 去重。
- [ ] 定向 GREEN 后提交 `perf: add incremental extractor checkpoints`。

## Task 7: 单一 RefreshSnapshot 和一次菜单刷新

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/RefreshActor.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenStatsAggregator.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/AppDelegate.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`
- Modify: RefreshActor/StatusBarController tests
- Create: `CopilotMonitor/CopilotMonitorTests/AppDelegateRefreshTests.swift`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先写 mixed source success/error、first tick repair、apply exactly once、identical UI no rebuild、changed UI exactly once、no 5s poll tests，确认 RED。
- [ ] `tickNow()`：ensure → concurrent extract → sequential atomic commits → one token/cost/source-health snapshot；复用 data plan 的 `MonthlyCostSummary`。
- [ ] AppDelegate 删除 5s 两套 polling；`applyRefreshSnapshot` 同时更新所有 cache，UI equality 排除 duration/sequence/fetch timestamp。
- [ ] GREEN 命令：`xcodebuild test -project CopilotMonitor/CopilotMonitor.xcodeproj -scheme CopilotMonitor -destination 'platform=macOS' -derivedDataPath /tmp/tk95-pipeline-refresh CODE_SIGNING_ALLOWED=NO -only-testing:CopilotMonitorTests/RefreshActorTests -only-testing:CopilotMonitorTests/StatusBarControllerTests -only-testing:CopilotMonitorTests/AppDelegateRefreshTests`。
- [ ] 提交 `refactor: publish one UI snapshot per refresh tick`。

## Task 8: 性能窗口和运行 Gate

**Files:**
- Create: `CopilotMonitor/CopilotMonitor/Helpers/RefreshMetricsWindow.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/RefreshActor.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/Helpers/RefreshMetricsWindowTests.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/Helpers/TokenPipelinePerformanceTests.swift`
- Create: `scripts/measure-token-king-idle.sh`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先写 fixed-capacity p50/p95/error/stale tests，以及 10k fixture 连续 20 个 unchanged ticks 的性能测试，确认 RED。
- [ ] ring buffer 记录 tick/error/duration/scanned/examined/new/duplicate/rescan/busy/rollback/last success，不记录路径、内容、账号或凭证。
- [ ] `RUN_TOKEN_PIPELINE_PERF=1 xcodebuild test -project CopilotMonitor/CopilotMonitor.xcodeproj -scheme CopilotMonitor -destination 'platform=macOS' -derivedDataPath /tmp/tk95-pipeline-perf CODE_SIGNING_ALLOWED=NO -only-testing:CopilotMonitorTests/TokenPipelinePerformanceTests`：重处理比例 <1%、p95 <1s、每 tick rebuild≤1。
- [ ] 运行 `scripts/measure-token-king-idle.sh --seconds 120 --max-cpu 2.0`；提交 `test: enforce refresh pipeline performance budgets`。

## Final verification

- [ ] fresh database/legacy v2/损坏 aggregate/DB busy/API auth failure 全部通过 regression。
- [ ] raw 与 day/month aggregates 五字段严格一致；snapshot 100→150 为150。
- [ ] unchanged tick 重处理 <1%、p95<1s、idle CPU<2%、一次 tick 最多一次完整 rebuild。
