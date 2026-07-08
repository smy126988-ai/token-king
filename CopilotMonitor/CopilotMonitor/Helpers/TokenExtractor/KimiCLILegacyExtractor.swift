import Foundation
import CryptoKit

/// Kimi CLI legacy JSONL scanner (老 kimi-cli `context.jsonl`).
/// Path: ~/.kimi/sessions/<workdir-md5>/<sessionId>/context.jsonl
/// Lines of interest: {"role": "_usage", "token_count": N}
///
/// Limitation: the legacy format only exposes a single `token_count` value.
/// It cannot be split into input/output/cache/reasoning, so the whole count
/// is recorded as `output`; input, cacheRead, cacheWrite and reasoning are 0.
struct KimiCLILegacyExtractor: TokenExtractorProtocol {
    let rootPath: String

    init(rootPath: String? = nil) {
        self.rootPath = rootPath
            ?? ProcessInfo.processInfo.environment["KIMI_DATA_DIR"]
            ?? "\(NSHomeDirectory())/.kimi/sessions"
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
        for case let url as URL in enumerator where url.lastPathComponent == "context.jsonl" {
            events.append(contentsOf: parseFile(at: url))
        }
        return events
    }

    private func parseFile(at url: URL) -> [TokenEvent] {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return []
        }
        let sessionId = url.deletingLastPathComponent().lastPathComponent
        var events: [TokenEvent] = []
        var lineIndex = 0

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            defer { lineIndex += 1 }
            guard let lineData = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let role = json["role"] as? String, role == "_usage" else {
                continue
            }

            let tokenCount = intValue(json["token_count"])
            if tokenCount <= 0 { continue }
            let timestamp = parseTimestamp(json["timestamp"]) ?? Date(timeIntervalSince1970: 0)
            let model = (json["model"] as? String) ?? ""

            // Legacy schema only gives a combined token_count; treat it as output.
            let tokens = TokenBreakdown(output: tokenCount)
            let provider = TokenNormalizer.matchProvider(model: model, providerID: "moonshot")

            events.append(TokenEvent(
                provider: provider, model: model.isEmpty ? "kimi-for-coding" : model,
                source: .kimiCli,
                sessionId: sessionId, timestamp: timestamp,
                tokens: tokens,
                sourceId: "kimi:\(sessionId):main:\(lineIndex)"
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