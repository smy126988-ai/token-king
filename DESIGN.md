---
# ============================================================================
# Token King Widget — 机器可读设计 token（唯一真相源）
# ============================================================================
# 本 YAML 块是 SwiftUI 侧 WidgetDesignToken.swift 的规范来源。
# 改视觉先改这里，再让代码跟上；代码里的字面量必须能追溯到这里的某个 key。
# 颜色一律 hex（含 # 前缀），深浅两套；数值单位 pt。
# 视觉原型:docs/design/widget/service-monitor-prototype-v6.html(源:ai-infra)

meta:
  prototype: docs/design/widget/service-monitor-prototype-v6.html
  status: 视觉方向已定稿(原型 v6)
  target: widget 能力内最接近原型(非 1:1 — WidgetKit Material 不透壁纸)

# --- 极光背景(装饰性渐变,containerBackground 用)---------------------------
aurora:
  light:
    # 三个 radial 焦点 + 一个 linear 收尾,顺序照 CSS --wall
    radial: ["#ffb98f", "#e9a9e0", "#b9a8f0"]
    linear: ["#ffcaa0", "#eebbe0", "#c7d0f2"]   # 150deg,中段 55%
  dark:
    radial: ["#1a3a44", "#281c44"]
    linear: ["#0d1316", "#13101f", "#0c1417"]   # 150deg,中段 60%

# --- 玻璃卡(WidgetKit 只能糊卡片内容,糊不到壁纸)---------------------------
glass:
  light:       { fill: "#ffffff", opacity: 0.24 }
  light_focus: { fill: "#ffffff", opacity: 0.52 }
  dark:        { fill: "#1c1e24", opacity: 0.30 }
  dark_focus:  { fill: "#1c1e24", opacity: 0.50 }
  blur: 38            # backdrop blur pt(SwiftUI 用 .ultraThinMaterial 近似)
  saturate: 1.50

# --- 语义色:用量严重度(<60 绿 / 60–85 橙 / >85 红)+ 健康状态点 ----------
severity:
  light: { green: "#28c63f", amber: "#e0972a", red: "#e8453f" }
  dark:  { green: "#34d94a", amber: "#f5b134", red: "#ff5b52" }
  threshold: { amber_at: 60, red_at: 85 }   # >= 值切色

# --- 文字色(ink 三级)-------------------------------------------------------
ink:
  light: { primary: "#2a2433", secondary: "#615a6d", faint: "#9a92a4", glance: "#3c3448" }
  dark:  { primary: "#eef2f0", secondary: "#9aa4a6", faint: "#646d71", glance: "#ffffff" }

# --- 品牌 tint(只给身份识别,克制;非选中态系统自动去色)--------------------
brand:
  kiro:   "#9046ff"
  claude: "#d97757"
  kimi:   "#1783ff"
  codex:  ink.primary        # 无品牌色,用文字色
  opencode: ink.primary

# --- 字体 --------------------------------------------------------------------
typography:
  mono: "系统等宽(.monospaced) — 原型用 JetBrains Mono,widget 内用系统等宽替代"
  sans: "系统(.system) — SF Pro"
  sizes:
    w_name: 14        # 卡片标题/服务名
    body: 13          # 正文
    percent_ring: 13  # 环下百分比(gpct)
    percent_big: 24   # 中卡主数值(big)
    caption: 11       # 说明/页脚
    m_label: 9.5      # 分组小标签(全大写 + letter-spacing)
    port: 10          # 端口/badge

# --- 尺寸 / 圆角 / 间距 ------------------------------------------------------
metrics:
  card_radius: 22
  bar_height: 6
  bar_radius: 6
  ring_stroke: 7          # 环线宽(trk/val 同)
  ring_cap: round        # 值弧圆头
  ring_diameter: 66      # 小尺寸环直径
  dot_size: 8            # 状态点
  hairline: 0.5          # 描边

# --- 三尺寸画布(pt,照原型 w-rings/w-med/w-lg)-----------------------------
family:
  small:  { w: 380, h: 172, layout: "环形表 — 图标在环中心 / % 在下 / 名字最下" }
  medium: { w: 380, h: 172, layout: "单/双 provider 详情 — 图标在名字前 + 进度/双窗口" }
  large:  { w: 380, h: 362, layout: "多 provider 聚合 — 每行 图标+名字+数值+进度条" }
---

# Token King Widget — 设计文档

> 视觉方向已定稿(原型 v6)。本文 = 设计思路 + 最终规范,供 SwiftUI 实现与 Kimi 视觉还原参照。
> **本文是视觉规则的唯一真相源。** 改视觉先改这里(YAML token),再让 `WidgetDesignToken.swift` 跟上。
> 血缘:视觉原型出自 `ai-infra/apps/service-monitor`(c2cc/kiro 场景);Token King 复用其**设计原则**,但数据契约是 Token King 自己的 22 家 provider + `windows[]`/`kind` schema。

---

## 0. 这是什么

Token King 桌面小组件:**一眼看到 22+ 家 AI provider 的额度消耗与月度花费**。
数据由主 app(`com.tokenking.app`)写入沙盒可读的 JSON 快照,widget(沙盒)只读它——不发网络、不算数据,纯展示。

---

## 1. 核心设计原则(最重要,先看这个)

1. **对齐原生,不自创一套。** macOS 原生小组件长什么样就长什么样——玻璃材质、SF 字体、克制配色。参照系统"电池"组件(环形表 + 图标 + 百分比)。
2. **焦点感知四态(决定性洞察)。** 原生小组件跟随桌面焦点变身:
   - **非选中**(桌面无焦点)= 玻璃 + **全去色**,退到背景 → WidgetKit `vibrant` 渲染。
   - **选中**(桌面获焦)= 玻璃 + **满色**,跳出来 → `fullColor` 渲染。
   - 实现上**只做满色版**,用语义色(`.green/.orange/.red`)+ `.primary/.secondary`,系统自动派生去色版。**不要手写两套**,也**不要在选中时把背景换成纯白**(那是提醒/日历类行为,电池式组件始终玻璃)。
   - ⚠️ 用户已明确:进度条在非选中态变白是 macOS 特性,**不是 bug**,不要"修"。
