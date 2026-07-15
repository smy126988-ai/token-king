# /goal:Token King 小组件视觉还原(v2 — 修正版)

> 转给 Kimi Code(多模态),用 `/goal` 起持续 loop。上一版你已跑过一轮,失败了:widget washout 成白底、中文文案违规、还用 `zeroInt=0` 这类假常量钻了验收空子。这一版把失败原因和正确做法都讲清楚了。
>
> **这不是"改一版交差"。是 render → 对照原型 → 修 → 再 render 的闭环,每轮只接受比上一版更接近原型的结果,直到停止判据全绿。**

---

## 0. 先搞懂上一轮为什么失败(不看懂就会重犯)

### 失败1:washout 成白底 —— 这是架构错误,不是调参问题
你把 `AuroraBackgroundView()` 放进 `.containerBackground`,又用**全屏 `.ultraThinMaterial` + 白色叠加**盖住整个内容区。

**关键技术事实(Apple 官方文档原文,不可违背):**
> "A material blurs a background that's part of your app, but not what appears behind your app on the screen. The content on the Home Screen doesn't affect the appearance of a widget." — [Apple: Material](https://developer.apple.com/documentation/swiftui/material)

也就是:**widget 里的 Material 糊不到桌面壁纸,只能糊 widget 自己的内容。** 你全屏铺一层白玻璃,它下面只有 aurora,于是把 aurora 糊成了近白色。aurora 一直在,是被你自己的玻璃吃掉了。

原型的心智模型(aurora=壁纸,玻璃卡浮在上面,blur 透出壁纸)在 widget 里**物理上做不到**。别再往这个方向使劲。

### 失败2:照抄了原型的中文 —— 违反项目铁律
你把原型里的 `配额` / `模型用量` / `刷新于` / `每 120s` 直接搬进代码。但 `AGENTS.md` 明确规定:**所有用户可见文案必须英文**。原型是中文设计稿(来自另一个项目),它的语言是占位内容,不是要你抄的东西。而且 `每 120s` 是假的(实际 15 分钟刷新)、那个刷新按钮框也是假的(widget 不能交互,点不动)。

### 失败3:用假常量骗过验收 —— gate 满足了,意图没满足
上一版验收写"grep 视图里不能有裸值",你就把 `0`/`1` 都做成 `zeroInt`/`zeroLength`/`singleLine`/`tinyGap`,写出 `Spacer(minLength: zeroLength)`。grep 是绿的,但代码被垃圾间接层污染了。**满足 gate 却没达成 gate 的意图 = 失败,即使检查是绿的。** 这一版的验收改了形式,下面详述。

---

## 1. 正确架构(照这个做,别再撞天花板)

来源:[Apple Material](https://developer.apple.com/documentation/swiftui/material)、[macOS 14 glassmorphism 实战](https://www.klaritydisk.com/blog/building-liquid-glass-ui-macos)、[Apple 渲染模式文档](https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances)。

### 1.1 分层(从下到上)
```
① .containerBackground(for: .widget) { AuroraBackground() }   ← aurora 当底,铺满
② 一张【内缩】玻璃卡:RoundedRectangle(22) + padding(12)      ← 关键:内缩!aurora 从四周露出来
   ├ 半透明线性渐变填充(白 0.30 → 0.12)                       ← 玻璃感靠这个,不靠 blur
   ├ 发丝渐变描边 .strokeBorder(白.opacity(0.25), lineWidth:1)  ← 玻璃感 80% 来自边缘
   └ 柔阴影 .shadow(黑.opacity(0.18), radius:14, y:6)
③ 内容(环/进度条/文字)坐在玻璃卡上
```

### 1.2 三条铁律(违反必washout)
- **玻璃卡必须内缩(padding ≥12),不能全屏铺。** aurora 必须从卡片四周露出来。这是治白底的唯一正解。
- **玻璃感靠"半透明渐变填充 + 发丝渐变描边 + 柔阴影"伪造,不靠 blur。** 实战经验原话:"玻璃看着扁平时别调填充透明度,把功夫花在边框上——人眼判断材质靠光在边界的反应,不是表面。" blur 是可选装饰,不是机制。
- **白色叠加透明度别超 0.35,别过度 blur。** 两者都会把 aurora 压扁。

### 1.3 渲染模式门控(不做会被系统抹掉)
- 读 `@Environment(\.widgetRenderingMode)`,**只在 `.fullColor` 画 aurora+玻璃**。
- `.vibrant`(桌面非选中/锁屏)会把内容去色成单色——这是**系统特性,进度条变白就是这么来的,不是 bug,不许"修"**。
- `.accented`(用户选 tinted 外观)会**移除你的背景**并染白——给一个高对比降级布局,别指望 aurora 活下来。
- **`.widgetAccentable()` 在这里有害**:它把元素塞进 accent 组被染白。你上一版给环、进度条、图标全加了——**背景和进度条上的必须删掉**,最多留一个你确实想被染色的字形。

### 1.4 aurora 渐变实现
- macOS 14:堆叠多个 `RadialGradient` + `.blendMode(.plusLighter)` 叠在 `LinearGradient` 底上。焦点位置照原型 CSS:`radial-gradient(... at 6% 0%)` → `RadialGradient(center: UnitPoint(x:0.06,y:0), endRadius:~520)`。
- **别用 `AngularGradient`**(那是绕中心扫,不是向外辐射,错的)。
- 精确色值已在 `WidgetDesignToken.Aurora` 里,直接用。

---

## 2. 你要做什么 / 不做什么

**做**:改 `CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift` 和 `TokenKingWidget.swift`(AuroraBackgroundView),必要时给 `WidgetDesignToken.swift` 加常量。

**不做**(动了=破坏):数据通道、图标映射、pbxproj、entitlements、token 已有数值。

---

## 3. 开工前必做(grounding — 别凭记忆做)

研究证明:视觉模型凭记忆会 drift,必须每轮重看原型。开工前:
1. 浏览器打开 `docs/design/widget/service-monitor-prototype-v6.html`,右上角切 浅/深 × 选中/非选中,**四态各截一张基准图存本地**。
2. 读 `DESIGN.md`(仓库根,YAML 是精确值)+ 本文件。
3. **输出一份诊断报告**:逐条列"当前 widget 截图 vs 原型的差距 → 对应代码位置 → 原型的目标值"。确认看懂了再动手。

---

## 4. 逐元素验收矩阵(每轮对每个尺寸逐项判,拿不准就判 FAIL)

对**每个尺寸**逐元素比对,判 PASS/FAIL,**任一 FAIL 就继续改**。研究表明:模型自评偏宽(self-preference bias),所以判定标准是"拿不准 = FAIL",不是"看着差不多 = PASS"。

### 小 systemSmall(原型 `.w-rings`)
S1 卡片圆角22内缩 · S2 aurora从卡四周露出(不是白底!) · S3 玻璃卡有渐变填充+发丝描边 · S4 环直径66 · S5 环线宽7圆头 · S6 环底轨可见 · S7 环填充=严重度色(28绿/59橙/87红) · S8 图标居环中心 · S9 百分比13等宽在环下 · S10 provider名faint在最下

### 中 systemMedium(原型 `.w-med`)
M1 aurora露出+内缩玻璃卡 · M2 状态点8 · M3 图标在名字前 · M4 名字14粗 · M5 右上badge(英文!) · M6 大数值24等宽 · M7 `/`+上限灰 · M8 进度条高6圆角6严重度色 · M9 双窗口竖排+重置倒计时 · M10 页脚英文(删掉假"每120s"和假刷新键)

### 大 systemLarge(原型 `.w-lg`)
L1 aurora露出+内缩玻璃卡 · L2 标题"Token King" · L3 每行=点+图标15+名+值+条 · L4 行进度条严重度色 · L5 "+N more"折叠 · L6 月费页脚(Monthly与金额间距收紧)

---

## 5. 每轮 loop 六步(缺一步=这轮无效)

研究结论:必须 render→compare→fix 闭环,且**只接受比上一版更接近原型的结果**(Forced Optimization)。

```
① 改视图(架构照 §1,文案全英文)
② 编译(见§6命令)→ 必须 SUCCEEDED
③ 客观检查(见§6)→ token映射/覆盖矩阵/文案 全过
④ 渲染截图:每个尺寸 × 浅/深 各截图(用§7的 fixture)
⑤ 逐元素比对:把你的截图和原型基准图【并排】,走完§4矩阵,逐项PASS/FAIL + 列出具体delta(不是打分,是"环线宽 5pt→应7pt"这种可执行差异)
⑥ 判定:比上一轮更接近?是→留;否→回退这步改法。全绿→停;否则→回①
```

---

## 6. 客观检查(取代"自己打分"——机器能验的用机器,别自评)

研究明确:**LLM 给自己的作品打绝对分不可信**(还会 self-preference)。所以这一版**没有自评分**,只有客观 artifact + 外部裁决。

### 编译(必须 SUCCEEDED)
```bash
cd CopilotMonitor && xcodebuild build -scheme CopilotMonitor \
  -target TokenKingWidget -destination 'platform=macOS' \
  -derivedDataPath /tmp/tk-widget 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```

### token 用法(闭列表,不是黑名单)
不再是"grep 不到裸值就过"(你上次用 `zeroInt` 钻了空子)。新规则:
- 每个 **颜色 / 字号 / 圆角 / 线宽 / 间距(spacing)** 必须引用 `WidgetDesignToken.*`。
- **`0` 和 `1` 允许裸写**(`Spacer(minLength: 0)`、`lineLimit(1)` 就该是字面量)。**禁止 `zeroInt`/`zeroLength`/`singleLine`/`tinyGap` 这类把 0/1/2 包装成常量的假 token——发现即判 FAIL,并删除。**
- 新增 token 的前提:该数值在**原型里真实存在**(能在 `DESIGN.md` YAML 或原型 CSS 里找到出处)。凭空造 `tinyGap=2` 而原型没有 2 → FAIL。
```bash
# 辅助:列出视图里所有 .system(size:) 和裸颜色,人工核对是否都走了 token
grep -nE '\.system\(size: *[0-9]|Color\(red:|#[0-9a-fA-F]{6}' \
  CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift
# 反例检测:假常量
grep -nE 'zeroInt|zeroLength|zeroSpacing|singleLine|tinyGap|zeroDouble' \
  CopilotMonitor/TokenKingWidget/*.swift   # 有输出=有假token,必须清掉
```

### 文案全英文(项目铁律)
```bash
# 视图里不应出现任何中文字符
grep -nP '[\x{4e00}-\x{9fff}]' CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift
# 有输出=有中文文案=FAIL,改成英文
```

### Preview 覆盖矩阵(不是数数,是维度)
不再是"≥6 个就过"(你上次 6 个全是浅色)。新规则:必须覆盖 **{浅, 深} × {正常, 空态}** 且**深色 preview 必须真的是深色**(截图平均亮度明显低于浅色版,肉眼可辨)。命名带状态如 `#Preview("Small/Dark")`。

### 外部裁决(取代自评分)
你**不给自己打分**。你产出:①三尺寸 × 浅深的截图,②与原型基准图的并排对照,③§4 矩阵逐项结论 + 具体 delta 列表。这些交给独立方(用户 + 另一个模型)判 pass/fail。你的职责是**把 artifact 摆出来**,不是宣布自己及格。

---

## 7. Fixture(固定假数据,放 preview 用,已核对可编译)

```swift
extension WidgetSnapshot {
    static var previewFixture: WidgetSnapshot {
        let now = Date()
        func reset(_ h: Int) -> Date { now.addingTimeInterval(Double(h) * 3600) }
        return WidgetSnapshot(version: 1, snapshotAt: now, providers: [
            ProviderSnapshot(id: "kimi_cn", displayName: "Kimi", kind: .quota, primaryWindowId: "monthly",
                windows: [UsageWindow(id: "monthly", label: "Monthly", usedPercent: 87, resetsAt: reset(240), used: 8700, limit: 10000)], spendUSD: nil, fetchedAt: now),
            ProviderSnapshot(id: "codex", displayName: "Codex", kind: .quota, primaryWindowId: "5h",
                windows: [UsageWindow(id: "5h", label: "5h", usedPercent: 25, resetsAt: reset(2), used: 38, limit: 150),
                          UsageWindow(id: "weekly", label: "Weekly", usedPercent: 59, resetsAt: reset(72), used: 1180, limit: 2000)], spendUSD: nil, fetchedAt: now),
            ProviderSnapshot(id: "claude", displayName: "Claude", kind: .quota, primaryWindowId: "5h",
                windows: [UsageWindow(id: "5h", label: "5h", usedPercent: 40, resetsAt: reset(3), used: 40, limit: 100)], spendUSD: nil, fetchedAt: now),
            ProviderSnapshot(id: "kiro", displayName: "Kiro", kind: .quota, primaryWindowId: "power",
                windows: [UsageWindow(id: "power", label: "Credits", usedPercent: 28.5, resetsAt: reset(120), used: 2853, limit: 10000)], spendUSD: nil, fetchedAt: now),
            ProviderSnapshot(id: "openrouter", displayName: "OpenRouter", kind: .usage, primaryWindowId: nil, windows: [], spendUSD: 37.42, fetchedAt: now)
        ], monthlyCost: MonthlyCost(usd: 124.80, rmb: 892.30))
    }
}

#Preview("Small/Light", as: .systemSmall) { TokenKingWidget() } timeline: {
    TokenKingEntry(date: .now, snapshot: .previewFixture, readStatus: .ok, snapshotAgeSeconds: 30)
}
#Preview("Small/Dark", as: .systemSmall) { TokenKingWidget() } timeline: {
    TokenKingEntry(date: .now, snapshot: .previewFixture, readStatus: .ok, snapshotAgeSeconds: 30)
}
// 同理补 Medium/Light、Medium/Dark、Large/Light、Large/Dark;深色用 .environment(\.colorScheme, .dark) 或系统深色预览
```
> label 用英文("Monthly"/"5h"/"Weekly"/"Credits"),别用中文。

---

## 8. 每轮报告格式(便于追踪收敛)

```
## Round N
本轮改动:<一句话,只改一处>
编译:** BUILD SUCCEEDED **   error:0
客观检查:假token grep 空✓  中文 grep 空✓  preview 浅深各覆盖✓
截图:small(浅/深)✓ medium(浅/深)✓ large(浅/深)✓
逐元素:小 9/10(S2 aurora 仍偏白)| 中 10/10 | 大 6/6
具体delta:小尺寸玻璃卡填充白 0.5 太高→降到 0.3 让 aurora 透出
比上一轮:更接近(aurora 开始露出)
未达标项:S2 → 下一轮降玻璃填充透明度
```
分数/通过项应逐轮上升。连续 2 轮某项无改善 → 别在同一处微调,回去重看原型那个元素的 CSS,换思路。

---

## 9. 停止判据(全绿才停)

- 逐元素矩阵每个尺寸 **100% PASS**(尤其 S2/M1/L1 = aurora 真的从玻璃卡四周露出,不是白底)
- 编译 0 error / 假 token grep 空 / 中文 grep 空 / preview 浅深覆盖齐
- 三尺寸 × 浅深 截图 + 与原型并排对照 + 逐元素结论,全部摆出来交外部裁决

> 收工不是你说"≥85 分",是你把上面全部 artifact 摆出来,由用户 + 独立模型判过。

---

## 10. 已知作弊清单(中性列举,满足 gate 但没达成意图 = 失败)

这些是上一轮真实发生的,别再犯:
- 把 `0`/`1`/`2` 包装成 `zeroInt`/`singleLine`/`tinyGap` 来骗 token grep。
- preview 数量凑够但全是同一种(浅色),不覆盖深色/状态。
- 照抄原型的中文占位文案。
- 加假的"每 120s"、假的刷新按钮(widget 点不动)。
- 全屏玻璃盖住 aurora 却声称"有玻璃感"。
- 宣布自己 ≥85 分而没有并排对照 artifact。

一句话:**一个你满足了检查、却没达成其意图的 gate,算任务失败,即使检查是绿的。**

---

## 参考血缘
- 视觉宪法:`DESIGN.md`(仓库根)
- 原型:`docs/design/widget/service-monitor-prototype-v6.html`
- 技术依据:[Apple Material 文档](https://developer.apple.com/documentation/swiftui/material)(Material 糊不到壁纸)、[macOS 14 glassmorphism 实战](https://www.klaritydisk.com/blog/building-liquid-glass-ui-macos)(边缘比表面重要)、[Apple 渲染模式](https://developer.apple.com/documentation/widgetkit/preparing-widgets-for-additional-contexts-and-appearances)
- 前车之鉴:`docs/handoffs/2026-07-14-widget-v2-real-assets.md`
