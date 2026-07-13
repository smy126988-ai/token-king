import Foundation
import os.log

private let tokenNormalizerLogger = Logger(subsystem: "com.opencodeproviders", category: "TokenNormalizer")

/// Provider normalization. Routes the raw `model` + `providerID` of each event
/// into a single `Provider` enum case. Resolution priority:
///
///   1. `providerID` is the strongest signal — direct routes take precedence
///      (e.g. `opencode-go` => `.opencodeGo`, `xiaomi-token-plan-cn` => `.xiaomiTokenPlanCN`).
///   2. `model` prefixes are used when `providerID` is empty or generic
///      (e.g. `claude-sonnet-4-5` => `.claude`, `gpt-4o` => `.codex`).
///   3. Unknown combinations fall back to `.nanoGpt` with a warning.
///
/// Note on `mimo`: the `mimo` model is only ever served through one of the
/// Xiaomi MiMo providers, so a model-based fallback is unnecessary; the
/// providerID-direct routes above handle it. Earlier code carried a
/// `mimo` model-fallback branch that was always shadowed by the
/// providerID check, removed in the audit.
///
/// Kimi Global / CN split: providerID contains `cn` / `kimi-cn` => `.kimiCN`,
/// otherwise `.kimi`. Same logic for `.minimaxCN` / `.xiaomiTokenPlanCN`.
struct TokenNormalizer {
    static func matchProvider(model: String, providerID: String) -> Provider {
        let m = model.lowercased()
        let p = providerID.lowercased()

        // providerID direct routes (strongest signal).
        if p.contains("minimax") {
            // `minimax-cn` => China, plain `minimax` => global. Substring match
            // keeps the rule resilient to slight naming changes.
            return p.contains("cn") ? .minimaxCN : .minimax
        }
        if p.contains("xiaomi-token-plan") || p.contains("xiaomi_token_plan") {
            return .xiaomiTokenPlanCN
        }
        if p.contains("xiaomi") {
            return .xiaomi
        }
        if p.contains("opencode-go") || p.contains("opencode_go") {
            return .opencodeGo
        }
        if p.contains("opencode") {
            // Older OpenCode SDKs emitted bare `opencode` as the providerID for the
            // Go subscription. Route to `.opencodeGo` to preserve attribution.
            return .opencodeGo
        }
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
        // P0-3 fix: NanoGPT routes via its own providerID, regardless of model
        // name. Without this branch, NanoGPT API responses carrying OpenAI-style
        // models (e.g. `gpt-4o`) would fall through to the model-based fallback
        // and be misclassified as `.codex`. The providerID is the strongest
        // signal — when it points at NanoGPT, we trust it over the model.
        if p.contains("nanogpt") || p.contains("nano-gpt") || p.contains("nano_gpt") {
            return .nanoGpt
        }

        // model-based routing as fallback when providerID is generic or empty.
        if m.contains("kimi") || m.hasPrefix("k2p") {
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
        if m.contains("minimax") {
            return p.contains("cn") ? .minimaxCN : .minimax
        }
        if m.contains("mimo") {
            // Xiaomi MiMo. Some Claude Code subagent chains pass model name
            // without providerID; we only know it via the model. Token-plan
            // hint would distinguish CN, but without providerID we default to
            // global MiMo (`.xiaomi`). Most observed: xiaomi-token-plan-cn.
            return .xiaomi
        }
        if m.hasPrefix("glm-") {
            return .zai
        }

        tokenNormalizerLogger.warning("F2b: unknown model '\(model, privacy: .public)' providerID '\(providerID, privacy: .public)', fallback to .nanoGpt")
        return .nanoGpt
    }
}
