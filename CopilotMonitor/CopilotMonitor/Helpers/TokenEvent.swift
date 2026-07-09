import Foundation

/// Provider 归一化后枚举 (F2b 主视角, F1/F3/F4 扩展).
/// - `.kimi`:    kimi Global — kimi-for-coding / k2p* / "moonshot" providerID
/// - `.kimiCN`:  kimi CN — kimi 模型但 providerID 含 'cn' / 'kimi-cn'
/// - `.claude`:  claude-* / anthropic providerID
/// - `.codex`:   gpt-* / o3-* / o4-* / openai providerID
/// - `.zai`:     glm-* / z-ai providerID
/// - `.minimax`: minimax Global — minimax-m* / mimo-v2.5-pro 等 model
/// - `.minimaxCN`: minimax CN — providerID 含 'cn' / 'minimax-cn'
/// - `.xiaomi`:  xiaomi Global — qwen3.7-max 等 model, providerID 'xiaomi'
/// - `.xiaomiTokenPlanCN`: xiaomi token-plan CN — providerID 含 'token-plan'
/// - `.nanoGpt`: 兜底 (任何未识别的 model + providerID)
enum Provider: String, Codable, CaseIterable, Hashable {
    case kimi, kimiCN, claude, codex, zai, nanoGpt
    case minimax, minimaxCN
    case xiaomi, xiaomiTokenPlanCN

    var displayName: String {
        switch self {
        case .kimi:                return "Kimi Global"
        case .kimiCN:              return "Kimi CN"
        case .claude:              return "Claude"
        case .codex:               return "Codex"
        case .zai:                 return "Z.AI"
        case .nanoGpt:             return "NanoGpt"
        case .minimax:             return "MiniMax Global"
        case .minimaxCN:           return "MiniMax CN"
        case .xiaomi:              return "Xiaomi Global"
        case .xiaomiTokenPlanCN:   return "Xiaomi Token Plan CN"
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
