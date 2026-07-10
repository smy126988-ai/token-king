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
        let fallbackTimestamp = fileModificationDate(at: url)
        var events: [TokenEvent] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let rawLine = String(line)
            guard let lineData = rawLine.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let role = json["role"] as? String, role == "_usage" else {
                continue
            }

            let tokenCount = intValue(json["token_count"])
            if tokenCount <= 0 { continue }
            let timestamp = parseTimestamp(json["timestamp"]) ?? fallbackTimestamp
            let model = (json["model"] as? String) ?? ""

            // Legacy schema only gives a combined token_count; treat it as output.
            let tokens = TokenBreakdown(output: tokenCount)
            let provider = TokenNormalizer.matchProvider(model: model, providerID: "moonshot")
            let sourceId = makeSourceId(sessionId: sessionId, file: url, json: json, rawLine: rawLine)

            events.append(TokenEvent(
                provider: provider, model: model.isEmpty ? "kimi-for-coding" : model,
                source: .kimiCli,
                sessionId: sessionId, timestamp: timestamp,
                tokens: tokens,
                sourceId: sourceId
            ))
        }
        return events
    }

    private func makeSourceId(sessionId: String, file: URL, json: [String: Any], rawLine: String) -> String {
        if let stableId = stableId(from: json) {
            return "kimi:\(sessionId):main:\(stableId)"
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

    private func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let i = Int(s) { return i }
        return 0
    }

    /// The legacy kimi-cli `context.jsonl` rows DO NOT carry a per-event
    /// timestamp — every `_usage` line is just `{"role": "_usage",
    /// "token_count": N}`. When `parseTimestamp` returns nil (field missing
    /// OR field present but unparseable) we fall back to the file's
    /// modification date. The file is append-only, so mtime is a
    /// reasonable upper-bound estimate of when the event was recorded.
    private func fileModificationDate(at url: URL) -> Date {
        let resources = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        if let date = resources?.contentModificationDate {
            return date
        }
        return Date(timeIntervalSince1970: 0)
    }

    private func parseTimestamp(_ any: Any?) -> Date? {
        if let ts = any as? Double { return Date(timeIntervalSince1970: ts) }
        if let s = any as? String {
            if let ts = Double(s) { return Date(timeIntervalSince1970: ts) }
            // Kimi CLI (legacy `context.jsonl`) stamps usage rows with ISO 8601
            // strings like "2026-06-24T09:44:55.227Z" or "2026-06-24T09:44:55Z".
            // Try with fractional seconds first (kimi-cli default), then fall
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
}