import Foundation
import SQLite3

/// OpenCode SQLite reader.
/// Path: ~/.local/share/opencode/opencode.db (overridable via $OPENCODE_DATA_DIR).
///
/// Schema (current OpenCode >= 1.0):
///   - `message.data` is a JSON blob with FLATTENED top-level fields,
///     NOT nested under `$.model.*`:
///       { "role": "assistant", "modelID": "...", "providerID": "...",
///         "tokens": { "input", "output", "reasoning",
///                     "cache": { "read", "write" } },
///         "time": { "created": <unix-ms> } }
///   - The actual session id lives in the `session_id` SQL column, not in JSON.
///
/// Earlier versions nested provider/model under `$.model.providerID` /
/// `$.model.modelID`. That old path is kept as a fallback for backward
/// compatibility with archived databases.
///
/// IMPORTANT — cache field semantics:
///   `cache.read` and `cache.write` are CUMULATIVE per-session values in
///   real OpenCode databases. They represent the current cache size / write
///   footprint at the end of each assistant turn, not the per-turn cache
///   hit count. Summing raw values across events inflates the totals by
///   ~10-30× (the reviewer's audit of user data showed 32× inflation for
///   minimaxCN, 8.7-70× per session depending on length).
///
/// To produce meaningful aggregate totals, this extractor computes the
/// per-session DELTA of `cache.read` and `cache.write`: for each event,
/// the delta is `max(0, current - previous_session_value)`. The first
/// event in a session always uses the raw value (the cache was freshly
/// created this turn, so the entire value is the "new" contribution).
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

        // Schema notes:
        //   - New OpenCode emits flat `$.providerID` / `$.modelID`.
        //   - Older builds emitted nested `$.model.providerID` / `$.model.modelID`.
        //   - `session_id` is a SQL column (not in JSON) and is authoritative.
        //   - `time_created` is the canonical timestamp; `$.time.created` is the
        //     JSON-side mirror. Prefer the column so we keep an integer ms.
        //
        // We pull `cache.read` and `cache.write` raw (cumulative session state)
        // and compute deltas after the rows come back, ordered by time, grouped
        // by session. Doing the delta on the Swift side keeps the SQL simple
        // and the per-session state co-located with the rows it applies to.
        let sql = """
            SELECT id,
                   session_id,
                   time_created,
                   COALESCE(NULLIF(json_extract(data, '$.providerID'), ''),
                            json_extract(data, '$.model.providerID')) AS provider_id,
                   COALESCE(NULLIF(json_extract(data, '$.modelID'), ''),
                            json_extract(data, '$.model.modelID')) AS model_id,
                   json_extract(data, '$.tokens.input')      AS input,
                   json_extract(data, '$.tokens.output')     AS output,
                   json_extract(data, '$.tokens.reasoning')  AS reasoning,
                   json_extract(data, '$.tokens.cache.read') AS cache_read,
                   json_extract(data, '$.tokens.cache.write') AS cache_write
            FROM message
            WHERE json_valid(data)
              AND json_extract(data, '$.role') = 'assistant'
              AND json_extract(data, '$.tokens') IS NOT NULL
            ORDER BY session_id, time_created, id
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        struct Row {
            let id: String
            let sessionId: String
            let tsMs: Int64
            let providerId: String
            let modelId: String
            let input: Int
            let output: Int
            let reasoning: Int
            let cacheRead: Int
            let cacheWrite: Int
        }

        var rowsBySession: [String: [Row]] = [:]
        rowsBySession.reserveCapacity(512)

        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
            let sessionCol = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
            let tsMs = sqlite3_column_int64(stmt, 2)
            let providerID = sqlite3_column_text(stmt, 3).flatMap { String(cString: $0) } ?? ""
            let modelID = sqlite3_column_text(stmt, 4).flatMap { String(cString: $0) } ?? ""
            let input = Int(sqlite3_column_int64(stmt, 5))
            let output = Int(sqlite3_column_int64(stmt, 6))
            let reasoning = Int(sqlite3_column_int64(stmt, 7))
            let cacheRead = Int(sqlite3_column_int64(stmt, 8))
            let cacheWrite = Int(sqlite3_column_int64(stmt, 9))

            let sessionId = sessionCol.isEmpty ? id : sessionCol
            let row = Row(
                id: id,
                sessionId: sessionId,
                tsMs: tsMs,
                providerId: providerID,
                modelId: modelID,
                input: input,
                output: output,
                reasoning: reasoning,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite
            )
            rowsBySession[sessionId, default: []].append(row)
        }

        // Second pass: per session, walk rows in time order and convert the
        // cumulative cache.read / cache.write into per-event deltas. Other
        // fields (input / output / reasoning) stay per-event as they are.
        var events: [TokenEvent] = []
        for (_, sessionRows) in rowsBySession {
            var prevCacheRead: Int? = nil
            var prevCacheWrite: Int? = nil
            for row in sessionRows {
                let deltaRead: Int
                let deltaWrite: Int
                if let prev = prevCacheRead {
                    deltaRead = max(0, row.cacheRead - prev)
                } else {
                    // First event in session: treat the raw cumulative value
                    // as the delta (the entire cache was built this turn
                    // if any). If the source emits 0 for a fresh session
                    // that simply had no cache activity yet, this stays 0.
                    deltaRead = max(0, row.cacheRead)
                }
                if let prev = prevCacheWrite {
                    deltaWrite = max(0, row.cacheWrite - prev)
                } else {
                    deltaWrite = max(0, row.cacheWrite)
                }
                prevCacheRead = row.cacheRead
                prevCacheWrite = row.cacheWrite

                let tokens = TokenBreakdown(
                    input: row.input, output: row.output,
                    cacheRead: deltaRead, cacheWrite: deltaWrite,
                    reasoning: row.reasoning
                )
                let provider = TokenNormalizer.matchProvider(model: row.modelId, providerID: row.providerId)
                let event = TokenEvent(
                    provider: provider, model: row.modelId, source: .opencode,
                    sessionId: row.sessionId,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(row.tsMs) / 1000),
                    tokens: tokens,
                    sourceId: "opencode:\(row.sessionId):main:\(row.id)"
                )
                events.append(event)
            }
        }

        return events
    }
}
