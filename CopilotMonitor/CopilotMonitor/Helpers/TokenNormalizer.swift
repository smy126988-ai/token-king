import Foundation
import os.log

private let tokenNormalizerLogger = Logger(subsystem: "com.opencodeproviders", category: "TokenNormalizer")

/// Provider normalization (providerID-first, model-name fallback).
///
/// Decision: `providerID` is the most reliable signal — it is the explicit
/// user choice of which upstream provider to route through, while `model` is
/// just a model name string. When both are present, trust providerID first.
/// When providerID is missing/empty, fall back to model-name heuristics.
/// Final fallback is `.nanoGpt`.
struct TokenNormalizer {
    /// Normalize a raw event's (model, providerID) into a Provider enum.
    ///
    /// Routing order:
    ///   1. `providerID` is checked first because it is the explicit user
    ///      choice (e.g. "opencode-go" / "opencode" / "xiaomi-token-plan-cn")
    ///      and is the only signal that disambiguates routing through a
    ///      multi-provider gateway like OpenCode Go.
    ///   2. When providerID is empty / unrecognized, fall back to model-name
    ///      patterns (`claude-` / `gpt-` / `glm-` / `kimi` / `minimax` /
    ///      `xiaomi` / `qwen3.7-max`).
    ///   3. Final fallback: `.nanoGpt` + a warning log so misclassified
    ///      events show up in `Console.app` instead of silently drifting.
    ///
    /// - Parameters:
    ///   - model:       raw model name (e.g. "kimi-for-coding", "claude-sonnet-4-5", "mimo-v2.5-pro")
    ///   - providerID:  raw providerID (e.g. "kimi", "anthropic", "openai", "z-ai", "opencode-go", "opencode")
    /// - Returns: normalized Provider
    static func matchProvider(model: String, providerID: String) -> Provider {
        let m = model.lowercased()
        let p = providerID.lowercased()

        // 1. providerID is the primary signal.
        if p.contains("nano-gpt") || p == "nanogpt" {
            return .nanoGpt
        }
        if p.contains("opencode-go") {
            if m.hasPrefix("gpt-5") || m.hasPrefix("gpt-4") {
                return .codex
            }
            if m.hasPrefix("claude-") {
                return .claude
            }
            if m.contains("minimax") || m.hasPrefix("mimo-") {
                return .minimaxCN
            }
            if m.contains("kimi") {
                return .kimi
            }
            return .kimi
        }
        if p == "opencode" || p.contains("opencode") {
            if m.contains("kimi") || m.hasPrefix("mimo-") {
                return .kimi
            }
            if m.contains("xiaomi") || m == "qwen3.7-max" {
                return .xiaomiTokenPlanCN
            }
            if m.contains("minimax") {
                return .minimaxCN
            }
            return .kimi
        }
        if p.contains("kimi-cn") || p.contains("kimicn") {
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
        if p.contains("minimax-cn") || (p.contains("minimax") && p.contains("cn")) {
            return .minimaxCN
        }
        if p.contains("minimax") {
            return .minimax
        }
        if p.contains("xiaomi-token-plan") || (p.contains("xiaomi") && p.contains("cn")) {
            return .xiaomiTokenPlanCN
        }
        if p.contains("xiaomi") {
            return .xiaomi
        }

        // 2. Model-name fallback (only when providerID is missing/empty).
        if m.hasPrefix("claude-") { return .claude }
        if m.hasPrefix("gpt-") || m.hasPrefix("o3-") || m.hasPrefix("o4-") {
            return .codex
        }
        if m.hasPrefix("glm-") { return .zai }
        if m.contains("kimi") || m == "kimi-for-coding" {
            return .kimi
        }
        if m.contains("minimax") || m.hasPrefix("mimo-") {
            return .minimax
        }
        if m.contains("xiaomi") || m == "qwen3.7-max" {
            return .xiaomiTokenPlanCN
        }

        // 3. Final fallback.
        tokenNormalizerLogger.warning("TokenNormalizer: unknown model '\(model, privacy: .public)' providerID '\(providerID, privacy: .public)', fallback to .nanoGpt")
        return .nanoGpt
    }
}