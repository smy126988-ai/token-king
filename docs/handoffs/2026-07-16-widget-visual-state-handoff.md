# Handoff: Token King Widget 视觉还原 — 2026-07-16

## 一句话现状
背景/容器层**已修好**（走系统原生磨砂，用户认可"好一些了"）；剩下的丑全是**内容排版层**（Kimi 的活，尚未做视觉还原）。

---

## 分工模型（贯穿全程）
- **我（Claude）**：出规划 + 改**背景/容器层** + 真机验证 + 当外部裁判。工作在 worktree `worktree-widget-p0-plan`。
- **Kimi Code**：在 **main** 上改**内容排版层**（布局/文案/图标/进度条/字体/间距）。
- 用户：小米 PM，看得懂 UX 看不了技术细节。中文回复，讨论优先。

---

## 两条分支现状（关键：分头改，未合并）

**worktree `worktree-widget-p0-plan`（我的，已推 PR #3）**
```
bb276d7 fix(widget): let the system own the widget background (drop painted aurora)  ← 最新
5b9b631 fix(widget): P0 — stop full-bleed glass washing out the aurora
5b87377 docs(widget): rewrite Kimi prompt v2
```
worktree 的 pbxproj 已同步过 main（含 Kimi 的 Intent/ 文件注册），能编译 Kimi 的 6-widget 结构。

**main（Kimi 的）**
```
7b3b3ed docs: script the manual R18 sandbox scenarios
34f3b06 widget: localhost HTTP snapshot channel, provider visibility menu, i18n foundation
78184ed chore: close Kiro/Sparkle/README gaps + R18 tests + dead-code Phase 1
8ed74d5 widget: multi-instance architecture + data flow fixes
6b0f8c1 merge: Token King 桌面 widget P0 + P2 视觉(V1/V2/V3)
```
Kimi 最近两轮**没做视觉还原**，做的是 backlog（HTTP 快照通道、provider 显隐菜单、i18n 地基、R18 测试脚本）。它自己承认：视觉还原 loop 处于 blocked，逐元素矩阵/VLM 打分/截图**从未跑过**。

---

## 背景层为什么反复失败 → 最终正解（已验证）
**根因（Apple 官方文档确认）**：widget 的 Material 糊不到桌面壁纸，只能糊自己内容。自画 aurora + Material + scrim 在 `.fullColor`（选中）叠成灰泥；`.vibrant`（非选中）系统又强行删掉自画背景。原生电池组件好看是因为**它不自画背景**，系统贴合真实壁纸。

**正解 = 方案 A（已实施，commit bb276d7）**：
- 6 处 `containerBackground` 从 `AuroraBackgroundView()` → `Color.clear`（保留调用让系统接管）
- 删掉 `AuroraBackgroundView` struct、`Aurora`/`Glass` token、`GlassCard` modifier、`.glassCard()` 调用
- 内容布局没动
- 结果：卡片变干净系统磨砂，与原生电池组件一致。用户认可。

**关键教训**：不要再自画任何渐变/毛玻璃背景。品牌感靠内容（图标/语义色/排版），不靠背景。

---

## 当前部署状态
- `/Applications/Token King.app` = 从 worktree 构建的 Release，inside-out 签名（widget appex 先签带 entitlements 再签 app，**不用 `--deep`**），widget 沙盒权限完好（app-sandbox + home-relative 例外在）。
- widget 已注册 `com.tokenking.app.TokenKingWidget(1.0)`，快照 6-7 家 provider 真实数据在。

---

## 下一步：内容层问题清单（据 2026-07-16 桌面截图，全是 Kimi 的活）
1. **中文没清干净 + 违反项目英文铁律**：`配额`、`刷新于 00:03:06`、`每 15min`；provider 名截断成 `MiniMax Coding P...`、`Kimi for Coding (...)`
2. **图标全是空方块 □**：OpenCode Go / ChatGPT / 小尺寸环中心 —— SF Symbol 兜底没映射上（`providerAssetName`/`providerIconSystemName` 需补映射）
3. **信息密度失衡**：中/大卡四行几乎全是 0（Primary 71/100、5h 0%、7d 0%、Monthly 71%）占大片却没信息量；大卡下半整片空白
4. **假控件**：右上角圆圈箭头刷新按钮 widget 点不动，纯装饰误导，该删
5. **焦点四态没做**：只有 `.widgetAccentable()`，没有 `widgetRenderingMode` 去色分支
6. **数值可疑（非 widget）**：`Monthly $14483.88 / ¥98230.08` 月花费一万四千刀明显不对，是主 app 成本统计问题，另查

## Kimi 侧最大的洞
**截图工具链不存在** —— Kimi 承认 xcodebuild 无法把 #Preview 渲染成图，scripts/ 里没有截图工具，所以它"改完截图对照"的 loop **跑不起来**，VLM 自评从未执行。视觉还原重启前必须先解决：要么给它一个 preview 截图脚本，要么由我（Claude）来当"眼睛"做真机截图对照。

---

## 给 Kimi 的提示词现状
`docs/handoffs/2026-07-15-widget-kimi-visual-prompt.md`（v2 版，已推）——含逐元素矩阵、反 gaming 验收、可编译 fixture。但因截图工具链缺失，Kimi 无法自验证。**下一步应把上面「内容层问题清单」整理成精确修复提示词发 Kimi**（用户已同意方向 B：把诊断喂给它，比它自己摸索命中率高）。

---

## Compact 后的下一步
1. 决定视觉还原怎么重启：解决截图工具链（给 Kimi preview 截图脚本）vs 我来当眼睛做真机截图对照
2. 把「内容层问题清单」写成给 Kimi 的精确修复提示词
3. 最终两分支合并：背景层用我的（worktree），内容层用 Kimi 的（main），有重叠文件（TokenKingWidgetView.swift / WidgetDesignToken.swift）需手工整合
4. 单独查 `$14483` 月花费数值是否算错（主 app 逻辑，非 widget）
