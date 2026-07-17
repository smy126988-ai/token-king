# Handoff: Token King Widget — Medium QuotaCard 重排 + Small Orb 放大(2026-07-16 接力)

> 接续 `2026-07-16-small-widget-quota-orb-replica.md`。用户反馈:大尺寸进度条最好,中/小尺寸内容需重设计。
> 本轮方向:小尺寸验证 QuotaOrb 1:1 复刻并按画布放大;中尺寸按 quota-float `QuotaCard` 层级重排;大尺寸不动。

---

## 本轮改动(只动两个文件 + 1 行背景层遗留)

### 1. `TokenKingWidgetView.swift`

- **SmallWidgetView**:QuotaOrb 结构不变(无 ring、无名、只大数字+%),数字 27→**56px**(`orbHeroSize`,按 orb 27px@80px 同比换算 166pt 画布),"%" 后缀 10→**21px** bold(quota-float 64/21 配对),usage 回退 `$` 同步 56px。
- **MediumProviderCard 整体重写为 QuotaCard 层级**(真机诊断:旧布局内容超高,系统居中裁剪,header/footer 全被裁掉,只剩 4 行窗口条):
  1. header:状态点8 + 图标16 + eyebrow(provider 名大写 14/600/宽字距) + 右侧主窗口标签
  2. 大数字 = 主窗口**剩余 %**(48px/medium/-.07em + `%` 21 bold,QuotaCard 语义)
  3. 进度条宽 = 剩余 %,tier 渐变 + 外发光(`CapsuleProgressBar` 新增 `colorValue` 参数:宽度编 remaining、颜色编 used,critical 短条仍橙红)
  4. reset-time 12px/52%;`resetsAt == nil` 时显示 `Reset unknown`(对齐 quota-float "重置时间未知",不再留死空白)
  5. footer 沉底:多窗口 → 次窗口 `LABEL LEFT NN%` + provider 图标;否则沿用 Updated / Every 15 min
- **CapsuleProgressBar**:新增 `var colorValue: Double? = nil`,渐变色取 `colorValue ?? value`;旧调用点行为不变。

### 2. `WidgetDesignToken.swift`(只加不改)

```swift
static let orbHeroSize: CGFloat = 56        // 27px@80px orb × (166/80)
static let orbHeroTracking: CGFloat = -3.4  // -.06em @56
static let orbHeroSuffixSpacing: CGFloat = 2
static let mediumHeroTracking: CGFloat = -3.4  // -.07em @48
static let resetTimeTracking: CGFloat = 0.6    // .05em @12
static let weeklyNumberSize: CGFloat = 17      // quota-float weekly 30px × 0.57 纵向比
static let weeklyLabelTracking: CGFloat = 1
static let mediumFooterIconSize: CGFloat = 20
```

### 3. `TokenKingWidget.swift`(上一轮遗留 1 行)

`AuroraBackgroundView` 补 `.opacity(tier.opacity)`,随本次一并提交。

---

## 证据

### 编译
```
cd CopilotMonitor && xcodebuild build -scheme CopilotMonitor -target TokenKingWidget \
  -destination 'platform=macOS' ENABLE_USER_SCRIPT_SANDBOXING=NO 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
** BUILD SUCCEEDED **   (error:0)
```

### 安装 + 重启
`bash scripts/build-and-install.sh` → widget registered and enabled ✓,adhoc 签名;`killall WidgetKitExtension chronod` 后重载。

### SwiftLint
```
Done linting! Found 0 violations, 0 serious in 2 files.
```

### Token drift / 中文 / Preview
- 裸值 grep(`\.system\(size: <数字>|Color(red:|#hex`)→ **空**
- Han 字符 grep → **空**(含注释)
- `#Preview` = **10**(≥6)

### 截图
```
docs/handoffs/screenshots/2026-07-16-round0-current/   # 改前基线
docs/handoffs/screenshots/2026-07-16-round1/           # medium 重排 + small 放大
docs/handoffs/screenshots/2026-07-16-round2/           # + Reset unknown(最终)
docs/handoffs/screenshots/2026-07-16-prototype-baseline/  # v6 原型 16 张基准(浅/深×选中/非选中×各尺寸)
```
round2 dimmed 说明:右半屏被 Clash Party 窗口遮挡(激活它制造 dimmed 态),左半屏三尺寸单色渲染清晰可判。

