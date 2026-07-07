# F2a — Pay-as-you-go Pricing Table（API 价硬编码基础设施）

> 状态：设计已获用户逐节确认（2026-07-07）。覆盖 F2a = "硬编码 API 单价表"基础设施层；F2b（UI 展示）/ F2c（跨 provider 汇总）后续单独 spec。
> 关联：`docs/需求池.md` F2 / F2a。`docs/handoffs/2026-07-07-b44-session-handoff.md` 项目状态。`~/.claude/projects/-Users-simengyu/memory/项目/Token King.md` 长期项目原则。

## 1. 动机 / 背景

用户原话（2026-07-07 需求池.md）：

> "加金额转比，比如 199 元的 kimi 订阅，按照 api 价格，我当前花了多钱"

Token King 当前**没有任何"按量价 vs 订阅价"对比能力**。`SubscriptionSettings.totalMonthlyCostDisplayText` 只算订阅累加（`"额度状态 ¥1329/月"`），不感知实际用量、不感知按量等效价。

**F2a 目标**：提供"每个 quota-based provider 的代表 model 按量单价"基础设施。F2b/F2c 调这个数据算"订阅 vs 按量"经济学。

**F2a 范围**：

- ✅ quota-based provider 的"按量价"（input / output / cache token 单价 per M tokens）
- ✅ 公开定价页查得到的 6 个 provider（+ 1 个 Copilot 标 nil）
- ❌ 计算逻辑（→ F2b）
- ❌ UI 展示（→ F2b / F2c）
- ❌ 公开定价页拉取 / 用户手设 override（→ 后续）
- ❌ pay-as-you-go provider 的"按量价"——按量就是按量，没"订阅价"可比

**F2a 决策记录**（2026-07-07 brainstorm 4 问）：

| 决策点 | 选择 | 备选 |
|---|---|---|
| 覆盖范围 | 只 quota-based provider | pay-as-you-go + quota-based 全覆盖 |
| 数据粒度 | 每 provider 一个 `PayAsYouGoRate`（含 input/output/cache 三价） | per-provider-per-model 多价 / 单 value |
| 硬编码源 | 编译期 Swift const in `Helpers/PricingTable.swift` | bundle plist/json / UserDefaults |
| Provider 清单 + 查不到 | Kimi/KimiCN/Claude/Z.AI/NanoGpt/Codex 6 个；Copilot/Antigravity/4 国内 nil | 只 3 个起步 / 查不到用估算 |
| 货币单位 | **RMB**（¥/M tokens） | USD（项目"USD 是数据层唯一真值"原则） |

## 2. 偏离项目原则的说明

**项目原则**："USD 是数据层唯一真值，国内用 cnyCost 人民币原生价，只在渲染边缘转换"（见 `~/.claude/projects/-Users-simengyu/memory/项目/Token King.md` 第 24 行）。

F2a 选择**存 RMB** 而非 USD，理由：

1. **来源不同**：PayAsYouGoRate 是"硬编码自公开定价页"的常量，不是从数据层收的 token 数。CurrencyFormatter 的 currentRate 是动态汇率，跟"硬编码时那天的汇率"无强绑定。
2. **避免双重漂移**：存 USD + 走 currentRate 转 RMB，汇率漂移时让 UI 显示偏差更大（定价漂移 × 汇率漂移）。存 RMB 直接暴露定价漂移，让用户能立刻看到 stale。
3. **简化**：F2a 起步要 1-2 天可验证，去掉 currency 字段简化类型。

**接受 trade-off**：PayAsYouGoRate 跟汇率脱钩后，海外 provider（Claude/Copilot/Codex/NanoGpt）如果想看 USD 等效价需手工除汇率。F2b 落地时如果用户要 USD 视图再加 `currency: .usd` 字段 + 算时除当前汇率。

**revisit 触发**：F2b 落地时如果发现"海外 provider 用户想看 USD 等效价"是高频诉求，spec v2 加 `currency` 字段。F2a v1 不加。

## 3. 架构

### 3.1 文件布局

新增：

- `CopilotMonitor/CopilotMonitor/Helpers/PricingTable.swift` — 数据 + 查询 API
- `CopilotMonitor/CopilotMonitorTests/Helpers/PricingTableTests.swift` — 单元测试

**pbxproj 注册**：4 处（PBXBuildFile / PBXFileReference / PBXGroup / PBXSourcesBuildPhase），per AGENTS.md 项目规则。新增 1 个 .swift test 文件 = 4 处 × 2 = 8 处 edit。

### 3.2 数据形态

