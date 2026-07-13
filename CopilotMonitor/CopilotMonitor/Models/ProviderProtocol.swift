import Foundation

/// Defines the type of provider based on billing model
enum ProviderType {
    /// Pay-as-you-go model (e.g., OpenRouter, OpenCode)
    case payAsYouGo
    /// Quota-based model with monthly reset (e.g., Copilot, Claude, Codex, Gemini CLI)
    case quotaBased
}

/// 供应商家族，用于订阅套餐按供应商聚合。
enum ProviderFamily: String, CaseIterable {
    case copilot, claude, codex, commandCode, cursor, geminiCLI
    case openRouter, openCode, openCodeZen, openCodeGo, antigravity, kiro, grok
    case kimi, minimax, zai, nanoGpt, synthetic, chutes
    case tavily, brave
    case mimo, volcanoArk, hunyuan, zhipuGLM
}

/// 服务区域，决定显示哪个地区的订阅套餐。
enum ProviderRegion {
    case global, china
}

/// Identifies the specific AI provider
///
/// F2a pricing context. Cases map to representative rates in `PricingTable.rate(for:)`.
/// Provider-level cases (e.g. `.kimi`, `.codex`) cover the subscription /
/// plan-tracked family; raw-API-rate cases (`.minimaxCN`, `.openCodeGo`,
/// `.xiaomiTokenPlanCN`) were added in t1.2 (audit/p0-batch-1-t1.2) so F2b's
/// `MonthCostCalculator` can compute the 3 previously-zero-cost provider rows
/// in `month_aggregates` (verified via SQLite 2026-07-13).
///
/// r1.c (audit/p1-r1.c-enum-pricing-snapshot, 2026-07-13): added `.minimax`
/// and `.xiaomi` (global variants) to align with F2b `TokenEvent.Provider`'s
/// `.minimax` / `.xiaomi` cases (TokenNormalizer.swift:32, 37-38). F2b's
/// normalizer produces these when `providerID` contains `"minimax"` without
/// `"cn"` or `"xiaomi"` without `"xiaomi-token-plan"`. Both use rawValue
/// equal to the case name (no underscore separator) so the SQLite string
/// matches F2b's `Provider.rawValue` exactly. PricingTable.rate(for:) still
/// returns nil for both — international pricing is not yet stable
/// (minimax.io's USD list is promotional; Xiaomi does not publish global
/// per-token pricing). When international pricing stabilizes, add rates in a
/// follow-up task.
enum ProviderIdentifier: String, CaseIterable {
    case copilot
    case claude
    case codex
    case commandCode = "command_code"
    case cursor
    case geminiCLI = "gemini_cli"
    case openRouter = "openrouter"
    case openCode = "open_code"
    case antigravity
    case openCodeZen = "opencode_zen"
    case openCodeGo = "opencode_go"
    case kiro
    case grok
    case kimi
    case kimiCN = "kimi_cn"
    case minimaxCodingPlan = "minimax_coding_plan"
    case minimaxCodingPlanCN = "minimax_coding_plan_cn"
    case minimaxCN = "minimax_cn"
    case zaiCodingPlan = "zai_coding_plan"
    case nanoGpt = "nano_gpt"
    case synthetic
    case chutes
    case tavilySearch = "tavily_search"
    case braveSearch = "brave_search"
    case mimo
    case xiaomiTokenPlanCN = "xiaomi_token_plan_cn"
    case volcanoArk = "volcano_ark"
    case hunyuan
    case zhipuGLM = "zhipu_glm"
    // r1.c additions: global raw-API-rate cases for F2b alignment.
    case minimax
    case xiaomi

    var family: ProviderFamily {
        switch self {
        case .copilot: return .copilot
        case .claude: return .claude
        case .codex: return .codex
        case .commandCode: return .commandCode
        case .cursor: return .cursor
        case .geminiCLI: return .geminiCLI
        case .openRouter: return .openRouter
        case .openCode: return .openCode
        case .openCodeZen: return .openCodeZen
        case .openCodeGo: return .openCodeGo
        case .antigravity: return .antigravity
        case .kiro: return .kiro
        case .grok: return .grok
        case .kimi, .kimiCN: return .kimi
        case .minimaxCodingPlan, .minimaxCodingPlanCN, .minimaxCN, .minimax: return .minimax
        case .zaiCodingPlan: return .zai
        case .nanoGpt: return .nanoGpt
        case .synthetic: return .synthetic
        case .chutes: return .chutes
        case .tavilySearch: return .tavily
        case .braveSearch: return .brave
        case .mimo, .xiaomiTokenPlanCN, .xiaomi: return .mimo
        case .volcanoArk: return .volcanoArk
        case .hunyuan: return .hunyuan
        case .zhipuGLM: return .zhipuGLM
        }
    }

