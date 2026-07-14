# Service Monitor 桌面小组件 — 设计文档

> 状态:视觉方向已定稿(原型 v6)。本文记录**设计思路 + 最终规范**,供 SwiftUI 实现与后续迭代参照。
> 可视化原型:`widget-prototype.html`(浏览器打开,右上角可切主题/焦点四态)。

---

## 0. 这是什么

一个 macOS 桌面小组件 + 配套主 app,用来**一眼看到本地 AI 基建的运行状态与各模型额度**:
- **服务层**:c2cc(codex2claudecode 代理)是否在跑、端口、延迟、自愈。
- **模型用量**:kiro / codex / kimi / opencode / mimo 等各家额度消耗。
数据由 `ai-infra` CLI/watchdog 写入 App Group 容器的 `service-status.json`,小组件(沙盒)只读它。

---

## 1. 核心设计原则(最重要,先看这个)

1. **对齐原生,不自创一套**。macOS 原生小组件长什么样,我们就长什么样 —— 玻璃材质、SF 字体、克制配色。参照物:**系统"电池"组件**(环形表 + 图标 + 百分比)。
2. **焦点感知四态**(决定性洞察)。原生小组件跟随桌面焦点变身:
   - **非选中**(桌面没焦点)= 透明玻璃 + **全单色**,退到背景 → WidgetKit `vibrant` 渲染模式。
   - **选中**(点桌面获焦)= 玻璃 + **满色**,跳出来 → `fullColor` 渲染模式。
   - 实现上:**只做对"满色版",用语义色(.green/.orange/.red)+ .primary/.secondary,系统自动派生去色版**。不要手写两套,也不要在选中时把背景换成纯白(那是"提醒/日历"类组件的行为,电池式组件始终玻璃)。
3. **颜色 = 语义,不是装饰**。进度条/环的颜色表"用量严重度"(`<60 绿 / 60–85 橙 / >85 红`),状态点表"健康"。**放弃 per-service 品牌彩色进度条**(试过,太花)。
4. **服务 vs 模型 两类实体**。c2cc 是服务(关心活没活);kiro/kimi/… 是模型(关心用多少)。**kiro 特殊**:用量透过 c2cc 才拿得到 → 合体卡(上=c2cc 服务状态,下=kiro 积分)。
5. **说人话**。`端口 8787` 而非 `:8787`;`服务正常 / 异常·正在自动修复 / 已停止` 而非 `healthy/degraded/down`;每块带刷新按钮 + `刷新于 HH:MM:SS`。
6. **品牌图标点身份**。每个服务/模型用其品牌图标(lobe-icons 单色字形 + 品牌色 tint),非选中态随焦点转灰。图标负责"认是谁",颜色克制。

---

## 2. 迭代历程(为什么是现在这样)

| 版本 | 做了什么 | 结果 / 教训 |
|---|---|---|
| v0 | 通用状态列表,深色仪表盘 | 干净但太普通 |
| v1 | 仪表盘 + 绿色强调 | 用户觉得"帅" → 克制是对的 |
| v2 | 加品牌色环 + 彩色字块字标 + 概念框 | **丑**:彩色方块字标玩具感、五色彩虹糖、布局乱 |
| v3 | 环做干净、品牌色调和、状态点 | 比 v2 好,仍不如 v1 |
| v4 | 进度条/环改纯单色 | 更贴原生,但丢了"选中态该有的颜色" |
| v5 | **焦点感知四态**(非选中单色 / 选中满色) | 关键突破:解开"要不要颜色"的纠结——两个都要,系统按焦点切 |
| v5.1 | 深浅色统一玻璃 + 壁纸透出 | 修正"浅色变纯白"的错(选中也是玻璃) |
| **v6** | **加品牌图标**(环中心 / 名字前) | **定稿**。牛逼。 |

**关键教训**:用户每次说"还不如上一版",根因都是**加功能时丢了克制/原生感**。正确做法是"保留克制 + 对齐原生"的前提下加东西。

---

## 3. 定稿规范(v6 / SwiftUI 实现依据)

### 尺寸
- **小(systemSmall)**:单服务**环形表** —— 图标在环中心,百分比在下,名字在最下。
- **中(systemMedium)**:单服务详情卡 —— 图标+名字+端口+刷新键 / 状态行(说人话)/ 额度组件 / 页脚(刷新于+周期)。
- **大(systemLarge)**:多服务聚合 —— 服务在顶、模型在下,每行 图标+名字+数值+进度条。

### 额度组件库(每 provider 形态不同,抽成可复用)
- `CreditBar` 积分型(kiro/mimo):已用/总额 + % + 条。
- `PercentBar` 纯进度型(kimi/opencode):单一百分比。
- `DualWindow` 双窗口型(codex):5 小时窗口 + 周限额,各带重置倒计时。
- `StatusOnly` 纯状态型:无额度 API 的服务。

### 颜色
- 用量严重度:`<60% 绿 / 60–85% 橙 / >85% 红`。
- 健康状态点:正常绿 / 异常橙 / 已停止红。
- 主题:深浅色均玻璃;背后需彩色壁纸才显毛玻璃感。
- 非选中态:全部去色(系统 vibrant 自动处理)。

### 图标(品牌)
- 来源:**lobe-icons**(开源 AI 图标集,`@lobehub/icons-static-svg`),用**单色字形版**(currentColor)+ 品牌色 tint。
- 已确认可用:`codex`(OpenAI Codex)、`claude`、`kimi`、`kiro`、`opencode`、`minimax`。
- 品牌色 tint:kiro 紫 `#9046ff` / claude 橙 `#d97757` / kimi 蓝 `#1783ff` / codex·opencode 用文字色。
- **mimo:用 lobe-icons 的 `xiaomimimo`**(单色版;另有带文字的 `xiaomimimo-text`)。mimo 数据源尚未接,优先级低但图标已就绪。
- 已确认可用(全 6 个):`codex`、`claude`、`kimi`、`kiro`、`opencode`、`xiaomimimo`;备用 `minimax`。
- SVG 已存档:`design/icons/*.svg`(lobe-icons 单色版,版本控制)。
- 待用户最终定:图标**品牌色** vs **纯单色**(更统一)。

---

## 4. 数据契约(status.json)

```
services: [{
  name, port, state(healthy/degraded/down), claude_ok, missing[],
  upstream{ok, latency_ms},
  usage{subscription, days_until_reset, used, limit, label, unit},
  last_self_heal, restarts_in_window
}]
```
当前只有 c2cc→kiro 一条真实数据;其他模型(kimi/codex/…)用量取数方式(API?)未接,后续逐个 provider 接入。

---

## 5. 待办 / 未定

- [ ] 图标 品牌色 vs 单色 最终定夺
- [x] mimo 图标来源(lobe 无)→ 已解决:`xiaomimimo`
- [ ] 其他模型用量数据源接入(kimi/codex/opencode/mimo)
- [ ] 把图标打包进 SwiftUI asset catalog,Image 渲染
- [ ] Xcode 跑真机,验证 App Group 读取 + 四态观感
