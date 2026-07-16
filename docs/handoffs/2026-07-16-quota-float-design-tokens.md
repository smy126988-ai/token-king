# quota-float 设计语言 → Token King 落地规范

> 目标:在 WidgetKit 能力内,把 Token King widget 的观感做到贴近 quota-float。
> 来源:quota-float 源码逐行提取(styles.css 186 行 + QuotaCard.tsx),非目测。
> 背景决策:重画**单层 tier 渐变**当 containerBackground(纯渐变,零 material、零 scrim——避开之前全彩态"灰泥")。

---

## 核心洞察(为什么 quota-float 好看,我们闷)

1. **卡片是浅色底 + 深色字**:`background:#edf3f8`(冷白) + `color:#17191f`(近黑)。我们现在是深色底,方向相反 → 显闷。
2. **彩色氛围来自 aurora 渐变层**(不是透桌面壁纸):3 radial + 1 linear 渐变,按 tier 换色,`opacity .42~.58`。它 Tauri 窗口透明才透出 aurora;我们 WidgetKit 直接把这层渐变画进 containerBackground 即可,视觉等价。
3. **大数字是视觉重心**:主数字 64px 超大,`letter-spacing:-.07em` 拉紧,`line-height:.82`。
4. **进度条有外发光**:填充渐变 + `box-shadow 0 0 14px 主色38%透明`。

---

## 一、Tier 语义配色(按用量健康度换整套色)

quota-float 分三档 + 登出态。**tier 判定**:remaining ≥50% healthy / ≥10% caution / <10% critical(注意它按剩余,我们按已用则反过来:usedPercent <50 healthy / <90 caution / ≥90 critical——沿用我们现有 Severity 阈值 60/85 也可)。

每档一整套(hex 精确值):

| tier | cool(冷) | glow(亮斑) | warm(暖斑) | progress-start | progress-end | aurora-opacity | gradient-angle |
|------|----------|-----------|-----------|----------------|--------------|----------------|----------------|
| healthy | #b9d5ee | #dff4e5 | #c7ddf2 | #397ae0 | #91baf0 | .42 | 145deg |
| caution | #b7d0ec | #fff0ba | #f4c979 | #4d88d8 | #9fc2ee | .50 | 213deg |
| critical | #c4cee0 | #ffd8a8 | #f07260 | #ff7848 | #ffd064 | .56 | 213deg |
| signed_out | #688cd4 | #d7eef3 | #d89ca5 | (无进度) | — | .58 | 145deg |

linear-gradient 中间色统一 `#c7c9d1`(47% 处),caution/critical 的 linear-warm=#e4e7ed/#e3e4e9、linear-end=#f1f5f8/#f3f5f8。

## 二、Aurora 渐变结构(画进 containerBackground,单层,SwiftUI)

原型 CSS(参考,SwiftUI 用 RadialGradient + LinearGradient 叠 ZStack 复刻):
```
背景 = 3 个 radial + 1 个 linear 叠加,整体 opacity=aurora-opacity
- radial @ 28% 68%: glow 色, 78%→transparent(glow-fade 43~60%)
- radial @ warm-position(默认 82% 82%): warm 色, 64%→transparent(warm-fade 34~68%)
- radial @ 52% 12%: cool 色, 90%→transparent(52%)
- linear(gradient-angle): cool → #c7c9d1(47%) → linear-warm(83%) → linear-end
```
**SwiftUI 落地**:`.containerBackground(for: .widget) { ZStack { LinearGradient(...); RadialGradient(...)×3 }.opacity(auroraOpacity) }`。
**禁止**:不叠 `.ultraThinMaterial`、不叠白色 scrim、不叠 `.background` — 这是之前灰泥的根因。纯渐变。
**动画**:CSS 有 drift 飘动,widget 不能动 → 我们用静态版,取 drift 起始 transform 的构图即可。

## 三、卡片容器(浅色底 + 深字 + 圆角 + 高光边)

| 属性 | quota-float 值 | Token King 落地 |
|------|---------------|----------------|
| 卡片底色 | `#edf3f8` 冷白 | 渐变已铺,卡片本身不再叠实色;文字改深色 |
| 文字主色 | `#17191f` 近黑 | Ink.primary 深色态(渐变亮,需深字) |
| 圆角 | `--card-radius: 38px` | cardCornerRadius 22→**28~30**(widget 比 320 小,按比例) |
| 边框 | `1px rgba(255,255,255,.34)` | 保留细白高光边 |
| 高光/阴影 | `inset 0 1px 0 rgba(255,255,255,.42), 0 1px 8px rgba(90,108,132,.05)` | 内高光 + 柔和外阴影 |

**重要**:渐变是亮色系,文字/图标必须用**深色**(#17191f 系),否则看不清。这是和现在深色卡最大的翻转。

## 四、排版 token(精确)

| 元素 | quota-float | 说明 |
|------|-------------|------|
| 主数字(百分比) | 64px / weight 500 / `letter-spacing -.07em` / `line-height .82` | 视觉重心,超大 |
| 数字后缀 `%` | 21px / weight 700 / `-.04em` | 小而粗,贴主数字底部对齐(align-items:flex-end) |
| eyebrow(标签) | 14px / weight 600 / `letter-spacing .18em` | 全大写宽字距 |
| updated(时间) | 14px / weight 500 / `.08em` / 透明度 .9 | |
| 进度条高度 | `--progress-height: 6px` | 我们 large 尺寸建议加粗到 8~10 |
| 进度条圆角 | `999px`(全圆) | |
| 进度条轨道 | `rgba(255,255,255,.2)` + `inset 0 1px 2px 阴影` | |
| 进度条填充 | `linear-gradient(90deg, start→end)` + `box-shadow 0 0 14px start色38%` | **外发光是关键质感** |
| weekly 次数字 | 30px / weight 400 | 副指标 |
| reset-time | 12px / `rgba(17,20,27,.52)` | 弱化 |
| orb 数字 | 27px / weight 560 / tabular-nums | 小尺寸环中心 |
| 数字字体 | tabular-nums(等宽数字) | 防跳动 |

## 五、状态圆点(quota-float 的语义灯)

- ok: `#63f58c` 亮绿 + 双层外发光 `0 0 7px + 0 0 15px`
- active(消耗中): 同绿 + pulse 动画(widget 不能动,省略脉冲,留发光)
- stale: `#8f9094` 灰
- error: `#ff7653` 橙红
- 尺寸 8px 圆,`inset 0 0 0 1px` 内描边

## 六、布局结构(三段式,解决 large 留白)

quota-float card 布局:`padding 30px 30px 27px`,header 顶部(min-height 48px),primary-metric 中部(大数字),footer 绝对定位 `bottom:26px`(weekly + reset-credit)。**三段式:header 顶 / 主指标中 / footer 沉底**。

我们 large overview / search engines 现在 `.topLeading` 钉顶 → 改三段式:标题顶、provider 行均分、Monthly footer 沉底。

---

## 落地顺序(给实现方)

1. 先做 tier 配色 + 排版 token(纯 WidgetDesignToken 加值,零风险)
2. 卡片翻转成浅底深字
3. 画单层 aurora 渐变进 containerBackground(纯渐变,禁叠 material)
4. 布局三段式
5. 装机截图,人 + 外部模型裁决;禁自评

## 硬门槛
- `xcodebuild build -target TokenKingWidget` → BUILD SUCCEEDED
- 渐变层零 material/scrim(grep 确认无 ultraThinMaterial)
- 深色文字在亮渐变上对比度足够
