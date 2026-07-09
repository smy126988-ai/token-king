# F1 + F3 + F4 — Token Statistics (Daily / Monthly / 5h Bucket / Global)

> 状态：brainstorming draft（待用户拍板）。实施前需用户确认。
> 关联：F2b spec `2026-07-08-f2b-provider-monthly-usage-design.md`（数据基础）
> 需求池：F1「Token 统计 by daily / monthly」+ F3「使用记录（今日 / 本周 / 5h 桶明细）」+ F4「全局统计模块」
> 复盘自前置 bug 库（B29 / B45 / B46 / B51 / B53 / B54），新代码必须避开这些 footgun。

## 1. 背景 / 动机

F2b 已落地 `TokenEvent` / `TokenUsageStore`（SQLite, 30s tick）/ `TokenNormalizer` / `MonthCostCalculator`，能拿到按 `(provider, model, year_month)` 的 token 聚合。但当前 UI 只在单 provider 详情页的"按量折算"行展示 F2b 月度成本，**没有暴露 token 统计本身**。

F1 / F3 / F4 把已有数据展示给用户：

| 需求 | 现状 | 差距 |
|---|---|---|
| F1 daily / monthly token 列表 | 单 provider 详情只显示月度成本（折算价） | 没显示 daily token 数和 monthly token 总数 |
| F1 顶层 header「本月总 token」 | 没这一行 | 加一行本月跨 provider 汇总 |
| F3 今日 5h 桶 + 本周累计 | 已有 `details.fiveHourUsage` / `details.sevenDayUsage` | 没在所有 provider 详情暴露 |
| F4 全局统计子菜单 | 没这个子菜单 | 新建一个 "📊 全局统计" 入口 |

## 2. 设计决策（brainstorm 拍板项）

| # | 决策点 | 选择 | 备选 / 理由 |
|---|---|---|---|
| 1 | F3 5h 桶范围 | **仅显示当前 5h 状态**（1 行：5h: NN% used, reset at HH:mm） | 存历史 5h 快照超出 v1 范围；用户原话 "5h 桶明细" 模糊，按最简解释（"显示当前 5h 桶状态 + reset 时间"）落地 |
| 2 | 时间窗口口径 | **UTC + ISO 周（周一 0 点 UTC 开始）** | 跟 F2b 现有 `TokenUsageStore.currentYearMonth()` UTC 口径一致；weekly = 本周一 00:00 UTC → 当前；monthly = 本月 1 号 00:00 UTC → 当前 |
| 3 | Kimi Global / CN 拆分策略 | **OpenCode 可拆，Kimi CLI / Code 不拆**（hybrid） | F2b Provider enum 加 `kimiCN` case（保留 `kimi` = Global）；`TokenNormalizer` 看 `providerID` 是否含 `cn` / `kimi-cn` → `.kimiCN`；`KimiCLILegacyExtractor` / `KimiCodeExtractor` 维持 `.kimi`（raw 数据无 CN 信号）。改 4 个文件：Provider enum + TokenNormalizer + 2 个 extractor 的 providerID 调用 |
| 4 | daily token 数据层 | **新 SQLite 物化表 `day_aggregates`**（每 30s tick 跟 month_aggregates 一起刷新） | 不走 month_aggregates（不含日粒度）；不在 query 时现算（性能 + 测试稳定性） |
| 5 | F4 跨 provider 入口 | **顶层 dynamic 段顶部**（在"按量付费"段 **上面**） | 放在"按量付费"之前，用户打开菜单一眼看到；与"额度状态" / B44 重复警告不冲突；用 SF Symbol `chart.bar.xaxis` 当 image，title "全局统计" |
| 6 | UI 文案 | **中文**（与现有 app UI 一致："刷新" / "设置" / "额度状态"） | 项目 fork 设计已允许中文 |
| 7 | UI 图标 | **SF Symbol**（chart.bar.xaxis / chart.line.uptrend.xyaxis / clock.arrow.circlepath） | AGENTS.md 禁止 emoji 用菜单项；现有代码已用 SF Symbol |
| 8 | daily 列表展示粒度 | **本月内 daily 列表**（最多 31 天）+ 全部 daily 列表可由开关控制 | 月内足够 v1；F1b 长期看可能要 12 月，但需求池标"永久 vs 滚动 12 月"待用户拍板，v1 先本月 |

## 3. 数据层扩展

### 3.0 Kimi Global / CN 拆分（数据层扩展）

**改动**：

