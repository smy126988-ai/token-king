import Foundation
import SQLite3
import os.log

private let openCodeExtractorLogger = Logger(subsystem: "com.opencodeproviders", category: "OpenCodeExtractor")

/// OpenCode SQLite reader (per-message.data JSON blob).
/// Path: ~/.local/share/opencode/opencode.db (overridable via $OPENCODE_DATA_DIR).
///
/// F2b: handles both JSON schemas emitted by OpenCode:
///   - Old schema: data.model.providerID + data.model.modelID nested object
///   - New schema: data.modelID (top-level, camelCase) + providerID looked up
///     via parentID -> user message's data.model.providerID
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

        var events: [TokenEvent] = []
        // `tokens.cache.read` / `tokens.cache.write` in the OpenCode SQLite
        // schema are session-cumulative counters (total cache hits/writes
        // since session start). To avoid double-counting, every event must
        // store the per-event DELTA. We track the previously-seen cumulative
        // value per session_id and convert on the fly. The map must be
        // shared across old-schema and new-schema calls so a session that
        // spans both schemas tracks consistently.
        var cacheStateBySession: [String: CacheState] = [:]
        events.append(contentsOf: extractOldSchema(from: db, cacheState: &cacheStateBySession))
        events.append(contentsOf: extractNewSchema(from: db, cacheState: &cacheStateBySession))
        return events
    }

    /// Old schema: `data.model.providerID` and `data.model.modelID` live on the
    /// assistant message itself.
    private func extractOldSchema(from db: OpaquePointer, cacheState: inout [String: CacheState]) -> [TokenEvent] {
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
              AND json_extract(data, '$.model.providerID') IS NOT NULL
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            openCodeExtractorLogger.warning("F2b: failed to prepare old-schema statement")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        return Self.iterateRows(stmt: stmt, cacheState: &cacheState)
    }

    /// New schema: `data.modelID` is camelCase top-level, `data.model.providerID`
    /// is absent on the assistant message. We join to the parent (user-role) message
    /// via `data.parentID` to recover the provider ID.
    private func extractNewSchema(from db: OpaquePointer, cacheState: inout [String: CacheState]) -> [TokenEvent] {
        let sql = """
            SELECT a.id,
                   json_extract(a.data, '$.tokens.input')      AS input,
                   json_extract(a.data, '$.tokens.output')     AS output,
                   json_extract(a.data, '$.tokens.reasoning')  AS reasoning,
                   json_extract(a.data, '$.tokens.cache.read') AS cache_read,
                   json_extract(a.data, '$.tokens.cache.write') AS cache_write,
                   json_extract(u.data, '$.model.providerID')  AS provider_id,
                   json_extract(a.data, '$.modelID')           AS model_id,
                   json_extract(a.data, '$.sessionID')         AS session_id,
                   json_extract(a.data, '$.time.created')      AS ts_ms
            FROM message a
            LEFT JOIN message u ON u.id = json_extract(a.data, '$.parentID')
            WHERE json_valid(a.data)
              AND json_extract(a.data, '$.role') = 'assistant'
              AND json_extract(a.data, '$.tokens') IS NOT NULL
              AND json_extract(a.data, '$.model.providerID') IS NULL
              AND json_extract(a.data, '$.modelID') IS NOT NULL
              AND u.id IS NOT NULL
              AND json_extract(u.data, '$.model.providerID') IS NOT NULL
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else {
            openCodeExtractorLogger.warning("F2b: failed to prepare new-schema statement")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        return Self.iterateRows(stmt: stmt, cacheState: &cacheState)
    }

    /// Iterate a prepared statement and build TokenEvent objects.
    private static func iterateRows(stmt: OpaquePointer, cacheState: inout [String: CacheState]) -> [TokenEvent] {
        var events: [TokenEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
            let input = Int(sqlite3_column_int64(stmt, 1))
            let output = Int(sqlite3_column_int64(stmt, 2))
            let reasoning = Int(sqlite3_column_int64(stmt, 3))
            let cumulativeCacheRead = Int(sqlite3_column_int64(stmt, 4))
            let cumulativeCacheWrite = Int(sqlite3_column_int64(stmt, 5))
            let providerID = sqlite3_column_text(stmt, 6).flatMap { String(cString: $0) } ?? ""
            let modelID = sqlite3_column_text(stmt, 7).flatMap { String(cString: $0) } ?? ""
            let sessionID = sqlite3_column_text(stmt, 8).flatMap { String(cString: $0) } ?? id
            let tsMs = sqlite3_column_int64(stmt, 9)

            // Convert session-cumulative cache counters to per-event deltas.
            // `max(0, …)` absorbs `/compact`-style drops without producing
            // negative cache values. The state is keyed on session_id so two
            // concurrent sessions track independently.
            let prev = cacheState[sessionID] ?? CacheState()
            let cacheRead = max(0, cumulativeCacheRead - prev.cumulativeCacheRead)
            let cacheWrite = max(0, cumulativeCacheWrite - prev.cumulativeCacheWrite)
            cacheState[sessionID] = CacheState(
                cumulativeCacheRead: cumulativeCacheRead,
                cumulativeCacheWrite: cumulativeCacheWrite
            )

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

/// Per-session accumulator for OpenCode's cumulative cache counters.
private struct CacheState {
    var cumulativeCacheRead: Int = 0
    var cumulativeCacheWrite: Int = 0
}
