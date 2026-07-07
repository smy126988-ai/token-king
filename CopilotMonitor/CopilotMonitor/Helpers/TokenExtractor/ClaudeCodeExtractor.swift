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
            let messageId = (message["id"] as? String) ?? "\(lineIndex)"
            guard let usage = message["usage"] as? [String: Any] else { continue }

            let inputTokens = intValue(usage["input_tokens"])
            let outputTokens = intValue(usage["output_tokens"])
            let cacheRead = intValue(usage["cache_read_input_tokens"])
            let cacheWrite = intValue(usage["cache_creation_input_tokens"])

            let tokens = TokenBreakdown(
                input: inputTokens, output: outputTokens,
                cacheRead: cacheRead, cacheWrite: cacheWrite
            )
            let provider = TokenNormalizer.matchProvider(model: model, providerID: "anthropic")
            let timestamp = parseTimestamp(json["timestamp"]) ?? Date(timeIntervalSince1970: 0)

            events.append(TokenEvent(
                provider: provider, model: model, source: .claudeCode,
                sessionId: sessionId, timestamp: timestamp,
                tokens: tokens,
                sourceId: "claudeCode:\(sessionId):main:\(messageId)"
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
        if let s = any as? String, let ts = Double(s) { return Date(timeIntervalSince1970: ts) }
        return nil
    }
}