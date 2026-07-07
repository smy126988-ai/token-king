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

    func extractAll() throws -> [TokenEvent] {
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

                let inputTokens = intValue(totalUsage["input_tokens"])
                let outputTokens = intValue(totalUsage["output_tokens"])
                let cachedTokens = intValue(totalUsage["cached_input_tokens"])
                let reasoningTokens = intValue(totalUsage["reasoning_output_tokens"])
                let totalTokens = intValue(totalUsage["total_tokens"])

                let effectiveModel = model.isEmpty
                    ? ((lastUsage?["model"] as? String) ?? "gpt-4o")
                    : model

                let nonCachedInput = max(0, inputTokens - cachedTokens)
                let timestamp = parseTimestamp(json["timestamp"]) ?? Date(timeIntervalSince1970: 0)
                let msgId = (json["id"] as? String) ?? "\(lineIndex)"

                let deltaTokens: TokenBreakdown
                if let prev = prevCumulativeTotal {
                    let delta = max(0, totalTokens - prev)
                    deltaTokens = TokenBreakdown(
                        input: nonCachedInput, output: outputTokens,
                        cacheRead: cachedTokens, cacheWrite: 0,
                        reasoning: reasoningTokens
                    )
                    _ = delta
                } else {
                    deltaTokens = TokenBreakdown(
                        input: nonCachedInput, output: outputTokens,
                        cacheRead: cachedTokens, cacheWrite: 0,
                        reasoning: reasoningTokens
                    )
                }
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
}