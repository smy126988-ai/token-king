# F2a Pricing Research — 2026-07-07

> Source-of-truth for the 6 PayAsYouGoRate values in `Helpers/PricingTable.swift`.
> This file is for traceability only; not shipped in the app bundle.

## FX Reference

- **Query date**: 2026-07-07
- **USD → CNY rate**: 1 USD = 6.79 CNY (per tradingeconomics.com, Wise, Yahoo Finance, Investing.com, CurrencyBeacon, 2026-07-06/07 close)
- **Note on user estimate**: Plan spec mentioned ~7.25 as a known reference. Actual rate on query date is **6.79**. All USD→RMB conversions below use **6.79**, not 7.25. Differs from spec by ~6.3%.

## Per-provider findings

### kimi / kimiCN (Moonshot platform)

- **Representative model**: `kimi-k2.6` (multimodal, current flagship per Moonshot docs as of 2026-07-07)
- **Input (uncached)**: ¥6.50 / M tokens
- **Output**: ¥27.00 / M tokens
- **Cache (cached input, hit)**: ¥1.10 / M tokens
- **URL**: https://platform.moonshot.cn/docs/pricing/chat-k26
- **Note**: .kimi and .kimiCN share the same Moonshot platform; both use this rate. Auto context caching is supported.
- **Alternative model observed**: `kimi-k2.7-code` at ¥6.50 uncached / ¥27.00 output / ¥1.30 cached (https://platform.moonshot.cn/docs/pricing/chat-k27-code). F2a uses the general K2.6 flagship; switching to K2.7-Code is a one-line edit in `PricingTable.swift` if needed.

### copilot

- **Representative model**: N/A (Premium request model, not token-based)
- **Input**: N/A (Premium request is a per-message multiplier, not a per-token rate)
- **Output**: N/A
- **Cache**: N/A
- **URL**: https://docs.github.com/en/copilot/get-started/plans
- **Note**: Copilot plans are flat-fee subscriptions ($10/$19/$39/$100/month for Pro/Pro+/Business/Enterprise/Max). The "Premium request" is a credit-multiplier abstraction, not a token rate — Copilot does not publish a $ or ¥ per-million-tokens rate for usage-based billing. F2a returns `nil` for both `.copilot` in `PricingTable.rate(for:)`. UI may show "—" or hide the row.

### claude (Sonnet 4.5)

- **Representative model**: `claude-sonnet-4-5`
- **Input (raw)**: $3.00 / M tokens
- **Output (raw)**: $15.00 / M tokens
- **Cache write (raw)**: $3.75 / M tokens
- **Cache read (raw)**: $0.30 / M tokens
- **Input (converted)**: ¥20.37 / M tokens
- **Output (converted)**: ¥101.85 / M tokens
- **Cache write (converted)**: ¥25.46 / M tokens
- **Cache read (converted)**: ¥2.04 / M tokens
- **URL**: https://www.anthropic.com/pricing
- **Note**: Same rate as Sonnet 4.6 ($3/$15). Sonnet 5 has a temporary $2/$10 intro price through Aug 31, 2026, then reverts to $3/$15 — using the **stable** Sonnet 4.5 standard rate for F2a. Cache TTL = 5 min for the listed rates.

### zaiCodingPlan (GLM-4.6)

- **Representative model**: `glm-4.6`
- **Input (raw)**: $0.60 / M tokens
- **Output (raw)**: $2.20 / M tokens
- **Cache read (raw)**: $0.11 / M tokens
- **Cache storage (raw)**: limited-time free
- **Input (converted)**: ¥4.07 / M tokens
- **Output (converted)**: ¥14.94 / M tokens
- **Cache read (converted)**: ¥0.75 / M tokens
- **URL**: https://docs.z.ai/guides/overview/pricing (also corroborated by https://openrouter.ai/z-ai/glm-4.6)
- **Note**: Original spec URL `https://z.ai/pricing` returns 404 — the real pricing page is at `docs.z.ai`. Z.AI publishes in USD; conversion to RMB done at 6.79. GLM-5.2 is the newer flagship ($1.40/$4.40) but F2a pins GLM-4.6 per the F2a spec.

### nanoGpt

- **Representative model**: `gpt-4o` (per F2a spec; NanoGPT is a pass-through)
- **Input (raw)**: $2.50 / M tokens (= OpenAI list)
- **Output (raw)**: $10.00 / M tokens (= OpenAI list)
- **Cache (raw)**: N/A — NanoGPT does not publish its own cache line; OpenAI's gpt-4o cache rate ($1.25) applies upstream but NanoGPT does not surface it
- **Input (converted)**: ¥16.98 / M tokens
- **Output (converted)**: ¥67.90 / M tokens
- **URL**: https://nano-gpt.com/pricing (the public pricing page is JS-rendered; the only static example confirms "GPT-5.5 costs $5/$30 per million tokens at OpenAI, and exactly $5/$30 here. We add no percentage on top")
- **Note**: Best-effort inference. NanoGPT's marketing copy states "API pricing - no markup: Text model API usage is billed at list prices" — so GPT-4o at $2.50/$10 is the pass-through rate. Dynamic JS-rendered table made per-model scraping infeasible; rate is the OpenAI list price for gpt-4o. Flagging as `best-effort` because not directly read from NanoGPT's table cell — only from their pass-through claim. Validate against actual NanoGPT API response cost if possible.

### codex (gpt-4o)

- **Representative model**: `gpt-4o`
- **Input (raw)**: $2.50 / M tokens
- **Output (raw)**: $10.00 / M tokens
- **Cache input (raw)**: $1.25 / M tokens (50% discount, automatic)
- **Input (converted)**: ¥16.98 / M tokens
- **Output (converted)**: ¥67.90 / M tokens
- **Cache (converted)**: ¥8.49 / M tokens
- **URL**: https://platform.openai.com/docs/pricing (corroborated by https://openai.com/api/pricing/ via third-party trackers)
- **Note**: openai.com/api/pricing/ returns 403 to scrapers but the platform.openai.com/docs/pricing page (developer docs) returned full rate tables. GPT-4o pricing has been stable since Oct 2024.

## Summary table (for Helpers/PricingTable.swift)

| Provider | input ¥/M | output ¥/M | cache ¥/M | Source URL | Quality |
|---|---|---|---|---|---|
| .kimi | 6.50 | 27.00 | 1.10 (read) | platform.moonshot.cn/docs/pricing/chat-k26 | direct |
| .kimiCN | 6.50 | 27.00 | 1.10 (read) | platform.moonshot.cn/docs/pricing/chat-k26 (same as .kimi) | direct |
| .copilot | nil | nil | nil | docs.github.com/en/copilot/get-started/plans | architectural — return nil |
| .claude | 20.37 | 101.85 | 25.46 (write) / 2.04 (read) | anthropic.com/pricing | direct |
| .zaiCodingPlan | 4.07 | 14.94 | 0.75 (read) | docs.z.ai/guides/overview/pricing | direct |
| .nanoGpt | 16.98 | 67.90 | nil | nano-gpt.com/pricing (pass-through claim) | **best-effort** — inferred from pass-through claim, not read from rate cell |
| .codex | 16.98 | 67.90 | 8.49 (read) | platform.openai.com/docs/pricing | direct |

## Self-review notes

- **Completeness**: All 7 URLs fetched (some required sub-pages or fallback paths). Real numbers filled in for all 6 non-nil providers; nil documented for Copilot.
- **Quality**:
  - 6/7 rates are direct reads from the provider's published pricing page.
  - 1/7 (NanoGPT) is best-effort inferred from the pass-through claim; the JS-rendered table couldn't be machine-read.
  - USD→CNY conversion done at 6.79 (real rate on 2026-07-07), not the 7.25 estimate in the spec.
  - Original spec URL `https://z.ai/pricing` is a 404 — the real page is `docs.z.ai`. Discovered during the second fetch attempt.
- **Architectural concern** (matches the plan's hypothesis): Copilot has no token rate; F2a should return nil. Confirmed.
- **Date drift risk**: All rates were live on 2026-07-07. Re-run this research before F2a ships; Anthropic has noted Sonnet 5 reverts to $3/$15 on 2026-08-31.
