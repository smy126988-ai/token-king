# 给 kimicode 的执行提示词 — Token King 阶段5

> 用途：把这份内容整段发给 kimicode，它照做即可。附带的实施计划在
> `docs/superpowers/plans/2026-07-01-token-king-阶段5-修复与provider指南.md`。

---

你是软件工程 agent。项目 **Token King**（fork 自 opgginc/opencode-bar，macOS 菜单栏 AI 用量监控，Swift）。

**工作区**：`/Users/simengyu/projects/usage-deck/`
**Xcode 工程**：`CopilotMonitor/`，scheme=`CopilotMonitor`，测试 module=`OpenCode_Bar`，macOS 13+ / Swift 5
**测试命令**：`cd /Users/simengyu/projects/usage-deck/CopilotMonitor && xcodebuild test -scheme CopilotMonitor -destination 'platform=macOS' 2>&1 | tail -30`
**构建命令**：把上面 `test` 换成 `build`

## 你的任务

严格照 `docs/superpowers/plans/2026-07-01-token-king-阶段5-修复与provider指南.md` 逐 Task 执行，TDD（先写失败测试→跑失败→改实现→跑通过→提交），每 Task 单独 commit。

## 强制铁律（违反会导致编译失败或返工）

1. **pbxproj 手动管理**：任何新增 `.swift` 文件（含测试文件）必须手动改 `CopilotMonitor.xcodeproj/project.pbxproj`——PBXBuildFile（app + CLI 各一条，测试文件是 test target 一条）、PBXFileReference、PBXGroup、PBXSourcesBuildPhase。参考现有 `MiniMaxProvider.swift` 或某个测试类的注册结构照抄，改文件名和 UUID（助记命名如 `KIMITESTFILE...`）。漏一处 = "Cannot find X in scope"。

2. **阶段3中文化铁律**：不翻译 provider displayName（品牌名）、authSource 数据标识、logger/debugLog 串、SF Symbol 名、被 `==` 比较的状态串。只翻面向用户的菜单/弹窗文案。

3. **阶段2货币铁律**：USD 是数据层唯一真值。本次货币方案已定为 **A**——给 `SubscriptionPreset` 加 `cnyCost: Double?`（默认 nil），国内套餐存人民币原生价，`cost`(USD) 仍作 ROI 计算真值，只在渲染边缘选择显示 ¥cnyCost 还是 format(usd:)。

4. **安全**：不 commit 含真实凭证的文件。auth.json（`~/.local/share/opencode/auth.json`）由用户手动填 key，你不代写。commit 用 `git add <具体文件>`，不用 `git add .`。

## 三个必须先做「实时验证」的阻塞点（不验证不许改代码）

- **Task 2（Kiro）**：先跑 `kiro-cli /usage` 拿真实输出，确认 1905 出现在什么格式，据实改正则。当前正则只认 `Credits (X of Y)`，真实格式可能不同。别照搬计划里的占位测试字符串。

- **Task 6（Kimi 国内价）**：Kimi 国内套餐人民币价**未核实**，你必须查 kimi 官网（platform.moonshot.cn / kimi.com）填真实人民币价，不许用 $19×7.2 凑。查 Context7 或官网。

- **Task 7（MiniMax 国内端点）**：先用用户提供的国内套餐 key，curl 测 `https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains`（Bearer 鉴权）。确认能否调通、是否需要 cookie/session（上游 issue #88 提过 cookie 依赖）。调通再改端点数组。用户套餐档位是 **Ultra 极速版 ¥899**。

## 两个需要跟用户确认的产品决策（做到对应 Task 前先问）

- **Task 4「点击配置」跳转目标**：计划默认方案(a)=弹窗提示 auth.json 字段名+路径。若用户想要(b)跳官网登录或(c)打开 auth.json 文件，据实改。

- **Task 6 CurrencyFormatter API**：计划假设有 `isRMB` 只读属性判断当前货币模式。执行前先看 `Services/CurrencyFormatter.swift` 实际 API 名，按真实的改（可能叫别的）。

## 执行顺序建议

Task 1（kimi，无阻塞）→ Task 3（codex，无阻塞）→ Task 5（antigravity）→ Task 4（错误过滤，依赖 T5 的关键词表）→ Task 8（品牌，无阻塞）→ Task 6（货币，需查 kimi 价）→ Task 2（kiro，需 CLI 输出）→ Task 7（minimax，需 curl 验证）→ Task 9（写指南文档）。

无阻塞的先做，需实时验证的攒到能拿到数据时做。每个 Task 做完跑一次全量测试确认原有 226 测试不回归。

全部做完，跑一次完整测试 + `make release` 装到 /Applications，人工确认菜单里 kimi/kiro/codex/minimax 显示正常、货币切换对订阅生效、未配置 provider 不刷屏。
