import Foundation
import SQLite3
import os.log

private let openCodeExtractorLogger = Logger(subsystem: "com.opencodeproviders", category: "OpenCodeExtractor")

/// OpenCode SQLite reader (per-message.data JSON blob).
/// Path: ~/.local/share/opencode/opencode.db (overridable via $OPENCODE_DATA_DIR).
///
/// F2b: unified extraction path covering both JSON schemas emitted by OpenCode:
///   - Old schema: data.model.providerID + data.model.modelID nested object on
///     the assistant message itself.
///   - New schema: top-level data.modelID (camelCase) on the assistant; the
///     providerID lives on the parent user message and is recovered via a
///     LEFT JOIN on data.parentID.
/// One SQL with `COALESCE` prefers the parent user message (the user's chosen
/// model/provider) and falls back to the assistant's own data. This avoids the
/// fragility of two divergent WHERE branches and means every assistant message
/// with valid tokens is classified using the best available signal.
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

        var cacheStateBySession: [String: CacheState] = [:]
        return Self.extractUnified(from: db, cacheState: &cacheStateBySession)
    }

    /// Single SQL covering both JSON schemas. The assistant message `a` carries
    /// the token counters; the optional parent user message `u` (joined via
    /// `a.data.parentID`) carries the user's chosen providerID / modelID in the
    /// new schema. `COALESCE` prefers the parent (which is the explicit user
    /// choice) and falls back to the assistant's own data when the parent is
    /// unreachable or the parent lacks the field (old-schema orphan).
    ///
    /// Schema notes:
    ///   - New schema drops `data.sessionID` on assistant messages; the
    ///     session identity is read from `message.session_id` (the table
    ///     column) so per-session cache delta tracking keys correctly.
    ///   - `tokens.cache.read` / `tokens.cache.write` in the OpenCode schema
    ///     are session-cumulative counters (total cache hits/writes since
    ///     session start). Converted to per-event deltas in `iterateRows`
    ///     using `cacheState` keyed on session_id.
    private static let unifiedSQL = """
        SELECT
            a.id,
            json_extract(a.data, '$.tokens.input') AS input,
            json_extract(a.data, '$.tokens.output') AS output,
            json_extract(a.data, '$.tokens.reasoning') AS reasoning,
            json_extract(a.data, '$.tokens.cache.read') AS cache_read,
            json_extract(a.data, '$.tokens.cache.write') AS cache_write,
            COALESCE(
                json_extract(u.data, '$.model.providerID'),
                json_extract(a.data, '$.model.providerID')
            ) AS provider_id,
            COALESCE(
                json_extract(u.data, '$.model.modelID'),
                json_extract(a.data, '$.model.modelID'),
                json_extract(a.data, '$.modelID')
            ) AS model_id,
            a.session_id AS session_id,
            json_extract(a.data, '$.time.created') AS ts_ms
        FROM message a
        LEFT JOIN message u ON u.id = json_extract(a.data, '$.parentID')
        WHERE json_valid(a.data)
          AND json_extract(a.data, '$.role') = 'assistant'
          AND json_extract(a.data, '$.tokens') IS NOT NULL
        """

    private static func extractUnified(from db: OpaquePointer, cacheState: inout [String: CacheState]) -> [TokenEvent] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, unifiedSQL, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            openCodeExtractorLogger.warning("F2b: failed to prepare unified OpenCode statement")
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
