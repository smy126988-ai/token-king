import Foundation
import CryptoKit

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
        // Kimi Code wire.jsonl `inputCacheRead` / `inputCacheCreation` are
        // session-cumulative counters. Track per-session to convert to
        // per-event deltas and avoid double-counting.
        var cacheStateBySession: [String: CacheState] = [:]
        for case let url as URL in enumerator where url.lastPathComponent == "wire.jsonl" {
            events.append(contentsOf: parseFile(at: url, cacheState: &cacheStateBySession))
        }
        return events
    }

    private func parseFile(at url: URL, cacheState: inout [String: CacheState]) -> [TokenEvent] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        let sessionId = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        let fallbackModel = lookupKimiModel()
        var events: [TokenEvent] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let rawLine = String(line)
            guard let lineData = rawLine.data(using: .utf8),
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
            let cumulativeCacheRead = intValue(usage["inputCacheRead"]) + intValue(usage["input_cache_read"])
            let cumulativeCacheWrite = intValue(usage["inputCacheCreation"]) + intValue(usage["input_cache_creation"])

            // Convert session-cumulative cache counters to per-event deltas.
            // `max(0, …)` absorbs cache-reset / context-compact drops without
            // emitting negative cache values.
            let prev = cacheState[sessionId] ?? CacheState()
            let cacheRead = max(0, cumulativeCacheRead - prev.cumulativeCacheRead)
            let cacheWrite = max(0, cumulativeCacheWrite - prev.cumulativeCacheWrite)
            cacheState[sessionId] = CacheState(
                cumulativeCacheRead: cumulativeCacheRead,
                cumulativeCacheWrite: cumulativeCacheWrite
            )

            let tokens = TokenBreakdown(
                input: input, output: output,
                cacheRead: cacheRead, cacheWrite: cacheWrite
            )
            let provider = TokenNormalizer.matchProvider(model: model, providerID: "moonshot")
            let sourceId = makeSourceId(sessionId: sessionId, file: url, json: json, rawLine: rawLine)
            events.append(TokenEvent(
                provider: provider, model: model, source: .kimiCode,
                sessionId: sessionId, timestamp: timestamp,
                tokens: tokens,
                sourceId: sourceId
            ))
        }
        return events
    }

    private func makeSourceId(sessionId: String, file: URL, json: [String: Any], rawLine: String) -> String {
        if let stableId = stableId(from: json) {
            return "kimiCode:\(sessionId):main:\(stableId)"
        }
        let hash = sha256Prefix(rawLine)
        return "file:\(sessionId)/\(file.lastPathComponent):hash:\(hash)"
    }

    private func stableId(from json: [String: Any]) -> String? {
        if let requestId = json["request_id"] as? String, !requestId.isEmpty { return requestId }
        if let message = json["message"] as? [String: Any],
           let messageId = message["id"] as? String, !messageId.isEmpty { return messageId }
        if let id = json["id"] as? String, !id.isEmpty { return id }
        return nil
    }

    private func sha256Prefix(_ string: String, length: Int = 16) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return String(Data(digest).map { String(format: "%02x", $0) }.joined().prefix(length))
    }

    private static func defaultConfigPath() -> String {
        "\(NSHomeDirectory())/.kimi/config.toml"
    }

    func lookupKimiModel(
        env: [String: String] = ProcessInfo.processInfo.environment,
        configPath: String? = Self.defaultConfigPath()
    ) -> String {
        if let env = env["KIMI_MODEL_NAME"], !env.isEmpty {
            return env
        }
        let path = configPath ?? Self.defaultConfigPath()
        if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
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

/// Per-session accumulator for Kimi Code's cumulative cache counters.
private struct CacheState {
    var cumulativeCacheRead: Int = 0
    var cumulativeCacheWrite: Int = 0
}