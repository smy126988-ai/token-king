# Token King Product Experience Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** 让用户打开菜单后十秒内读懂本月 Token、实际按量支出、API 折算价值、订阅成本，并能控制需要展示和刷新的 Provider。

**Architecture:** 保留现有 NSMenu + `MenuDesignToken` 布局，以可测试的展示模型承载五态、coverage 和时间戳；Provider 显隐统一由可注入的偏好存储驱动，菜单和抓取链路共用同一过滤结果。

**Tech Stack:** Swift 6, AppKit, XCTest, UserDefaults dependency injection, shell documentation checks.

---

## Task 1: 补齐 Token 格式和明细组件

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenUsageFormatter.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/Helpers/TokenUsageFormatterTests.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/ProviderMenuBuilder.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/MonthCostCalculator.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/Helpers/MonthCostCalculatorTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/Helpers/ProviderMenuBuilderF1F3Tests.swift`

- [ ] 先增加 `1.0B`、`10.5B`、`1.0T` 边界测试，并断言 Provider 月度明细显示 input、cache read、cache write、output、reasoning、按模型成本；增加 `testUnpricedModelStillShowsTokensAndExplicitStatus`。
- [ ] 运行 `xcodebuild test ... -only-testing:CopilotMonitorTests/TokenUsageFormatterTests -only-testing:CopilotMonitorTests/ProviderMenuBuilderF1F3Tests`，确认 RED 是缺少 B/T 和明细行。
- [ ] 扩展 formatter；用 `MenuDesignToken` 和右对齐字段构建明细，不用空格对齐。
- [ ] 重跑定向测试，确认 GREEN；提交 `feat: improve token usage detail formatting`。

## Task 2: 建立统计五态展示模型

**Files:**
- Create: `CopilotMonitor/CopilotMonitor/Models/UsageSummaryState.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Services/ProviderManager.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/RefreshActor.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/TokenUsageStore.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/UsageSummaryStateTests.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/UsageSummarySnapshotTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/StatusBarControllerTests.swift`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 为 loading、empty、partial、failed、complete 写纯模型测试；partial 必须带 coverage、缺失来源、最后成功时间，failed 必须带下一步和缓存状态。
- [ ] 为顶层摘要顺序写结构测试：`本月 Token` → `全局统计` → `按量付费` → `本月 API 折算` → `额度状态`。
- [ ] 定向测试确认 RED 后，实现 `UsageSummaryState` 和无副作用的菜单渲染映射；由 Provider health、Extractor metrics、aggregate freshness 共同生成真实 `UsageSummarySnapshot`，不允许 UI 自己猜状态。
- [ ] 保持 `按量付费：…`、`额度状态：…` 两个组标题不可变；实际支出、API 折算、订阅成本不得相加成单个总额。
- [ ] 运行新测试及 `StatusBarControllerTests`，提交 `feat: expose trustworthy usage summary states`。

## Task 3: 完成 Provider 显隐闭环

**Files:**
- Create: `CopilotMonitor/CopilotMonitor/Services/ProviderVisibilityStore.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Services/ProviderManager.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/ProviderVisibilityStoreTests.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/ProviderManagerTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/StatusBarControllerTests.swift`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先写测试证明当前 `ProviderManager.fetchAll()` 即使菜单禁用 Provider 仍会抓取；再写持久化、重启恢复和“至少保留一个/明确空态”的行为测试。
- [ ] 实现可注入的 `ProviderVisibilityStore`，键名兼容现有 `provider.<id>.enabled`，让 ProviderManager 接收 enabled identifiers 而不是总抓取后再过滤。
- [ ] 把菜单重命名为 `设置 → 显示的服务商`；禁用立即影响主菜单、刷新任务和状态栏候选。
- [ ] 定向测试 GREEN 后提交 `feat: unify provider visibility and refresh filtering`。

## Task 4: 收口中文文案和无障碍语义

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/ProviderMenuBuilder.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/ModernApp.swift`
- Create: `scripts/check-user-facing-language.sh`
- Create: `CopilotMonitor/CopilotMonitorTests/UserFacingLanguageTests.swift`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 建立允许列表，先让扫描脚本对 F1/F3/F4 残留的 Loading/No History/Error 等用户文案失败。
- [ ] 中文化普通文案；Provider、模型、API、Token 品牌词保留英文；为 SF Symbol 增加可理解的中文 accessibility description。
- [ ] 清理用两个空格制造缩进的自定义 row，全部使用 `MenuDesignToken` 的 indent/constraint。
- [ ] 运行脚本与语言测试，提交 `fix: align menu language and accessibility`。

## Task 5: 扩展统一 demo/UI harness 做产品验收

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/App/DemoProviderData.swift`（由 quality plan 创建）
- Modify: `CopilotMonitor/CopilotMonitorUITests/F2bE2ETests.swift`
- Modify: `CopilotMonitor/CopilotMonitorUITests/TokenStatsE2ETests.swift`
- Modify: `CopilotMonitor/CopilotMonitorUITests/UITestPage.swift`

- [ ] 前置条件：quality plan 的唯一 `--ui-testing` harness、`TokenKingUITests` scheme 和 `UITests.xctestplan` 已完成；本任务不创建第二套 launch mode/scheme。
- [ ] 扩展固定 fixture，测试四个核心数字、五态入口、Provider 显隐和设置入口；先确认新增断言 RED。
- [ ] 使用现有 page object 的 predicate/expectation 等待，保存稳定截图到测试附件。
- [ ] 运行 `xcodebuild test -project CopilotMonitor/CopilotMonitor.xcodeproj -scheme TokenKingUITests -testPlan UITests -destination 'platform=macOS' -derivedDataPath /tmp/token-king-95-ui`；提交 `test: cover the complete menu experience`。

## Task 6: 重写用户文档和 backlog 事实源

**Files:**
- Modify: `README.md`
- Modify: `docs/backlog/README.md`
- Modify: `docs/需求池.md`
- Create: `scripts/check-product-docs.sh`
- Replace: `docs/screenshot-subscription.png`
- Replace: `docs/screenshot3.png`

- [ ] 脚本先断言 fork URL、`Token King.app`、动态读取 Xcode build settings 的版本与源码 Provider 列表、backlog ID 唯一性；运行确认对旧 README RED，禁止把执行当日版本硬编码进脚本。
- [ ] README 第一屏写清 Provider 主视角、四种金额口径和本地数据隐私；安装/clone/Issue/Release/badge 全指向 fork，上游只留 Credits。
- [ ] `docs/需求池.md` 降为 inbox，正式状态只在 backlog；完成项附 commit/test，未完成项附验收标准。
- [ ] 用 Task 5 demo 模式生成当前中文截图并替换旧图。
- [ ] 运行 `scripts/check-product-docs.sh`，提交 `docs: align product guide with Token King experience`。

## Final verification

- [ ] 运行全部 unit/UI tests、语言扫描、文档校验。
- [ ] 构建并启动 demo 与真实本地模式；记录十秒可读性和四个数字的截图证据。
- [ ] 检查 `git diff --check`，并确认未出现随机空格布局、硬编码像素或新敏感日志。
