# /goal:Token King 小组件视觉还原(持续 loop 直到全部指标达标)

> 转给 Kimi Code,用 `/goal` 起一个持续 loop。地基已由 Claude 建好(DESIGN.md + design token + GlassCard),你只做**视觉还原 + 自验证**。
> **这不是"改一版交差"的任务。你要在 loop 里反复:改 → 编译 → 渲染截图 → 逐元素比对原型 → 打分 → 没达标就继续,直到下面「停止判据」全绿才允许收工。**

---

## GOAL(loop 的终止条件,全绿才算达成)

三类硬指标,**全部满足**才允许结束 loop。任一未达标,继续下一轮。

| 类别 | 指标 | 阈值 | 怎么测(命令/方法) |
|---|---|---|---|
| **工程健全性** | Widget target 编译 | `** BUILD SUCCEEDED **` | 见 §编译命令 |
| | Swift 编译 error | 0 | `xcodebuild ... \| grep "error:"` 无输出 |
| | SwiftLint | 0 violation | `swiftlint lint --path CopilotMonitor/TokenKingWidget` |
| | 无裸值(token drift) | 0 命中 | 见 §token-drift 检测命令 |
| | 范围隔离 | 只改允许文件 | `git diff --stat` 只含 `TokenKingWidgetView.swift`(+ 必要时 token 文件加常量) |
| **可观测性** | 每个 View 有 `#Preview` | 小/中/大 × 浅/深 × 四态 全覆盖 | `grep -c "#Preview" TokenKingWidgetView.swift` ≥ 6 |
| | 渲染日志 | 每次 body 求值可追踪 | 关键分支有 `WidgetLogger` 或 preview trait 注释 |
| | Fixture 可复现 | 假数据固定 | 用 §Fixture 里的固定快照,不随机 |
| **效果还原** | VLM 自评分(逐元素) | 每个尺寸 **≥85** | 见 §逐元素验收矩阵 + §自评方法 |
| | 逐元素通过率 | 矩阵中 **100% 项 = PASS** | 见 §逐元素验收矩阵 |
| | 四态观感正确 | 非选中去色/选中满色/始终玻璃 | 见 §四态验收 |

> **停止判据一句话:** 三尺寸每个 VLM ≥85 且逐元素矩阵全 PASS 且工程/可观测性全绿。达不到就继续 loop。

---

## 你是谁 / 做什么 / 不做什么

你是 Kimi Code(多模态),负责把 Token King macOS 桌面小组件 SwiftUI 视图**还原成设计原型**,并**自己看图验证**。多模态"看图对照"是你的核心武器,每轮都要用。

**不做**(已完成,动了就是破坏):
- 数据通道(JSON 快照读取)——已通。
- design token 数值(`WidgetDesignToken.swift` 里的 hex/pt)——已按原型精确值定好,**只引用不改数值**(可加新常量,不可改已有值)。
- 品牌图标映射(`providerAssetName`/`providerIconSystemName`)——已对齐主 app。
- pbxproj / entitlements / SharedPaths。

**做**:改 `CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift`,并为它加 `#Preview`。

---

## 开工前必读(顺序别乱)

1. **`DESIGN.md`**(仓库根)——视觉规则唯一真相源。YAML 前置块=精确 token,markdown=为什么。**这是宪法。**
2. **`docs/design/widget/service-monitor-prototype-v6.html`**——视觉原型。浏览器打开,右上角切主题(浅/深)+ 焦点(选中/非选中)。**四态各截一张图存本地当基准。**
3. **`CopilotMonitor/TokenKingWidget/WidgetDesignToken.swift`**——token 层,你写视图只引用这里。
4. **`CopilotMonitor/CopilotMonitor/Shared/WidgetSnapshot.swift`**——数据模型(下面 Fixture 就是照它造的)。

已封装好、直接用的 API:
- `Color(hex: "#xxxxxx")`
- `WidgetDesignToken.Severity.green(scheme)/.amber(scheme)/.red(scheme)`
- `WidgetDesignToken.Ink.primary(scheme)/.secondary(scheme)/.faint(scheme)`
- `WidgetDesignToken.Brand.kiro/.claude/.kimi`
- `WidgetDesignToken.Aurora.*`
- `.glassCard()` — 玻璃卡(圆角+材质+描边)
- `Double.severityColor(scheme)` — 百分比 → 严重度色
- `@Environment(\.colorScheme) private var scheme`

---

## 逐元素验收矩阵(每轮对每个尺寸逐项打勾,不许跳)

对**每个尺寸**,逐元素比对原型截图,判 PASS/FAIL,记录差异。**任一 FAIL 就继续改。**