3. **颜色 = 语义,不是装饰。** 进度条/环颜色表**用量严重度**(`<60 绿 / 60–85 橙 / >85 红`),状态点表**健康**。放弃 per-provider 品牌彩色进度条(试过,太花)。
4. **两类实体:配额型 vs 用量型。** 对应 schema 的 `kind`:
   - `quota`(配额型,如 Claude/Codex/Kiro):关心**用了百分之多少**,画进度条/环。
   - `usage`(用量型,如按量计费):关心**花了多少钱**,显示金额。
5. **多窗口用 `windows[]`。** Claude(5h+7d)、Codex(5h+周)、Z.ai(token+mcp)一个 provider 多个计量窗口。`primaryWindowId` 指定主窗口(小尺寸/聚合只显主窗口,中/大尺寸展开全部)。
6. **说人话。** `28% Used` / `重置 2h13m` / `刷新于 10:40`,别甩 `healthy/degraded`。
7. **品牌图标点身份。** 每个 provider 用其品牌图标(主 app Assets.xcassets 已有 17 家 imageset)+ 品牌色 tint;无 asset 的走 SF Symbol 兜底。图标负责"认是谁",颜色克制。非选中态随焦点转灰。

---

## 2. 迭代历程(为什么是现在这样)

原型经历 v0→v6(详见 ai-infra 原版 DESIGN.md)。关键教训:
**用户每次说"还不如上一版",根因都是加功能时丢了克制/原生感。** 正确做法 = 保留克制 + 对齐原生的前提下加东西。
v6 定稿的突破:①焦点感知四态解开"要不要颜色"的纠结(两个都要,系统按焦点切);②深浅色统一玻璃(选中也是玻璃,不变纯白);③加品牌图标点身份。

---

## 3. 定稿规范(SwiftUI 实现依据)

精确 token 值见本文 YAML 前置块。下面是形态与结构。

### 三尺寸(见 `family`)
- **小(systemSmall)**:环形表。图标在环中心,`% Used` 在下,provider 名最下。只显 top provider 的主窗口。
- **中(systemMedium)**:详情。`quota` → 进度条 + `X% Used`;多窗口 → 每窗口一条(如 Codex 5h/周)。`usage` → 金额。
- **大(systemLarge)**:聚合。top N provider,每行 图标+名字+数值+进度条;底部月度花费页脚。

### 额度组件形态(按 `kind` + `windows` 数量派生,不硬编码 provider)
| 形态 | 触发条件 | 渲染 |
|---|---|---|
| 环形 | 小尺寸 | 图标居中 + 环按严重度上色 + `% Used` |
| 单进度条 | `kind=quota` 且单窗口 | 名字 + 条 + `% Used` |
| 双/多窗口 | `kind=quota` 且 `windows.count>1` | 每窗口一行:标签 + 条 + 重置倒计时 |
| 金额 | `kind=usage` | 名字 + `$X spent` |

### 颜色(见 `severity` / `ink` / `brand`)
- 严重度阈值:`>=85 红 / >=60 橙 / <60 绿`(`Double.severityColor`)。
- 深浅两套,系统按 `colorScheme` 切;非选中态系统 vibrant 自动去色。
- 玻璃:深浅色均玻璃,背后需彩色壁纸才显毛玻璃感。

### 图标(见 `brand`)
- 主 app `Assets.xcassets` 已有 17 家 imageset(PDF 矢量 + template 渲染),已 embed 进 widget target。
- 映射走 `providerAssetName(_:)`,与主 app `StatusBarController.iconForProvider(_:)` 一致(单一真相源)。
- 无 asset 的 10 家走 `providerIconSystemName(_:)` SF Symbol 兜底。
- 品牌 tint 只给 kiro/claude/kimi 三家,其余用 `.secondary`(克制)。

---

## 4. 数据契约(JSON 快照,widget 只读)

```
WidgetSnapshot {
  providers: [ProviderSnapshot], monthlyCost?: {usd, rmb?}, date
}
ProviderSnapshot {
  id, displayName, kind(quota|usage), primaryWindowId?,
  windows: [UsageWindow], spendUSD?
}
UsageWindow { id, label, usedPercent, resetsAt? }
```

---

## 5. 验收标尺(视觉还原是否达标)

1. **token drift 检测**:`WidgetDesignToken.swift` 里每个字面量能追溯到本文 YAML;无游离硬编码。
2. **多模态打分**:截图 vs 原型,VLM(Gemini/Kimi)0–100 打分,**≥80 过**。评分维度:玻璃质感 / 圆角 / 环形表 / 品牌图标 / 字体层级 / 语义配色。
3. **四态观感**:桌面选中/非选中各截一张,确认非选中去色、选中满色、始终玻璃(不变纯白)。
4. **三尺寸真机**:小/中/大各加一个,确认布局不溢出、`+N more` 折叠正确。

---

## 6. 待办 / 未定

- [ ] 图标品牌色 vs 纯单色最终定夺(当前:仅 3 家上色)
- [ ] 10 家无 asset 的 provider 补 imageset(等上游)
- [ ] Kimi 视觉还原迭代闭环(改→截图→对照原型→再改)
- [ ] `WidgetDesignToken.swift` 按本文 YAML 重构(Color(hex:)/(light:dark:)、Aurora 分层、GlassCard modifier)
