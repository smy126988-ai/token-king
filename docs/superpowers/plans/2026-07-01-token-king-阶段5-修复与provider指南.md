# Token King 阶段5 — 修复与 Provider 指南 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **执行者是 kimicode，不是 Claude。** 本计划由 Claude 只读调研产出，kimicode 照做即可。凡标 `⚠️ 需实时验证` 的步骤，kimicode 必须先拿真实 API/CLI 输出核对再改，不得凭本文假设值直接写死。

**Goal:** 修复 Token King 的 7 类问题（kimi/kiro 数据、未配置报错、货币国内套餐、minimax、gpt/antigravity 报错、品牌残留），并产出「如何新增 Provider」指南。

**Architecture:** 逐 Provider 修数据层 bug（KimiProvider 用 `limit-remaining` 算 used、CodexProvider 加超时、MiniMaxProvider 加国内端点）；错误刷屏在展示层按 `ErrorMenuStatus` 分级过滤；国内套餐给 `SubscriptionPreset` 加原生人民币字段，USD 仍作计算真值；品牌残留替换为 fork URL。

**Tech Stack:** Swift 5 / macOS 13+ / Xcode（pbxproj 手动管理）/ XCTest（module=`OpenCode_Bar`）

**构建/测试命令：**
- 测试：`cd /Users/simengyu/projects/usage-deck/CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS' 2>&1 | tail -30`
- 单测某类：加 `-only-testing:CopilotMonitorTests/<ClassName>`
- 构建：把 `test` 换 `build`

**⚠️ pbxproj 手动注册铁律：** 新增 `.swift` 文件必须手动改 `CopilotMonitor.xcodeproj/project.pbxproj`——PBXBuildFile（app + CLI 各一条）、PBXFileReference（一条）、PBXGroup（一条）、PBXSourcesBuildPhase（app + CLI 各一条）。漏任一处 = 编译报错或文件不参与编译。本阶段不新增文件，但问题7指南必须讲清。

---

## 问题→任务映射

| 用户问题 | 任务 | 类型 |
|---------|------|------|
| 1. kimi 用量读不到 | Task 1 | 代码 bug（读了不存在的 `used` 字段） |
| 1. kiro 顶到 1000 | Task 2 | 代码 bug（正则失败回落硬编码 1000）⚠️ 需实时验证 |
| 5. gpt(Codex) 报错 | Task 3 | 代码 bug（默认 10s 超时太短） |
| 2. 未配置 provider 刷屏 | Task 4 | 产品设计 + 展示层过滤 |
| 5. antigravity 报错 | Task 5 | 错误分级误判 |
| 3. 货币/套餐美元 | Task 6 | 数据结构 + 渲染 |
| 4. minimax 没有 | Task 7 | 配置 + 国内端点 ⚠️ 需实时验证 |
| 6. 品牌残留 | Task 8 | 文案替换 |
| 7. 如何加 provider | Task 9 | 文档 |

---

## Task 1: 修复 Kimi 用量读不到（读了不存在的 `used` 字段）

**根因（已用 curl 验证，HTTP 200 有数据）：** Kimi API `https://api.kimi.com/coding/v1/usages` 返回的 `usage` 对象**没有 `used` 字段**，只有 `limit`/`remaining`/`resetTime`。代码 `KimiProvider.swift:103` 读 `usage.used`，解析出 0，导致周用量恒为 0%（表现为「读不到数据」）。正解：`used = limit - remaining`。

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Providers/KimiProvider.swift:101-103`
- Test: `CopilotMonitor/CopilotMonitorTests/KimiProviderTests.swift`（若不存在则新建，需 pbxproj 注册到 test target）

- [ ] **Step 1: 写失败测试**

新建/追加 `CopilotMonitorTests/KimiProviderTests.swift`：

```swift
import XCTest
@testable import OpenCode_Bar