### 小尺寸 systemSmall(原型 `.w-rings`)
| # | 元素 | 原型规格 | token | 判据 |
|---|---|---|---|---|
| S1 | 卡片圆角 | 22pt continuous | `cardCornerRadius` | 圆角弧度肉眼一致 |
| S2 | 玻璃背景 | blur 38 材质 | `.glassCard()` | 有磨砂/透明感,非纯色块 |
| S3 | 环直径 | 66pt | `ringDiameter` | 环占比与原型一致 |
| S4 | 环线宽 | 7pt 圆头 | `ringStroke` + `.round` | 粗细+端点圆 |
| S5 | 环底轨 | track 灰 | — | 未填充部分可见浅轨 |
| S6 | 环填充色 | 严重度 | `severityColor(scheme)` | 28%绿/59%橙/87%红 对得上 |
| S7 | 图标居中 | 环正中心 24pt | `ProviderIconView` | 图标在环心,不偏 |
| S8 | 百分比 | 环下 13pt 等宽 | `percentRingSize` mono | "28%" 位置字号 |
| S9 | provider 名 | 最下 faint | `Ink.faint` caption | 名字在最底 |

### 中尺寸 systemMedium(原型 `.w-med`)
| # | 元素 | 原型规格 | token | 判据 |
|---|---|---|---|---|
| M1 | 卡头状态点 | 8pt | `dotSize` | 左上有圆点 |
| M2 | 卡头图标+名 | 图标 + 14pt 粗 | `wNameSize` | 图标在名字前 |
| M3 | 右上 badge | 端口/"模型用量" | `portSize` | 右上有胶囊标签 |
| M4 | 大数值 | 24pt 等宽粗 | `percentBigSize` mono | "2,853" 醒目 |
| M5 | `/` + 上限 | 灰 | `Ink.secondary` | "/10,000" |
| M6 | 进度条 | 高6圆角6 严重度 | `barHeight`/`barRadius` | 条形正确上色 |
| M7 | 双窗口 | 竖排两条+重置 | — | Codex 5h/周 各一行 |
| M8 | 页脚 | 刷新于+周期 | `captionSize` faint | 底部两端对齐 |

### 大尺寸 systemLarge(原型 `.w-lg`)
| # | 元素 | 原型规格 | token | 判据 |
|---|---|---|---|---|
| L1 | 卡头标题 | "Token King" | `Ink.primary` | 顶部标题 |
| L2 | 每行结构 | 点+图标15+名+值+条 | — | 行内五元素齐 |
| L3 | 行进度条 | 严重度色 | `severityColor` | 每行条上色对 |
| L4 | 折叠 | "+N more" | `Ink.faint` | 超限折叠正确 |
| L5 | 月费页脚 | 底部金额 | `USDFormatter` | 有月度花费 |

---

## 四态验收(最关键的原生感)

你**只写满色版**,系统按焦点派生去色版:
- **选中**(桌面获焦)= 玻璃 + 满色。
- **非选中**(无焦点)= 玻璃 + 全去色(系统 `vibrant` 自动,你别管)。
- ⚠️ 进度条非选中变白/灰是 **macOS 特性,不是 bug,不许"修"**。
- ⚠️ 选中态背景仍是玻璃,**不许换纯白**。
- 实现:语义色 + `.primary/.secondary` + 需跟随强调色的元素加 `.widgetAccentable()`,**不写两套配色**。

验收:`.environment(\.colorScheme, .dark/.light)` + widget rendering mode preview 各截图,确认四态表现。

---

## 可观测性要求(让"还原到什么程度"可追踪,不靠嘴说)

1. **每个 View 加 `#Preview`**,覆盖 小/中/大 × 浅/深(≥6 个),用下面 Fixture 的固定数据。
2. **Preview 命名带状态**,如 `#Preview("Small/Dark/Focused")`,截图能对号入座。
3. **关键渲染分支留痕**:body 里 `kind`/`windows.count` 分支处,用注释标明命中的原型形态(环/单条/双窗口/金额),方便比对时定位。
4. **Fixture 固定不随机**:所有截图基于同一份假数据,保证轮次间可比。

---

## Fixture(照 WidgetSnapshot schema 造的固定假数据,放 preview 里用)

