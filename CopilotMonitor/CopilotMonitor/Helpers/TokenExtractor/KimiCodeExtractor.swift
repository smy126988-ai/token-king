import Foundation

/// Kimi Code (newer Rust port) JSONL scanner.
/// Path: ~/.kimi-code/sessions/<workdir-hash>/<sessionId>/agents/main/wire.jsonl
/// Schema (camelCase): {"time": ms, "model": "...", "usage": {inputOther, output, inputCacheRead, inputCacheCreation}}
struct KimiCodeExtractor: TokenExtractorProtocol {
    let rootPath: String

    init(rootPath: String? = nil) {
        self.rootPath = rootPath
            ?? ProcessInfo.processInfo.environment["KIMI_CODE_DATA_DIR"]
            ?? "\(NSHomeDirectory())/.kimi-code/sessions"
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
        for case let url as URL in enumerator where url.lastPathComponent == "wire.jsonl" {
            events.append(contentsOf: parseFile(at: url))
        }
        return events
    }

    private func parseFile(at url: URL) -> [TokenEvent] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        let sessionId = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        let fallbackModel = lookupKimiModel()
        var events: [TokenEvent] = []
        var lineIndex = 0

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            defer { lineIndex += 1 }
            guard let lineData = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let model = (json["model"] as? String) ?? fallbackModel
            let timestampMs = intValue(json["time"])
            let timestamp = timestampMs > 0
                ? Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
                : Date(timeIntervalSince1970: 0)

            let usage = (json["usage"] as? [String: Any])
                ?? (json["event"] as? [String: Any]).flatMap { $0["usage"] as? [String: Any] }
            guard let usage = usage else { continue }

            let input = intValue(usage["inputOther"]) + intValue(usage["input_other"])
            let output = intValue(usage["output"])
            let cacheRead = intValue(usage["inputCacheRead"]) + intValue(usage["input_cache_read"])
            let cacheWrite = intValue(usage["inputCacheCreation"]) + intValue(usage["input_cache_creation"])

            let tokens = TokenBreakdown(
                input: input, output: output,
                cacheRead: cacheRead, cacheWrite: cacheWrite
            )
            let provider = TokenNormalizer.matchProvider(model: model, providerID: "moonshot")
            events.append(TokenEvent(
                provider: provider, model: model, source: .kimiCode,
                sessionId: sessionId, timestamp: timestamp,
                tokens: tokens,
                sourceId: "kimiCode:\(sessionId):main:\(lineIndex)"
            ))
        }
        return events
    }

    private func lookupKimiModel() -> String {
        if let env = ProcessInfo.processInfo.environment["KIMI_MODEL_NAME"], !env.isEmpty {
            return env
        }
        let configPath = "\(NSHomeDirectory())/.kimi/config.toml"
        if let contents = try? String(contentsOfFile: configPath, encoding: .utf8) {
            for line in contents.split(separator: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("default_model") {
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        return parts[1]
                            .trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    }
                }
            }
        }
        return "kimi-auto"
    }

    private func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let i = Int(s) { return i }
        return 0
    }
}