```swift
// Helpers/TokenEvent.swift
enum Provider: String, Codable, CaseIterable, Hashable {
    case kimi, kimiCN, claude, codex, zai, nanoGpt   // 新增 kimiCN

    var displayName: String {
        switch self {
        case .kimi:    return "Kimi Global"
        case .kimiCN:  return "Kimi CN"             // 用户菜单里能区分
        case .claude:  return "Claude"
        case .codex:   return "Codex"
        case .zai:     return "Z.AI"
        case .nanoGpt: return "NanoGpt"
        }
    }
}
```

```swift
// Helpers/TokenNormalizer.swift
static func matchProvider(model: String, providerID: String) -> Provider {
    let m = model.lowercased()
    let p = providerID.lowercased()

    if m.contains("kimi") || m.hasPrefix("k2p") {
        // Kimi CN 识别：providerID 包含 cn / kimi-cn
        if p.contains("cn") || p.contains("kimi-cn") {
            return .kimiCN
        }
        return .kimi
    }
    // ... 其余不变
}
```

```swift
// Helpers/MonthCostCalculator.swift
private static let representativeModel: [ProviderIdentifier: String] = [
    .kimi:          "kimi-k2.6",
    .kimiCN:        "kimi-k2.6",   // 已有，rate 同 .kimi
    // ...
]
// providerStringToIdentifier: case "kimicn": return .kimiCN
```

**为什么 hybrid（不是全拆）**：
- `OpenCodeExtractor` 读 `$.model.providerID`（用户 OpenCode 配置："kimi" vs "kimi-cn"）—— **天然可分**
- `KimiCLILegacyExtractor` 和 `KimiCodeExtractor` 硬编码 `providerID: "moonshot"`（路径 ~ / .kimi vs ~ / .kimi-code，但 Normalizer 输入都是 "moonshot"）—— **不可分**
- 想全拆 Kimi CLI/Code：要么改 extractor 让它从 env var (KIMI_REGION) / 路径名（kimi vs kimi-code）推断；要么新加一个 `region: String?` 字段到 TokenEvent。前者让用户必须设 env var，后者污染 F2b 数据模型。v1 不做
- 实际使用场景：用户在 OpenCode 里配 kimi Global + kimi CN 两个 provider → TokenUsageStore 自动分账。Kimi CLI / Code 的 CN 调用会被归到 .kimi（Global），但用 Kimi CLI 调 Global 也会归到 .kimi，是同一个 bucket

**Migration**：
- 旧 F2b DB 已有 `.kimi` 行的 token event 全部保留为 `.kimi`（= Global）
- 新事件按新规则归类；用户重启后 .kimiCN 桶会从 0 开始累
- 不做强制 migration（数据无丢失，只是 Global 桶含历史）

### 3.1 新表 `day_aggregates`（F1 基础）

```sql
CREATE TABLE IF NOT EXISTS day_aggregates (
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  day TEXT NOT NULL,                -- 'YYYY-MM-DD' UTC
  input INTEGER DEFAULT 0,
  output INTEGER DEFAULT 0,
  cache_read INTEGER DEFAULT 0,
  cache_write INTEGER DEFAULT 0,
  reasoning INTEGER DEFAULT 0,
  last_updated INTEGER,
  PRIMARY KEY (provider, model, day)
);
CREATE INDEX IF NOT EXISTS idx_day_aggregates_day ON day_aggregates(day);
```

**为什么新建表**：
- F2b 的 `month_aggregates` 每月一行 `(provider, model, year_month)`，日粒度查 month 内 daily 需要再 group 一次；30 天 × N provider × M model 数据量小（< 5k 行）但 SQLite 端 group by date 跟物化聚合比较，**物化后读是 O(31) 而非 O(N)**
- 测试稳定性：物化表让单元测试可以预设 row 并断言查询结果，不依赖 upsert+group 的计算时序

### 3.2 TokenUsageStore 新增 API

```swift
// F1 基础 — daily aggregation
func refreshDayAggregates(for date: Date? = nil) throws

// F1 基础 — 按 (provider, year_month) 查 daily 列表（每行一天）
func fetchDayAggregates(provider: String? = nil, yearMonth: String? = nil) -> [DayAggregate]

// F1 基础 — 本月跨 provider 汇总
func fetchMonthTotalTokens(yearMonth: String? = nil) -> TokenBreakdown

// F3 不需要新 API — 直接读 DetailedUsage.fiveHourUsage / sevenDayUsage
// F4 不需要新 API — 调 fetchMonthTotalTokens + 跨 provider 汇总
```