    var region: ProviderRegion {
        switch self {
        case .kimiCN, .minimaxCodingPlanCN, .minimaxCN, .mimo, .xiaomiTokenPlanCN,
             .volcanoArk, .hunyuan, .zhipuGLM: return .china
        // r1.c: `.minimax` and `.xiaomi` are the international/global variants
        // (CN counterparts are `.minimaxCN` / `.xiaomiTokenPlanCN`). Defaults
        // to `.global` via the existing default branch.
        default: return .global
        }
    }

    var displayName: String {
        switch self {
        case .copilot:
            return "GitHub Copilot"
        case .claude:
            return "Claude"
        case .codex:
            return "ChatGPT"
        case .commandCode:
            return "Command Code"
        case .cursor:
            return "Cursor"
        case .geminiCLI:
            return "Gemini CLI"
        case .openRouter:
            return "OpenRouter"
        case .openCode:
            return "OpenCode"
        case .antigravity:
            return "Antigravity"
        case .openCodeZen:
            return "OpenCode Zen"
        case .openCodeGo:
            return "OpenCode Go"
        case .kiro:
            return "Kiro"
        case .grok:
            return "Grok"
        case .kimi:
            return "Kimi for Coding"
        case .kimiCN:
            return "Kimi for Coding（国内）"
        case .minimaxCodingPlan:
            return "MiniMax Coding Plan"
        case .minimaxCodingPlanCN:
            return "MiniMax Coding Plan（国内）"
        case .zaiCodingPlan:
            return "Z.AI Coding Plan"
        case .nanoGpt:
            return "Nano-GPT"
        case .synthetic:
            return "Synthetic"
        case .chutes:
            return "Chutes AI"
        case .tavilySearch:
            return "Tavily"
        case .braveSearch:
            return "Brave Search"
        case .mimo:
            return "MiMo"
        case .minimaxCN:
            // Raw-API rate-tracking case. Distinct from .minimaxCodingPlanCN
            // (the Coding Plan subscription). Used by F2b MonthCostCalculator
            // when the SQLite `month_aggregates` row has provider="minimaxCN".
            return "MiniMax CN"
        case .xiaomiTokenPlanCN:
            // Raw-API rate-tracking case for Xiaomi MiMo Token Plan CN.
            // Distinct from .mimo (the F2a subscription-tracked MiMo entry).
            // F2b uses this for SQLite provider="xiaomiTokenPlanCN" rows.
            return "MiMo Token Plan CN"
        case .minimax:
            // r1.c: global raw-API rate-tracking case. Distinct from
            // .minimaxCodingPlan (the Coding Plan subscription). F2b
            // TokenNormalizer produces `.minimax` when providerID contains
            // "minimax" without "cn" (international routes). Display mirrors
            // F2b TokenEvent.Provider.minimax.displayName = "MiniMax".
            return "MiniMax"
        case .xiaomi:
            // r1.c: global raw-API rate-tracking case for Xiaomi MiMo.
            // Distinct from .mimo (the F2a subscription-tracked MiMo entry).
            // F2b TokenNormalizer produces `.xiaomi` when providerID contains
            // "xiaomi" without "xiaomi-token-plan". Display mirrors F2b
            // TokenEvent.Provider.xiaomi.displayName = "MiMo".
            return "MiMo"
        case .volcanoArk:
            return "火山 Ark"
        case .hunyuan:
            return "腾讯混元"
        case .zhipuGLM:
            return "智谱 GLM"
        }
    }

