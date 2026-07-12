# Token King Data Correctness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** 让本月 API 折算按 Provider、source、模型、tier 和原生币种精确路由，保留所有未知价格 Token，并能用独立 oracle 对账。

**Architecture:** 计价目录只返回带币种/来源/核验时间的 `TokenRate`；Store 先直接从 raw `token_events` 提供 source-aware 月聚合，避免旧 materialized aggregate 丢 source；Calculator 通过注入的汇率快照生成金额、coverage 与未知原因。

**Tech Stack:** Swift 6, XCTest, SQLite, Codable fixtures, shell/Python-independent CTCA oracle.

---

## Task 1: 建立有单位的计价领域类型

**Files:**
- Create: `CopilotMonitor/CopilotMonitor/Models/Pricing.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/PricingDomainTests.swift`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先写编译/行为测试覆盖 `PricingCurrency`、`PricingTier`、`PricingContext`、`TokenRate`、`UnknownPricingReason`、`CostCoverage` 和 `MonthlyCostSummary`，确认当前类型不存在而 RED。
- [ ] `TokenRate` 必须含 fresh input、cache read、cache write、output、reasoning、currency、source URL、verifiedAt；金额语义固定为原生币种/百万 Token。
- [ ] coverage 的分母包含所有五类 Token，priced/unknown 不可出现负数或 priced > total。
- [ ] 定向测试 GREEN 后提交 `refactor: add explicit pricing domain types`。

## Task 2: 重建有来源的 PricingCatalog

**Files:**
- Replace: `CopilotMonitor/CopilotMonitor/Helpers/PricingTable.swift`
- Create: `CopilotMonitor/CopilotMonitor/Helpers/PricingCatalog.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/Helpers/PricingTableTests.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/PricingCatalogTests.swift`
- Modify: `docs/superpowers/research/f2a-pricing-research-2026-07-07.md`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先写精确路由测试：Kimi K2.7 原生 CNY、OpenCode Go DeepSeek/MiniMax/Kimi/MiMo 为 OpenCode Go USD、MiMo CN 为官方 CNY、Claude Opus/Sonnet/Haiku 各自价格、OpenAI 模型价；跨 Provider 同名模型不得命中。
- [ ] 写 RED 断言：Kimi rate.currency == CNY 且数值不乘 FX；MiniMax CN M3 standard 为 ¥2.10/¥0.42/¥8.40，缺 context length 时记录 standard-estimate assumption；未知 Claude 不回退 Sonnet；tier unknown 不得伪装为精确值。
- [ ] 用可审计 entry 表替代大 switch，每项记录 URL 与 verifiedAt；只录入 2026-07-13 能由官方源验证的价格，删除硬编码 FX 与过期 M3 直连价。
- [ ] 保留最小兼容 facade 供迁移期 call sites 编译，最终 calculator 不再读取旧无单位 `PayAsYouGoRate`。
- [ ] 定向测试 GREEN 后提交 `fix: route pricing by provider source model and currency`。

## Task 3: 提供 source-aware 月度计价聚合

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenUsageStore.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenEvent.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/MonthlyPricingAggregateTests.swift`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先构造同 Provider/模型、不同 source 的 raw events，断言现有 `month_aggregates` 无法区分而 RED。
- [ ] 新增 `fetchMonthlyPricingAggregates(yearMonth:)`，直接从 `token_events` 按 provider/source/model 分组，返回五类 Token；本任务不迁移 materialized schema，避免与聚合计划争抢 migration。
- [ ] 校验 UTC 月边界、空月、未知 source、负/溢出保护和 deterministic ordering。
- [ ] 定向 Store 测试 GREEN 后提交 `feat: expose source aware monthly pricing aggregates`。

## Task 4: 重写 Calculator、汇率与 coverage

**Files:**
- Replace: `CopilotMonitor/CopilotMonitor/Helpers/MonthCostCalculator.swift`
- Create: `CopilotMonitor/CopilotMonitor/Services/ExchangeRateProviding.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Services/ExchangeRateStore.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/Helpers/MonthCostCalculatorTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/Helpers/TokenEventKimiCNTests.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/MonthlyCostCoverageTests.swift`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先写固定汇率 fixture 的 native CNY、USD→CNY、cache read/write、reasoning、unknown price、missing/stale FX 测试；Kimi `1M input + 1M cache read + 1M output == ¥34.80`。
- [ ] Calculator 只接收 `MonthlyPricingAggregate` + `PricingCatalog` + `ExchangeRateProviding`，不解析字符串猜 Provider、不读取单例、不硬编码 FX。
- [ ] reasoning 按明确 rate；仅当官方定义等同 output 时 catalog 显式给出同价。cache read/write 分开，nil 表示未知而不是免费。
- [ ] 返回 provider/model/source 明细、原生金额、CNY 小计、coverage、未知原因和汇率/价格/tier assumptions；未知行保留 Token 且不计入 pricedTokens。
- [ ] 定向测试 GREEN 后提交 `fix: calculate monthly value with coverage and native currency`。

## Task 5: 建立脱敏 CTCA 独立 oracle

**Files:**
- Create: `CopilotMonitor/CopilotMonitorTests/Fixtures/monthly-pricing-2026-07.json`
- Create: `scripts/ctca-monthly-oracle.swift`
- Create: `scripts/tests/ctca-monthly-oracle-tests.sh`
- Create: `CopilotMonitor/CopilotMonitorTests/MonthlyPricingOracleTests.swift`
- Modify: `docs/methodology/ctca-cli-token-cost-audit.md`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] fixture 只保留 provider/source/model/五类 Token，不含 session、路径、邮箱、project/account/credential；覆盖 Kimi K2.7、OpenCode Go DeepSeek、MiMo CN、GPT 5.x、Claude exact/unknown、MiniMax CN M3 standard estimate。
- [ ] oracle 自己读取独立 rate fixture/公式，禁止 import App 的 PricingCatalog/Calculator；先让 App 与 oracle 对账测试对当前实现 RED。
- [ ] 每模型误差 ≤¥0.01、已知总额误差 ≤1%；所有 fixture Token 均进入 coverage 分母，未知行数量与原因一致。
- [ ] shell 和 XCTest GREEN 后提交 `test: add independent monthly pricing oracle`。

## Task 6: 接入 RefreshActor 与可信 UI

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/RefreshActor.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/ProviderMenuBuilder.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/RefreshActorTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/StatusBarControllerTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/Helpers/ProviderMenuBuilderF1F3Tests.swift`

- [ ] 先写 UI 结构测试：顶层显示 `本月 API 折算：¥…（已计价 N%）`，明细显示 source、模型、五类 Token、价格来源/汇率时间，未知模型显示“未计价”而不消失。
- [ ] RefreshActor 改用 source-aware query 和单次汇率 snapshot；初始化/汇率失败返回 explicit state，不回退硬编码值。
- [ ] 缓存 summary 带 generatedAt/lastSuccessAt；相同 summary 不触发重复 menu rebuild。
- [ ] 定向 UI/actor 测试及全量 OfflineTests GREEN 后提交 `feat: surface auditable monthly API value`。

## Final verification

- [ ] PricingCatalog 中每个非 nil entry 都有官方 URL、原生币种和核验日期；无生产硬编码 6.79。
- [ ] CTCA fixture 逐模型误差 ≤¥0.01、总额误差 ≤1%，coverage 分母等于五类 Token 总和。
- [ ] 当前真实数据库只读对账报告列出已计价、未计价与假设，不把未知数据显示为 ¥0 的完整总额。