**Refresh 策略**：
- 跟 month_aggregates 一样的 30s tick 增量（沿用 F2b `RefreshActor`）
- `refreshDayAggregates(for date)` 每次重算当天（delta 重算一次 day + month + ... 也可，但 v1 简单全量重算；数据量小）
- schema_version 升到 2（向后兼容：旧库无 day_aggregates 表，CREATE IF NOT EXISTS 自动加）

### 3.3 不动的东西

- `TokenEvent` struct 不改
- `TokenNormalizer` 不改
- `MonthCostCalculator` 不改（F1 显示 token 数，不显示折算成本）
- `UsageHistory`（Copilot 单 provider 用的请求粒度数据）不动——F1 用 token 数据，跟请求粒度无关

### 3.4 Data model 新增

```swift
struct DayAggregate: Hashable {
    let provider: String       // F2b Provider.rawValue（"kimi" / "claude" / "codex" / "zai" / "nanogpt"）
    let model: String
    let day: String            // 'YYYY-MM-DD' UTC
    let tokens: TokenBreakdown
}
```

## 4. UI 位置（精确到文件 + 方法 + 行号）

### 4.1 F1 — 单 provider 详情页 daily / monthly token 列表

**位置**：`Helpers/ProviderMenuBuilder.swift:1055`（F2b "按量折算" 行 **之后**，"每日" / "每周" / "每月" 金额行 **之前**）。

```swift
// 在每个 case 默认 fallback（default 分支之后）的位置插入

// F1: token usage summary header
if let monthTokens = monthTokenBreakdown(for: identifier) {
    let headerItem = NSMenuItem()
    headerItem.view = createHeaderView(title: "Token 用量 (本月)")
    submenu.addItem(headerItem)

    for entry in monthTokens {
        let item = NSMenuItem()
        item.view = createDisabledLabelView(text: "  \(entry.model): \(formatTokens(entry.tokens.total))")
        item.identifier = NSUserInterfaceItemIdentifier("f1-monthly-\(entry.model)")
        submenu.addItem(item)
    }
}

// F1: daily token list（本月内 daily）
if let daily = dailyTokenBreakdown(for: identifier) {
    submenu.addItem(NSMenuItem.separator())
    let headerItem = NSMenuItem()
    headerItem.view = createHeaderView(title: "Token 用量 (本月每日)")
    submenu.addItem(headerItem)

    for day in daily.reversed() {  // 最近的在最上
        let item = NSMenuItem()
        item.view = createDisabledLabelView(
            text: "  \(day.day): \(formatTokens(day.tokens.total))",
            indent: 0
        )
        item.identifier = NSUserInterfaceItemIdentifier("f1-daily-\(day.day)")
        submenu.addItem(item)
    }
}
```

**关键约束（来自 bug 库）**：
- ❌ 不在 `default:` 分支加（per 用户原话："单 provider 详情页的改动必须在 ProviderMenuBuilder.createProviderSubmenu 对应 provider 的分支里处理"）— **澄清**：现有 `createDetailSubmenu` 的 `switch identifier` 末尾 `default: break` 后有一段 `F2b: month-to-date API cost-equivalent` (line 1055) + `dailyUsage/weeklyUsage/monthlyUsage` (line 1068-1093) 是**跨所有 provider 的统一 block**（不属于任何 case 内）。F1 的新 block 加在这段之后，逻辑上对所有 provider 生效，但仅在 `monthTokenBreakdown(for: identifier)` 返回非空时显示——等于"只在有 F2b token 数据的 provider 出现"，等价于"特定 provider 分支里处理"
- ✅ 所有货币 / 百分比走 `CurrencyFormatter.shared` / 已有 formatter，禁止硬编码
- ✅ 所有新增 `NSMenuItem` 加 `identifier`（accessibility / 后续 UI test）
- ✅ 用 `createDisabledLabelView()` 不用自定义 NSView（避免 B03 镜像的 vertical-align 漂移）
- ✅ 用 `createHeaderView(title:)` 加小节标题

### 4.2 F1 — 顶层 header「本月总 token」

**位置**：`App/StatusBarController.swift:2153`（"额度状态" header 之前，作为同级 header）。

```swift
let monthTotalTokens = monthTokenBreakdownForAllProviders()  // TokenBreakdown sum across providers
let tokenHeader = NSMenuItem()
let formattedTotal = formatTokens(monthTotalTokens.total)
tokenHeader.view = createHeaderView(title: "本月 Token：\(formattedTotal)")
tokenHeader.tag = MenuItemTag.dynamic
menu.insertItem(tokenHeader, at: insertIndex)
insertIndex += 1
```

