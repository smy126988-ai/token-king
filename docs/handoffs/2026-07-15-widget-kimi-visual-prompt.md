# 给 Kimi Code 的任务:Token King 小组件视觉还原

> 这份提示词直接转给 Kimi Code(多模态)。地基已由 Claude 建好,你只做**视觉还原**——把 SwiftUI 视图接上已有的 design token,让三个尺寸的 widget 尽量接近设计原型。

---

## 你是谁 / 做什么

你是 Kimi Code,负责把 Token King macOS 桌面小组件的 SwiftUI 视图**还原成设计原型的样子**。
你有多模态能力,所以你能**看原型截图、看你自己渲染出的截图、对照差异、再改**。这是你相比纯文本模型的核心优势,请充分利用。

**你不需要做的**(已完成,别动):
- 数据通道(JSON 快照读取)——已通,别碰。
- design token 定义(`WidgetDesignToken.swift`)——已按原型精确值重构好,直接用,别改数值。
- 品牌图标映射(`providerAssetName`/`providerIconSystemName`)——已对齐主 app,别改。

**你要做的**:改 `CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift` 里的视图,让它长得像原型。

---

## 第一步:先读这三样(顺序别乱)

1. **`DESIGN.md`**(仓库根)——视觉规则唯一真相源。YAML 前置块是精确 token 值,markdown 正文是"为什么这么设计"。**这是你的宪法。**
2. **`docs/design/widget/service-monitor-prototype-v6.html`**——视觉原型。用浏览器打开,右上角能切主题(浅/深)和焦点(选中/非选中)四态。**这是你要还原的目标。** 建议每个状态各截一张图存下来当参照。
3. **`CopilotMonitor/TokenKingWidget/WidgetDesignToken.swift`**——已重构好的 token 层。你写视图时**只引用这里的常量**,不要写裸 hex / 裸数字。

关键 API(已给你封装好,直接用):
- `Color(hex: "#xxxxxx")` — hex 转色
- `WidgetDesignToken.Severity.green(scheme)` / `.amber(scheme)` / `.red(scheme)` — 严重度色(深浅两套)
- `WidgetDesignToken.Ink.primary(scheme)` / `.secondary(scheme)` / `.faint(scheme)` — 文字三级色
- `WidgetDesignToken.Brand.kiro/.claude/.kimi` — 品牌 tint
- `WidgetDesignToken.Aurora.*` — 极光背景色
- `.glassCard()` — 玻璃卡 modifier(圆角 + 材质 + 描边,一行搞定)
- `Double.severityColor(scheme)` — 百分比直接映射到严重度色
- `@Environment(\.colorScheme) private var scheme` — 在 View 里拿当前深浅色

---

## 还原目标(按尺寸,对照原型 HTML 的三个 section)

### 小尺寸 systemSmall — 环形表(原型 `.w-rings`)
- 一圈环形表,**品牌图标在环正中心**(电池组件式),环按用量严重度上色。
- 环下方:`28%` 百分比(等宽字,`percentRingSize`=13)。
- 最下方:provider 名(`gname`,`captionSize`,faint 色)。
- 环:直径 `ringDiameter`=66,线宽 `ringStroke`=7,值弧圆头(`.round`),底轨用 track 色。

### 中尺寸 systemMedium — 详情卡(原型 `.w-med`,两种)
- **卡头**:状态点(`dotSize`=8)+ 品牌图标 + provider 名(`wNameSize`=14,粗)+ 右侧 badge(端口/"模型用量")+ 刷新键。
- **单窗口 provider**(如 Kiro):大数值 `big`(`percentBigSize`=24,等宽粗)+ `/` + 上限 + 右侧百分比 + 进度条(高 6 圆角 6)。
- **多窗口 provider**(如 Codex 5h+周):`.dual` 竖排,每窗口一行:标签 + 重置倒计时(右,faint)+ 进度条。
- **页脚**:左"刷新于 HH:MM:SS" 右周期(`captionSize`,faint)。

### 大尺寸 systemLarge — 聚合(原型 `.w-lg`)
- 卡头:标题 "Token King" + 刷新键。
- `.multi` 竖排,每行:状态点 + 品牌图标(15pt)+ 名字 + 右侧数值 + 下方进度条。
- 底部:月度花费页脚。

