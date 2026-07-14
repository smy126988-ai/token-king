# Token King Widget P2 — 视觉实现规范（给 minimax）

> 面向读者：写代码的 AI（minimax）
>
> 作者：外部技术审查员
>
> 日期：2026-07-14
>
> 前提：P0 已完成（数据通道跑通、沙盒墙穿过、tier 配色 + 环形表 + 焦点四态已实现）。本文是 **P2 视觉打磨**，把 widget 从「朴素」提升到用户在 Kiro 定稿的设计原型 v6 的观感。
>
> **设计原型（已归档，务必先看）**：
> - `docs/design/widget/service-monitor-prototype-v6.html`（浏览器打开，右上角切主题/焦点）
> - `docs/design/widget/service-monitor-DESIGN.md`（设计思路 + v0-v6 迭代教训）
> - `docs/design/widget/icons/*.svg`（6 个 lobe-icons 单色品牌图标）

---

## 0. 最重要：这份设计的来源与适配

**来源**：用户在 Kiro 为 `ai-infra service-monitor`（监控 c2cc 服务 + 模型额度）做的桌面组件设计，v6 定稿。视觉语言与 Token King widget **通用**（都是 macOS 桌面额度组件），但**数据模型不同，必须适配，不能照搬**：

| 维度 | service-monitor 原型 | Token King 实际 |
|---|---|---|
| 实体 | 服务(c2cc) + 模型(kiro/codex/…) 两类 | 只有 provider 额度，无「服务健康」概念 |
| provider 数 | ~5 个 | 30 个 |
| 数据源 | status.json 的 service/usage | 已有 `WidgetSnapshot`（version=1，windows[]+kind） |
| 「说人话」状态行 | 服务正常/异常/已停止 | **Token King 无此概念，跳过** |
| 端口/自愈/刷新按钮 | 有 | **widget 无交互，跳过刷新按钮；端口无意义** |

**适配原则**：借鉴原型的**视觉语言**（玻璃、aurora、tier 配色、环形表放图标、品牌图标、克制排版），**不借鉴** service-monitor 的业务语义（服务状态、端口、自愈）。

---

## 1. 已做对的（P0 保留，不要动）

对照 DESIGN.md，当前实现已经对齐的核心，**不要在 P2 破坏**：
- ✅ **焦点感知四态**：非选中去色 / 选中满色。这是 macOS widget 系统 `vibrant`/`fullColor` 自动行为——**只写满色版，用语义色（.green/.orange/.red）+ .primary/.secondary，系统自动派生去色版**。不要手写两套，不要在选中态换纯白背景。
- ✅ **tier 配色**：`<60% 绿 / 60-85% 橙 / >85% 红`（`WidgetDesignToken.severityColor` 已实现，阈值一致）。
- ✅ **环形表**（Small）+ 进度条（Medium/Large）。
- ✅ 英文 UI、SF 数字等宽、USD 2 位、`+N more` 不静默截断。

---

## 2. 要补的视觉（P2 核心，4 项）

### V1｜玻璃材质 + aurora 渐变背景（最大差距，优先做）

**现状**：widget 背景是系统默认灰（`.containerBackground(.fill.tertiary, for: .widget)`，见 `TokenKingWidget.swift:17`）。

**目标**：玻璃材质 + 极光渐变，对齐原型 `--wall` + `--glass`。

**实现**（SwiftUI，`TokenKingWidget.swift` 的 `.containerBackground`）：
```swift
.containerBackground(for: .widget) {
    ZStack {
        // aurora 渐变——对齐原型 --wall 的 4 层 radial + linear
        // 浅色：暖橙→粉紫→蓝紫；深色：深青→深紫→近黑
        LinearGradient(
            colors: [/* 见下方色值，用 Color(.sRGB) 从原型 hex 转 */],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        // 玻璃层
        Rectangle().fill(.ultraThinMaterial)
    }
}
```

**原型色值（从 `service-monitor-prototype-v6.html` CSS `--wall` 抄，禁止自己编）**：
- 浅色 `--wall`：4 层叠加
  - `radial-gradient(1000px 720px at 6% 0%, #ffb98f, transparent 58%)`
  - `radial-gradient(900px 800px at 100% 100%, #e9a9e0, transparent 55%)`
  - `radial-gradient(700px 600px at 55% 50%, #b9a8f0, transparent 60%)`
  - `linear-gradient(150deg, #ffcaa0, #eebbe0 55%, #c7d0f2)`
- 深色 `--wall`：`#1a3a44`→透明 / `#281c44`→透明 / `linear-gradient(150deg, #0d1316, #13101f 60%, #0c1417)`

**关键约束（与 AGENTS.md 的张力，必须处理）**：
- AGENTS.md 规则「不硬编码 RGB」是针对**语义色**（进度/状态用系统色）。**aurora 背景是装饰性渐变，本质需要具体色值**——这是合理例外，参照原型 hex。但**必须集中定义**在 `WidgetDesignToken` 里（如 `auroraLight: [Color]` / `auroraDark: [Color]`），不散落在 View。
- tier 配色、状态点**仍用系统语义色**，不受此例外影响。
- SwiftUI 的 `RadialGradient` 无法完全复刻 CSS 的 `Npx at X% Y%` 定位，**P2 允许用近似**：2-3 层 `RadialGradient`（`center: .topLeading/.bottomTrailing`）叠加即可，不追求像素级还原。目标是「暖橙-粉紫-蓝紫的极光气质」，不是精确复制。