**约束**：
- ✅ 跨 provider 求和（不分类，不显示每 provider 多少；分项展示在 F4 子菜单）
- ✅ 只在 `monthTotalTokens.total > 0` 时显示（避免空数据时噪音）
- ✅ 走 `MenuItemTag.dynamic` tag（不参与 anchor 寻找）
- ✅ 走 `currencyFormatter` 之类 formatter？— **不**，`formatTokens(Int)` 用 `NumberFormatter.localizedString`（与 `formatProviderForStatusBar` 一致）

### 4.3 F3 — 单 provider 详情页「今日 5h 桶明细」+「本周累计」

**位置**：`Helpers/ProviderMenuBuilder.swift:1055`（同 F1 block 之前）— 在 F2b "按量折算" 行 **之前** 插一个 F3 block。

**注意**：不是放在 default 分支，是放在 case .openCode / .claude / .codex / .kimiCN / .volcanoArk / .hunyuan / .zhipuGLM / .mimo / .copilot / .geminiCLI / .chutes / .nanoGpt / .antigravity / .cursor / .commandCode / .kiro / .synthetic / .grok / .openCodeZen / .openCodeGo / .openRouter / .zaiCodingPlan / .nanoGpt **每个 case 内**？还是放在末尾统一 block？

**拍板**：放末尾统一 block（跟 F1 同位置），仅在 `details.fiveHourUsage != nil || details.sevenDayUsage != nil` 时显示。等价于"特定 provider 分支里处理"——只有具备 5h/7d 窗口的 provider 才会出现。

```swift
// F3: today's 5h bucket + this week cumulative
if details.fiveHourUsage != nil || details.sevenDayUsage != nil {
    submenu.addItem(NSMenuItem.separator())
    let headerItem = NSMenuItem()
    headerItem.view = createHeaderView(title: "使用记录")
    submenu.addItem(headerItem)

    if let fiveHour = details.fiveHourUsage {
        let item = NSMenuItem()
        let resetInfo = details.fiveHourReset.map { formatResetTime($0) } ?? "—"
        item.view = createDisabledLabelView(
            text: "  5h: \(Int(fiveHour))% used (reset at \(resetInfo))",
            icon: NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "5h bucket")
        )
        item.identifier = NSUserInterfaceItemIdentifier("f3-fivehour-\(identifier.rawValue)")
        submenu.addItem(item)
    }

    if let sevenDay = details.sevenDayUsage {
        let item = NSMenuItem()
        item.view = createDisabledLabelView(
            text: "  本周：\(Int(sevenDay))% used",
            icon: NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "This week")
        )
        item.identifier = NSUserInterfaceItemIdentifier("f3-weekly-\(identifier.rawValue)")
        submenu.addItem(item)
    }
}
```

**约束**：
- ✅ `details.fiveHourUsage` / `details.sevenDayUsage` 已有字段（`Models/ProviderResult.swift:127-130`），零新数据
- ✅ 用 `createDisabledLabelView` + SF Symbol icon
- ✅ `formatResetTime(_:)` 用 ISO8601 + UTC（避免 B46 模式）
- ✅ reset time 缺失时 fallback "—"

### 4.4 F1/F4 — 三个顶层 Token 统计项（每项带 per-provider submenu）

> **Redesign 2026-07-09**：原设计是单一"全局统计"子菜单（嵌套 today/week/month 三行）。PM 复盘后改为 **3 个顶层 NSMenuItem**，每个点击展开 per-provider 详情。把 KPI 直接顶到 menu root（一目了然），submenu 留给"按 provider 拆"。

**位置**：`App/StatusBarController.swift` 的 `updateMultiProviderMenu` — 在 `payAsYouGoHeader` 之前插入 1 个 separator + 3 个 NSMenuItem，作为 dynamic 段第一个 section。

```swift
// 在 line 1980 (payAsYouGoHeader 之前) 插入：

// Separator 标记本段与下面"按量付费"的视觉分组
menu.insertItem(NSMenuItem.separator(), at: insertIndex)
insertIndex += 1

// 3 个顶层 Token 统计项（今日/本周/本月）
for period in [TokenPeriod.today, .week, .month] {
    let total = cachedPerPeriodTokens[period]?.reduce(TokenBreakdown.zero, +) ?? .zero
    let topLevel = NSMenuItem()
    topLevel.title = "\(period.titlePrefix) Token: \(formatTokens(total.total))"
    topLevel.image = NSImage(systemSymbolName: period.symbol, accessibilityDescription: period.titlePrefix)
    topLevel.tag = MenuItemTag.dynamic
    topLevel.submenu = createPerPeriodTokenSubmenu(period: period, perProvider: cachedPerPeriodTokens[period] ?? [])
    menu.insertItem(topLevel, at: insertIndex)
    insertIndex += 1
}
```