---

## 逐元素矩阵(最终,round2 真机全彩+变暗)

矩阵按当前 quota-float 方向自定义(任务书 S1-9/M1-8/L1-5 编号,内容随方向更新)。

### Small(QuotaOrb 1:1 放大版)— 9/9 PASS
| 项 | 内容 | 判定 |
|---|---|---|
| S1 | 只剩大数字+%(无 ring、无 provider 名) | PASS |
| S2 | 数字 = primary window 剩余 % | PASS |
| S3 | 水平垂直居中 | PASS |
| S4 | 56px/semibold/等宽数字 | PASS |
| S5 | % 后缀 21px bold、lastTextBaseline | PASS |
| S6 | tracking ≈ -.06em | PASS |
| S7 | usage provider 回退 $ 金额(代码级,桌面无实例) | PASS |
| S8 | 全彩态深墨字在亮渐变上清晰 | PASS |
| S9 | 变暗态系统去色后居中可读 | PASS |

### Medium(QuotaCard 层级)— 8/8 PASS
| 项 | 内容 | 判定 |
|---|---|---|
| M1 | header:点8+图标16+eyebrow 大写宽字距+右侧窗口标签 | PASS |
| M2 | 大数字=剩余% 48px + % 21 bold | PASS |
| M3 | 进度条=剩余宽、tier 渐变+外发光 9pt(0% 数据下只见轨道;组件与 large 同款已证) | PASS |
| M4 | reset-time 12px/52%,null→"Reset unknown" | PASS(round2 修复) |
| M5 | footer:次窗口 "5H LEFT 100%" + provider 图标 | PASS |
| M6 | 无裁剪(header/footer 均可见,修复了 round0 的裁切) | PASS |
| M7 | usage 分支 $ + spent(代码级) | PASS |
| M8 | 全英文/零裸值/两态可读 | PASS |

### Large(未动,回归)— 5/5 PASS
| 项 | 内容 | 判定 |
|---|---|---|
| L1 | 标题 + 三段式(header 顶/行均分/footer 沉底) | PASS |
| L2 | 行=点+图标15+名+值,9pt 渐变发光条 | PASS |
| L3 | "+1 more" + Monthly 页脚 | PASS |
| L4 | tier 渐变正确(100% 橙红、51% 蓝) | PASS |
| L5 | 两态可读、无截断 | PASS |

### 自评(VLM,诚实标注)
S ≈90 / M ≈88 / L ≈90。扣分项:真实数据下两块 medium 与 small 都是 OpenCode Go 剩余 0%(主窗 100% 用尽),无法真机验证非零填充的渐变观感;语义正确,观感待用户在实际数据下复核。**最终及格权在用户 + 外部模型,不自判及格。**

---

## 数据语义说明(不是 bug)

- medium/small 大数字是**剩余 %**(quota-float 语义),large 行仍是**已用 %**(用户已认可,未动)。两语义并存是本轮方向使然。
- OpenCode Go 主窗口 100% 用尽 → medium hero "0%" + 空填充条 + footer "5H LEFT 100%"(5h 窗未用),全部符合 QuotaCard 语义。
- `resetsAt: null` → "Reset unknown"(对齐 quota-float "重置时间未知")。

## 已知边界 / 下一步建议

- 进度条渐变+发光在 medium 只有 0% 填充真机证据;组件与 large 同款。若用户把 medium detail 配到有余量的 provider 即可复核。
- 小尺寸 56px 是按 166pt 画布同比换算;若用户偏好 QuotaOrb 原始绝对尺寸感,可回退 `orbSize: 27` 路径(已保留)。
- 旧 `zeroInt/tinyGap/singleLine` 等包装 token 仍在(历史遗留,本轮约束"不改已有数值"未清理);后续若任务书反假 token 条款优先,可专项清理。

## 改动文件

