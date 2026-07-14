# Token King 桌面小部件 P0 实现规范

> 面向读者：负责写代码的 AI（minimax）
>
> 文档性质：实现规范（给 AI 看），每条 R 编号带验收标准
>
> 文档日期：2026-07-14
>
> 项目根：`/Users/simengyu/projects/usage-deck/`
>
> 主分支 HEAD：`7992ec2`
>
> 前置决策：桌面 widget 走 WidgetKit + JSON 镜像（方案②），localhost HTTP（方案④）不在 P0 实现。Schema 采用 windows[] + kind 口径。

---

## 0. 已实地核实的代码事实（不要再推翻，除非发现硬错误）

这些是本次动手前 grep + Read 源码确认的，不是 handoff 转述：

- 主 app bundle id：`com.tokenking.app`（`project.pbxproj` 确认）。
- 主 app entitlements 只有 `com.apple.security.network.client`，**无 sandbox、无 App Group**（`CopilotMonitor.entitlements` 全文确认）。**保持不动。**
- `ProviderUsage` 是二态枚举（`Models/ProviderUsage.swift`）：
  - `.quotaBased(remaining: Int, entitlement: Int, overagePermitted: Bool)`
  - `.payAsYouGo(utilization: Double, cost: Double?, resetsAt: Date?)`
  - 已实现 `Codable`、`usagePercentage`、`remainingQuota`、`totalEntitlement`、`cost`、`resetTime` 计算属性。**直接复用，不要重写。**
- `DetailedUsage`（`Models/ProviderResult.swift`）是巨型结构体，多窗口数据散落其中：Claude `fiveHourUsage/fiveHourReset` + `sevenDayUsage/sevenDayReset`；Codex `secondaryUsage/primaryReset/codexPrimaryWindowLabel/...`；Z.ai `tokenUsagePercent/mcpUsagePercent`；这些窗口值大多是百分比（Double 0-100）。
- `ProviderIdentifier` 枚举定义在 `Models/ProviderProtocol.swift`，是 provider 的稳定 id（`rawValue`）。snapshot 里 provider id 一律用 `ProviderIdentifier.rawValue`。
- 已有 `JSONFormatter.format(_:)`（`Models/ProviderResult.swift:608`）把结果转 JSON（CLI 用）。**它不是 widget snapshot，但映射逻辑可参考。** widget snapshot 用独立类型，不复用这个函数的输出结构。
- 5 秒缓存同步循环在 `App/AppDelegate.swift:305-311`（`monthlyTotalsRefreshTask`）。**这是 writer 的挂载点。**
- 当前无任何 widget target / WidgetKit 代码（grep 确认）。从零建。
- 全量测试基线：746 tests / 19 skipped / 0 failures。

---

## 1. P0 目标

新增一个 WidgetKit extension，出现在桌面 Widget Gallery，能搜到 "Token King"，可添加 Small/Medium/Large family，显示真实 provider 用量。数据通道：主 app 每 ≤30 秒写一个 JSON 快照到共享目录，widget 沙盒内用 home-relative temporary exception 读取。

**P0 不做**：localhost HTTP（④）、Darwin notify（③）、AppIntent 刷新、NSPanel、多 provider 全量展示的复杂布局。

---

## 2. 共享路径（R1-R3）

**R1｜新增 `SharedPaths`（app + widget 共享源文件）**
- 位置：`CopilotMonitor/CopilotMonitor/Shared/SharedPaths.swift`，同时加入 **app target 和 widget target** 两个 Sources。
- 真实 home 用 `getpwuid`，禁止 `NSHomeDirectory()`：
```swift
import Foundation

enum SharedPaths {
    static let sharedDirName = "com.tokenking.app.shared"
    static let snapshotFileName = "widget-snapshot.json"

    static func realHome() -> String {
        String(cString: getpwuid(getuid()).pointee.pw_dir)
    }

    static var sharedDirectory: URL {
        URL(fileURLWithPath: realHome())
            .appendingPathComponent("Library/Application Support/\(sharedDirName)", isDirectory: true)
    }

    static var snapshotURL: URL {
        sharedDirectory.appendingPathComponent(snapshotFileName)
    }
}
```
- 验收：app 和 widget 编译后调用 `SharedPaths.snapshotURL` 返回同一真实路径 `~/Library/Application Support/com.tokenking.app.shared/widget-snapshot.json`（用真实登录用户 home，不是容器 home）。