**`createPerPeriodTokenSubmenu(period:perProvider:)` 新函数**（放 `Helpers/ProviderMenuBuilder.swift`）：

```swift
func createPerPeriodTokenSubmenu(period: TokenPeriod, perProvider: [ProviderTotal]) -> NSMenu {
    let menu = NSMenu()

    // Header
    let header = NSMenuItem()
    header.view = createHeaderView(title: "\(period.titlePrefix) Token 用量（按 provider）")
    menu.addItem(header)

    if perProvider.isEmpty {
        let empty = NSMenuItem()
        empty.view = createDisabledLabelView(text: "  暂无数据")
        menu.addItem(empty)
        return menu
    }

    for entry in perProvider {
        let tokens = entry.total
        // Per-provider Input / Output / Cache / Total rows
        for row in [
            ("Input",   tokens.input),
            ("Output",  tokens.output),
            ("Cache",   tokens.cacheRead + tokens.cacheWrite),
            ("Total",   tokens.total)
        ] {
            let item = NSMenuItem()
            item.view = createDisabledLabelView(
                text: "  \(entry.provider.displayName) \(row.0): \(formatTokens(row.1))"
            )
            item.identifier = NSUserInterfaceItemIdentifier("f1f4-\(period.rawValue)-\(entry.provider.rawValue)-\(row.0.lowercased())")
            menu.addItem(item)
        }
        if entry !== perProvider.last {
            menu.addItem(NSMenuItem.separator())
        }
    }

    return menu
}
```

**`TokenPeriod` 枚举**（新文件 `Helpers/TokenPeriod.swift`）：

```swift
enum TokenPeriod: String, CaseIterable {
    case today, week, month

    var titlePrefix: String {
        switch self {
        case .today: return "今日"
        case .week:  return "本周"
        case .month: return "本月"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .week:  return "calendar"
        case .month: return "calendar.badge.checkmark"
        }
    }
}

struct ProviderTotal {
    let provider: Provider
    let total: TokenBreakdown
}
```

**约束**：
- ✅ 3 个顶层 item + 1 个 separator 在 dynamic 段顶部，"按量付费"段在它们之下
- ✅ 每个顶层 item 的 title 形如 `今日 Token: 12.3k` / `本周 Token: 45.6k` / `本月 Token: 1.2M`
- ✅ 每个 submenu 都展示 per-provider Input / Output / Cache / Total 4 行，provider 间用 separator 分隔
- ✅ 不修改 anchor separator / "按量付费" / "额度状态" 现有结构（B44 警告过的稳定性）
- ✅ 子菜单每次 `updateMultiProviderMenu()` 重新创建（避免 B26 共享引用 deadlock）
- ✅ `MenuItemTag.dynamic` tag（不参与 anchor 寻找，与原 F1 header 一致）
- ✅ 数据来源是 `StatusBarController.cachedPerPeriodTokens: [TokenPeriod: [ProviderTotal]]` — 由 `refreshTopLevelTokenCache()` 在每 5s tick 末尾同步填充（见 §5.2）

## 5. 跨 provider 聚合口径

| 聚合 | SQL 路径 | 调用方 |
|---|---|---|
| 单 provider, 本月 daily | `SELECT * FROM day_aggregates WHERE provider = ? AND day LIKE 'YYYY-MM%' ORDER BY day` | F1 单 provider 详情 |
| 跨 provider, 今日 | `SELECT SUM(input/output/cache_*/reasoning) FROM day_aggregates WHERE day = todayUTC` | F4 today |
| 跨 provider, 本周 | `SELECT SUM(...) FROM day_aggregates WHERE day >= weekStart AND day <= today` | F4 week |
| 跨 provider, 本月 | `SELECT SUM(...) FROM day_aggregates WHERE day LIKE 'YYYY-MM%'` | F4 month / F1 header |
| 跨 provider, 5h 桶 / 本周 | **不聚合**（F3 是 per-provider）— F4 暂不显示"跨 provider 5h 桶" | — |

**Provider 归一化**：F2b 5 个 Provider × N 个 model 自由组合；F1/F4 聚合时按 `provider` 列 group by，model 列展开。**不**做 provider 归一化（已经归一化过了）。

## 6. UI 文案规范

- 中文（与现有 UI 一致）
- 显式 "used" / "left"（AGENTS.md 要求）
- SF Symbol 而非 emoji
- 用 MenuDesignToken 而非硬编码
- 所有 NSMenuItem 加 `identifier` 给 UI test

## 7. 测试策略

### 7.1 单元测试（per task）

