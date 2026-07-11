import Foundation

/// Codex rollout JSONL scanner.
/// Path: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
///
/// IMPORTANT — `last_token_usage` semantics:
///   Codex CLI emits `last_token_usage.{input_tokens, cached_input_tokens,
///   reasoning_output_tokens}` as CUMULATIVE-per-session values (mirroring
///   `total_token_usage`), NOT per-turn deltas. The previous extractor
///   assumed per-turn semantics and stored the raw values directly, which
///   inflated `input` and `cache_read` by 10-30× depending on session length
///   (the inflation factor scales with turns-per-session because the same
///   numbers were summed many times).
///
/// To produce correct per-event values, this extractor walks each rollout in
/// order and applies `delta = max(0, current - previous)` to the cumulative
/// fields:
///   - input_tokens            (cumulative session) -> delta = per-turn input
///   - cached_input_tokens     (cumulative session) -> delta = per-turn cache
///   - reasoning_output_tokens (cumulative session) -> delta = per-turn reasoning
///   - output_tokens           is per-turn already (it does not accumulate
///                              across turns the same way cache does), so it
///                              is stored as-is.
/// First event in a session uses the raw cumulative value (the entire
/// "first turn" usage counts as that turn's delta). Shrinks clamp to 0.
///
/// When `last_token_usage` is absent, the older `total_token_usage`-vs-prev
/// fallback path is used (proportional split). That path was already correct
/// because it already treats the cumulative total as input to a delta
/// computation; the bug was only on the `last_token_usage` fast path.
struct CodexExtractor: TokenExtractorProtocol {
    let rootPath: String

    init(rootPath: String? = nil) {
        self.rootPath = rootPath
            ?? ProcessInfo.processInfo.environment["CODEX_DATA_DIR"]
            ?? "\(NSHomeDirectory())/.codex/sessions"
    }