**R2｜共享目录必须由主 app 创建**
- writer 首次写入前 `FileManager.default.createDirectory(at: SharedPaths.sharedDirectory, withIntermediateDirectories: true)`。
- 验收：主 app 冷启动一次后目录存在。

**R3｜snapshot 相关类型全部放 `Shared/`，加入两个 target**
- `SharedPaths.swift`、`WidgetSnapshot.swift`（R4）都 app + widget 双 target membership。
- 验收：widget target 单独编译通过，不依赖 app target 的其它文件。

---

## 3. Snapshot Schema（R4-R6）—— windows[] + kind

**R4｜定义 `WidgetSnapshot` Codable 类型**
- 位置：`CopilotMonitor/CopilotMonitor/Shared/WidgetSnapshot.swift`
- 结构（这是 v1 契约，定死；`Date` 用 `JSONEncoder.dateEncodingStrategy = .iso8601`）：
```swift
import Foundation

struct WidgetSnapshot: Codable, Equatable {
    let version: Int              // 固定 1
    let snapshotAt: Date          // 文件生成时间
    let providers: [ProviderSnapshot]
    let monthlyCost: MonthlyCost?
}

struct ProviderSnapshot: Codable, Equatable {
    let id: String                // ProviderIdentifier.rawValue
    let displayName: String
    let kind: Kind                // quota | usage
    let primaryWindowId: String?  // Small family 渲染哪个 window
    let windows: [UsageWindow]    // 可为空（usage 类可能无窗口）
    let spendUSD: Double?         // 仅 usage 类
    let fetchedAt: Date?          // provider 实际抓取时间，可能早于 snapshotAt

    enum Kind: String, Codable { case quota, usage }
}

struct UsageWindow: Codable, Equatable {
    let id: String                // "5h" / "7d" / "monthly" / "token" / "mcp" / "primary" / "secondary"
    let label: String             // UI 显示用
    let usedPercent: Double        // 0-100+，所有 provider 都能算出，widget 画 ring/bar 用这个
    let resetsAt: Date?
    let used: Int?                // 绝对值，可选（quotaBased 有）
    let limit: Int?               // 绝对值，可选（quotaBased 有）
}

struct MonthlyCost: Codable, Equatable {
    let usd: Double
    let rmb: Double?
}
```
- 设计说明（给写代码的：为什么这么定）：
  - `usedPercent` 是所有 provider 的最大公约数字段——`ProviderUsage.usagePercentage` 已能算出。widget 主要靠它画进度。`used/limit` 只有 quotaBased 填。
  - `windows` 是数组因为 Claude(5h+7d)、Codex(primary+secondary)、Z.ai(token+mcp) 都是多窗口。Small family 只渲染 `primaryWindowId` 对应的那个。
  - `kind` 让 widget 决定画进度条(quota)还是画金额(usage)。
- 验收：`WidgetSnapshot` round-trip 编解码单测通过（encode 再 decode 等于原值）。

**R5｜从 `[ProviderIdentifier: ProviderResult]` 映射到 `WidgetSnapshot`**
- 新增 `WidgetSnapshotMapper`（`Shared/` 或 app target 均可，仅 app 用）。映射规则：
  - `.quotaBased(remaining, entitlement, _)` → `kind = .quota`。生成一个基础 window：`id="primary"`, `usedPercent = usage.usagePercentage`, `used = entitlement - remaining`, `limit = entitlement`。
  - `.payAsYouGo(utilization, cost, resetsAt)` → `kind = .usage`, `spendUSD = cost`, window：`id="primary"`, `usedPercent = utilization`, `resetsAt`。
  - **多窗口叠加**（从 `DetailedUsage` 补 window，有则加，无则跳过）：
    - Claude：`fiveHourUsage`→window `5h`，`sevenDayUsage`→window `7d`，reset 分别取 `fiveHourReset`/`sevenDayReset`。
    - Codex：`secondaryUsage`+`secondaryReset`→用 `codexSecondaryWindowLabel` 作 label；主窗口 reset 用 `primaryReset`，label 用 `codexPrimaryWindowLabel`。
    - Z.ai：`tokenUsagePercent`→window `token`，`mcpUsagePercent`→window `mcp`。
    - MiniMax/OpenCodeGo：`fiveHourUsage`/`sevenDayUsage`/`openCodeGoMonthlyUsage` 各成 window。
  - `primaryWindowId`：有多窗口时选"最紧张的"（`usedPercent` 最大）或第一个明确主窗口；单窗口就是 `"primary"`。**P0 允许简单实现：多窗口选 usedPercent 最大的作 primary。**
  - `displayName` 用 `ProviderIdentifier.displayName`。