**验收**：widget 有毛玻璃 + 渐变背景，深浅色各一套，观感接近原型（浏览器打开原型对比）。非选中态系统自动去色不受影响。

---

### V2｜品牌图标（lobe-icons，替换通用 SF Symbol）

**现状**：`TokenKingWidgetView.swift:317` `providerIcon(_:)` 用通用 SF Symbol（sparkles/gauge.medium 等）。

**目标**：用 `docs/design/widget/icons/*.svg` 的品牌图标，环中心放图标（Small）、名字前放图标（Medium/Large）。

**实现步骤**：
1. 6 个 SVG（claude/codex/kimi/kiro/opencode/xiaomimimo）导入 widget target 的 **Asset Catalog**，设为 **template rendering**（单色字形，可 tint）。
2. `providerIcon(_:)` 改为返回 asset 名；无对应品牌图标的 provider（Token King 有 30 个，图标只有 6 个）**fallback 到现有 SF Symbol**。
3. 品牌色 tint（原型定义，从 DESIGN.md §3）：`kiro #9046ff` / `claude #d97757` / `kimi #1783ff` / `codex·opencode` 用文字色 `.primary`。**同样集中进 `WidgetDesignToken`**。
4. **非选中态自动转灰**：用 template image + `.foregroundStyle`，系统 vibrant 会自动去色，不用手写。

**待用户定（DESIGN.md §5 遗留，先按①做，可后调）**：
- ① 图标品牌色 vs 纯单色 → **P2 先用品牌色**（原型 v6 定稿即品牌色），用户看了不满意再改纯单色。
- Token King 的 30 个 provider 里，只有能对上 lobe-icons 的用品牌图标，其余 fallback。**不要为凑齐 30 个去编图标。**

**验收**：Small 环中心有品牌图标，Medium/Large 名字前有品牌图标；无品牌图标的 provider 用 SF Symbol 兜底不崩。

---

### V3｜排版对齐原型（克制、原生感）

对照原型，调整现有 View 的排版细节（`TokenKingWidgetView.swift`）：
- Small 环形表：图标进环中心（现在图标在顶部 HStack，要挪进 `ZStack` 环中央），% 在环下方，provider 名在最下。对齐原型 `.gauge .ctr .ic` 结构。
- 字体：等宽用于所有数字/百分比（原型用 JetBrains Mono，SwiftUI 用 `.system(design: .monospaced)` 即可，**不引入外部字体**）。
- 卡片圆角、hairline 描边、内边距对齐原型 `.widget`（radius 22、1px hairline）——用 `WidgetDesignToken` 已有的 spacing token 微调。

**验收**：三尺寸排版接近原型，克制不花哨。

---

### V4｜第 4 family：accessoryRectangular（可选，排最后）

原型未涉及，但决策文档 §4.3 列了。**P2 可选**：加锁屏/通知中心单行组件，显示最紧张 provider 的 `名 + %`。做不做看时间，不阻塞 V1-V3。

---

## 3. 明确不做（防加戏）

- 不做 service-monitor 的「服务健康状态行」「端口」「自愈」——Token King 无此概念。
- 不做刷新按钮（widget 静态，RefreshIntent 归 P3，见决策文档）。
- 不引入外部字体（JetBrains Mono 用系统等宽替代）。
- 不为 30 个 provider 编 30 个图标——只用现有 6 个 lobe-icons，其余 SF Symbol 兜底。
- aurora 背景不追求像素级复刻 CSS，近似极光气质即可。
- 不动 P0 已跑通的数据通道 / 焦点四态 / tier 配色逻辑。

---

## 4. 实施顺序 + 验收

1. **V1 aurora + 玻璃**（最大观感提升，先做）→ 浏览器对比原型。
2. **V2 品牌图标**（导入 asset + tint + fallback）。
3. **V3 排版对齐**（图标进环心 + 等宽字体 + 圆角描边）。
4. **V4 accessoryRectangular**（可选）。

**每步**：`git` 快照 → 改 → 真机加 widget 看观感 → 单独 commit。

**全局验收**：
- `make test` 750（+新增）/0；SwiftLint 0 warning。
- 浏览器打开 `docs/design/widget/service-monitor-prototype-v6.html` 切「选中/非选中」，widget 真机观感接近。
- AGENTS.md：aurora 色值集中在 `WidgetDesignToken`（装饰性例外，已说明）；语义色仍用系统色；英文 UI；无 emoji。
- 非选中态系统自动去色仍正常（不被 aurora 破坏）。

---

## 5. 给 minimax 的一句话

P0 已把「数据能上桌面」跑通，骨架（焦点四态 + tier 配色 + 环形表）也对了。P2 只补「皮肤」：**aurora 渐变玻璃背景（V1，最关键）+ 品牌图标进环心（V2）+ 排版对齐原型（V3）**。视觉标准 = `docs/design/widget/` 里用户 Kiro 定稿的 v6 原型，色值从原型 CSS 抄、不要自己编。适配注意：Token King 只有 provider 额度，没有 service-monitor 的服务/端口/自愈概念。
