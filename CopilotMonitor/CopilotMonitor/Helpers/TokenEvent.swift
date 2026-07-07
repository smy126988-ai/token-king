import Foundation

/// Provider 归一化后枚举 (F2b 主视角).
enum Provider: String, Codable, CaseIterable, Hashable {
    case kimi, claude, codex, zai, nanoGpt

    var displayName: String {
        switch self {
        case .kimi:    return "Kimi"
        case .claude:  return "Claude"
        case .codex:   return "Codex"
        case .zai:     return "Z.AI"
        case .nanoGpt: return "NanoGpt"
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