- **不要**把 prediction、subscription、exchangeRate 等塞进 schema（无 widget 消费者，过度工程）。
- 验收：单测覆盖 Claude(多窗口)、一个 payAsYouGo provider、一个纯 quotaBased provider 三种映射，字段正确。

---

## 4. Snapshot Writer（R6-R8）

**R6｜monthlyCost 来源**
- 从 controller 现有 `cachedMonthlyTotals`（USD）+ `ExchangeRateStore` 算 RMB。USD 保留 2 位小数显示（schema 存原始 Double，显示层格式化）。
- 验收：snapshot 里 `monthlyCost.usd` 与菜单栏"本月 API 折算"数值一致。

**R7｜新增 `WidgetSnapshotWriter`（app target）**
- 位置：`CopilotMonitor/CopilotMonitor/Services/WidgetSnapshotWriter.swift`
- 原子写 + NSFileCoordinator：
```swift
func write(_ snapshot: WidgetSnapshot) {
    let coordinator = NSFileCoordinator()
    var coordError: NSError?
    var writeError: Error?
    try? FileManager.default.createDirectory(at: SharedPaths.sharedDirectory, withIntermediateDirectories: true)
    coordinator.coordinate(writingItemAt: SharedPaths.snapshotURL, options: .forReplacing, error: &coordError) { url in
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
            // 结构化日志：见 R11
        } catch { writeError = error }
    }
}
```
- 验收：写入过程中 widget 不会读到半截文件（atomic）；文件是合法 JSON（用 `python3 -m json.tool` 验证）。

**R8｜挂载到 5 秒循环 + 30 秒节流**
- 挂在 `AppDelegate.swift:305-311` 的 `monthlyTotalsRefreshTask` 循环末尾：读完 `refreshMonthlyTotalsCache()`/`refreshTokenStatsCache()` 后，从 `StatusBarController.providerResults`（内存里最新结果）映射 snapshot 并写。
- writer 内部 30 秒节流：记录 `lastWriteAt`，距上次 <30s 直接 return。
- **不新增独立的 provider fetch**；**不让 widget 触发拉取**。writer 只消费已在内存的数据。
- 启动 prime 一次（`AppDelegate.swift:314` 附近的立即 prime 逻辑同处补一次 writer 调用），避免 widget 首次添加时无文件。
- 验收：主 app 运行时，`~/Library/Application Support/com.tokenking.app.shared/widget-snapshot.json` 的 mtime 每约 30 秒更新一次，不是每 5 秒；启动 ~1s 内文件已存在。

---

## 5. Widget Target 配置（R9-R13）

**R9｜新建 WidgetKit extension target**
- target 名 `TokenKingWidget`，bundle id `com.tokenking.app.TokenKingWidget`。
- Info.plist 含：
```xml
<key>NSExtension</key>
<dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.widgetkit-extension</string>
</dict>
```
- 主 app 加 "Embed App Extensions" build phase，主 app target 依赖 widget target。
- 验收：`xcodebuild -scheme TokenKingWidget build` 成功；`.appex` 被 embed 进 `TokenKing.app/Contents/PlugIns/`。

**R10｜widget entitlements（sandbox + home-relative 只读）**
- 新文件 `TokenKingWidget/TokenKingWidget.entitlements`：
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
    <array>
        <string>/Library/Application Support/com.tokenking.app.shared/</string>
    </array>