```swift
/// 单个 provider 的"假设按量价"。单位：¥/百万 tokens (RMB per million tokens)。
/// `cache == nil` 表示该 provider 不公开 cache 价或 cache 价不单独定价。
struct PayAsYouGoRate {
    let input: Double
    let output: Double
    let cache: Double?
}

/// 公开定价页硬编码的 quota-based provider 按量价表。
/// 维护策略：定价页改了手动改这里。源码注释附公开页 URL + 查询日期。
enum PricingTable {
    /// 返回 provider 的代表 model 按量价。nil = 无公开价或 Premium-request 模型（Copilot / Antigravity / Mimo / VolcanoArk / Hunyuan / ZhipuGLM 等）。
    static func rate(for provider: ProviderIdentifier) -> PayAsYouGoRate?
    
    /// 列出所有有公开价的 quota-based provider。F2b/F4 用。
    static var providersWithPublicPricing: [ProviderIdentifier] { get }
}
```

### 3.3 6 个 Provider 定价骨架

> 具体数字已于 2026-07-07 通过 subagent 并行调研各 provider 公开定价页填入。
> 源码注释附：定价页 URL + 查询日期 + 代表 model 选型理由。
> 详细调研笔记见 `docs/superpowers/research/f2a-pricing-research-2026-07-07.md`。

| Provider | 代表 model | Input ¥/M | Output ¥/M | Cache ¥/M | 公开页 URL（已填，2026-07-07）|
|---|---|---|---|---|---|
| `kimi` | kimi-k2.6 | 6.50 | 27.00 | 1.10 | platform.moonshot.cn/docs/pricing/chat-k26 |
| `kimiCN` | kimi-k2.6 (国内同价) | 6.50 | 27.00 | 1.10 | platform.moonshot.cn/docs/pricing/chat-k26 |
| `copilot` | N/A (Premium request model) | nil | nil | nil | docs.github.com/copilot — out of scope: Copilot Premium is request-multiplier, not per-token rate |
| `claude` | claude-sonnet-4-5 | 20.37 | 101.85 | 25.46 (write) | anthropic.com/pricing |
| `zaiCodingPlan` | glm-4.6 | 4.07 | 14.94 | 0.75 (read) | docs.z.ai/guides/overview/pricing |
| `nanoGpt` | gpt-4o (pass-through) | 16.98 | 67.90 | nil | nano-gpt.com/pricing (best-effort, JS-rendered) |
| `codex` | gpt-4o | 16.98 | 67.90 | 8.49 (read) | platform.openai.com/docs/pricing |

**5 个暂不覆盖**（公开定价页查不到或估算无依据）：

- `antigravity` — Google 不公开 token 单价
- `mimo` / `volcanoArk` / `hunyuan` / `zhipuGLM` — 国内平台定价页情况各异，待 P2 调研
- `grok` / `commandCode` / `cursor` / `kiro` / `synthetic` / `chutes` / `geminiCLI` — 当前 F2a scope 外（包含 subscription 但公开 token 单价难查）

→ `rate(for: .antigravity)` 返回 nil，F2b UI 显示 "API 价：N/A"。

### 3.4 与已有 `ProviderSubscriptionPresets` 的关系

`Models/SubscriptionSettings.swift:126` 已有 `ProviderSubscriptionPresets`，存每个 provider 的"订阅套餐原生价"（cnyCost）。**F2a 是镜像这个模式**，存"按量价"——两者构成完整的"订阅 vs 按量"对比基础。

**不**合并到 `ProviderSubscriptionPresets` —— 责任不同：

- `ProviderSubscriptionPresets`：订阅档位（plan name + cost + cnyCost）
- `PricingTable`：按量单价（input/output/cache rate）

独立 file 让 reflection 互不污染，也方便后续 F2b 单独引用。

## 4. 数据流

```
                ┌──────────────────┐
                │ PricingTable     │  ← 编译期常量，无 IO
                │ (static func)    │
                └────────┬─────────┘
                         │ PayAsYouGoRate
                         │ (F2a 只产数据)
                         ▼
                ┌──────────────────┐
                │ F2b / F2c        │  ← 后续 spec
                │ (计算 + UI)      │
                └──────────────────┘
```

F2a 自身**不做计算**，只产数据。F2b 才会 `PricingTable.rate(for: .kimi) × tokenUsage.input + ... = costRMB`。

## 5. 错误处理

- `rate(for:)` 找不到 = 返回 nil（**不抛错**）
- F2a 没有任何 IO / 异步 / 异常路径

## 6. 测试策略

### 6.1 单元测试（必须）

