# Token King 数据与计价正确性设计

## 1. 目标

让“本月 API 折算”成为可解释、可对账的估算结果：每一行都能回答由哪个数据源产生、按哪个 Provider/模型/计费层级、使用什么币种和价格来源计算，以及还有多少数据未计价。

## 2. 已确认根因

- `PricingTable.modelRate` 只在 Codex/OpenAI 分支被调用，Kimi、MiniMax、OpenCode Go 条目不可达。
- Kimi K2.7 原生 CNY 价格再次乘以 USD/CNY 汇率。
- `MonthCostCalculator` 不映射 `minimaxCN`、`opencodeGo`、`xiaomiTokenPlanCN`。
- Claude 不同模型被统一套用 Sonnet 代表价。
- 单一 `cache` 字段同时承担 cache read/write 含义，reasoning 未计价。
- 未知价格行保留 token 却以 0 元从顶层总额和列表消失。

## 3. 类型边界

新增明确类型，替换计价链中的无单位值：

```swift
enum PricingCurrency: String, Codable {
    case cny = "CNY"
    case usd = "USD"
}

struct PricingContext: Hashable {
    let provider: Provider
    let source: TokenSource
    let model: String
    let tier: PricingTier
}

struct TokenRate: Equatable {
    let freshInput: Double
    let cacheRead: Double?
    let cacheWrite: Double?
    let output: Double
    let reasoning: Double?
    let currency: PricingCurrency
    let sourceURL: URL
    let verifiedAt: Date
}

struct CostCoverage: Equatable {
    let pricedTokens: Int
    let totalTokens: Int
    let unknownReasons: Set<UnknownPricingReason>
}
```

`PricingTier` 首版包含 `.standard`、`.longContext`、`.unknown`。事件无法判断长上下文时不得假装精确，必须标 `.unknown` 并将结果设为估算或范围。

## 4. 查价顺序

1. 精确 `(provider, source, normalized model, tier)`。
2. 精确 `(provider, normalized model, standard)`，同时记录 tier 假设。
3. 仅当 Provider 的模型语义确实等价时使用 Provider 代表价。
4. 否则返回未计价，不跨 Provider 猜价。

关键路由：

- Kimi Code/Kimi CLI 归 Kimi 计费，K2.7 原生 CNY，不乘汇率。
- `opencodeGo` 的 DeepSeek/MiniMax/Kimi/MiMo 使用 OpenCode Go 官方 USD 价格。
- `minimaxCN` 使用 MiniMax 当前官方中国直连价格：M3 标准层 ≤512K 为 ¥2.10 input / ¥0.42 cache read / ¥8.40 output；不得套 OpenCode Go、划线原价或国际价格。事件缺少 context length 时只能以 standard estimate 计价并记录 tier 假设。
- `xiaomiTokenPlanCN` 使用对应 MiMo 模型公开价格并保留来源假设。
- Codex/OpenAI 按具体 GPT 模型；reasoning 默认按 output 价格，除非官方另有定义。
- Claude 只有精确官方模型价格才计价；未知新模型不回退为 Sonnet 精确值。

## 5. 币种转换

- `TokenRate` 保留原生币种。
- `MonthCostCalculator` 接收注入的 `ExchangeRateProviding`，把 USD 转成人民币。
- 测试使用固定汇率 fixture；生产使用 `ExchangeRateStore` 的带时间戳快照。
- UI 显示折算汇率和更新时间；汇率不可用时保留原生金额或标记缓存，不硬编码 6.79。

## 6. 计价结果

`MonthlyCostSummary` 同时返回：

- 已计价小计；
- Provider/模型明细；
- 已计价 token 数与总 token 数；
- 未计价原因；
- 是否使用价格、汇率或 tier 假设。

顶层不得把未知数据视为 0 元完整总额。显示示例：`本月 API 折算：¥70,840（已计价 92%）`；未计价 Provider 仍显示 token 和“未计价”。

## 7. 独立 oracle

从当前 2026-07 数据库导出脱敏、只含 Provider/模型/五类 token 的 fixture。期望金额由 CTCA 脚本或手工公式生成，不调用 App 的 `PricingCatalog`。

至少覆盖：

- Kimi K2.7 原生 CNY；
- MiniMax M3 中国直连 standard estimate；
- OpenCode Go DeepSeek V4 Pro/Flash；
- MiMo V2.5 Pro；
- GPT-5.4/5.5/5.6 系列；
- 未知 Claude 模型和长上下文未知状态。

## 8. 验收

- Kimi K2.7 `1M input + 1M cache read + 1M output = ¥34.80`。
- App calculator 与 CTCA fixture 逐模型误差 ≤¥0.01，总额误差 ≤1%。
- 所有 fixture token 都出现在 coverage 分母；未知行不消失。
- 原生 CNY、USD 转 CNY、reasoning、cache read/write 各有 RED→GREEN 测试。
- UI 顶层和明细都能看到 coverage 与未知原因。
