import Foundation
import SQLite3

/// OpenCode SQLite reader (per-message.data JSON blob).
/// Path: ~/.local/share/opencode/opencode.db (overridable via $OPENCODE_DATA_DIR).
struct OpenCodeExtractor: TokenExtractorProtocol {
    let rootPath: String

    init(rootPath: String? = nil) {
        self.rootPath = rootPath
            ?? ProcessInfo.processInfo.environment["OPENCODE_DATA_DIR"]
            ?? "\(NSHomeDirectory())/.local/share/opencode"
    }

    func extractAll() async throws -> [TokenEvent] {
        let dbPath = "\(rootPath)/opencode.db"
        guard FileManager.default.fileExists(atPath: dbPath) else { return [] }

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK, let db = db else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT id,
                   json_extract(data, '$.tokens.input')      AS input,
                   json_extract(data, '$.tokens.output')     AS output,
                   json_extract(data, '$.tokens.reasoning')  AS reasoning,
                   json_extract(data, '$.tokens.cache.read') AS cache_read,
                   json_extract(data, '$.tokens.cache.write') AS cache_write,
                   json_extract(data, '$.model.providerID')  AS provider_id,
                   json_extract(data, '$.model.modelID')     AS model_id,
                   json_extract(data, '$.sessionID')         AS session_id,
                   json_extract(data, '$.time.created')      AS ts_ms
            FROM message
            WHERE json_valid(data)
              AND json_extract(data, '$.role') = 'assistant'
              AND json_extract(data, '$.tokens') IS NOT NULL
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var events: [TokenEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
            let input = Int(sqlite3_column_int64(stmt, 1))
            let output = Int(sqlite3_column_int64(stmt, 2))
            let reasoning = Int(sqlite3_column_int64(stmt, 3))
            let cacheRead = Int(sqlite3_column_int64(stmt, 4))
            let cacheWrite = Int(sqlite3_column_int64(stmt, 5))
            let providerID = sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) } ?? ""
            let modelID = sqlite3_column_text(stmt, 7).flatMap { String(cString: $0) } ?? ""
            let sessionID = sqlite3_column_text(stmt, 8).flatMap { String(cString: $0) } ?? id
            let tsMs = sqlite3_column_int64(stmt, 9)

            let tokens = TokenBreakdown(
                input: input, output: output,
                cacheRead: cacheRead, cacheWrite: cacheWrite,
                reasoning: reasoning
            )
            let provider = TokenNormalizer.matchProvider(model: modelID, providerID: providerID)
            let event = TokenEvent(
                provider: provider, model: modelID, source: .opencode,
                sessionId: sessionID,
                timestamp: Date(timeIntervalSince1970: TimeInterval(tsMs) / 1000),
                tokens: tokens,
                sourceId: "opencode:\(sessionID):main:\(id)"
            )
            events.append(event)
        }
        return events
    }
}