    func extractAll() async throws -> [TokenEvent] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootPath),
              let enumerator = fm.enumerator(
                at: URL(fileURLWithPath: rootPath),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var events: [TokenEvent] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            events.append(contentsOf: parseFile(at: url))
        }
        return events
    }

    private func parseFile(at url: URL) -> [TokenEvent] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        let sessionId = url.deletingPathExtension().lastPathComponent

        var model = ""
        var events: [TokenEvent] = []
        var lineIndex = 0

        // Per-session cumulative trackers. Reset each rollout (session_id).
        // First event in a session has nil prev -> the raw value is treated
        // as the first turn's delta.
        var prevCumulativeInput: Int? = nil
        var prevCumulativeCache: Int? = nil
        var prevCumulativeReasoning: Int? = nil
        // Fallback cumulative total when `last_token_usage` is missing.
        var prevFallbackTotal: Int? = nil

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            defer { lineIndex += 1 }
            guard let lineData = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }

            if type == "session_meta" {
                if let payload = json["payload"] as? [String: Any],
                   let m = payload["model"] as? String {
                    model = m
                }
            } else if type == "turn_context" {
                if let payload = json["payload"] as? [String: Any],
                   let m = payload["model"] as? String {
                    model = m
                }
            } else if type == "event_msg",
                      let payload = json["payload"] as? [String: Any],
                      let payloadType = payload["type"] as? String,
                      payloadType == "token_count",
                      let info = payload["info"] as? [String: Any] {
                let totalUsage = info["total_token_usage"] as? [String: Any]
                let lastUsage = info["last_token_usage"] as? [String: Any]
                guard totalUsage != nil else { continue }

                let timestamp = parseTimestamp(json["timestamp"]) ?? Date(timeIntervalSince1970: 0)
                let msgId = (json["id"] as? String) ?? "\(lineIndex)"
                let effectiveModel = model.isEmpty
                    ? ((lastUsage?["model"] as? String) ?? "gpt-4o")
                    : model

                let breakdown: TokenBreakdown
                if isCompleteLastUsage(lastUsage) {
                    breakdown = deltaFromLastUsage(
                        lastUsage: lastUsage!,
                        prevInput: prevCumulativeInput,
                        prevCache: prevCumulativeCache,
                        prevReasoning: prevCumulativeReasoning
                    )
                    prevCumulativeInput = intValue(lastUsage?["input_tokens"])
                    prevCumulativeCache = intValue(lastUsage?["cached_input_tokens"])
                    // reasoning/output are per-turn, no prev tracking needed
                } else {
                    // Older Codex builds didn't emit `last_token_usage`. Fall
                    // back to the cumulative total track, proportional-split.
                    guard let totalUsage = totalUsage else { continue }
                    let totalTokens = intValue(totalUsage["total_tokens"])
                    let inputTokens = intValue(totalUsage["input_tokens"])
                    let outputTokens = intValue(totalUsage["output_tokens"])
                    let cachedTokens = intValue(totalUsage["cached_input_tokens"])
                    let reasoningTokens = intValue(totalUsage["reasoning_output_tokens"])
                    let nonCachedInput = max(0, inputTokens - cachedTokens)
                    guard let prev = prevFallbackTotal else {
                        // First event: treat raw cumulative as first turn's
                        // usage, just like the OpenCode first-event rule.
                        breakdown = TokenBreakdown(
                            input: nonCachedInput,
                            output: outputTokens,
                            cacheRead: cachedTokens,
                            cacheWrite: 0,
                            reasoning: reasoningTokens
                        )
                        prevFallbackTotal = totalTokens
                        _ = timestamp; _ = msgId; _ = effectiveModel
                        let event = TokenEvent(
                            provider: .codex, model: effectiveModel, source: .codexCli,
                            sessionId: sessionId, timestamp: timestamp,
                            tokens: breakdown,
                            sourceId: "codex:\(sessionId):main:\(msgId)"
                        )
                        events.append(event)
                        continue
                    }
                    let delta = max(0, totalTokens - prev)
                    prevFallbackTotal = totalTokens
                    breakdown = proportionalDelta(
                        totalDelta: delta,
                        nonCachedInput: nonCachedInput,
                        output: outputTokens,
                        cacheRead: cachedTokens,
                        reasoning: reasoningTokens,
                        total: totalTokens
                    )
                }

                let provider = TokenNormalizer.matchProvider(model: effectiveModel, providerID: "openai")
                events.append(TokenEvent(
                    provider: provider, model: effectiveModel, source: .codexCli,
                    sessionId: sessionId, timestamp: timestamp,
                    tokens: breakdown,
                    sourceId: "codex:\(sessionId):main:\(msgId)"
                ))
            }
        }
        return events
    }

    /// Convert Codex's `last_token_usage` fields into per-event values.
    ///
    /// Field semantics in real Codex rollouts (verified against user data):
    ///   - input_tokens:             CUMULATIVE per session (cache footprint
    ///                               that grew across turns). Must be delta-ed.
    ///   - cached_input_tokens:      CUMULATIVE per session. Must be delta-ed.
    ///   - output_tokens:            PER-TURN (fluctuates independently).
    ///                               Use raw value as-is.
    ///   - reasoning_output_tokens:  PER-TURN. Use raw value as-is.
    ///
    /// First event in a session uses the raw cumulative value as the delta
    /// (the entire first turn counts as that turn's contribution).
    /// Shrinks clamp to 0 — never negative.
    private func deltaFromLastUsage(
        lastUsage: [String: Any],
        prevInput: Int?,
        prevCache: Int?,
        prevReasoning: Int?    // kept for API symmetry; reasoning is per-turn, ignored below
    ) -> TokenBreakdown {
        let rawInput = intValue(lastUsage["input_tokens"])
        let rawCache = intValue(lastUsage["cached_input_tokens"])
        let rawOutput = intValue(lastUsage["output_tokens"])
        let rawReasoning = intValue(lastUsage["reasoning_output_tokens"])

        let deltaInput: Int
        if let pi = prevInput {
            deltaInput = max(0, rawInput - pi)
        } else {
            deltaInput = max(0, rawInput)
        }
        let deltaCache: Int
        if let pc = prevCache {
            deltaCache = max(0, rawCache - pc)
        } else {
            deltaCache = max(0, rawCache)
        }
        _ = prevReasoning    // reasoning/output are per-turn; see below.

        // Fresh input this turn = total input sent - cache hits served.
        // Can be 0 when nearly all of this turn's input was served from
        // an existing cache prefix.
        let freshInput = max(0, deltaInput - deltaCache)

        return TokenBreakdown(
            input: freshInput,
            output: max(0, rawOutput),
            cacheRead: deltaCache,
            cacheWrite: 0,
            reasoning: max(0, rawReasoning)
        )
    }

    private func isCompleteLastUsage(_ lastUsage: [String: Any]?) -> Bool {
        guard let lastUsage = lastUsage else { return false }
        let required = [
            "input_tokens",
            "output_tokens",
            "cached_input_tokens",
            "reasoning_output_tokens",
            "total_tokens",
        ]
        return required.allSatisfy { lastUsage[$0] != nil }
    }

    private func proportionalDelta(
        totalDelta: Int,
        nonCachedInput: Int,
        output: Int,
        cacheRead: Int,
        reasoning: Int,
        total: Int
    ) -> TokenBreakdown {
        guard totalDelta > 0, total > 0 else {
            return TokenBreakdown(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0)
        }

        let inputDelta = Int(Double(totalDelta) * Double(nonCachedInput) / Double(total))
        let outputDelta = Int(Double(totalDelta) * Double(output) / Double(total))
        let cacheReadDelta = Int(Double(totalDelta) * Double(cacheRead) / Double(total))
        let reasoningDelta = Int(Double(totalDelta) * Double(reasoning) / Double(total))

        let remainder = totalDelta - (inputDelta + outputDelta + cacheReadDelta + reasoningDelta)

        return TokenBreakdown(
            input: inputDelta + remainder,
            output: outputDelta,
            cacheRead: cacheReadDelta,
            cacheWrite: 0,
            reasoning: reasoningDelta
        )
    }

    private func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let i = Int(s) { return i }
        return 0
    }

    private func parseTimestamp(_ any: Any?) -> Date? {
        if let ts = any as? Double { return Date(timeIntervalSince1970: ts) }
        if let s = any as? String {
            // First try ISO 8601 (Codex CLI emits e.g. "2026-07-03T07:12:26.884Z").
            // Try with fractional seconds first, then plain.
            if let d = CodeISO8601DateParser.parse(s) { return d }
            // Last-resort: numeric seconds.
            if let ts = Double(s) { return Date(timeIntervalSince1970: ts) }
        }
        return nil
    }
}

/// Tiny helper: ISO 8601 strings with optional fractional seconds and a
/// trailing `Z`. Centralized so other extractors (ClaudeCode,
/// KimiCode) can reuse the same parser without bringing in DateFormatter
/// boilerplate each time.
enum CodeISO8601DateParser {
    static func parse(_ s: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: s) { return d }
        return nil
    }
}
