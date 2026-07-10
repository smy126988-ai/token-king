import Foundation

/// Codex rollout JSONL scanner.
/// Path: ~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl
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
        // Tracks the cumulative `total_token_usage.total_tokens` from the
        // previous event in this file. Used ONLY as a safety check to detect
        // `/compact` (cumulative shrink) when the fallback path is taken.
        // Per-field token counts come from `last_token_usage` directly.
        var prevCumulativeTotal: Int? = nil
        // Tracks the cumulative `cached_input_tokens` from the previous event
        // in this file. Codex's `last_token_usage.cached_input_tokens` is the
        // cumulative size of the cache context at the most recent API call
        // (same shape as `total_token_usage.cached_input_tokens`), NOT a
        // per-event delta. Storing it verbatim per event would double-count
        // the actual cache usage (1B+ in real sessions); emit per-event
        // deltas instead. When the previous event has no `last_token_usage`
        // we fall back to its `total_token_usage.cached_input_tokens` as the
        // cumulative reference, so subsequent deltas stay consistent.
        var prevCachedInputTokens: Int? = nil

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

                let effectiveModel = model.isEmpty
                    ? ((lastUsage?["model"] as? String) ?? "gpt-4o")
                    : model

                let timestamp = parseTimestamp(json["timestamp"]) ?? Date(timeIntervalSince1970: 0)
                let msgId = (json["id"] as? String) ?? "\(lineIndex)"

                let tokens = makeBreakdown(
                    lastUsage: lastUsage,
                    totalUsage: totalUsage,
                    prevCumulativeTotal: prevCumulativeTotal,
                    prevCachedInputTokens: prevCachedInputTokens
                )
                if let totalUsage {
                    prevCumulativeTotal = intValue(totalUsage["total_tokens"])
                }
                // Advance the cumulative cache reference for the next event.
                // Prefer `last_token_usage.cached_input_tokens` (per-call
                // cumulative) when available; otherwise use
                // `total_token_usage.cached_input_tokens` (session
                // cumulative). Either way the value is cumulative, so
                // subtracting it on the next event yields a per-event delta.
                if let lastUsage {
                    prevCachedInputTokens = intValue(lastUsage["cached_input_tokens"])
                } else if let totalUsage {
                    prevCachedInputTokens = intValue(totalUsage["cached_input_tokens"])
                }

                let provider = TokenNormalizer.matchProvider(model: effectiveModel, providerID: "openai")
                events.append(TokenEvent(
                    provider: provider, model: effectiveModel, source: .codexCli,
                    sessionId: sessionId, timestamp: timestamp,
                    tokens: tokens,
                    sourceId: "codex:\(sessionId):main:\(msgId)"
                ))
            }
        }
        return events
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
            if let ts = Double(s) { return Date(timeIntervalSince1970: ts) }
            // Codex rollout JSONL lines stamp events with ISO 8601 strings
            // like "2026-05-20T08:33:54.127Z" or "2026-07-05T16:17:22Z".
            // Try with fractional seconds first (Codex default), then fall
            // back to plain ISO 8601.
            let formatterWithFrac = ISO8601DateFormatter()
            formatterWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = formatterWithFrac.date(from: s) { return d }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            if let d = formatter.date(from: s) { return d }
        }
        return nil
    }

    /// Build a per-event TokenBreakdown from a Codex rollout token_count event.
    ///
    /// Primary path: read `last_token_usage` directly. Codex's
    /// `last_token_usage.input_tokens` / `output_tokens` /
    /// `reasoning_output_tokens` are per-event deltas (the most recent API
    /// call's contribution). `last_token_usage.cached_input_tokens` however
    /// is the CUMULATIVE size of the cache context — same shape as
    /// `total_token_usage.cached_input_tokens`. To avoid double-counting the
    /// cache across events in a session we convert it to a per-event delta
    /// via `prevCachedInputTokens`. Negative deltas (after `/compact`) are
    /// clamped to 0. Codex does not expose a `cache_write` field, so it is
    /// always 0.
    ///
    /// Fallback path: when `last_token_usage` is absent (older rollouts), fall
    /// back to the cumulative delta via `prevCumulativeTotal`. The delta is
    /// assigned to `input`; output / cacheRead / reasoning / cacheWrite stay
    /// at 0 because the per-field split cannot be reconstructed. Negative
    /// deltas (e.g., after `/compact`) are clamped to 0.
    private func makeBreakdown(
        lastUsage: [String: Any]?,
        totalUsage: [String: Any]?,
        prevCumulativeTotal: Int?,
        prevCachedInputTokens: Int?
    ) -> TokenBreakdown {
        if let lastUsage {
            let input = intValue(lastUsage["input_tokens"])
            let output = intValue(lastUsage["output_tokens"])
            let reasoning = intValue(lastUsage["reasoning_output_tokens"])
            let currentCacheRead = intValue(lastUsage["cached_input_tokens"])
            // Convert the cumulative cache context size to a per-event delta.
            // `?? 0` covers the first event in the file (no prior reference).
            // `max(0, …)` covers cumulative shrinks from `/compact`.
            let cacheRead = max(0, currentCacheRead - (prevCachedInputTokens ?? 0))
            return TokenBreakdown(
                input: input,
                output: output,
                cacheRead: cacheRead,
                cacheWrite: 0,
                reasoning: reasoning
            )
        }

        guard let totalUsage else {
            return TokenBreakdown.zero
        }
        let totalTokens = intValue(totalUsage["total_tokens"])
        let delta: Int
        if let prev = prevCumulativeTotal {
            delta = max(0, totalTokens - prev)
        } else {
            delta = totalTokens
        }
        return TokenBreakdown(
            input: delta,
            output: 0,
            cacheRead: 0,
            cacheWrite: 0,
            reasoning: 0
        )
    }
}