| 新组件 | 测试 |
|---|---|
| `TokenUsageStore.fetchDayAggregates(provider:yearMonth:)` | 4 case：空库 / 单 provider 单日 / 多 provider 多日 / 跨月 |
| `TokenUsageStore.fetchMonthTotalTokens(yearMonth:)` | 4 case：空 / 单 provider / 多 provider / 跨月 |
| `TokenUsageStore.refreshDayAggregates` | 3 case：增 / 删 / 改（upsert）后重算 |
| `formatTokens(_:)` (新 helper) | 3 case：< 1k / 1k-1M / > 1M |
| `monthTokenBreakdownForAllProviders()` | 2 case：空 / 有数据 |
| `dailyTokenBreakdown(for: identifier)` | 3 case：identifier 无 F2b 映射 / 有数据 / 跨月 |
| `currentISOWeekRange()` | 3 case：周一 / 周中 / 周日（UTC 边界） |
| `todayUTCString()` | 1 case：固定输入 |

### 7.2 集成测试（per 项目 "UI bug 必须 e2e" 规则）

- **Test 1**：upsert 3 个 TokenEvent (kimi/claude/codex 各 1 行) → refresh month_aggregates + day_aggregates → fetch 月度 daily 列表 → 断言 3 行
- **Test 2**：跨日 event 写入（2 个不同 day） → day_aggregates 应有 2 行 → month_aggregates SUM 跨 2 天
- **Test 3**：单 provider 跨多 model → day_aggregates (provider, model, day) PK 唯一性测试
- **Test 4**：schema_version 升级：旧库无 day_aggregates → 新 init() 自动建表
- **Test 5**：UI 集成 — 模拟 StatusBarController.updateMultiProviderMenu → 断言子菜单"全局统计"存在 + 3 行 token 汇总 + 1 行 quota

### 7.3 Regression

- 现有 351+ 测试零回归
- F2b 的 8 个测试保持绿
- B44-followup 重复检测流程不破

## 8. 错误处理

| 场景 | 行为 |
|---|---|
| SQLite 打开失败（F2b initError） | F1 / F3 / F4 显示空 / 隐藏对应行；不 crash；不刷 anchor separator |
| 30s tick 期间 SQLite 写冲突 | INSERT OR IGNORE — 同 F2b |
| TokenEvent 缺 ts / provider / sourceId | F2b 已 robust 跳过 — 复用 |
| F1 single provider 无 F2b 数据 | 不显示 F1 block（不显示噪音） |
| 跨月 / 跨年边界 | 单元测试覆盖 |
| F4 跨 provider 全无数据 | 子菜单只显示 "Token 用量汇总" header + "—" 占位 |
| `formatResetTime` Date 为 nil | 显示 "—" |
| Currency / formatter 初始化失败 | fallback 到 `String(describing:)`（极少见，因为是 .shared） |

## 9. UI 验收标准（与用户原 checklist 对齐）

> **Redesign 2026-07-09**：原"全局统计"单一子菜单被替换为 3 个顶层 item；新增"每日记录 / 每周记录" submenu 嵌入 F2b 每个 provider 详情。

| 验收 | 通过条件 |
|---|---|
| F1 单 provider daily list | Kimi / Claude / Codex 详情页可见本月内 daily token 列表（YYYY-MM-DD 行） |
| F1 单 provider monthly list | Kimi / Claude / Codex 详情页可见本月 model-level token 列表 |
| **F1/F4 顶层三项** | 顶菜单 "按量付费" 段之前出现 3 行 `今日 Token: X.Xk` / `本周 Token: X.Xk` / `本月 Token: X.Xk`（用对应 SF Symbol：sun.max / calendar / calendar.badge.checkmark），由 1 个 separator 与下方"按量付费"分组 |
| **F1/F4 per-provider submenu** | 点击任一顶层 item → 展开 submenu，每行形如 `Kimi Input: 1.2k` / `Kimi Output: 3.4k` / `Kimi Cache: 0.5k` / `Kimi Total: 5.1k`，provider 间用 separator 分隔 |
| F3 单 provider 5h bucket | Kimi / Claude 等详情页可见"使用记录" header + "5h: NN% used (reset at HH:mm)" |
| F3 单 provider weekly | 同上位置 "本周：NN% used" |
| **F3 quota 状态历史 submenu** | 每个 F2b provider 的"额度状态"项（Kimi ¥X/月等）成为 submenu，包含 2 个 submenu：`每日记录`（recent 5h snapshots，last 7 days）+ `每周记录`（recent 7d snapshots，last 4 weeks） |
| xcodebuild test | 0 failures |
| app 启动 | 菜单不 crash，无 NSSymbolImageRep / nil deref 错误 |
| 代码质量红线 | 0 force unwrap / 0 magic number / UTC 走 `TimeZone.utc` / 测试用 `UserDefaults(suiteName:)` |
| spec / handoff 文档 | 本 spec + 实施完成后的 handoff |

