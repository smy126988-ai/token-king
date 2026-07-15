# 给 Kimi Code:Token King Widget 内容层修复(精确清单)

> 转给 Kimi。**背景/容器层已由另一方改好**(走系统原生磨砂,别碰 `containerBackground`/aurora/glass,已全删)。这轮你只修**内容排版层**。下面每条都附了我核实过的真因,别自己重新猜。

---

## 前提:先解决你的截图盲区

你上轮承认"截不了图、VLM 打分从没跑过"。这轮先解决:
- macOS 上 `#Preview` 无法用 xcodebuild 命令行渲染成图 —— 这是真的。
- **替代方案**:改完后不要自己判"及格"。把改动 commit + push,由人(用户)+ 外部模型(Claude)真机截图裁决。你的职责是**把改动做对 + 给编译证据**,不是自评视觉分。
- 所以这轮**取消 VLM 自评分要求**,改为:每条修复给出"改了哪个文件哪个函数 + 编译通过原文 + 一句话说明改法"。

---

## 逐条修复(按优先级)

### P0-1 中文文案清干净(违反项目英文铁律)
`AGENTS.md` 规定所有用户可见文案必须英文。widget 里现存中文:
- `配额` / `模型用量` badge → 英文(如 `Quota` / `Usage`)
- `刷新于 HH:MM:SS` → `Updated HH:MM:SS`
- `每 15min` / `每 120s` → `Every 15 min`(且数值要真实,别硬编码假周期)
- 检测命令:`grep -nP '[\x{4e00}-\x{9fff}]' CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift` 必须**无输出**
- 注意:provider 的 `displayName`(如 `Kimi for Coding(国内)`)来自数据层快照,不是 widget 硬编码的,那个不归你改。

### P0-2 provider 名截断
`MiniMax Coding P...`、`Kimi for Coding (...)` 被省略号截断。
- 真因:名字太长 + 容器宽度不够 + 右侧数值抢空间。
- 改法:名字行 `lineLimit(1)` + `.truncationMode(.tail)` 已有的话,考虑缩短显示名或把数值换行/降字号;大尺寸可用更紧凑的 `Primary 71%` 而非 `Primary 71% · 5h 0% · 7d...` 这种超长串。

### P1-3 ChatGPT 图标空方块(真 bug)
**我已核实**:16 个 imageset 都在 widget bundle 里,`providerAssetName` 映射也全命中(`codex`→`CodexIcon` 是对的)。所以**不是映射问题**。
- 真因候选:`CodexIcon` 是 PDF 矢量,`Image("CodexIcon").foregroundStyle(...)` 走了 template 渲染但 PDF 的渲染意图不对,渲染成空。
- 改法:检查 `CodexIcon.imageset` 的 `Contents.json` 渲染意图(template vs original);或 `ProviderIconView` 里对 PDF 资产不要强套 `.foregroundStyle`(template 化会把非单色 PDF 抹成空)。逐个 provider 实测哪些 asset 渲染出来、哪些空。
- **注意:OpenCode Go 显示的 □ 可能是对的** —— OpenCode 品牌 logo 本身就是方框(见原型 `ic-opencode` SVG 是嵌套方块)。别把正确的 logo 当 bug 改掉。先确认每个 □ 到底是"没渲染"还是"logo 本来就是方"。

### P1-4 删掉假刷新按钮
右上角圆圈箭头(`arrow.clockwise`)—— widget **不能交互**,点不动,是装饰误导。删掉。除非用 App Intent 做成真能刷新的按钮(成本高,这轮不做),否则不留假控件。

### P1-5 信息密度失衡
中/大尺寸单 provider 卡:`Primary 71/100` / `5h 0%` / `7d 0%` / `Monthly 71%` 四行,三行是 0,占大片没信息量;大卡下半整片空白、进度条却顶在最上。
- 改法:0% 的窗口行可折叠/弱化(如只在有量时显示,或并成一行);大尺寸重新平衡纵向留白,别让内容全挤在顶部。参考原型 `.w-lg` 的行间距和 footer 布局。

### P2-6 焦点四态(可选,本轮可不做)
只有 `.widgetAccentable()`,没有 `widgetRenderingMode` 去色分支。但**背景层已交给系统**,系统会自动处理 vibrant 去色,所以这条现在优先级低。先做 P0/P1。

---

## 不做
- 不碰 `containerBackground` / aurora / glass / 任何背景层(已删,走系统磨砂)。
- 不碰数据通道(HTTP/文件快照)、provider 的 `displayName` 来源、pbxproj、entitlements。
- 不做 VLM 自评分(截图工具链缺失,改由人+外部模型裁决)。

## 硬门槛(每条给证据)
1. 编译原文:`cd CopilotMonitor && xcodebuild build -scheme CopilotMonitor -target TokenKingWidget -destination 'platform=macOS' 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"` → 必须 `** BUILD SUCCEEDED **`
2. 中文检测:`grep -nP '[\x{4e00}-\x{9fff}]' CopilotMonitor/TokenKingWidget/TokenKingWidgetView.swift` → 无输出
3. 每条修复说明:改了哪个文件/函数 + 一句话改法
4. 只改内容层文件(`TokenKingWidgetView.swift`,必要时 `WidgetDesignToken.swift` 加内容 token);不碰背景层。

## 汇报格式
```
## P0-1 中文清理
文件:TokenKingWidgetView.swift MediumProviderCard
改法:badge "配额"→"Quota","刷新于"→"Updated","每15min"→"Every 15 min"
证据:grep 中文 无输出;BUILD SUCCEEDED
```
每条如实汇报,做了就做了,没做/没把握就明说,别报喜不报忧。
