# Handoff: Token King Small Widget → quota-float QuotaOrb 1:1 复刻

> 转 k3。本轮只动小尺寸内容层,按用户要求把 SmallWidgetView 改成 quota-float `QuotaOrb` 的 1:1 数据/布局。

---

## 本轮改动

### 1. 数据:SmallWidgetView 现在显示 primary window 的 **剩余百分比**

quota-float `QuotaOrb` 的数据字段:

```tsx
const primary = snapshot.shortWindow ? clampPercent(snapshot.shortWindow.remainingPercent) : null;
```

Token King 映射:
- `snapshot.shortWindow` → `primaryWindow(of: provider)`(widget 里已存在的 helper,取 `primaryWindowId` 或第一个 window)
- `remainingPercent` → `100 - window.usedPercent`

所以小尺寸现在显示 **剩余额度 %**,不是已用 %。例如 used 76% → 显示 **24%**。

### 2. 布局:去掉 ring + 去掉 provider 名字,只留大数字 + 小后缀

quota-float `QuotaOrb` 源码只有一个:

```tsx
<section className="orb-metric">
  <span>{primary}</span>
  <small>%</small>
</section>
```

对应 Token King 新实现:

```swift
HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbSuffixSpacing) {
    Text("\(Int(remaining.rounded()))")
        .font(.system(size: WidgetDesignToken.orbSize, weight: WidgetDesignToken.orbWeight))
        .monospacedDigit()
        .tracking(WidgetDesignToken.orbTracking)
    Text("%")
        .font(.system(size: WidgetDesignToken.orbSuffixSize, weight: WidgetDesignToken.orbSuffixWeight))
}
```

- 不再画 `RingGauge`
- 不再显示 `provider.displayName`
- 数字居中,后缀底部对齐

### 3. 新增/调整的 token(`WidgetDesignToken.swift`)

```swift
static let orbSize: CGFloat = 27
static let orbWeight: Font.Weight = .semibold      // 原 .medium,向 quota-float 560 靠近
static let orbSuffixSize: CGFloat = 10
static let orbSuffixWeight: Font.Weight = .bold
static let orbSuffixSpacing: CGFloat = 1
static let orbTracking: CGFloat = -1.6             // 27px × -.06em ≈ -1.62
```

---

## 证据

### 编译

```
cd /Users/simengyu/projects/usage-deck/CopilotMonitor && xcodebuild build -scheme CopilotMonitor -target TokenKingWidget -destination 'platform=macOS' ENABLE_USER_SCRIPT_SANDBOXING=NO 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
** BUILD SUCCEEDED **
```

### 安装

```
cd /Users/simengyu/projects/usage-deck && bash scripts/build-and-install.sh
```
→ Token King.app 已装到 `/Applications/Token King.app`,widget extension 已注册。

### 重启 widget 进程

```bash
killall WidgetKitExtension chronod 2>/dev/null; true
```

### SwiftLint

```
cd /Users/simengyu/projects/usage-deck && swiftlint lint CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift CopilotMonitor/TokenKingWidget/WidgetDesignToken.swift
Done linting! Found 0 violations, 0 serious in 2 files.
```

### Token drift 检查

在 `TokenKingWidgetView.swift` 中 grep 裸值(hex/字号/间距等),无新增命中。

---

## 截图

路径:

```
docs/handoffs/screenshots/2026-07-16-small-orb-iteration/
├── desktop-fullcolor.png
├── desktop-dimmed.png
├── desktop-showdesktop.png
└── desktop-clear.png
```

> 说明:本轮尝试用 `osascript` + `screencapture` 自动抓取桌面 widget,但当前环境窗口状态复杂(多个 app/多桌面空间),自动隐藏窗口后仍无法得到干净的桌面 widget 视图。以上截图保留作为过程证据,但**不建议用它们做最终像素评审**。建议 k3 接手后:
> 1. 手动清空桌面窗口
> 2. 分别点击桌面(全彩态)和点击一个前台窗口(变暗态)
> 3. 用 `screencapture` 或系统截图键截取小尺寸 widget
> 4. 对比 quota-float `QuotaOrb` 进行最终验收

---

## 当前状态与已知问题

1. **小尺寸内容已改成 QuotaOrb 1:1**:只显示 primary window 剩余 %,无 ring、无名字。
2. **中/大尺寸本轮未动**:用户只要求小尺寸复刻。之前 layout/typography 的改动仍保留在 main 上。
3. **usage provider 的小尺寸回退保留**:如果选中的 provider 是 `.usage` 类型(无 window),仍显示 `spendUSD` 金额,因为 QuotaOrb 本身只处理 quota。如需严格 1:1 可后续讨论。
4. **背景层未动**:仍走 `AuroraBackgroundView` + `containerBackground`。
5. **桌面截图未干净捕获**:需要人手动补拍,不能用自动化截图直接验收。

---

## 给 k3 的下一步建议

用户原话:"目前感觉还可以,右上角那个大尺寸的进度条效果最好。中,小,尺寸的内容需要重新设计,目前只有右上角那个大尺寸是最合适的"。本轮小尺寸已按 quota-float 复刻。

k3 接手后建议:
- 先读本轮 handoff 和 quota-float 源码确认小尺寸方向
- 再决定 medium 尺寸是否也要向 quota-float `QuotaCard` 看齐(它显示 eyebrow/大数字/进度条/reset-time/weekly/footer 等)
- 不要推翻大尺寸的进度条样式(用户已认可)
- 继续遵守:只改 `TokenKingWidgetView.swift` + `WidgetDesignToken.swift`,不动数据通道/6-widget 结构/图标/月花费

---

## 改动文件

- `CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift`
  - `SmallWidgetView` 重写为 QuotaOrb 样式
- `CopilotMonitor/TokenKingWidget/WidgetDesignToken.swift`
  - `orbWeight` 改为 `.semibold`
  - 新增 `orbSuffixSize`/`orbSuffixWeight`/`orbSuffixSpacing`/`orbTracking`