    var shortDisplayName: String {
        switch self {
        case .copilot:
            return "Copilot"
        case .claude:
            return "Claude"
        case .codex:
            return "Codex"
        case .commandCode:
            return "Command"
        case .cursor:
            return "Cursor"
        case .geminiCLI:
            return "Gemini"
        case .openRouter:
            return "Router"
        case .openCode:
            return "OpenCode"
        case .antigravity:
            return "Google"
        case .openCodeZen:
            return "Zen"
        case .openCodeGo:
            return "Go"
        case .kiro:
            return "Kiro"
        case .grok:
            return "Grok"
        case .kimi:
            return "Kimi"
        case .kimiCN:
            return "Kimi"
        case .minimaxCodingPlan:
            return "MiniMax"
        case .minimaxCodingPlanCN:
            return "MiniMax"
        case .zaiCodingPlan:
            return "Z.AI"
        case .nanoGpt:
            return "Nano"
        case .synthetic:
            return "Synth"
        case .chutes:
            return "Chutes"
        case .tavilySearch:
            return "Tavily"
        case .braveSearch:
            return "Brave"
        case .mimo:
            return "MiMo"
        case .minimaxCN:
            return "MiniMax CN"
        case .xiaomiTokenPlanCN:
            return "MiMo TP"
        case .minimax:
            // r1.c: short name for international MiniMax raw-API rate-tracking.
            return "MiniMax"
        case .xiaomi:
            // r1.c: short name for international Xiaomi raw-API rate-tracking.
            return "MiMo"
        case .volcanoArk:
            return "Ark"
        case .hunyuan:
            return "Hunyuan"
        case .zhipuGLM:
            return "GLM"
        }
    }

    var iconName: String {
        switch self {
        case .copilot:
            return "github"
        case .claude:
            return "brain.head.profile"
        case .codex:
            return "sparkles"
        case .commandCode:
            return "command"
        case .cursor:
            return "CursorIcon"
        case .geminiCLI:
            return "g.circle"
        case .openRouter:
            return "network"
        case .openCode:
            return "terminal"
        case .antigravity:
            return "arrow.up.circle"
        case .openCodeZen:
            return "moon.stars"
        case .openCodeGo:
            return "chevron.left.forwardslash.chevron.right"
        case .kiro:
            return "KiroIcon"
        case .grok:
            return "GrokIcon"
        case .kimi:
            return "k.circle"
        case .kimiCN:
            return "k.circle"
        case .minimaxCodingPlan:
            return "MinimaxIcon"
        case .minimaxCodingPlanCN:
            return "MinimaxIcon"
        case .zaiCodingPlan:
            return "globe"
        case .nanoGpt:
            return "NanoGptIcon"
        case .synthetic:
            return "SyntheticIcon"
        case .chutes:
            return "c.circle"
        case .tavilySearch:
            return "TavilyIcon"
        case .braveSearch:
            return "BraveSearchIcon"
        case .mimo:
            return "m.circle"
        case .minimaxCN:
            return "MinimaxIcon"
        case .xiaomiTokenPlanCN:
            return "m.circle"
        case .minimax:
            // r1.c: international MiniMax. Share icon with .minimaxCN.
            return "MinimaxIcon"
        case .xiaomi:
            // r1.c: international Xiaomi. Share icon with .xiaomiTokenPlanCN.
            return "m.circle"
        case .volcanoArk:
            return "v.circle"
        case .hunyuan:
            return "h.circle"
        case .zhipuGLM:
            return "z.circle"
        }
    }

    /// Whether this provider is enabled in the default app menu and refresh flow.
    /// Disabled providers remain available for explicit instantiation and unit tests.
    var isEnabled: Bool {
        switch self {
        case .kiro:
            return false
        default:
            return true
        }
    }
}

/// Protocol for fetching usage data from AI providers
protocol ProviderProtocol: AnyObject {
    /// The identifier for this provider
    var identifier: ProviderIdentifier { get }

    /// The type of billing model this provider uses
    var type: ProviderType { get }

    /// Timeout for fetch operations (default: 10 seconds)
    var fetchTimeout: TimeInterval { get }

    /// Minimum interval between network fetches for this provider (default: no throttling)
    var minimumFetchInterval: TimeInterval { get }

    /// Fetches current usage data from the provider
    /// - Returns: ProviderResult containing usage and optional detailed information
    /// - Throws: ProviderError if fetch fails
    func fetch() async throws -> ProviderResult
}

extension ProviderProtocol {
    var fetchTimeout: TimeInterval { 10.0 }
    var minimumFetchInterval: TimeInterval { 0 }
}

/// Errors that can occur during provider operations
enum ProviderError: LocalizedError {
    /// Authentication token is missing or invalid
    case authenticationFailed(String)
    /// Network request failed
    case networkError(String)
    /// Failed to parse API response
    case decodingError(String)
    /// Provider-specific error
    case providerError(String)
    /// Unsupported operation for this provider
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Failed to decode response: \(message)"
        case .providerError(let message):
            return "Provider error: \(message)"
        case .unsupported(let message):
            return "Unsupported: \(message)"
        }
    }
}
