# F2b Session Handoff — 2026-07-08

> Source: 2026-07-07 user choice "F2b（推荐）"  after F2a 5-commit landing (d443677 + 4 prior).
> Reads: F2a spec / plan / research / implementation commits + session signal log.

## F2a 已落地（2026-07-07 闭环）

- `d443677` chore: bump v2.12.0
- `57a09db` build: pbxproj 8 处注册
- `87c4ef7` feat: PricingTable.swift + 8 tests + spec + research
- `f82b424` docs: implementation plan
- `3701162` docs: spec

**测试**: 422 pass / 19 skipped（live-network）/ 0 fail
**Push**: origin (smy126988-ai/token-king), 147 ahead / 4 behind upstream（fork policy）

## F2a 已开放的接口（直接用）

```swift
import OpenCode_Bar

// 6 个 provider 有 rate; 21 个 nil
let rate = PricingTable.rate(for: .kimi)
// rate.input, rate.output (RMB ¥/M tokens), rate.cache?

// 列出所有有公开价的 quota-based provider
let providers = PricingTable.providersWithPublicPricing
// [.kimi, .kimiCN, .claude, .zaiCodingPlan, .nanoGpt, .codex]
```

## F2b 范围（已结构化在 docs/需求池.md F2 + F2b）

**F2b = 单 provider UI 展示 "API 价 vs 订阅价"**

需求池.md 的"潜在拆解"：
> F2b: 单 provider 头部加一行 API 价 vs 订阅价

**用户原话**（"kimi 199 元订阅，按当前 API 用量折算我花了多少"）：
- 顶部 header 加新行：「按量价: ¥XXX / 订阅: ¥YYY / 节省/超出: ¥ZZZ」
- OR 单 provider 详情里加 1 个新 row
- 显示粒度 + 计算口径需要决策

## F2b 已知的 5 个开放问题（next session 进 brainstorm 时先问这 5 个）

| # | 问题 | F2a 已经处理的部分 |
|---|---|---|
| 1 | 计算口径 — 本月累计 token × rate vs 上次 fetch token × rate vs 日聚合 × 月聚合 | F2a 不算, 只给 rate。F2b 算 |
| 2 | 展示形态 — "API 价 ¥450 / 订阅 ¥199" vs "(API 价 / 订阅价) × 100 = 226%" | F2a 不涉及 |
| 3 | 单 provider 顶部 vs 跨 provider 汇总 — F2b scope 是哪个 | 需用户拍 |
| 4 | token 拆分粒度不统一 — Z.AI/NanoGpt/Codex 字段不同, 怎么算 cost | F2a 不能解, F2b 必须用估算策略 |
| 5 | 持久化本月累计 token 数据 — 跟 F1 数据基建重叠 | F1 是独立大任务, F2b 可走"in-memory 月度累计"绕过 |

## 关键数据基础（relevance 评估）

| Provider | F2a rate 有 | token 数据有（月度）| F2b 能算吗 |
|---|---|---|---|
| Kimi | ✅ ¥6.50/¥27.00 | ❌ 只有 quota%, 无 input/output 拆 | ⚠️ 用 tokenUsageUsed (总额) × 平均 rate 估算 |
| Kimi CN | ✅ 同 Kimi | ❌ 同上 | ⚠️ 同上 |
| Claude | ✅ ¥20.37/¥101.85 | ❌ 同上 | ⚠️ 同上 |
| Z.AI Coding Plan | ✅ ¥4.07/¥14.94 | ✅ `totalTokensUsage` 字段（line 91） | ✅ input rate × totalTokensUsage, 估算成本 |
| NanoGpt | ✅ ¥16.98/¥67.90 | ✅ `weeklyInputTokens`/`dailyInputTokens`（line 11-17） | ⚠️ 只 input 拆, 无 output 拆, 只能算 input 部分 |
| Codex | ✅ ¥16.98/¥67.90 | ✅ `totalTokens`/`cachedInputTokens` | ⚠️ 有 total 和 cache, 无 input/output 拆 |
| Copilot | ❌ nil | ❌ | ❌ UI 显示 "不适用" |

**结论**: F2b 起步 = **in-memory 月度 token 累计** + 用 `tokenUsagePercent/Used/Total` 字段粗算。**严格"按 token 数 × 单价"要等 F1 数据基建。**

## 关键文件位置（next session 必读）

- `Helpers/PricingTable.swift` — F2a 产出的查表 API
- `Helpers/PricingTableTests.swift` — F2a 8 个测试
- `Models/ProviderResult.swift:207-210` — `tokenUsagePercent/Reset/Used/Total` 字段定义
- `App/StatusBarController.swift:2011` — 顶部 header "额度状态 ¥1329/月" 位置
- `App/StatusBarController.swift:4335-4370` — `aggregatedDailyCosts` in-memory 跨 provider USD 累计（参考实现模式）
- `Helpers/ProviderMenuBuilder.swift:758-768` — tokenUsage % 在单 provider 详情的现有渲染

## F2b brainstorm 流程建议

按 superpowers brainstorming skill：
1. 读本 handoff + F2a spec/plan + 需求池.md
2. 问 user scope/计算口径/展示形态/UI 位置 4 个核心问题
3. 提 2-3 个 design approach
4. 写 spec + 写 plan
5. 实施 + e2e driver test（per 项目"UI bug 必须 e2e"规则）
6. CLAUDE.md signal + bump version

## 不立即开始 F2b 的理由

- 当前 session 已 1.5+ 小时, 4 commits + 4 subagent dispatch + 多轮 review, context 风险高
- F2b 是 UI 层（需要真 e2e driver test + Xcode 跑 build + 截图验证），单 session 难闭环
- next session 拿本 handoff + 现成 spec/plan 模板, 启动快

## 项目活跃度

- 2026-07-08 next session 启动提示：`docs/handoffs/2026-07-08-f2b-session-handoff.md`（本文件）
- 长期项目状态：`~/.claude/projects/-Users-simengyu/memory/项目/Token King.md`（需在 F2a 落地后更新）
- 版本号：v2.12.0 → 下一个 v2.13.0 (F2b 估 minor bump)
- 跳过项：B39/B40/B46 (low priority, multi-monitor/timezone 留 backlog)