</dict>
</plist>
```
- 路径必须以 `/` 开头、`/` 结尾、放数组里；不写 `~`、不写绝对 `/Users/...`。
- **主 app entitlements 不动**（保持只有 network.client）。
- 验收：见 R17 codesign 检查。

**R11｜结构化日志（可观测性）**
- subsystem 稳定含 `com.tokenking`，category 区分 `widget.writer` / `widget.provider`。
- writer 记录：write start / success|failure、file path、schema version、encoded bytes、provider count、snapshotAt、write duration。
- widget provider 记录：read source(file)、read success|failure、decode 失败类型、stale age、timeline requested next date。
- **禁止记录** API key / OAuth token / 完整凭证。日志用英文。
- 验收：Console.app 能看到一条含 `snapshotAt` + provider 数量的 decode success 正向日志（这是 R16 验收的硬证据）。

**R12｜TimelineProvider**
- placeholder/preview 用固定样例，不读盘。
- snapshot/timeline：用 `SharedPaths.snapshotURL` + `Data(contentsOf:)` 读一次，decode，生成一个 entry，`policy: .after(now + 15min)`。
- 读失败 → diagnostics entry；读到旧数据 → 标 stale。
- **stale 阈值 ≥ 90 分钟**（系统实际刷新 15-60 分钟，阈值若也设 15 分钟会长期误报 stale）。按 `snapshotAt` 判 stale。
- 验收：无文件/坏 JSON/主 app 未运行三种情况 widget 不崩，显示明确 stale 或 EmptyState。

**R13｜Widget View（Small / Medium / Large 三尺寸）**

**设计原则（用户定，不可违背）**：小部件布局由**数据颗粒度 + 尺寸物理空间**决定，不是"作者替用户挑看啥"。每个尺寸把它那块空间的信息密度吃满，用户自己选拖哪个尺寸到桌面。目标是"一眼看全貌"，全貌按尺寸递进：小尺寸看一家、中尺寸看一家详情或多家概览、大尺寸看多家详情。

**P0 交付范围（用户明确优先级）**：第一版只要求「能放到桌面 Widget Gallery + 显示真实数据」。视觉先对齐现有调性即可，精细样式优化留到后续迭代。不要为 P0 追求像素级还原或复杂动效。

**通用规则**：英文、SF Symbols、不用 emoji、用量百分比显式写 `Used`/`Left`、不硬编码 RGB（进度条/状态色可用系统色）、USD 2 位小数。排序默认按 `usedPercent` 降序（最紧张的在前）。kind=usage 的 provider 显示 `spendUSD` 而非进度条。

**WidgetDesignToken（新建，SwiftUI 版，数值对齐 `MenuDesignToken`）**：
- 现有 `MenuDesignToken`（`Helpers/MenuDesignToken.swift`）是 **AppKit**（`NSFont`/`NSColor`/CGFloat 常量），widget 用 **SwiftUI**，**不能直接复用代码**，需新建 `WidgetDesignToken`（放 widget target 或 `Shared/`），把下列视觉语言翻成 SwiftUI。
- 数值对齐（从 `MenuDesignToken` 抄）：
  - 正文字号 `13`（SwiftUI `.font(.system(size: 13))`）；数字/百分比用**等宽字体**（`.monospacedDigit()` 或 `.system(size:13, design:.monospaced)`）——对应现有 `Typography.monospacedFont`。
  - SF Symbol 图标尺寸 `16`；状态圆点 `8`。
  - 强调用 `.bold`（对应 `boldFont`），不用颜色强调普通文本。
- 状态视觉语言（从 `StatusBarIconView` 提炼，widget 版简化）：
  - 主用量图标 SF Symbol：`gauge.medium`（现有菜单栏用它表用量）。
  - 临界（额度快满）状态：用**系统红**小圆点/描边（对应现有 `criticalBadge` systemRed），不用自定义 RGB。P0 可简单用 `.foregroundStyle(.red)` 于临界项。
  - loading/error：widget 是静态快照，**不做转圈动画**；无数据显示 EmptyState 文案，stale 显示带时间戳的旧值。
- 进度条/ring 颜色：用系统色（`.tint`/`.green`/`.orange`/`.red` 按 usedPercent 分档），不硬编码 RGB。

**三尺寸各司其职**：

- **Small（正方形，空间只够一家）**：显示"最紧张的一家"的核心窗口——即所有 provider 里 `usedPercent` 最高的那个 provider 的 `primaryWindowId` 窗口。内容：displayName + ring/bar(`usedPercent`) + `Used`/`Left` 百分比 + reset 相对时间。
  - （P0 先固定显示"最紧张一家"；用户手动指定看哪家的配置项属于后续增强，不在 P0。）

- **Medium（横条）**：两种布局，二选一由 widget family 上下文或后续配置决定；**P0 实现"多家概览"**：按 `usedPercent` 降序列出尽量多的 provider，每家一行——displayName + 单条进度条(`usedPercent`) + 百分比。行数吃满横条高度。
  - （"单家多窗口详情"布局留作后续；P0 中尺寸先做多家概览，因为它更贴近"看全貌"。）

- **Large（方块，信息最密）**：多家 provider，每家展开其**全部 windows**（Claude 显示 5h + 7d 两条，Codex 显示 primary + secondary，Z.ai 显示 token + mcp）。每家一个分组：displayName 作组标题，下面每个 window 一条进度条 + label + 百分比 + reset。按 provider 的最高 `usedPercent` 降序排组。底部一行显示 `monthlyCost`（USD / RMB）。
  - 空间放不下所有 provider 时，按紧张度截断并明确标"+N more"（不静默省略）。

- **kind=usage provider 在任意尺寸**：不画进度条，显示 `spendUSD`（"$12.34 spent"），有 `resetsAt` 则附重置时间。

- **验收**：三个尺寸真机各添加一次，显示真实数据；Small 显示最紧张一家、Medium 显示多家每家一条、Large 显示多家展开多窗口 + 月成本；样式符合通用规则；截断时有 "+N more" 不静默丢数据。

---

## 6. 验收（R14-R18）—— 强于"只看没有 deny"

**R14｜全量测试 + lint 不回归**
- `make test` → 746(+新增) / 0 failures；`make setup` 已跑；pre-commit SwiftLint 0 warning。

**R15｜Release 产物验收**
- entitlement/签名可能 Debug/Release 分叉，必须验 **Release** 签出的 `.appex`（不只 Debug）。

**R16｜正向读取证明（fs_usage，比"没有 deny"强）**
- widget 刷新时：`sudo fs_usage -w -f filesys | grep tokenking.app.shared`，确认 widget 进程真的 `open` 了目标文件。
- 配合 R11 的 decode success 日志（含 snapshotAt + provider 数）。**只有"没有 deny"不算通过**（可能 widget 根本没执行读）。

**R17｜签名保真——禁用 `--deep`**
- **不要**用 `codesign --deep --force --sign -`（会丢/改嵌套 entitlement）。
- 用 inside-out 手动签名：先单独签 `.appex`，再签外层 app，不加 `--deep`。
- 签完检查：
```bash
codesign -d --entitlements - /Applications/TokenKing.app/Contents/PlugIns/TokenKingWidget.appex
```
- 期望：`app-sandbox = true`、`temporary-exception.files.home-relative-path.read-only` 存在、path 精确为 `/Library/Application Support/com.tokenking.app.shared/`。

**R18｜边界矩阵**
- 无文件 / 坏 JSON / 半写入 / stale / 主 app 被杀 —— 逐个验 widget 表现（明确 stale 或 EmptyState，不崩不空白）。
- 主 app 重启后 snapshot 能继续更新。

---

## 7. 明确不做（防 minimax 加戏）

- 不给主 app 加 sandbox / App Group（会让 Antigravity/Cursor/Kiro/OpenCode Zen 的 `Process` 调 CLI 失效）。
- 不走 App Group / `UserDefaults(suiteName:)` / Group Container。
- 不把 `f2b.sqlite` 搬进共享目录，不让 widget 读 SQLite、不让 widget 写库。
- 不让 widget 直接拉 provider、不执行外部 CLI、不用 `NSHomeDirectory()` / `/tmp` / absolute-path exception。
- P0 不实现 localhost HTTP、Darwin notify、AppIntent、NSPanel。
- schema 不加 prediction/subscription/exchangeRate 等无消费者字段。
- 不改 `StatusBarController.swift`（236KB 巨型文件）的既有逻辑；只在 AppDelegate 循环末尾加 writer 调用。

---

## 8. 建议实施顺序（小步）

1. R1-R5：SharedPaths + WidgetSnapshot + Mapper + 单测（纯逻辑，无 target 改动，最先验）。
2. R6-R8：Writer + monthlyCost + 挂载 5 秒循环 + 节流（app 侧，能看到 JSON 文件产出即验证一半）。
3. R9-R13：建 widget target + entitlements + TimelineProvider + View。
4. R14-R18：签名 + 真机 + fs_usage + 边界矩阵。

每步 `git stash` 快照、单独 commit。R1-R2 阶段先跑一次 `xcodebuild ... test` 确认基线 746/0 未破。

---

## 9. 引用

- 数据模型：`CopilotMonitor/CopilotMonitor/Models/ProviderUsage.swift`、`Models/ProviderResult.swift`、`Models/ProviderProtocol.swift`
- Writer 挂载点：`CopilotMonitor/CopilotMonitor/App/AppDelegate.swift:305-317`
- 主 app entitlements：`CopilotMonitor/CopilotMonitor/CopilotMonitor.entitlements`
- pbxproj：`CopilotMonitor/CopilotMonitor.xcodeproj/project.pbxproj`
- 上游决策 handoff：`docs/handoffs/2026-07-14-widget-decision-rethink.md`
- TokenEater 范式：`.swarm/workers/recon-A-tokeneater-real.md`