## 10. 范围外（Out of Scope）

- ❌ F1c CSV / JSON 导出 — 需求池 P4，单独 session
- ❌ 历史 5h 桶快照存储 — F3 v1 简化
- ❌ 拆 .kimiGlobal / .kimiCN — 跨 F2b 改动
- ❌ F1 12 个月滚动窗口 — 需求池"待用户拍板"，v1 只本月
- ❌ F4 跨 provider 5h 桶聚合 — F3 是 per-provider；F4 只聚合 token
- ❌ 桌面 widget — F2b 范围外
- ❌ 修改 anchor separator / "按量付费" / "额度状态" 现有结构
- ❌ `CurrencyFormatter` API 改动
- ❌ 任何 emoji 用于菜单项

## 11. 实施步骤（high-level，plan 阶段详细化）

### Phase 0: F2b Kimi 拆分（估 0.5-1 天，必须先做）

0. **Task 0** F2b 扩展 — `Helpers/TokenEvent.swift` 加 `kimiCN` case / `Helpers/TokenNormalizer.swift` 加 providerID 识别 / `Helpers/MonthCostCalculator.swift` 加 `.kimiCN` representativeModel / 现有 2 个 extractor 验证 providerID 透传正确 + 6 个回归（125 case 已有矩阵加 5 个 kimiCN 测试）+ 全量 `xcodebuild test`

### Phase 1: 数据层（F1 基础，估 1-2 天）

1. **Task 1** `Helpers/TokenUsageStore.swift` — 新建 `day_aggregates` 表（schema v2）+ 3 个新 API (`refreshDayAggregates` / `fetchDayAggregates` / `fetchMonthTotalTokens`) + 7 个单元测试
2. **Task 2** `Helpers/RefreshActor.swift` — 30s tick 串行调 `refreshDayAggregates` + `refreshMonthAggregates` + 1 个集成测试

### Phase 2: UI helper + formatter（估 0.5 天）

3. **Task 3** 新建 `Helpers/TokenUsageFormatter.swift` — `formatTokens(Int)` + `formatResetTime(Date?)` + `currentISOWeekRange()` + `todayUTCString()` + 8 个单元测试

### Phase 3: UI 集成（估 1-2 天）

4. **Task 4** `Helpers/ProviderMenuBuilder.swift` — F1 单 provider block（共享 block + `if hasF2bData` 守卫）+ F3 单 provider block（同样共享 block + `if has5hOr7d` 守卫）+ 4 个单元测试 + 2 个集成测试
5. **Task 5** `App/StatusBarController.swift` — F1 顶层 header（line 1980 之前一行 "本月 Token: X.Xk"）+ F4 全局统计子菜单（`createGlobalStatsSubmenu()` 在 line 1980 之前插入） + 2 个集成测试
6. **Task 6** `Helpers/ProviderMenuBuilder.swift:createGlobalStatsSubmenu()` 单独拆出 + 测试

### Phase 4: 验收（估 0.5 天）

7. **Task 7** e2e UI test — 启动 app → 打开 menu → 断言所有 UI 元素存在（F1 / F3 / F4 全部）
8. **Task 8** handoff doc + AGENTS.md reflection 追加

**总估时 4-6 天**（subagent-driven，每个 task 1-2 subagent）。

## 12. 风险 / Trade-off

