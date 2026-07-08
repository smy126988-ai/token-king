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

                guard let totalUsage = totalUsage else { continue }

                let totalTokens = intValue(totalUsage["total_tokens"])

                let effectiveModel = model.isEmpty
                    ? ((lastUsage?["model"] as? String) ?? "gpt-4o")
                    : model

                let timestamp = parseTimestamp(json["timestamp"]) ?? Date(timeIntervalSince1970: 0)
                let msgId = (json["id"] as? String) ?? "\(lineIndex)"

                let deltaTokens = makeDeltaBreakdown(
                    totalUsage: totalUsage,
                    lastUsage: lastUsage,
                    prevCumulativeTotal: prevCumulativeTotal
                )
                prevCumulativeTotal = totalTokens

                let provider = TokenNormalizer.matchProvider(model: effectiveModel, providerID: "openai")
                events.append(TokenEvent(
                    provider: provider, model: effectiveModel, source: .codexCli,
                    sessionId: sessionId, timestamp: timestamp,
                    tokens: deltaTokens,
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
        if let s = any as? String, let ts = Double(s) { return Date(timeIntervalSince1970: ts) }
        return nil
    }

    private func makeDeltaBreakdown(
        totalUsage: [String: Any],
        lastUsage: [String: Any]?,
        prevCumulativeTotal: Int?
    ) -> TokenBreakdown {
        let inputTokens = intValue(totalUsage["input_tokens"])
        let outputTokens = intValue(totalUsage["output_tokens"])
        let cachedTokens = intValue(totalUsage["cached_input_tokens"])
        let reasoningTokens = intValue(totalUsage["reasoning_output_tokens"])
        let totalTokens = intValue(totalUsage["total_tokens"])

        let nonCachedInput = max(0, inputTokens - cachedTokens)

        // Prefer last_token_usage (per-turn delta) when fully present.
        if isCompleteLastUsage(lastUsage) {
            let li = intValue(lastUsage?["input_tokens"])
            let lo = intValue(lastUsage?["output_tokens"])
            let lc = intValue(lastUsage?["cached_input_tokens"])
            let lr = intValue(lastUsage?["reasoning_output_tokens"])
            return TokenBreakdown(
                input: max(0, li - lc),
                output: lo,
                cacheRead: lc,
                cacheWrite: 0,
                reasoning: lr
            )
        }

        guard let prev = prevCumulativeTotal else {
            // First token_count in this rollout: treat cumulative total as the
            // first turn's usage because no delta is available.
            return TokenBreakdown(
                input: nonCachedInput,
                output: outputTokens,
                cacheRead: cachedTokens,
                cacheWrite: 0,
                reasoning: reasoningTokens
            )
        }

        let delta = max(0, totalTokens - prev)
        return proportionalDelta(
            totalDelta: delta,
            nonCachedInput: nonCachedInput,
            output: outputTokens,
            cacheRead: cachedTokens,
            reasoning: reasoningTokens,
            total: totalTokens
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
}