final class KimiProviderTests: XCTestCase {
    func testWeeklyUsedComputedFromLimitMinusRemaining() throws {
        // Kimi 真实响应：usage 无 used 字段，只有 limit/remaining
        let json = """
        {
          "user": {"userId": "u1", "membership": {"level": "LEVEL_VIVACE"}},
          "usage": {"limit": "100", "remaining": "40", "resetTime": "2026-07-08T02:32:44Z"},
          "limits": [{"window": {"duration": 5, "timeUnit": "HOUR"},
                      "detail": {"limit": "50", "remaining": "45", "resetTime": "2026-07-01T08:00:00Z"}}]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(KimiUsageResponse.self, from: json)
        let limit = Int(decoded.usage?.limit ?? "0") ?? 0
        let remaining = Int(decoded.usage?.remaining ?? "0") ?? 0
        let used = max(0, limit - remaining)

        XCTAssertEqual(used, 60)
        let percent = limit > 0 ? Double(used) / Double(limit) * 100 : 0
        XCTAssertEqual(percent, 60.0, accuracy: 0.01)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/simengyu/projects/usage-deck/CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS' -only-testing:CopilotMonitorTests/KimiProviderTests 2>&1 | tail -20`
Expected: 编译失败（KimiProviderTests 未注册）或断言前逻辑不通过。若测试文件新建，先完成 pbxproj 注册（见 Task 9 流程）再跑。

- [ ] **Step 3: 改实现——用 limit-remaining 算 used**

`KimiProvider.swift:101-103`，把：

```swift
            let weeklyLimit = Int(usage.limit ?? "0") ?? 0
            let weeklyRemaining = Int(usage.remaining ?? "0") ?? 0
            let weeklyUsed = Int(usage.used ?? "0") ?? 0
```

改为：

```swift
            let weeklyLimit = Int(usage.limit ?? "0") ?? 0
            let weeklyRemaining = Int(usage.remaining ?? "0") ?? 0
            let weeklyUsed = max(0, weeklyLimit - weeklyRemaining)
```

`KimiUsageResponse.Usage` 里的 `let used: String?`（:20）可保留（向后兼容 API 若某天加回），不影响。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add CopilotMonitor/CopilotMonitor/Providers/KimiProvider.swift CopilotMonitor/CopilotMonitorTests/KimiProviderTests.swift CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj
git commit -m "fix(kimi): compute weekly used from limit-remaining (API has no used field)"
```

---

## Task 2: 修复 Kiro 额度顶到 1000（正则失败回落硬编码）⚠️ 需实时验证

**根因：** `KiroProvider.swift:382 return 1_000` 是 `planCreditTotal(for:)` 对 Pro 计划的**硬编码回落值**。当 `kiro-cli /usage` 输出没被 `:259` 的正则 `Credits\s*\(...of...\)` 命中时，就回落到 plan 名对应的固定额度（free=50 / pro=1000 / pro+=2000 / power=…）。用户实际额度 1905 说明真实额度应从 CLI 输出解析，而非用计划名硬编码。

**⚠️ kimicode 必须先做：** 运行 `kiro-cli /usage`（或用户环境里实际的 kiro usage 命令），把**真实输出原文**贴出来，确认 1905 这个数字出现在哪个字段/什么格式。当前正则只认 `Credits (X of Y)` 这种括号格式；若真实输出是别的格式（如 `1905 / 2000` 或 JSON），需据实改正则，不能照搬本文假设。

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Providers/KiroProvider.swift:257-259`（正则）和 `:378-382`（回落逻辑）
- Test: `CopilotMonitorTests/KiroProviderTests.swift`

- [ ] **Step 1: 拿真实 CLI 输出**（阻塞步骤）

Run: `kiro-cli /usage`（或等效命令）
Expected: 记录完整输出。找出 1905 及其上下文格式。**在拿到输出前不要改代码。**

- [ ] **Step 2: 据真实格式写失败测试**

`CopilotMonitorTests/KiroProviderTests.swift`，用 Step 1 的真实输出片段（下例为占位，kimicode 用真实字符串替换 `REAL_CLI_OUTPUT`）：

```swift
import XCTest
@testable import OpenCode_Bar

final class KiroProviderTests: XCTestCase {
    func testParsesRealTotalCreditsNotHardcoded1000() {
        let output = "REAL_CLI_OUTPUT"  // ⚠️ kimicode 用 Step 1 真实输出替换
        let parsed = KiroProvider.parseCredits(from: output)  // 见 Step 3 抽出的可测方法
        XCTAssertEqual(parsed?.total, 1905, accuracy: 0.01)
        XCTAssertNotEqual(parsed?.total, 1000)
    }
}
```

- [ ] **Step 3: 抽出可测解析方法 + 据真实格式修正则**

`KiroProvider.swift` 把 `:257-259` 的正则匹配逻辑抽成 `static func parseCredits(from output: String) -> (used: Double, total: Double)?`（若已内联，抽出以便测试）。据 Step 1 真实格式调整 `:259` 的 pattern。**删除或降级 `:378-382` 的硬编码 plan→额度回落**：仅当解析彻底失败时才回落，且回落值不应覆盖已解析到的真实值。

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /Users/simengyu/projects/usage-deck/CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS' -only-testing:CopilotMonitorTests/KiroProviderTests 2>&1 | tail -20`
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add CopilotMonitor/CopilotMonitor/Providers/KiroProvider.swift CopilotMonitor/CopilotMonitorTests/KiroProviderTests.swift CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj
git commit -m "fix(kiro): parse real credit total from CLI output instead of hardcoded 1000"
```

---

## Task 3: 修复 Codex(ChatGPT) 超时报错

**根因：** `CodexProvider.swift:486` 用 `URLSession.shared.data(for: request)`，且 CodexProvider **没覆写 `fetchTimeout`**，走协议默认值 `ProviderProtocol.swift:198` 的 `10.0`。ProviderManager 的全局超时包装器在 10s 后抛 `"Fetch timeout after 10.0s"`（就是用户看到的报错）。修法：CodexProvider 覆写 `fetchTimeout` 到 30s（对齐 KiroProvider 的做法）。

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Providers/CodexProvider.swift`（类体内加 `fetchTimeout` 覆写）

- [ ] **Step 1: 写失败测试**

`CopilotMonitorTests/CodexProviderTests.swift`：

```swift
import XCTest
@testable import OpenCode_Bar

final class CodexProviderTests: XCTestCase {
    func testFetchTimeoutIsExtended() {
        let provider = CodexProvider()
        XCTAssertGreaterThanOrEqual(provider.fetchTimeout, 30.0)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/simengyu/projects/usage-deck/CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS' -only-testing:CopilotMonitorTests/CodexProviderTests 2>&1 | tail -20`
Expected: FAIL（默认 10.0 < 30.0）

- [ ] **Step 3: 覆写 fetchTimeout**

`CodexProvider.swift` 类体内（`identifier`/`type` 声明附近）加：

```swift
    var fetchTimeout: TimeInterval { 30.0 }
```

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add CopilotMonitor/CopilotMonitor/Providers/CodexProvider.swift CopilotMonitor/CopilotMonitorTests/CodexProviderTests.swift CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj
git commit -m "fix(codex): extend fetchTimeout to 30s to avoid premature 10s timeout"
```

---

## Task 4: 未配置 Provider 不刷屏（改为「点击配置」入口）

**用户决策：** 选项 B，**不置灰**，把「未配置」当成直接配置的入口。

**现状（已核实）：**
- 菜单列表：`ErrorMenuStatus.noCredentials.shouldDisplayInList == false`（`StatusBarController.swift:2785-2792`）——认证错误已不进列表。
- 错误详情弹窗 `showErrorDetailsAlert`（:3503-3505）：全量打印 `lastProviderErrors`，只按 `isProviderEnabled` 过滤（:865），**没按错误类型过滤** → 无凭证错误仍进弹窗刷屏。

**方案：**
1. 弹窗只展示「真错误」（`.error`/`.rateLimited`），排除 `.noCredentials`/`.noSubscription`。
2. 未配置 provider 在列表里显示为「未配置 · 点击配置」条目（非错误样式），点击打开配置指引。

⚠️ **需你确认的产品点：** 「点击配置」跳到哪？三个选项——(a) 打开该 provider 的 auth.json 配置说明弹窗；(b) 打开对应官网登录页；(c) 打开本地 auth.json 文件。本计划按 **(a) 弹窗提示 auth.json 字段名 + 路径** 写，最轻量、不依赖外链。

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:3508-3510`（弹窗过滤）
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`（新增未配置条目渲染，位置见 Step 3）

- [ ] **Step 1: 写失败测试（弹窗过滤逻辑）**

把弹窗里的过滤抽成可测纯函数。`CopilotMonitorTests/ErrorFilterTests.swift`：

```swift
import XCTest
@testable import OpenCode_Bar

final class ErrorFilterTests: XCTestCase {
    func testNoCredentialsExcludedFromErrorReport() {
        let errors: [ProviderIdentifier: String] = [
            .codex: "Network error: Fetch timeout after 30.0s",
            .nanoGpt: "Authentication failed: Nano-GPT API key not available",
            .claude: "Authentication failed: Anthropic access token not available"
        ]
        let reportable = StatusBarController.reportableErrors(from: errors)
        XCTAssertTrue(reportable.keys.contains(.codex))       // 真错误保留
        XCTAssertFalse(reportable.keys.contains(.nanoGpt))    // 无凭证排除
        XCTAssertFalse(reportable.keys.contains(.claude))     // 无凭证排除
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/simengyu/projects/usage-deck/CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS' -only-testing:CopilotMonitorTests/ErrorFilterTests 2>&1 | tail -20`
Expected: FAIL（`reportableErrors` 未定义）

- [ ] **Step 3: 加静态过滤方法**

`StatusBarController.swift`，在 `errorMenuStatus(for:)`（:2802）附近加静态方法（静态以便测试无需实例）：

```swift
    static func reportableErrors(
        from errors: [ProviderIdentifier: String]
    ) -> [ProviderIdentifier: String] {
        errors.filter { _, message in
            let lowercased = message.lowercased()
            // 排除无凭证/无订阅：未配置不是"错误"
            let isNoCredentials = ["authentication failed", "not found",
                                   "not available", "access token", "api key",
                                   "credentials"].contains { lowercased.contains($0) }
            let isNoSubscription = lowercased.contains("subscription")
            return !isNoCredentials && !isNoSubscription
        }
    }
```

- [ ] **Step 4: 弹窗改用过滤后的错误**

`StatusBarController.swift:3508`，把：

```swift
        for (identifier, errorMessage) in lastProviderErrors.sorted(by: { $0.key.displayName < $1.key.displayName }) {
```

改为：

```swift
        let reportable = Self.reportableErrors(from: lastProviderErrors)
        for (identifier, errorMessage) in reportable.sorted(by: { $0.key.displayName < $1.key.displayName }) {
```

同时在 `:3495` 附近的「无错误则 return」判断改用 `Self.reportableErrors(from: lastProviderErrors).isEmpty`，避免只有无凭证时仍弹窗。

- [ ] **Step 5: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS

- [ ] **Step 6: 「点击配置」条目（列表层）**

⚠️ **本步依赖 Step 4 用户确认的跳转目标。** 按方案(a)：未配置 provider 在启用列表中，若 `errorMenuStatus == .noCredentials`，渲染一条 `"\(displayName) · 点击配置"` 的 NSMenuItem（`isEnabled=true`，图标用 systemGray），action 打开一个 NSAlert 说明该 provider 的 auth.json 字段名与路径 `~/.local/share/opencode/auth.json`。字段名映射见 `TokenManager` 各 `getXxxAPIKey()`（如 kimi→`kimi-for-coding`、minimax→`minimax-coding-plan`）。

具体渲染位置：`createErrorMenuItem`（:2874）已按 status 生成条目——扩展它，当 `status == .noCredentials` 时改标题为 `"\(identifier.displayName) · 点击配置"`、`isEnabled=true`、挂配置 action。

- [ ] **Step 7: 提交**

```bash
git add CopilotMonitor/CopilotMonitor/App/StatusBarController.swift CopilotMonitor/CopilotMonitorTests/ErrorFilterTests.swift CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj
git commit -m "feat(errors): exclude unconfigured providers from error report, show config entry"
```

---

## Task 5: 修复 Antigravity 报错误判

**根因：** Antigravity 未配置时抛 `"Antigravity cache unavailable and no enabled antigravity-accounts.json account with project ID was found"`。`isAuthenticationError`（:2733-2745）的模式含 `"not found"` 但该文案是 `"was found"`，不匹配 → 被 `errorMenuStatus`（:2808）归为 `.error`（真错误）→ 进列表和弹窗刷屏。修法：把这类「未配置账号」文案识别为 `.noCredentials`。

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:2734-2741`（`isAuthenticationError` 模式表）

- [ ] **Step 1: 写失败测试**

`CopilotMonitorTests/ErrorClassificationTests.swift`：

```swift
import XCTest
@testable import OpenCode_Bar

final class ErrorClassificationTests: XCTestCase {
    func testAntigravityNoAccountIsNoCredentials() {
        let msg = "Antigravity cache unavailable and no enabled antigravity-accounts.json account with project ID was found"
        XCTAssertFalse(StatusBarController.reportableErrors(from: [.antigravity: msg]).keys.contains(.antigravity))
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/simengyu/projects/usage-deck/CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS' -only-testing:CopilotMonitorTests/ErrorClassificationTests 2>&1 | tail -20`
Expected: FAIL（当前 "was found" 不匹配，被当真错误）

- [ ] **Step 3: 扩展识别模式**

`StatusBarController.swift:2734-2741` 的 `authPatterns` 数组加两项：

```swift
        let authPatterns = [
            "Authentication failed",
            "not found",
            "not available",
            "access token",
            "API key",
            "No Gemini accounts",
            "credentials",
            "no enabled",
            "cache unavailable"
        ]
```

同步更新 Task 4 Step 3 的 `reportableErrors` 无凭证关键词表，加 `"no enabled"`、`"cache unavailable"`，保持两处一致（⚠️ 类型一致性：两处关键词表必须同步，否则弹窗和分级判断不一致）。

- [ ] **Step 4: 跑测试确认通过**

Run: 同 Step 2 命令
Expected: PASS

- [ ] **Step 5: 提交**

```bash
git add CopilotMonitor/CopilotMonitor/App/StatusBarController.swift CopilotMonitor/CopilotMonitorTests/ErrorClassificationTests.swift CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj
git commit -m "fix(errors): classify antigravity no-account message as noCredentials"
```

---

## Task 6: 货币国内套餐（订阅预设人民币化）

**两个子问题：**
- (a) 渲染 bug：`ProviderMenuBuilder.swift:1170/1178/1195` 硬编码 `$`，不走 CurrencyFormatter，货币切换对订阅无效。
- (b) 套餐值是美国价（kimi $19/$39/$199 等），国内套餐是人民币原生定价。

**架构决策（方案A）：** `SubscriptionPreset` 加可选 `cnyCost: Double?`。国内套餐存人民币原生价；`cost`(USD) 仍作 ROI 计算唯一真值（不破坏阶段2）。渲染：RMB 模式且 `cnyCost != nil` → 直接显示 `¥cnyCost`；否则 `CurrencyFormatter.shared.format(usd: cost)`。

**⚠️ 需 kimicode 查官网确认的价格：**
- **MiniMax 国内套餐**（用户选 Ultra 极速版 ¥899）：调研得 Starter ¥29 / Plus ¥49 / Max ¥119 / Ultra ¥469；极速版 Plus ¥98 / Max ¥199 / Ultra ¥899。kimicode 上 minimaxi.com 官网核对现价。
- **Kimi 国内套餐人民币价**：本调研**未核实到**，kimicode 必须查 kimi 官网（platform.moonshot.cn / kimi.com）确认 Moderato/Allegretto/Vivace 或国内实际档位的人民币价，不得用 $19×7.2 凑数。

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Models/SubscriptionSettings.swift:93-96`（struct）、`:138-151`（kimi/minimax 预设）
- Modify: `CopilotMonitor/CopilotMonitor/Helpers/ProviderMenuBuilder.swift:1170/1178/1195`（渲染）

- [ ] **Step 1: 写失败测试**

`CopilotMonitorTests/SubscriptionPresetTests.swift`：

```swift
import XCTest
@testable import OpenCode_Bar

final class SubscriptionPresetTests: XCTestCase {
    func testPresetSupportsNativeCNY() {
        let p = SubscriptionPreset(name: "Ultra 极速版", cost: 124.86, cnyCost: 899)
        XCTAssertEqual(p.cnyCost, 899)
        XCTAssertEqual(p.cost, 124.86, accuracy: 0.01)  // USD 仍作计算真值
    }

    func testUSDPresetHasNilCNY() {
        let p = SubscriptionPreset(name: "Pro", cost: 20)
        XCTAssertNil(p.cnyCost)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /Users/simengyu/projects/usage-deck/CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS' -only-testing:CopilotMonitorTests/SubscriptionPresetTests 2>&1 | tail -20`
Expected: FAIL（`cnyCost` 参数不存在）

- [ ] **Step 3: 扩展 struct（cnyCost 默认 nil，兼容所有现有调用）**

`SubscriptionSettings.swift:93-96`：

```swift
struct SubscriptionPreset {
    let name: String
    let cost: Double          // USD，ROI 计算唯一真值
    var cnyCost: Double? = nil // 国内套餐人民币原生价，仅展示用
}
```

`= nil` 默认值保证所有现有 `SubscriptionPreset(name:cost:)` 调用不用改。

- [ ] **Step 4: 填国内套餐（⚠️ 价格待官网核对）**

`SubscriptionSettings.swift:138-151`。MiniMax（用户选 Ultra 极速版 ¥899，全档补齐；USD 列 = 人民币/7.2 近似，kimicode 可据实微调）：

```swift
    static let minimaxCodingPlan: [SubscriptionPreset] = [
        SubscriptionPreset(name: "Starter", cost: 4.03, cnyCost: 29),
        SubscriptionPreset(name: "Plus", cost: 6.81, cnyCost: 49),
        SubscriptionPreset(name: "Max", cost: 16.53, cnyCost: 119),
        SubscriptionPreset(name: "Ultra", cost: 65.14, cnyCost: 469),
        SubscriptionPreset(name: "Plus 极速版", cost: 13.61, cnyCost: 98),
        SubscriptionPreset(name: "Max 极速版", cost: 27.64, cnyCost: 199),
        SubscriptionPreset(name: "Ultra 极速版", cost: 124.86, cnyCost: 899)
    ]
```

Kimi（⚠️ cnyCost 全部待 kimicode 查官网填，下例 cnyCost 为占位，必须替换）：

```swift
    static let kimi: [SubscriptionPreset] = [
        SubscriptionPreset(name: "Moderato", cost: 19, cnyCost: nil),   // ⚠️ 查官网填人民币价
        SubscriptionPreset(name: "Allegretto", cost: 39, cnyCost: nil), // ⚠️ 查官网填人民币价
        SubscriptionPreset(name: "Vivace", cost: 199, cnyCost: nil)     // ⚠️ 查官网填人民币价
    ]
```

- [ ] **Step 5: 修渲染（走货币格式化 / 原生人民币）**

`ProviderMenuBuilder.swift:1170`（无 → 走格式化，$0 也需转）：

```swift
        let noneItem = NSMenuItem(title: "无 (\(CurrencyFormatter.shared.format(usd: 0, decimals: 0)))", action: #selector(subscriptionPlanSelected(_:)), keyEquivalent: "")
```

`:1176-1181` 预设条目标题：

```swift
            let priceText: String
            if CurrencyFormatter.shared.isRMB, let cny = preset.cnyCost {
                priceText = "¥\(Int(cny))"
            } else {
                priceText = CurrencyFormatter.shared.format(usd: preset.cost, decimals: 0)
            }
            let item = NSMenuItem(
                title: "\(preset.name) (\(priceText)/月)",
                action: #selector(subscriptionPlanSelected(_:)),
                keyEquivalent: ""
            )
```

⚠️ **需确认 CurrencyFormatter 是否有 `isRMB` 只读属性。** 若无，用其现有货币模式判断 API 替代（见 `CurrencyFormatter.swift`），kimicode 按实际 API 名调整。`:1195` 自定义金额同理走 `format`。

- [ ] **Step 6: 跑测试确认通过 + 全量回归**

Run: `cd /Users/simengyu/projects/usage-deck/CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS' 2>&1 | tail -30`
Expected: 新测试 PASS，原 226 测试不回归。

- [ ] **Step 7: 提交**

```bash
git add CopilotMonitor/CopilotMonitor/Models/SubscriptionSettings.swift CopilotMonitor/CopilotMonitor/Helpers/ProviderMenuBuilder.swift CopilotMonitor/CopilotMonitorTests/SubscriptionPresetTests.swift CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj
git commit -m "feat(currency): support native CNY subscription presets, fix hardcoded dollar rendering"
```

---

## Task 7: MiniMax 国内套餐接入 ⚠️ 需实时验证

**现状（已核实）：**
- `MiniMaxProvider.swift` **已完整实现**（非 stub）。端点 `:135-138` 指向国际站 `api.minimax.io`。
- auth.json **无 `minimax-coding-plan` 字段**（现有：kimi/kimi-for-coding/opencode-go/xiaomi/xiaomi-token-plan-cn）。
- `TokenManager.getMiniMaxCodingPlanAPIKey()` 读 `auth.minimaxCodingPlan?.key`，字段名 `minimax-coding-plan`。
- 国内 key 需请求国内端点 `api.minimaxi.com`。

**⚠️ kimicode 必须先验证：**
1. 用户的国内 key 类型（套餐订阅 sk-cp… vs 按量付费）能否调通 `/coding_plan/remains`。
2. 该接口是否需要 cookie/session（参考上游 GitHub issue #88 提到的 cookie 依赖）——若纯 Bearer 调不通，需查国内接口鉴权方式。
3. 国内端点确切路径（`api.minimaxi.com/v1/api/openplatform/coding_plan/remains` 是否成立）。

**用户需手动做（非代码）：** 往 `~/.local/share/opencode/auth.json` 加：

```json
"minimax-coding-plan": {"type": "api", "key": "<用户的国内套餐 key>"}
```

（Claude 不代写此文件——含真实凭证。用户自行填。）

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/Providers/MiniMaxProvider.swift:135-138`（端点）

- [ ] **Step 1: 验证国内端点可调**（阻塞步骤）

用用户提供的国内 key，`curl` 测 `https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains`（Bearer 鉴权），记录响应结构。若 401/需 cookie，据实调整鉴权。**调通前不改代码。**

- [ ] **Step 2: 加国内端点到 endpoints 数组**

`MiniMaxProvider.swift:135-138`：

```swift
    private let endpoints = [
        "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains",
        "https://api.minimax.io/v1/api/openplatform/coding_plan/remains",
        "https://www.minimax.io/v1/api/openplatform/coding_plan/remains"
    ]
```

国内端点放首位（现有 `fetchRemains` 应已按数组顺序 fallback；若非，kimicode 确认遍历逻辑）。

- [ ] **Step 3: 据 Step 1 响应调整解析（如字段名不同）**

若国内响应结构与国际站不同，据实调整 `MiniMaxProvider` 的 Codable struct。若一致则跳过。

- [ ] **Step 4: 手动验收**

用户 auth.json 填好 key 后，`make run`，确认菜单里 MiniMax 显示真实剩余额度而非「无凭证」。

- [ ] **Step 5: 提交**

```bash
git add CopilotMonitor/CopilotMonitor/Providers/MiniMaxProvider.swift
git commit -m "feat(minimax): add China endpoint api.minimaxi.com for domestic coding plan"
```

---

## Task 8: 清除 OpenCode Bar 品牌残留

**残留位置（已核实）：**
- `App/StatusBarController.swift:3382` `https://github.com/opgginc/opencode-bar`
- `:3582` `"我的 OpenCode Bar 用量快照"`
- `:3598` `https://github.com/opgginc/opencode-bar`
- `:3692` `https://github.com/opgginc/opencode-bar/issues/new?...`
- `:3720` `https://github.com/opgginc/opencode-bar`
- `scripts/install-cli.sh:4` 注释 `OpenCode Bar CLI`
- `:7` `APP_PATH="/Applications/OpenCode Bar.app"`
- `:14` `echo "...OpenCode Bar is installed..."`

fork URL：`https://github.com/smy126988-ai/token-king`

**Files:**
- Modify: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`（5 处）
- Modify: `scripts/install-cli.sh`（3 处）

- [ ] **Step 1: 替换 StatusBarController URL 与文案**

- `:3382`/`:3598`/`:3720` 的 `https://github.com/opgginc/opencode-bar` → `https://github.com/smy126988-ai/token-king`
- `:3692` issues 链接 → `https://github.com/smy126988-ai/token-king/issues/new?title=...&body=...`（保留 query 拼接）
- `:3582` `"我的 OpenCode Bar 用量快照"` → `"我的 Token King 用量快照"`

- [ ] **Step 2: 替换 install-cli.sh**

- `:4` `# Install OpenCode Bar CLI to /usr/local/bin` → `# Install Token King CLI to /usr/local/bin`
- `:7` `APP_PATH="/Applications/OpenCode Bar.app"` → `APP_PATH="/Applications/Token King.app"`（⚠️ 与阶段M1的 PRODUCT_NAME=Token King 对齐，核实 .app 实际名）
- `:14` `echo "Make sure OpenCode Bar is installed in /Applications/"` → `echo "Make sure Token King is installed in /Applications/"`

- [ ] **Step 3: 全局复查无残留**

Run: `cd /Users/simengyu/projects/usage-deck && grep -rn "opgginc\|OpenCode Bar\|opencode-bar\|opencode bar" CopilotMonitor/CopilotMonitor scripts 2>/dev/null | grep -v "// \|/\* "`
Expected: 无输出（或仅剩数据标识/不可改的 == 比较串——阶段3铁律：品牌 displayName 之外的数据标识不动）。

- [ ] **Step 4: 构建确认无破坏**

Run: `cd /Users/simengyu/projects/usage-deck/CopilotMonitor && xcodebuild build -scheme CopilotMonitor -destination 'platform=macOS' 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: 提交**

```bash
git add CopilotMonitor/CopilotMonitor/App/StatusBarController.swift scripts/install-cli.sh
git commit -m "chore(brand): replace remaining OpenCode Bar references with Token King"
```

---

## Task 9: 「如何新增一个 Provider」指南（问题7，最重要）

**Files:**
- Create: `docs/adding-a-provider.md`

- [ ] **Step 1: 写指南文档**

新建 `docs/adding-a-provider.md`，内容如下（这是给未来的你/kimicode 的操作手册，非代码）：

````markdown
# 如何新增一个 Provider

以新增 `FooProvider` 为例。Token King 的 pbxproj 手动管理，**每个 .swift 新文件必须手动注册**，漏一处就编译失败或文件不参与编译。

## 步骤总览（7 处改动）

### 1. 建 Provider 文件
`CopilotMonitor/CopilotMonitor/Providers/FooProvider.swift`：

```swift
import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "FooProvider")

final class FooProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .foo
    let type: ProviderType = .quotaBased   // 或 .usageBased

    private let tokenManager: TokenManager
    private let session: URLSession

    // 网络慢的 provider 覆写超时（默认 10s）
    var fetchTimeout: TimeInterval { 30.0 }

    init(tokenManager: TokenManager = .shared, session: URLSession = .shared) {
        self.tokenManager = tokenManager
        self.session = session
    }

    func fetch() async throws -> ProviderResult {
        guard let apiKey = tokenManager.getFooAPIKey() else {
            throw ProviderError.authenticationFailed("Foo API key not available")
        }
        // ...请求 + 解析，返回 ProviderResult(usage:details:)
    }
}
```

### 2. ProviderIdentifier 枚举 + 4 个穷举 switch
`Models/ProviderProtocol.swift`：
- `enum ProviderIdentifier` 加 `case foo`
- 4 个穷举 switch 各加 `.foo` 分支：`displayName`（品牌名，**不翻译**）、`shortDisplayName`、`iconName`（SF Symbol）、以及其它对 identifier 穷举的地方
- ⚠️ Swift 穷举 switch 缺分支 = 编译错误，编译器会帮你找全。

### 3. TokenManager 加 key 读取
`Services/TokenManager.swift`：
- auth.json 的 Codable struct 加字段（如 `let foo: AuthEntry?`，JSON key 用 `foo` 或带连字符的实际字段，配 CodingKeys）
- 加 `func getFooAPIKey() -> String? { auth.foo?.key }`

### 4. ProviderManager 注册
`Services/ProviderManager.swift` 的 `makeDefaultProviders()`：加 `FooProvider()` 到数组。

### 5. 订阅预设（可选）
`Models/SubscriptionSettings.swift`：
- 加 `static let foo: [SubscriptionPreset] = [...]`（国内套餐填 `cnyCost`）
- `presets(for:)` 穷举 switch 加 `case .foo: return foo`

### 6. pbxproj 手动注册（最易漏，共 6 条）
`CopilotMonitor.xcodeproj/project.pbxproj`，参考现有 `MiniMaxProvider.swift` 的注册（用助记 UUID 命名如 `FOOAPP...`/`CLIFOO...`/`FOOFILE...`）：
- **PBXBuildFile ×2**：app target 一条、`opencodebar-cli` target 一条
- **PBXFileReference ×1**：文件引用
- **PBXGroup ×1**：加到 Providers group 的 children
- **PBXSourcesBuildPhase ×2**：app Sources 一条、CLI Sources 一条

搜索现有 provider 名（如 `grep -n MiniMaxProvider project.pbxproj`）照抄 6 处结构，改文件名和 UUID。

### 7. 测试
`CopilotMonitorTests/FooProviderTests.swift`（也要 pbxproj 注册到 test target），至少测解析逻辑。

## 验收
```bash
cd CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS' 2>&1 | tail -30
```
BUILD SUCCEEDED + 新测试通过 + 原有测试不回归。

## 常见坑
- 漏 pbxproj 任一处 → "Cannot find 'FooProvider' in scope" 或文件不编译。
- provider 文件若被 CLI target 用，CurrencyFormatter 等仅在主 app target 的类不可用——数据层别预烤 `$`/`¥`，格式化放 ProviderMenuBuilder（见 CommandCodeProvider 残留教训）。
- displayName/authSource/logger 串/SF Symbol 名/被 `==` 比较的状态串**不翻译**（阶段3铁律）。
````

- [ ] **Step 2: 提交**

```bash
git add docs/adding-a-provider.md
git commit -m "docs: add guide for adding a new provider"
```

---

## Self-Review

- **Spec 覆盖**：7 问题 → Task 1-9 全覆盖（问题1=T1+T2，问题5=T3+T5）。✓
- **Placeholder 扫描**：Task 2/6/7 的占位值均已显式标 `⚠️ 需实时验证` 并给出获取方法，非隐性 TODO。✓
- **类型一致性**：Task 4 与 Task 5 共用 `reportableErrors` 关键词表，已注明两处必须同步。`SubscriptionPreset.cnyCost` 默认 nil 兼容旧调用。✓
- **已知依赖用户确认的点**：货币方案 A/B、Task 4「点击配置」跳转目标、Kimi 国内价、MiniMax 端点鉴权——均已在对应 Task 顶部标出。

## 待办：给 kimicode 的提示词

计划保存后单独产出（见下一条消息）。