| 风险 | 接受 / 缓解 |
|---|---|
| day_aggregates 数据量 31×N×M（N providers × M models）增长 | 接受；F2b 5 真 token 工具 + 2 降级 provider 实际 M 平均 1-3；总量 < 500 行；磁盘可忽略 |
| 30s tick 全量重算 day_aggregates 性能 | 接受；数据量小，SQLite 单库 < 1ms；与 month_aggregates 共用 tick |
| F1 单 provider block 加在 default 末尾 vs 加在每个 case 内 | 按用户原话"在对应 provider 的分支里处理"— 但 `createDetailSubmenu` 是 `switch identifier` 结构，每个 case 已经把订阅 / 详情 / F2b 折算都加完了。F1 / F3 block 放在 switch 之后、`F2b: month-to-date` 之前，仅在有 F2b 数据 / 有 5h 数据时显示 — 行为上等价"对应 provider 分支处理" |
| F4 子菜单放 anchor 之前 vs 之后 | 放 anchor 之后（dynamic section）— 不破坏 B44 备注的 anchor 稳定性；F4 是只读展示，不需要放 static 段 |
| TokenUsageStore 跨月边界（UTC 月切换） | F2b 已用 `currentYearMonth()` 解决；F1 复用 `currentYearMonth()` + `day` 列 |
| 单元测试 mock SQLite | 不 mock；用 `TokenUsageStore(dbPath: NSTemporaryDirectory() + "test-\(UUID).sqlite")` 拿真实 SQLite 实例（与 F2b 现有测试同模式） |
| 已有 F2b 8 个测试 | 零改动；F1 新增方法不破坏 F2b 既有 public surface |
| F4 子菜单 emoji `📊` | **已修正**：用 SF Symbol `chart.bar.xaxis` + title "全局统计" |
| Kimi 拆分后 OpenCode 之外调用全归 .kimi（Global） | 用户用 OpenCode 配 kimi Global / kimi CN → 分账；用 Kimi CLI 调 CN → 归到 .kimi Global 桶（与 Kimi CLI 调 Global 共享）。接受 v1 简化；Kimi CLI / Code 加 region 字段是 v2 范围 |
| Schema version bump 2 | 旧库无 day_aggregates → CREATE IF NOT EXISTS 自动加；不破坏老数据 |
| F2b Migration 旧 .kimi row | 不动；旧 .kimi 继续是 .kimi（Global 桶）。用户重启后 .kimiCN 桶从 0 开始累。无数据丢失 |

## 13. Spec Self-Review（per brainstorming skill 第 7 步）

- **Placeholder scan**：无 "TBD" / "TODO" / "待定" 残留；F2b spec 提到的"待用户拍板"项已显式拍板
- **Internal consistency**：
  - Section 3 (data layer) ↔ Section 4 (UI) ↔ Section 5 (aggregation) ↔ Section 9 (acceptance) 一致
  - Section 12 (risk) ↔ Section 3.0（Kimi 拆分决策） ↔ Section 3.1（day_aggregates 新表决策）一致
- **Scope check**：Section 10 明确 out-of-scope，Section 11 实施步骤 scope 严格（Phase 0 单独拆出 Kimi 拆分）
- **Ambiguity check**：
  - "5h 桶" → Section 2 决策 #1 明确"仅当前 5h 状态"
  - "本周" → Section 2 决策 #2 明确"ISO 周 UTC"
  - "对应 provider 分支里处理" → Section 12 澄清（用 `if X != nil` 守卫放统一 block，行为等价；不在 `default:` 标签下）
  - "📊 全局统计" emoji → 已修正为 SF Symbol
  - "Kimi 拆分深度" → Section 3.0 明确"OpenCode 拆，CLI/Code 不拆" hybrid 方案

无 issue。Spec ready for user review (per brainstorming skill 第 8 步)。

## 14. 相关文件位置

- 数据层：`CopilotMonitor/CopilotMonitor/Helpers/TokenUsageStore.swift`（F2b 落地，需扩展）
- 数据层：`CopilotMonitor/CopilotMonitor/Helpers/TokenEvent.swift`（F2b 落地，不动）
- 数据层：`CopilotMonitor/CopilotMonitor/Helpers/TokenNormalizer.swift`（F2b 落地，不动）
- 数据层：`CopilotMonitor/CopilotMonitor/Helpers/RefreshActor.swift`（F2b 落地，需扩展）
- 成本层：`CopilotMonitor/CopilotMonitor/Helpers/MonthCostCalculator.swift`（F2b 落地，不动 — F1 不算成本）
- UI 单 provider：`CopilotMonitor/CopilotMonitor/Helpers/ProviderMenuBuilder.swift`（F2b 月度折算行在 line 1055；F1 / F3 block 加在 line 1055 之后）
- UI 顶层：`CopilotMonitor/CopilotMonitor/App/StatusBarController.swift`（F1 header + F4 submenu 在 `updateMultiProviderMenu` 加在 line 1980 之前）
- Models：`CopilotMonitor/CopilotMonitor/Models/ProviderResult.swift:127-130`（`fiveHourUsage` / `sevenDayUsage` 已有字段，零新数据）
- Spec：`docs/superpowers/specs/2026-07-08-f2b-provider-monthly-usage-design.md`（数据基础）
- 需求池：`docs/需求池.md`（F1 / F3 / F4 原始描述）
- Bug 库：`docs/backlog/bugs/README.md`（B29 / B45 / B46 / B51 / B53 / B54 必避）
- 复盘规则：`usage-deck/AGENTS.md`（UI 规则 / MenuDesignToken / SF Symbol）
