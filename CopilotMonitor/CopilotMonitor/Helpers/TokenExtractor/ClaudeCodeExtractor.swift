import Foundation

/// Claude Code JSONL scanner.
/// Path: ~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl
struct ClaudeCodeExtractor: TokenExtractorProtocol {
    let rootPath: String

    init(rootPath: String? = nil) {
        self.rootPath = rootPath
            ?? ProcessInfo.processInfo.environment["CLAUDE_CODE_DATA_DIR"]
            ?? "\(NSHomeDirectory())/.claude/projects"
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
        var events: [TokenEvent] = []
        var lineIndex = 0

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            defer { lineIndex += 1 }
            guard let lineData = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String, type == "assistant",
                  let message = json["message"] as? [String: Any] else {
                continue
            }

            let model = (message["model"] as? String) ?? ""
            guard let usage = message["usage"] as? [String: Any] else { continue }

            let inputTokens = intValue(usage["input_tokens"])
            let outputTokens = intValue(usage["output_tokens"])
            let cacheRead = intValue(usage["cache_read_input_tokens"])
            let cacheWrite = intValue(usage["cache_creation_input_tokens"])

            let tokens = TokenBreakdown(
                input: inputTokens, output: outputTokens,
                cacheRead: cacheRead, cacheWrite: cacheWrite
            )
            // Pass providerID="" so TokenNormalizer routes by model name.
            // Hard-coding "anthropic" caused subagent sessions that call
            // through Xiaomi (mimo-v2.5-pro) or other providers to be
            // mis-classified as .claude, hiding the real spend. Model-based
            // routing correctly sends `mimo-*` to .xiaomi / .xiaomiTokenPlanCN
            // and keeps `claude-*` on .claude.
            let provider = TokenNormalizer.matchProvider(model: model, providerID: "")
            let timestamp = parseTimestamp(json["timestamp"]) ?? Date(timeIntervalSince1970: 0)

            // Source id includes the line index because some Claude Code
            // subagent chains reuse the same `message.id` across multiple
            // assistant turns (up to ~12 in observed data). Without the
            // line index the F2b `source_id UNIQUE` constraint would silently
            // drop duplicates via `INSERT OR IGNORE` — losing the events that
            // carry the actual usage deltas.
            //
            // Stable across runs so dedup at insert time still works.
            let sourceId = "claudeCode:\(sessionId):main:line:\(lineIndex)"

            events.append(TokenEvent(
                provider: provider, model: model, source: .claudeCode,
                sessionId: sessionId, timestamp: timestamp,
                tokens: tokens,
                sourceId: sourceId
            ))
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
            if let d = CodeISO8601DateParser.parse(s) { return d }
            if let ts = Double(s) { return Date(timeIntervalSince1970: ts) }
        }
        return nil
    }
}