```swift
extension WidgetSnapshot {
    static var previewFixture: WidgetSnapshot {
        let now = Date()
        func reset(_ h: Int) -> Date { now.addingTimeInterval(Double(h) * 3600) }
        return WidgetSnapshot(
            version: 1,
            snapshotAt: now,
            providers: [
                ProviderSnapshot(id: "kimi_cn", displayName: "Kimi", kind: .quota,
                    primaryWindowId: "monthly",
                    windows: [UsageWindow(id: "monthly", label: "本月", usedPercent: 87,
                        resetsAt: reset(240), used: 8700, limit: 10000)],
                    spendUSD: nil, fetchedAt: now),
                ProviderSnapshot(id: "codex", displayName: "Codex", kind: .quota,
                    primaryWindowId: "5h",
                    windows: [
                        UsageWindow(id: "5h", label: "5 小时", usedPercent: 25, resetsAt: reset(2), used: 38, limit: 150),
                        UsageWindow(id: "weekly", label: "周限额", usedPercent: 59, resetsAt: reset(72), used: 1180, limit: 2000)],
                    spendUSD: nil, fetchedAt: now),
                ProviderSnapshot(id: "claude", displayName: "Claude", kind: .quota,
                    primaryWindowId: "5h",
                    windows: [UsageWindow(id: "5h", label: "5 小时", usedPercent: 40, resetsAt: reset(3), used: 40, limit: 100)],
                    spendUSD: nil, fetchedAt: now),
                ProviderSnapshot(id: "kiro", displayName: "Kiro", kind: .quota,
                    primaryWindowId: "power",
                    windows: [UsageWindow(id: "power", label: "积分", usedPercent: 28.5, resetsAt: reset(120), used: 2853, limit: 10000)],
                    spendUSD: nil, fetchedAt: now),
                ProviderSnapshot(id: "openrouter", displayName: "OpenRouter", kind: .usage,
                    primaryWindowId: nil, windows: [], spendUSD: 37.42, fetchedAt: now)
            ],
            monthlyCost: MonthlyCost(usd: 124.80, rmb: 892.30)
        )
    }
}

// 示例 preview(照此补齐 6+ 个)
#Preview("Small/Light/Focused", as: .systemSmall) {
    TokenKingWidget()
} timeline: {
    TokenKingEntry(date: .now, snapshot: .previewFixture, readStatus: .ok, snapshotAgeSeconds: 30)
}
```

---

## 每一轮 loop 必做的六步(缺一步 = 这轮无效)

```
① 改视图(只引用 token,不写裸 hex/裸 pt/裸字号)
② 编译(见下)→ 必须 SUCCEEDED,有 error 先修
③ token-drift 检测(见下)→ 必须 0 命中
④ 渲染截图:6+ 个 preview 各截图(小/中/大 × 浅/深,含四态)
⑤ 逐元素比对:对每个尺寸走完上面的验收矩阵,逐项 PASS/FAIL + VLM 打分
⑥ 判定:全绿 → 收工;否则记录"这轮改了啥 / 分数 / 还差哪几项" → 回 ①
```

### 编译命令
```bash
cd CopilotMonitor && xcodebuild build -scheme CopilotMonitor \
  -target TokenKingWidget -destination 'platform=macOS' \
  -derivedDataPath /tmp/tk-widget 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

### token-drift 检测命令(必须 0 输出)
```bash
grep -nE 'Color\(red:|Color\(#|#[0-9a-fA-F]{6}|\.system\(size: *[0-9]+|cornerRadius: *[0-9]+|lineWidth: *[0-9]+' \
  CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift
```
有命中 = 视图里写了裸值,必须换成 `WidgetDesignToken.*`。

### 自评方法(VLM 打分)
你自己是多模态:把你渲染的截图 + 原型对应截图并排看,按 §逐元素矩阵逐项判,给每个尺寸一个 0-100 分。评分维度:玻璃质感 / 圆角 / 环形表 / 图标位置大小 / 字体层级 / 语义配色 / 间距对齐。**<85 或有 FAIL 项 → 继续。**

---

## 每轮报告格式(loop 里每轮都输出这个,便于追踪收敛)

```
## Round N
改动:<一句话>
编译:** BUILD SUCCEEDED **   error:0   swiftlint:0   token-drift:0
截图:small✓ medium✓ large✓ (light/dark/focus)
逐元素:小尺寸 8/9 PASS(S5 底轨太浅)| 中 8/8 | 大 5/5
VLM:小 82 / 中 88 / 大 90
未达标:小尺寸 S5 + 小尺寸<85 → 下一轮修底轨对比度
```

分数应逐轮收敛。若连续 2 轮无提升,换思路(重看原型该元素的 CSS,别在同一处反复微调)。

---

## 硬门槛(收工报告必须给证据,否则视为没做)

1. 编译原文 `** BUILD SUCCEEDED **`(贴出来,不是"应该能过")。
2. `grep "error:"` 无输出。
3. token-drift 命令 0 命中。
4. 三尺寸每个 VLM ≥85 且逐元素矩阵全 PASS(贴最终矩阵)。
5. `git diff --stat` 只动 `TokenKingWidgetView.swift`(+ 可选 token 文件加常量)。

---

## 参考血缘 / 前车之鉴

- 视觉宪法:`DESIGN.md`(仓库根)。
- 原型来源:`ai-infra/apps/service-monitor`(设计原则复用)。
- ⚠️ **上上轮教训**(`docs/handoffs/2026-07-14-widget-v2-real-assets.md`):有人手写 340 行 SVG parser,编译失败还谎报"通过"。**本任务硬门槛第 1 条就是治这个——先真编译过,再谈还原。别自欺。**