---

## 视觉细节对照表(原型 → SwiftUI)

| 原型 CSS | 值 | SwiftUI token |
|---|---|---|
| `border-radius:22px` | 卡片圆角 | `WidgetDesignToken.cardCornerRadius` |
| `backdrop-filter:blur(38px)` | 玻璃 | `.glassCard()`(WidgetKit 只糊卡内容,糊不到壁纸——这是平台天花板,别硬试) |
| `.bar{height:6;radius:6}` | 进度条 | `barHeight`/`barRadius` |
| `.gauge stroke-width:7` | 环线宽 | `ringStroke` |
| `--green/#28c63f` 等 | 严重度 | `Severity.green(scheme)` 等 |
| `JetBrains Mono` | 数字字体 | `.system(size:, design:.monospaced)`(系统等宽替代) |
| 品牌 tint kiro紫/claude橙/kimi蓝 | 图标色 | `Brand.kiro/.claude/.kimi` |

---

## 焦点四态(最关键的原生感,别做错)

macOS 小组件跟随桌面焦点变身,你**只做满色版**,系统自动派生去色版:
- **选中**(桌面获焦)= 玻璃 + 满色(你写的语义色生效)。
- **非选中**(桌面无焦点)= 玻璃 + 全去色(系统 `vibrant` 自动处理,你不用管)。
- ⚠️ **进度条在非选中态变白/变灰是 macOS 特性,不是 bug,不要去"修"。**
- ⚠️ **选中态背景仍是玻璃,不要换成纯白**(那是提醒/日历类组件行为,电池式组件始终玻璃)。
- 实现:用语义色 + `.primary/.secondary` + `.widgetAccentable()`(需要跟随强调色的元素),不要手写两套配色。

---

## 迭代闭环(你的多模态优势,每轮都走完)

```
① 改视图代码(只引用 token,不写裸值)
   ↓
② 编译验证:
   cd CopilotMonitor && xcodebuild build -scheme CopilotMonitor \
     -target TokenKingWidget -destination 'platform=macOS' \
     -derivedDataPath /tmp/tk-widget 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
   必须 ** BUILD SUCCEEDED **,有 error 先修再往下。
   ↓
③ 渲染截图:用 SwiftUI #Preview 或跑起来截图(小/中/大 × 浅/深 × 选中/非选中)
   ↓
④ 多模态对照:把你的截图和原型截图并排,自己打分(0-100),逐项找差异:
   玻璃质感 / 圆角 / 环形表 / 品牌图标位置大小 / 字体层级 / 语义配色 / 间距
   ↓
⑤ <80 分 → 回 ① 改;≥80 分 → 交付
```

**别只改一轮就说"做完了"。** 至少走 2-3 轮闭环,每轮贴出:改了什么 + 编译结果 + 截图 + 自评分 + 还差什么。

---

## 硬门槛(报告里必须给证据,否则视为没做)

1. **编译真过**:贴 `xcodebuild ... | grep BUILD` 的原文 `** BUILD SUCCEEDED **`,不是"应该能过"。
2. **无 error**:`xcodebuild ... | grep "error:"` 无输出。
3. **无裸值**:`grep -nE "Color\(red:|#[0-9a-fA-F]{6}|\.system\(size: [0-9]" TokenKingWidgetView.swift`
   ——视图里不应出现裸 hex/裸 RGB/裸字号(全走 token)。token drift = 直接打回。
4. **截图对照**:每个尺寸至少一张你渲染的截图 + 对应原型截图,并排 + 自评分。
5. **范围隔离**:只改 `TokenKingWidgetView.swift`(必要时加 token 到 `WidgetDesignToken.swift`,但**不改已有数值**)。别碰数据通道、图标映射、pbxproj。

---

## 参考血缘

- 视觉规则宪法:`DESIGN.md`(仓库根)
- 原型来源:`ai-infra/apps/service-monitor`(c2cc/kiro 场景;Token King 复用其设计原则)
- 上一版视觉失败教训:见 `docs/handoffs/2026-07-14-widget-v2-real-assets.md`
  ——上上轮手写 340 行 SVG parser 编译失败还谎报通过。**别重蹈:先编译过,再谈还原。**
