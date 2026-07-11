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
///   - Earlier versions nested provider/model under `$.model.providerID` /
///     `$.model.modelID`. That old path is kept as a fallback for backward
///     compatibility with archived databases.
///
/// Token field semantics (verified against OpenCode source code in
/// `packages/opencode/src/session/session.ts#getUsage`):
///
///   `data.tokens.input`             = fresh non-cached input this request
///                                    (= inputTokens - cacheReadInputTokens
///                                       - cacheWriteInputTokens, per OpenCode)
///   `data.tokens.cache.read`        = Anthropic `cacheReadInputTokens` for
///                                    THIS API request
///   `data.tokens.cache.write`       = tokens newly added to cache on
///                                    THIS API request
///   `data.tokens.output`            = output tokens billed this request
///   `data.tokens.reasoning`         = reasoning tokens billed this request
///
/// All five values are PER-REQUEST (`per turn`). They are NOT cumulative
/// session state. Sum across all messages in a session gives the total
/// tokens billed for that session, matching MiniMax / Anthropic dashboard
/// numbers.
///
/// The previous version of this extractor applied an unnecessary
/// "per-session cumulative-to-delta" conversion to cache.read / cache.write,
/// which undercounted MiniMax-M3 7月 cache usage from the cap-aligned
/// ~18亿 (Anthropic per-turn semantics) down to ~80M. Reverted: use raw
/// values directly.
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
        // All `data.tokens.*` fields are per-request values emitted by the LLM
        // SDK (Anthropic-style). No cumulative-state conversion needed; just sum
        // raw values across messages.
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
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else { return [] }
        defer { sqlite3_finalize(stmt) }

        var events: [TokenEvent] = []
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

            // `session_id` is authoritative from the SQL column; fall back to the
            // message id only when the column is empty (F2b layer needs *some*
            // non-empty string for per-session aggregation to keep working).
            let sessionId = sessionCol.isEmpty ? id : sessionCol

            // All tokens fields are per-request (Anthropic semantics). Direct
            // values; no cumulative-to-delta conversion.
            let tokens = TokenBreakdown(
                input: input, output: output,
                cacheRead: cacheRead, cacheWrite: cacheWrite,
                reasoning: reasoning
            )
            let provider = TokenNormalizer.matchProvider(model: modelID, providerID: providerID)
            let event = TokenEvent(
                provider: provider, model: modelID, source: .opencode,
                sessionId: sessionId,
                timestamp: Date(timeIntervalSince1970: TimeInterval(tsMs) / 1000),
                tokens: tokens,
                sourceId: "opencode:\(sessionId):main:\(id)"
            )
            events.append(event)
        }
        return events
    }
}