`PricingTableTests.swift`：

| 测试 | 验证 |
|---|---|
| `testAll6CoveredProvidersReturnNonNilRate` | 6 个 provider 全部有 rate |
| `testProvidersWithPublicPricingContainsExactly6` | 公开 API 列出的 provider 集合 = 6 个 |
| `testCopilotReturnsNil` | Copilot Premium 是 request 倍率非按量 → 返 nil |
| `testAntigravityReturnsNil` | 公开页查不到的 provider 返回 nil |
| `testOtherUncoveredProvidersReturnNil` | mimo / volcanoArk / hunyuan / zhipuGLM 返回 nil |
| `testRateValuesArePositive` | 所有 rate > 0（不出现 0/负数/NaN） |
| `testOutputRateGreaterOrEqualToInputRate` | 业界惯例 output ≥ input（防数据录入错误） |
| `testKimiAndKimiCNHaveSameRate` | 同一代表 model 同价（防 KimiCN 误填 Global 海外价） |

### 6.2 E2E 测试

F2a **不需要 e2e**（无 UI / 无 IO / 无副作用）。F2b 落地时再做 e2e driver test（per 项目"UI bug 必须 e2e driver test"规则）。

## 7. 风险 / 已知 trade-off

| 风险 | 影响 | 缓解 |
|---|---|---|
| Hardcode 数字过期 | 高（定价漂移会让"按量价"显示失真） | 源码注释附 URL + 查询日期；refresh 时 review；F2b UI 加 [stale] 标记（P2） |
| 代表 model 选择偏颇 | 中（用户用别的 model 会有偏差） | 选"用户最常用" model；F2b 落地时考虑"按 user selected model 细分"（P2） |
| Antigravity 等 5 个不公开 | 中（用户用这些看不到按量价） | F2b UI 标 N/A；后续 P2 调研 |
| 偏离 USD 唯一真值原则 | 低（F2a 接受，见 §2） | F2b 落地时如需 USD 视图，spec v2 加 `currency` 字段 |
| PayAsYouGoRate 5 个不覆盖 provider 后续要加 | 低（function-level switch，加 case 即可） | implementation 时 follow "switch exhaustiveness" 编译检查 |

## 8. 范围外（明确）

- 计算逻辑（input × rate + output × rate + cache × rate = cost）→ F2b
- UI 展示（"订阅 vs 按量" 折算行）→ F2b（单 provider）/ F2c（跨 provider 汇总）
- 公开定价页定期拉取 → 后续 spec
- 用户手设 override（`UserDefaults`）→ 后续 spec
- Antigravity / Mimo / VolcanoArk / Hunyuan / ZhipuGLM 等 5 个不公开 provider → 后续调研补
- pay-as-you-go provider 的"按量价 vs 订阅价"对比 → **永远不做**（按量就是按量，无订阅可比）
- 跟 `UsageHistory` 的整合（聚合 daily 按量 cost）→ F1 数据基建

## 9. 实施步骤（high-level，不展开为 plan）

> 详细 plan 走 `writing-plans` skill 单独产出。

1. **建 file**：`Helpers/PricingTable.swift` + `Helpers/PricingTableTests.swift` + pbxproj 4+4 处注册
2. **填数据**：6 个 provider 的 PayAsYouGoRate（Copilot 标 nil）调研 + 填值 + 注释
3. **测试**：8 个单元测试全 pass
4. **PR 验证**：`xcodebuild test` 全 414+8 = 422 测试通过
5. **CLAUDE.md 信号 + version bump**：per 项目规则

## 10. Files Affected

```
新增：
  CopilotMonitor/CopilotMonitor/Helpers/PricingTable.swift
  CopilotMonitor/CopilotMonitorTests/Helpers/PricingTableTests.swift
修改：
  CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj  (8 处: 2 file × 4 register locations)
```

## 11. 验收

- [ ] 8 个单元测试全 pass
- [ ] 总测试数从 414 涨到 422（全 pass）
- [ ] `PricingTable.rate(for: .kimi)` 返回 `PayAsYouGoRate(input: 6.50, output: 27.00, cache: 1.10)`（2026-07-07 调研值）
- [ ] `PricingTable.rate(for: .antigravity)` 返回 nil
- [ ] 源码注释包含定价页 URL + 查询日期
- [ ] 无新增 dead code（每个新增 type/func 在 spec 里有引用）
- [ ] commit message 英文（per AGENTS.md upstream 规则——本 fork 覆盖了但 commit 仍走英文）
- [ ] CLAUDE.md 信号 + version bump per 项目规则
