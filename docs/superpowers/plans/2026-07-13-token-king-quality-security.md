# Token King Quality and Security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** 让默认测试完全离线且真实覆盖 active target，建立有界脱敏诊断，并把 build hash 与状态栏桥接收敛为不会污染源码、可长期运行的实现。

**Architecture:** Offline、Live、UI 三套 test plan 分离；凭证和网络通过可注入协议隔离；所有可选文件诊断统一经过 `DiagnosticLog`；状态栏生命周期集中到 `StatusItemBridge`。

**Tech Stack:** Swift 6, XCTest/XCUITest, URLProtocol, Xcode test plans, os.Logger, shell gates.

---

## Task 1: 强制测试 target membership 完整

**Files:**
- Create: `scripts/check-test-target-membership.sh`
- Create: `scripts/tests/check-test-target-membership-tests.sh`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`
- Modify: `Makefile`
- Modify: `.github/workflows/test.yml`

- [ ] 先写 shell fixture test，运行后确认 RED：checker 不存在或没有识别未注册测试。
- [ ] checker 比较 `CopilotMonitorTests/**/*.swift` 与 PBXSourcesBuildPhase，输出缺失/多余项并非零退出。
- [ ] 运行 checker，确认准确列出 `AntigravityProviderVarintTests.swift`、`CLIFormatterTests.swift`、`ClaudeProviderTests.swift`、`SubscriptionSettingsManagerTests.swift`、`ZaiCodingPlanProviderTests.swift`。
- [ ] 将五个文件加入 test target，checker 显示磁盘数与 active Sources 数相等；再用 `-only-testing` 真正执行五个 test class。71 只是当前基线，后续新增测试后必须动态计算。
- [ ] 提交 `test: enforce complete unit test target membership`。

## Task 2: 分离默认 Offline 与显式 Live 测试

**Files:**
- Create: `CopilotMonitor/CopilotMonitorTests/Support/TestURLProtocol.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/Support/FakeProviderCredentialStore.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/OfflineNetworkGuardTests.swift`
- Create: `CopilotMonitor/CopilotMonitorLiveTests/ProviderLiveIntegrationTests.swift`
- Create: `CopilotMonitor/CopilotMonitor.xcodeproj/xcshareddata/xctestplans/OfflineTests.xctestplan`
- Create: `CopilotMonitor/CopilotMonitor.xcodeproj/xcshareddata/xctestplans/LiveProviderTests.xctestplan`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/xcshareddata/xcschemes/CopilotMonitor.xcscheme`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`
- Modify: `CopilotMonitor/CopilotMonitor/Services/TokenManager.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/KimiCNProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/KimiGlobalProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/NanoGptProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/MiniMaxCNProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/MiniMaxGlobalProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/SyntheticProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/VolcanoArkProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/TavilySearchProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/KimiProviderTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/NanoGptProviderTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/MiniMaxProviderTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/SyntheticProviderTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/VolcanoArkProviderTests.swift`
- Move: `CopilotMonitor/CopilotMonitorTests/TavilyLiveIntegrationTests.swift` → `CopilotMonitor/CopilotMonitorLiveTests/TavilyLiveIntegrationTests.swift`
- Modify: `.github/workflows/test.yml`

- [ ] 先写 `OfflineNetworkGuardTests.testDefaultPlanBlocksUnexpectedHTTPSRequest`；把 mock parser tests 改为 fake credentials，并在空 HOME 下确认当前仍 skip/联网而 RED。
- [ ] 抽最小 `ProviderCredentialProviding` 协议，由 TokenManager 适配；默认 mock tests 只使用完整 response fixture 和 URLProtocol。
- [ ] Tavily、MiniMax CN/global、Volcano 真网用例迁到 Live target；每条同时 guard `RUN_LIVE_PROVIDER_TESTS == "1"`，默认 scheme 只引用 OfflineTests。
- [ ] App 的 test mode 跳过 Sparkle、RefreshActor 和 Provider background work；默认 target 的 HTTP session 使用注入的 rejecting URLProtocol，CI 再扫描默认 target 中的 `.shared`/live markers 并审计 xcresult 的 unexpected request。
- [ ] 运行 `env -u RUN_LIVE_PROVIDER_TESTS HOME=$(mktemp -d) xcodebuild test ... -testPlan OfflineTests`，要求零外部请求、零凭证型 skip；只在显式 env 下运行 LiveProviderTests。
- [ ] 提交 `test: isolate offline and live provider suites`。

## Task 3: 建立 deterministic UI test plan

**Files:**
- Create: `CopilotMonitor/CopilotMonitor/App/AppLaunchMode.swift`
- Create: `CopilotMonitor/CopilotMonitor/App/DemoProviderData.swift`
- Create: `CopilotMonitor/CopilotMonitorUITests/UITestPage.swift`
- Create: `CopilotMonitor/CopilotMonitor.xcodeproj/xcshareddata/xctestplans/UITests.xctestplan`
- Create: `CopilotMonitor/CopilotMonitor.xcodeproj/xcshareddata/xcschemes/TokenKingUITests.xcscheme`
- Modify: `CopilotMonitor/CopilotMonitor/App/AppDelegate.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/AppLaunchModeTests.swift`
- Modify: `CopilotMonitor/CopilotMonitorUITests/F2bE2ETests.swift`
- Modify: `CopilotMonitor/CopilotMonitorUITests/TokenStatsE2ETests.swift`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先写 demo 不构造 RefreshActor/不读用户 store 的 unit test，以及四条无 skip 的菜单 UI tests，确认当前 RED。
- [ ] `--ui-testing` 注入固定 Provider/Token/cost 数据，跳过 Keychain、SQLite、TokenManager、真实 Provider 和 updater。
- [ ] 为 status item、核心摘要、Provider、全局统计和明细行加 accessibility identifier；页面对象只用 predicate/`waitForExistence`。
- [ ] 静态断言 UI tests 中无 `sleep(` 和 `XCTSkip`；运行独立 UI scheme/test plan GREEN。
- [ ] 提交 `test: make menu UI coverage deterministic`。

## Task 4: 统一安全且有界的诊断日志

**Files:**
- Create: `CopilotMonitor/CopilotMonitor/Services/DiagnosticLog.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/DiagnosticLogTests.swift`
- Create: `scripts/check-sensitive-logging.sh`
- Create: `scripts/measure-diagnostic-log-growth.sh`
- Modify: `CopilotMonitor/CopilotMonitor/Services/ProviderManager.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Services/BrowserCookieService.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Services/TokenManager.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/CommandCodeProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/KiroProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/CursorProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/OpenCodeZenProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/Providers/CodexProvider.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/AppDelegate.swift`
- Modify: `.github/workflows/test.yml`

- [ ] 先写 disabled/no-file、credential/email/account/project/path redaction、0600、active+3 archives（每份≤1MiB、总量≤4MiB）、explicit flag 五类测试，确认 RED；size/clock 必须可注入以加速测试。
- [ ] 生产只使用带 privacy 的 os.Logger；文件诊断必须 `#if DEBUG` 且 `TOKEN_KING_DIAGNOSTICS=1`。
- [ ] 菜单树、anchor、KVO、window landscape 全部经诊断开关；不写 raw response、token/cookie/key 片段、邮箱、account/project id、完整用户路径。
- [ ] 运行 `DiagnosticLogTests` 与 `scripts/check-sensitive-logging.sh`；默认启动不得创建 `/tmp/provider_debug.log` 或 `/tmp/tk_observ.log`。
- [ ] 运行 `scripts/measure-diagnostic-log-growth.sh --hours 24 --max-bytes 4194304` 生成 soak 证据；短验收允许注入 clock/size，不得用 sleep 模拟 24 小时。
- [ ] 提交 `security: centralize bounded redacted diagnostics`。

## Task 5: 构建不再修改源码 Info.plist

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`
- Modify: `CopilotMonitor/CopilotMonitor/Info.plist`
- Create: `scripts/verify-build-does-not-dirty-source.sh`
- Create: `scripts/tests/verify-build-metadata-tests.sh`
- Modify: `.github/workflows/test.yml`

- [ ] 先捕获 build 前后 porcelain，确认当前 `Inject Git Hash` 修改源码而 RED。
- [ ] phase 只修改 `$TARGET_BUILD_DIR/$INFOPLIST_PATH`，文件不存在立即失败；source plist 使用稳定 placeholder，并声明正确 input/output。
- [ ] fresh build/test/archive 后 worktree 状态与 before 完全一致，产物 GitCommitHash 等于 `git rev-parse HEAD`。
- [ ] 提交 `build: keep generated metadata out of source files`。

## Task 6: 提取 StatusItemBridge 并移除私有 KVC

**Files:**
- Create: `CopilotMonitor/CopilotMonitor/App/StatusItemBridge.swift`
- Create: `CopilotMonitor/CopilotMonitorTests/StatusItemBridgeTests.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/ModernApp.swift`
- Modify: `CopilotMonitor/CopilotMonitor/App/AppDelegate.swift`
- Modify: `CopilotMonitor/CopilotMonitorTests/AppDelegateB39Tests.swift`
- Modify: `CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`

- [ ] 先写 primary callback、secondary best-effort、missing reflected item、stop cleanup、repeated attach 五类测试，确认当前责任散落/无法注入而 RED。
- [ ] bridge 拥有 pending item、retry task、notification tokens 与 KVO；`stop()`/deinit 全部释放，公开 callback 是 primary 唯一 attach 入口。
- [ ] secondary 只用安全反射 best-effort；找不到时保留 primary，彻底移除 `value(forKey: "statusItem")`。
- [ ] unit/UI GREEN 后，运行 source gate `! rg 'value\(forKey: *"statusItem"' CopilotMonitor/CopilotMonitor`。
- [ ] 完成冷启动 100 次、登录启动、sleep/wake 和当前显示器矩阵采样，再提交 `refactor: isolate status item bridge lifecycle`。

## Final verification

- [ ] fresh OfflineTests 零真实请求、target membership 100%、UI tests 无 sleep/skip。
- [ ] build/test/archive 不改变 worktree；默认日志增长与敏感扫描满足设计门槛。
- [ ] bridge 当前硬件矩阵无重复、消失或不可点击图标。
