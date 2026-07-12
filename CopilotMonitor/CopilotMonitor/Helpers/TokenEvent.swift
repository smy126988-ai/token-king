import Foundation

/// Provider normalization enum (F2b internal perspective).
/// Cases follow the cross-tool normalized routing used by `TokenNormalizer`.
/// - `.kimi`, `.kimiCN`:    Moonshot Kimi (Global / China)
/// - `.claude`:             Anthropic Claude family
/// - `.codex`:              OpenAI GPT family
/// - `.minimax`, `.minimaxCN`: MiniMax brand (used by minimax-cn providerID)
/// - `.xiaomi`, `.xiaomiTokenPlanCN`: Xiaomi MiMo (used by xiaomi / xiaomi-token-plan-cn providerID)
/// - `.opencodeGo`:         OpenCode Go subscription
/// - `.zai`, `.nanoGpt`:    legacy cases (Z.AI / Nano-GPT API)
enum Provider: String, Codable, CaseIterable, Hashable {
    case kimi, kimiCN, claude, codex
    case minimax, minimaxCN
    case xiaomi, xiaomiTokenPlanCN
    case opencodeGo
    case zai, nanoGpt

    var displayName: String {
        switch self {
        case .kimi:               return "Kimi Global"
        case .kimiCN:             return "Kimi CN"
        case .claude:             return "Claude"
        case .codex:              return "Codex"
        case .minimax:            return "MiniMax"
        case .minimaxCN:          return "MiniMax CN"
        case .xiaomi:             return "MiMo"
        case .xiaomiTokenPlanCN:  return "MiMo (Token Plan CN)"
        case .opencodeGo:         return "OpenCode Go"
        case .zai:                return "Z.AI"
        case .nanoGpt:            return "NanoGpt"
        }
    }
}

enum TokenSource: String, Codable, CaseIterable, Hashable {
    case opencode, claudeCode, codexCli
    case kimiCli, kimiCode
    case zaiApi, nanoGptApi
}

struct TokenBreakdown: Codable, Hashable {
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheWrite: Int = 0
    var reasoning: Int = 0

    static let zero = TokenBreakdown()

    var total: Int {
        input + output + cacheRead + cacheWrite + reasoning
    }
}

struct TokenEvent: Codable, Hashable {
    let provider: Provider
    let model: String
    let source: TokenSource
    let sessionId: String
    let timestamp: Date
    let tokens: TokenBreakdown
    let sourceId: String
}
