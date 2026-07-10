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
                    prevCumulativeTotal: prevCumulativeTotal
                )
                if let totalUsage {
                    prevCumulativeTotal = intValue(totalUsage["total_tokens"])
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
    /// Primary path: read `last_token_usage` directly. Codex's `last_token_usage`
    /// IS the per-event delta (it reports the most recent API call's usage),
    /// while `total_token_usage` is the cumulative context size — using it
    /// directly double-counts cache across events. Codex does not expose a
    /// cache_write field, so it is always 0.
    ///
    /// Fallback path: when `last_token_usage` is absent (older rollouts), fall
    /// back to the cumulative delta via `prevCumulativeTotal`. The delta is
    /// assigned to `input`; output / cacheRead / reasoning / cacheWrite stay
    /// at 0 because the per-field split cannot be reconstructed. Negative
    /// deltas (e.g., after `/compact`) are clamped to 0.
    private func makeBreakdown(
        lastUsage: [String: Any]?,
        totalUsage: [String: Any]?,
        prevCumulativeTotal: Int?
    ) -> TokenBreakdown {
        if let lastUsage {
            let input = intValue(lastUsage["input_tokens"])
            let output = intValue(lastUsage["output_tokens"])
            let cacheRead = intValue(lastUsage["cached_input_tokens"])
            let reasoning = intValue(lastUsage["reasoning_output_tokens"])
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