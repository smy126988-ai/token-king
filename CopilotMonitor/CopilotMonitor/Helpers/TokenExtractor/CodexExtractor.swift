import Foundation

/// Codex rollout JSONL scanner.
/// Path: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
///
/// Codex CLI emits `event_msg` rows with `payload.info.{total_token_usage,
/// last_token_usage}`. Both objects are cumulative session totals in the
/// underlying Anthropic-compatible API response:
///
///   - `total_token_usage`: cumulative from session start (always grows)
///   - `last_token_usage`: also cumulative for the last API call's view of
///     the conversation. Anthropic's prompt-caching layer returns
///     `input_tokens` (total prompt this call) and `cached_input_tokens`
///     (cached subset of this call's prompt). For our purposes:
///       * `cache_read_input_tokens` is per-request — it is the count of
///         cached prompt tokens served on THIS API call.
///       * `input_tokens` is the size of the prompt sent on THIS API call.
///         With AI SDK v6 normalization this includes the cached portion;
///         subtract cache_read (and cache_creation for write side) to get
///         the fresh non-cached input count.
///
/// Token handling therefore mirrors OpenCode's `data.tokens.*` shape:
///
///   fresh input  = input_tokens - cached_input_tokens - cache_creation_input_tokens
///   cache_read   = cached_input_tokens  (per-request; sum gives total billed)
///   output       = output_tokens         (per-request; sum gives total billed)
///   reasoning    = reasoning_output_tokens (per-request; sum gives total billed)
///   cache_write  = cache_creation_input_tokens (per-request; sum gives total billed)
///
/// **No cumulative-to-delta conversion is applied**: the Anthropic values
/// already represent this request's billing, not session state. Sum raw.
///
/// An older Codex CLI path that emitted only `total_token_usage` (no
/// `last_token_usage`) is still supported via the proportional-split
/// fallback that compares against the prior cumulative total.
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
        // Per-session cumulative trackers used by BOTH paths:
        // - `last_token_usage` path: tracks the previous 5 fields of
        //   `last_token_usage` to skip duplicate snapshots Codex CLI
        //   re-emits between billable turns (see ccusage PR #824 + issue
        //   #876 — raw-sum otherwise double-counts and inflates cache_read
        //   by ~30% on busy sessions like 7月10/11 2026).
        // - fallback path: tracks the previous `total_token_usage.total_tokens`
        //   for proportional delta split. Each tracker is initialized to
        //   nil so the first event always emits.
        var prevFallbackTotal: Int? = nil
        var prevLastInput: Int? = nil
        var prevLastCached: Int? = nil
        var prevLastOutput: Int? = nil
        var prevLastReasoning: Int? = nil
        var prevLastTotal: Int? = nil

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
                guard let totalUsage = info["total_token_usage"] as? [String: Any] else { continue }
                let lastUsage = info["last_token_usage"] as? [String: Any]

                let effectiveModel = model.isEmpty
                    ? ((lastUsage?["model"] as? String) ?? "gpt-4o")
                    : model

                let timestamp = parseTimestamp(json["timestamp"]) ?? Date(timeIntervalSince1970: 0)
                let msgId = (json["id"] as? String) ?? "\(lineIndex)"

                // Apply dedup. Two-step:
                //   1. If `last_token_usage` is complete, compare its 5 fields
                //      to the previous `last_token_usage`. Skip when every
                //      field is identical — Codex CLI re-emits the same
                //      snapshot between billable turns. (ccusage PR #824.)
                //   2. If `last_token_usage` is missing, the fallback path
                //      uses `prevFallbackTotal` to compute a cumulative
                //      delta and self-dedups. We also gate that branch on
                //      `input | cached | output | reasoning` equality vs the
                //      previous `total_token_usage` so identical snapshots
                //      are dropped.
                let breakdown: TokenBreakdown
                if isCompleteLastUsage(lastUsage) {
                    let curInput = intValue(lastUsage!["input_tokens"])
                    let curCached = intValue(lastUsage!["cached_input_tokens"])
                    let curOutput = intValue(lastUsage!["output_tokens"])
                    let curReasoning = intValue(lastUsage!["reasoning_output_tokens"])
                    let curTotal = intValue(lastUsage!["total_tokens"])
                    if let pIn = prevLastInput, let pC = prevLastCached,
                       let pO = prevLastOutput, let pR = prevLastReasoning,
                       let pT = prevLastTotal,
                       curInput == pIn, curCached == pC,
                       curOutput == pO, curReasoning == pR, curTotal == pT {
                        // Duplicate snapshot — Codex CLI re-emitted the same
                        // per-request value (no billable work between events).
                        prevLastInput = curInput
                        prevLastCached = curCached
                        prevLastOutput = curOutput
                        prevLastReasoning = curReasoning
                        prevLastTotal = curTotal
                        continue
                    }
                    prevLastInput = curInput
                    prevLastCached = curCached
                    prevLastOutput = curOutput
                    prevLastReasoning = curReasoning
                    prevLastTotal = curTotal
                    breakdown = perRequestBreakdown(
                        lastUsage: lastUsage!,
                        providerID: effectiveModel // use provider as id field hint
                    )
                } else {
                    // Older Codex builds didn't emit `last_token_usage`. Fall
                    // back to total_token_usage vs prior cumulative total.
                    let totalTokens = intValue(totalUsage["total_tokens"])
                    let inputTokens = intValue(totalUsage["input_tokens"])
                    let outputTokens = intValue(totalUsage["output_tokens"])
                    let cachedTokens = intValue(totalUsage["cached_input_tokens"])
                    let reasoningTokens = intValue(totalUsage["reasoning_output_tokens"])
                    let nonCachedInput = max(0, inputTokens - cachedTokens)
                    // Mirror OpenCode's `output = outputTokens - reasoningTokens`
                    // normalization so the two extractors produce comparable
                    // output/reasoning splits.
                    let netOutput = max(0, outputTokens - reasoningTokens)
                    guard let prev = prevFallbackTotal else {
                        breakdown = TokenBreakdown(
                            input: nonCachedInput,
                            output: netOutput,
                            cacheRead: cachedTokens,
                            cacheWrite: 0,
                            reasoning: reasoningTokens
                        )
                        prevFallbackTotal = totalTokens
                        push(&events, context: PushContext(
                            sessionId: sessionId,
                            model: effectiveModel,
                            timestamp: timestamp,
                            msgId: msgId,
                            breakdown: breakdown
                        ))
                        continue
                    }
                    let delta = max(0, totalTokens - prev)
                    prevFallbackTotal = totalTokens
                    breakdown = proportionalDelta(inputs: ProportionalDeltaInputs(
                        totalDelta: delta,
                        nonCachedInput: nonCachedInput,
                        output: netOutput,
                        cacheRead: cachedTokens,
                        reasoning: reasoningTokens,
                        total: totalTokens
                    ))
                }

                push(&events, context: PushContext(
                    sessionId: sessionId,
                    model: effectiveModel,
                    timestamp: timestamp,
                    msgId: msgId,
                    breakdown: breakdown
                ))
            }
        }
        return events
    }

    // MARK: - Push / delta helpers

    private struct PushContext {
        let sessionId: String
        let model: String
        let timestamp: Date
        let msgId: String
        let breakdown: TokenBreakdown
    }

    private struct ProportionalDeltaInputs {
        let totalDelta: Int
        let nonCachedInput: Int
        let output: Int
        let cacheRead: Int
        let reasoning: Int
        let total: Int
    }

    private func push(
        _ events: inout [TokenEvent],
        context: PushContext
    ) {
        let provider = TokenNormalizer.matchProvider(model: context.model, providerID: "openai")
        events.append(TokenEvent(
            provider: provider, model: context.model, source: .codexCli,
            sessionId: context.sessionId, timestamp: context.timestamp,
            tokens: context.breakdown,
            sourceId: "codex:\(context.sessionId):main:\(context.msgId)"
        ))
    }

    /// Per-request (Anthropic semantics) conversion of `last_token_usage`.
    /// All four token fields are read raw; no cumulative-to-delta math.
    /// `freshInput = input - cache_read - cache_write` mirrors OpenCode's
    /// `getUsage` formula so the two extractors produce comparable numbers.
    private func perRequestBreakdown(
        lastUsage: [String: Any],
        providerID _: String
    ) -> TokenBreakdown {
        let inputTokens = intValue(lastUsage["input_tokens"])
        let outputTokens = intValue(lastUsage["output_tokens"])
        let cachedTokens = intValue(lastUsage["cached_input_tokens"])
        let reasoningTokens = intValue(lastUsage["reasoning_output_tokens"])

        // AI SDK v6 normalizes `input_tokens` to include the cached portion
        // across all providers. Subtract cache to recover fresh non-cached
        // input, matching OpenCode's `data.tokens.input` semantics.
        let cacheRead = max(0, cachedTokens)
        let freshInput = max(0, inputTokens - cachedTokens)
        return TokenBreakdown(
            input: freshInput,
            output: max(0, outputTokens - reasoningTokens),
            cacheRead: cacheRead,
            cacheWrite: 0,
            reasoning: max(0, reasoningTokens)
        )
    }

    private func isCompleteLastUsage(_ lastUsage: [String: Any]?) -> Bool {
        guard let lastUsage = lastUsage else { return false }
        let required = [
            "input_tokens",
            "output_tokens",
            "cached_input_tokens",
            "reasoning_output_tokens",
            "total_tokens"
        ]
        return required.allSatisfy { lastUsage[$0] != nil }
    }

    private func proportionalDelta(inputs: ProportionalDeltaInputs) -> TokenBreakdown {
        guard inputs.totalDelta > 0, inputs.total > 0 else {
            return TokenBreakdown(input: 0, output: 0, cacheRead: 0, cacheWrite: 0, reasoning: 0)
        }

        let inputDelta = Int(Double(inputs.totalDelta) * Double(inputs.nonCachedInput) / Double(inputs.total))
        let outputDelta = Int(Double(inputs.totalDelta) * Double(inputs.output) / Double(inputs.total))
        let cacheReadDelta = Int(Double(inputs.totalDelta) * Double(inputs.cacheRead) / Double(inputs.total))
        let reasoningDelta = Int(Double(inputs.totalDelta) * Double(inputs.reasoning) / Double(inputs.total))

        let remainder = inputs.totalDelta - (inputDelta + outputDelta + cacheReadDelta + reasoningDelta)

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
            if let d = CodeISO8601DateParser.parse(s) { return d }
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