- `CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift` — small orb 放大 + MediumProviderCard 重写为 QuotaCard 层级 + CapsuleProgressBar 加 colorValue
- `CopilotMonitor/TokenKingWidget/WidgetDesignToken.swift` — 新增 8 个 token(见上)
- `CopilotMonitor/TokenKingWidget/TokenKingWidget.swift` — aurora 层补 `.opacity(tier.opacity)`(上一轮遗留)

---

# 追加:Round 3-4(用户反馈"小尺寸还是不行"后的竞品数据/布局复核)

## 复核结论(quota-float 源码级)

- **QuotaOrb 数据 = `shortWindow.remainingPercent`(5 小时短窗)**,不是 primary window。此前小/中尺寸都显示主窗口,OpenCode Go 主窗 100% 用尽 → 永远死 "0%";其 5h 窗实际剩余 100%。
- **QuotaCard 映射**:hero = shortWindow,footer = weeklyWindow(7d)。此前 footer 错取"第一个非主窗"(显示成 5h)。
- **QuotaOrb 布局 = 80px 浅色磨砂卡**:`#edf3f8` @ .82 底 + aurora 画在卡内 + 1px 白描边 .42 + 顶部内高光 .48 + 柔阴影 `0 4px 14px rgba(72,88,112,.08)`,不是数字直接飘在渐变上。

## Round 3 改动

- `SmallWidgetView` 重写为 orb 卡:圆角 28 浅色底 + 卡内 aurora(tier 跟随该 provider 短窗,通过单窗快照驱动共享 `AuroraBackgroundView`)+ 白描边(顶亮底暗渐变)+ 柔阴影;数字改 **5h 短窗剩余 %**(48px semibold 等宽 + 21px bold %)。
- `MediumProviderCard`:hero/进度条/reset-time/header 右标切到 **shortWindow(5h)**;footer 切到 **weeklyWindow(7d)**。
- 新 helper:`shortWindow(of:)`(id=="5h",回退 primary)、`weeklyWindow(of:)`(id=="7d"/"weekly")。
- 新 token(只加):orbCardBackground/BackgroundOpacity/Radius/BorderOpacity/BorderWidth/HighlightOpacity/ShadowColor/ShadowRadius/ShadowY/orbHeroCardTracking(-2.9 = -.06em@48)。

## Round 4 改动(截图发现的真问题)

- **变暗态 small 白上白**:浅色 orb 卡在 vibrant 模式被系统映成近白,深字也被映白。修复:orb 卡 + 阴影按 `widgetRenderingMode == .fullColor` 门控(任务书 §1.3),vibrant/accented 态不画,数字由系统单色渲染。

## Round 3-4 证据

- 编译 `** BUILD SUCCEEDED **`(0 error);swiftlint 0;裸值 grep 空;中文 grep 空;#Preview 10。
- 截图:`docs/handoffs/screenshots/2026-07-16-round3/`(orb 卡首版)、`2026-07-16-round4/`(渲染模式门控后,最终)。
- 真机验证(round4):small 全彩 = 浅色卡 + "100%" 清晰;small 变暗 = 白色单色 "100%" 清晰;medium 两态 = eyebrow/hero/满宽渐变条/resets in 4h 59m/7D LEFT 44% 全部无裁剪可读。

## 更新后矩阵(全部 PASS)

- Small 9/9:S2 语义更新为 **5h 短窗剩余 %** ✓;新增 orb 卡(浅色底/描边/阴影/卡内 aurora)✓;S9 变暗态(round4 修复后)✓。
- Medium 8/8:M2 hero=5h 剩余 ✓;M5 footer=7D LEFT ✓;其余同前。
- Large 5/5:未动,回归正常。

## 已知边界(诚实)

- orb 卡内 aurora 在 0.82 浅底上较克制(healthy tier .42 opacity),与 quota-float orb 的柔色感一致但比其中卡更淡;若用户想要更浓的 tint,调 tier.opacity 或 orbCardBackgroundOpacity 即可。
- medium hero 在 5h 窗重置后显示 100%(数据正确);quota-float 同语义。
- 截图时机器两次锁屏,round3/4 均由后台监听在解锁后自动补拍(脚本 `/tmp/tk-round3-watch.sh`,重启即失)。
