import Foundation
import os.log

private let tokenNormalizerLogger = Logger(subsystem: "com.opencodeproviders", category: "TokenNormalizer")

/// Provider 归一化 (5 reference 共识: model 字段为主 + providerID 辅助).
/// 决策: model 优先, 匹配不到再用 providerID, 都失败 → .nanoGpt 兜底 + logger.warning.
/// Kimi Global / CN 区分: providerID 含 'cn' / 'kimi-cn' → .kimiCN, 否则 .kimi.
struct TokenNormalizer {
    /// 把 raw event 的 model + providerID 归一化到 Provider enum.
    /// - Parameters:
    ///   - model:       原始 model 名 (e.g. "kimi-for-coding", "claude-sonnet-4-5", "gpt-4o")
    ///   - providerID:  原始 providerID (e.g. "kimi", "anthropic", "openai", "z-ai", "opencode-go")
    /// - Returns: 归一化后的 Provider
    static func matchProvider(model: String, providerID: String) -> Provider {
        let m = model.lowercased()
        let p = providerID.lowercased()

        // model 字段为主
        if m.contains("kimi") || m.hasPrefix("k2p") {
            // Kimi CN 识别: providerID 含 cn / kimi-cn
            if p.contains("cn") || p.contains("kimi-cn") {
                return .kimiCN
            }
            return .kimi
        }
        if m.hasPrefix("claude-") {
            return .claude
        }
        if m.hasPrefix("gpt-") || m.hasPrefix("o3-") || m.hasPrefix("o4-") {
            return .codex
        }
        if m.hasPrefix("glm-") {
            return .zai
        }

        // providerID 辅助
        if p.contains("kimi-cn") || (p.contains("kimi") && p.contains("cn")) {
            return .kimiCN
        }
        if p.contains("kimi") || p.contains("moonshot") {
            return .kimi
        }
        if p.contains("anthropic") {
            return .claude
        }
        if p.contains("openai") {
            return .codex
        }
        if p.contains("z-ai") || p.contains("zai") {
            return .zai
        }

        // 兜底 (5 reference 共识: 不 panic, logger warning + 默认值)
        tokenNormalizerLogger.warning("F2b: unknown model '\(model, privacy: .public)' providerID '\(providerID, privacy: .public)', fallback to .nanoGpt")
        return .nanoGpt
    }
}
