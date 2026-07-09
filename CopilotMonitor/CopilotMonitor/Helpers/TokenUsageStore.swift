import Foundation
import SQLite3
import os.log

private let tokenUsageStoreLogger = Logger(subsystem: "com.opencodeproviders", category: "TokenUsageStore")

/// Concrete SQLite errors surfaced by `TokenUsageStore`.
indirect enum SQLiteError: Error, Equatable, Sendable {
    case openFailed(path: String, code: Int32, message: String)
    case execFailed(sql: String, code: Int32, message: String)
    case prepareFailed(sql: String, code: Int32, message: String)
    case bindFailed(index: Int32, code: Int32, message: String)
    case stepFailed(sql: String, code: Int32, message: String)
    case storeClosed
    case storeUninitialized(underlying: SQLiteError)
}

/// Persistence layer (SQLite, schema 3).
/// 5 tables:
/// - token_events: raw event (cross-tool normalized, source_id UNIQUE for dedup)
/// - month_aggregates: per provider x model x year_month, materialized
/// - day_aggregates: per provider x model x day (UTC), materialized (F1)
/// - quota_snapshots: 5h/7d quota state snapshots (F4 redesign), per provider x window x ts
/// - model_pricing_cache: mirrors F2a PricingTable
actor TokenUsageStore {
    private let dbPath: String
    private(set) nonisolated(unsafe) var initError: SQLiteError?

    // `db` is marked `nonisolated(unsafe)` because `deinit` is not isolated and
    // must be able to close the handle without crossing actor isolation.
    // All normal access still happens on the actor via `ensureOpen()`.
    nonisolated(unsafe) private var db: OpaquePointer?

    init(dbPath: String? = nil) {
        self.dbPath = dbPath ?? "\(NSHomeDirectory())/Library/Application Support/TokenKing/f2b.sqlite"
        let dir = (self.dbPath as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let openCode = sqlite3_open(self.dbPath, &db)
        guard openCode == SQLITE_OK, db != nil else {
            let message = errorMessage(at: openCode)
            sqlite3_close(db)
            db = nil
            initError = .openFailed(path: self.dbPath, code: openCode, message: message)
            return
        }

        let sqls = [
            "CREATE TABLE IF NOT EXISTS token_events (id INTEGER PRIMARY KEY AUTOINCREMENT, provider TEXT NOT NULL, model TEXT NOT NULL, source TEXT NOT NULL, session_id TEXT NOT NULL, ts_ms INTEGER NOT NULL, input INTEGER DEFAULT 0, output INTEGER DEFAULT 0, cache_read INTEGER DEFAULT 0, cache_write INTEGER DEFAULT 0, reasoning INTEGER DEFAULT 0, source_id TEXT UNIQUE NOT NULL, inserted_at INTEGER DEFAULT (strftime('%s','now')))",
            "CREATE TABLE IF NOT EXISTS month_aggregates (provider TEXT NOT NULL, model TEXT NOT NULL, year_month TEXT NOT NULL, input INTEGER DEFAULT 0, output INTEGER DEFAULT 0, cache_read INTEGER DEFAULT 0, cache_write INTEGER DEFAULT 0, reasoning INTEGER DEFAULT 0, last_updated INTEGER, PRIMARY KEY (provider, model, year_month))",
            "CREATE TABLE IF NOT EXISTS day_aggregates (provider TEXT NOT NULL, model TEXT NOT NULL, day TEXT NOT NULL, input INTEGER DEFAULT 0, output INTEGER DEFAULT 0, cache_read INTEGER DEFAULT 0, cache_write INTEGER DEFAULT 0, reasoning INTEGER DEFAULT 0, last_updated INTEGER, PRIMARY KEY (provider, model, day))",
            "CREATE TABLE IF NOT EXISTS model_pricing_cache (provider TEXT NOT NULL, model TEXT NOT NULL, input_rate REAL, output_rate REAL, cache_read_rate REAL, source TEXT, fetched_at INTEGER, PRIMARY KEY (provider, model))",
            "CREATE TABLE IF NOT EXISTS quota_snapshots (provider TEXT NOT NULL, window TEXT NOT NULL, usage_percent REAL NOT NULL, reset_at INTEGER, snapshot_ts INTEGER NOT NULL, PRIMARY KEY (provider, window, snapshot_ts))",
            "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)",
            "INSERT OR IGNORE INTO schema_version VALUES (1)",
            "INSERT OR IGNORE INTO schema_version VALUES (2)",
            "INSERT OR IGNORE INTO schema_version VALUES (3)",
            "CREATE INDEX IF NOT EXISTS idx_token_events_provider_ts ON token_events(provider, ts_ms)",
            "CREATE INDEX IF NOT EXISTS idx_token_events_session ON token_events(session_id)",
            "CREATE INDEX IF NOT EXISTS idx_day_aggregates_day ON day_aggregates(day)",
            "CREATE INDEX IF NOT EXISTS idx_quota_snapshots_pw_ts ON quota_snapshots(provider, window, snapshot_ts DESC)"
        ]
        for sql in sqls {
            let rc = sqlite3_exec(db, sql, nil, nil, nil)
            guard rc == SQLITE_OK else {
                let message = errorMessage(at: rc)
                sqlite3_close(db)
                db = nil
                initError = .execFailed(sql: sql, code: rc, message: message)
                return
            }
        }
    }

    deinit {
        sqlite3_close(db)
        db = nil
    }

    /// Explicitly close the database. After closing, further operations throw `storeClosed`.
    func close() throws {
        guard initError == nil else { return }
        guard db != nil else { return }
        let code = sqlite3_close(db)
        guard code == SQLITE_OK else {
            throw SQLiteError.execFailed(sql: "sqlite3_close", code: code, message: errorMessage(at: code))
        }
        db = nil
    }

    /// Insert raw event (dedup by source_id UNIQUE).
    func upsertEvent(_ event: TokenEvent) throws {
        try ensureOpen()
        let sql = "INSERT OR IGNORE INTO token_events (provider, model, source, session_id, ts_ms, input, output, cache_read, cache_write, reasoning, source_id) VALUES (?,?,?,?,?,?,?,?,?,?,?)"
        var stmt: OpaquePointer?
        let prepareCode = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareCode == SQLITE_OK, let stmt else {
            throw SQLiteError.prepareFailed(sql: sql, code: prepareCode, message: errorMessage(at: prepareCode))
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        try bindText(stmt, index: 1, text: event.provider.rawValue, destructor: SQLITE_TRANSIENT)
        try bindText(stmt, index: 2, text: event.model, destructor: SQLITE_TRANSIENT)
        try bindText(stmt, index: 3, text: event.source.rawValue, destructor: SQLITE_TRANSIENT)
        try bindText(stmt, index: 4, text: event.sessionId, destructor: SQLITE_TRANSIENT)
        try bindInt64(stmt, index: 5, value: Int64(event.timestamp.timeIntervalSince1970 * 1000))
        try bindInt64(stmt, index: 6, value: Int64(event.tokens.input))
        try bindInt64(stmt, index: 7, value: Int64(event.tokens.output))
        try bindInt64(stmt, index: 8, value: Int64(event.tokens.cacheRead))
        try bindInt64(stmt, index: 9, value: Int64(event.tokens.cacheWrite))
        try bindInt64(stmt, index: 10, value: Int64(event.tokens.reasoning))
        try bindText(stmt, index: 11, text: event.sourceId, destructor: SQLITE_TRANSIENT)

        let stepCode = sqlite3_step(stmt)
        guard stepCode == SQLITE_DONE else {
            throw SQLiteError.stepFailed(sql: sql, code: stepCode, message: errorMessage(at: stepCode))
        }
    }

    /// Re-aggregate month_aggregates for the given month (defaults to current UTC month).
    func refreshMonthAggregates(for yearMonth: String? = nil) throws {
        try ensureOpen()
        let ym = yearMonth ?? currentYearMonth()
        let deleteSQL = "DELETE FROM month_aggregates WHERE year_month = ?"
        try execute(deleteSQL, parameters: [ym])

        let insertSQL = """
            INSERT INTO month_aggregates
            (provider, model, year_month, input, output, cache_read, cache_write, reasoning, last_updated)
            SELECT provider, model, ?,
                   SUM(input), SUM(output), SUM(cache_read), SUM(cache_write),
                   SUM(reasoning), strftime('%s','now')
            FROM token_events
            WHERE strftime('%Y-%m', ts_ms / 1000, 'unixepoch') = ?
            GROUP BY provider, model
        """
        try execute(insertSQL, parameters: [ym, ym])
    }

    /// Re-aggregate day_aggregates for the given day (defaults to today UTC).
    func refreshDayAggregates(for day: Date? = nil) throws {
        try ensureOpen()
        let d = day ?? Date()
        let dayString = dayString(for: d)
        let deleteSQL = "DELETE FROM day_aggregates WHERE day = ?"
        try execute(deleteSQL, parameters: [dayString])

        let insertSQL = """
            INSERT INTO day_aggregates
            (provider, model, day, input, output, cache_read, cache_write, reasoning, last_updated)
            SELECT provider, model, ?,
                   SUM(input), SUM(output), SUM(cache_read), SUM(cache_write),
                   SUM(reasoning), strftime('%s','now')
            FROM token_events
            WHERE strftime('%Y-%m-%d', ts_ms / 1000, 'unixepoch') = ?
            GROUP BY provider, model
        """
        try execute(insertSQL, parameters: [dayString, dayString])
    }

    /// Current UTC year-month (matches the SQLite `strftime('%Y-%m', ts_ms/1000, 'unixepoch')` filter).
    func currentYearMonth(for date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone(identifier: "UTC")
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: date)
    }

    /// Query month aggregates (for UI consumption).
    func fetchMonthAggregates(yearMonth: String? = nil) -> [MonthAggregate] {
        guard initError == nil, let db = db else { return [] }
        let ym = yearMonth ?? currentYearMonth()
        var stmt: OpaquePointer?
        let sql = "SELECT provider, model, input, output, cache_read, cache_write, reasoning FROM month_aggregates WHERE year_month = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, ym, -1, SQLITE_TRANSIENT)
        var results: [MonthAggregate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let provider = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
            let model = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
            let tokens = TokenBreakdown(
                input: Int(sqlite3_column_int64(stmt, 2)),
                output: Int(sqlite3_column_int64(stmt, 3)),
                cacheRead: Int(sqlite3_column_int64(stmt, 4)),
                cacheWrite: Int(sqlite3_column_int64(stmt, 5)),
                reasoning: Int(sqlite3_column_int64(stmt, 6))
            )
            results.append(MonthAggregate(provider: provider, model: model, tokens: tokens, yearMonth: ym))
        }
        return results
    }

    /// Query day_aggregates (for UI consumption).
    /// `provider` filter is optional; `yearMonth` filter (e.g. "2026-07") scopes to that month.
    func fetchDayAggregates(provider: String? = nil, yearMonth: String? = nil) -> [DayAggregate] {
        guard initError == nil, let db = db else { return [] }
        var sql = "SELECT provider, model, day, input, output, cache_read, cache_write, reasoning FROM day_aggregates"
        var conditions: [String] = []
        if provider != nil { conditions.append("provider = ?") }
        if yearMonth != nil { conditions.append("day LIKE ?") }
        if !conditions.isEmpty { sql += " WHERE " + conditions.joined(separator: " AND ") }
        sql += " ORDER BY day ASC, provider ASC, model ASC"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var bindIndex: Int32 = 1
        if let provider { sqlite3_bind_text(stmt, bindIndex, provider, -1, SQLITE_TRANSIENT); bindIndex += 1 }
        if let yearMonth {
            let pattern = "\(yearMonth)-%"
            sqlite3_bind_text(stmt, bindIndex, pattern, -1, SQLITE_TRANSIENT)
        }
        var results: [DayAggregate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let provider = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
            let model = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
            let day = sqlite3_column_text(stmt, 2).flatMap { String(cString: $0) } ?? ""
            let tokens = TokenBreakdown(
                input: Int(sqlite3_column_int64(stmt, 3)),
                output: Int(sqlite3_column_int64(stmt, 4)),
                cacheRead: Int(sqlite3_column_int64(stmt, 5)),
                cacheWrite: Int(sqlite3_column_int64(stmt, 6)),
                reasoning: Int(sqlite3_column_int64(stmt, 7))
            )
            results.append(DayAggregate(provider: provider, model: model, day: day, tokens: tokens))
        }
        return results
    }

    /// Cross-provider sum of all token fields for the given month (default: current UTC month).
    func fetchMonthTotalTokens(yearMonth: String? = nil) -> TokenBreakdown {
        guard initError == nil, let db = db else { return TokenBreakdown.zero }
        let ym = yearMonth ?? currentYearMonth()
        let sql = """
            SELECT COALESCE(SUM(input), 0), COALESCE(SUM(output), 0),
                   COALESCE(SUM(cache_read), 0), COALESCE(SUM(cache_write), 0),
                   COALESCE(SUM(reasoning), 0)
            FROM day_aggregates WHERE day LIKE ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return TokenBreakdown.zero }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, "\(ym)-%", -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return TokenBreakdown.zero }
        return TokenBreakdown(
            input: Int(sqlite3_column_int64(stmt, 0)),
            output: Int(sqlite3_column_int64(stmt, 1)),
            cacheRead: Int(sqlite3_column_int64(stmt, 2)),
            cacheWrite: Int(sqlite3_column_int64(stmt, 3)),
            reasoning: Int(sqlite3_column_int64(stmt, 4))
        )
    }

    /// Insert or ignore a quota snapshot (5h or 7d usage state).
    /// Idempotent on PK collision (provider, window, snapshot_ts) — first one wins.
    func upsertQuotaSnapshot(_ snapshot: QuotaSnapshot) throws {
        try ensureOpen()
        guard let db else { return }
        let sql = "INSERT OR IGNORE INTO quota_snapshots (provider, window, usage_percent, reset_at, snapshot_ts) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SQLiteError.execFailed(sql: sql, code: 0, message: errorMessage(at: 0))
        }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, snapshot.provider, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, snapshot.window, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, snapshot.usagePercent)
        if let resetAt = snapshot.resetAt {
            sqlite3_bind_int64(stmt, 4, Int64(resetAt.timeIntervalSince1970))
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_int64(stmt, 5, Int64(snapshot.snapshotTs.timeIntervalSince1970))
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.stepFailed(sql: sql, code: 0, message: errorMessage(at: 0))
        }
    }

    /// Query quota snapshots for a (provider, window) pair since a cutoff time.
    /// Returns most recent first (DESC). Optional `limit` caps the result count.
    func fetchQuotaSnapshots(provider: String, window: String, since: Date, limit: Int = 200) -> [QuotaSnapshot] {
        guard initError == nil, let db = db else { return [] }
        let sql = "SELECT provider, window, usage_percent, reset_at, snapshot_ts FROM quota_snapshots WHERE provider = ? AND window = ? AND snapshot_ts >= ? ORDER BY snapshot_ts DESC LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, provider, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, window, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 3, Int64(since.timeIntervalSince1970))
        sqlite3_bind_int(stmt, 4, Int32(limit))
        var results: [QuotaSnapshot] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let provider = sqlite3_column_text(stmt, 0).flatMap { String(cString: $0) } ?? ""
            let window = sqlite3_column_text(stmt, 1).flatMap { String(cString: $0) } ?? ""
            let usagePercent = sqlite3_column_double(stmt, 2)
            let resetAt: Date? = sqlite3_column_type(stmt, 3) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 3)))
            let snapshotTs = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 4)))
            results.append(QuotaSnapshot(
                provider: provider, window: window, usagePercent: usagePercent,
                resetAt: resetAt, snapshotTs: snapshotTs
            ))
        }
        return results
    }

    /// One-shot migration: re-classify OpenCode events whose original
    /// message providerID is one of the new targets
    /// (`minimax` / `minimax-cn` / `xiaomi` / `xiaomi-token-plan-cn`).
    ///
    /// Before this migration the `TokenNormalizer` did not recognize those
    /// providerIDs, so the events were stored under `.nanoGpt`. The migration
    /// re-reads the source OpenCode SQLite, classifies each affected message
    /// with the updated normalizer, and `UPDATE`s the F2b row.
    ///
    /// Idempotent: the `provider != ?` predicate skips rows already correctly
    /// classified. Safe to call repeatedly.
    ///
    /// Side effect: rebuilds `month_aggregates` and `day_aggregates` for every
    /// distinct (year_month, day) present in `token_events` so the per-provider
    /// monthly rollup reflects the new classification.
    ///
    /// - Returns: number of rows updated. Returns 0 when the OpenCode DB is
    ///   missing or contains no migration-target messages.
    func migrateOpenCodeProviderIDs(openCodeDBPath: String) async throws -> Int {
        guard initError == nil else {
            throw SQLiteError.storeUninitialized(underlying: initError!)
        }
        guard FileManager.default.fileExists(atPath: openCodeDBPath) else {
            tokenUsageStoreLogger.info("OpenCode DB not found at \(openCodeDBPath, privacy: .public); migration is a no-op")
            return 0
        }

        let migrations = try loadOpenCodeMigrations(openCodeDBPath: openCodeDBPath)
        guard !migrations.isEmpty else {
            tokenUsageStoreLogger.info("No OpenCode messages match migration targets; skipping")
            return 0
        }

        let totalUpdated = try applyProviderUpdates(migrations: migrations)
        tokenUsageStoreLogger.info("Migrated \(totalUpdated) OpenCode token_events to new provider classification")

        try refreshAllAggregates()
        return totalUpdated
    }

    /// Read `~/.local/share/opencode/opencode.db` (or the provided path) and
    /// return one `(msgId, newProviderRaw)` tuple per message whose
    /// `data.model.providerID` is one of the new targets. Messages whose
    /// re-classification still falls back to `.nanoGpt` are excluded.
    private func loadOpenCodeMigrations(openCodeDBPath: String) throws -> [(msgId: String, providerRaw: String)] {
        var db: OpaquePointer?
        let openFlags = SQLITE_OPEN_READONLY
        let openCode = sqlite3_open_v2(openCodeDBPath, &db, openFlags, nil)
        guard openCode == SQLITE_OK, let db else {
            tokenUsageStoreLogger.warning("Failed to open OpenCode DB read-only at \(openCodeDBPath, privacy: .public)")
            return []
        }
        defer { sqlite3_close(db) }

        let sql = """
            SELECT id, json_extract(data, '$.model.providerID')
            FROM message
            WHERE json_valid(data)
              AND json_extract(data, '$.model.providerID') IS NOT NULL
              AND (json_extract(data, '$.model.providerID') LIKE '%minimax%'
                   OR json_extract(data, '$.model.providerID') LIKE '%xiaomi%')
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            tokenUsageStoreLogger.warning("Failed to prepare OpenCode providerID scan")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var results: [(msgId: String, providerRaw: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let msgIdC = sqlite3_column_text(stmt, 0),
                  let providerIDC = sqlite3_column_text(stmt, 1) else { continue }
            let msgId = String(cString: msgIdC)
            let providerID = String(cString: providerIDC)
            // Model field is not stored alongside the providerID in the
            // OpenCode schema; pass an empty model string. The new
            // providerID-only fallback rules in TokenNormalizer cover
            // minimax / xiaomi targets so this still classifies correctly.
            let normalized = TokenNormalizer.matchProvider(model: "", providerID: providerID)
            if normalized == .nanoGpt { continue }
            results.append((msgId: msgId, providerRaw: normalized.rawValue))
        }
        return results
    }

    /// Apply one `UPDATE token_events SET provider = ? WHERE source = 'opencode' AND source_id LIKE '%:<msgId>' AND provider != ?`
    /// per migration tuple. The `provider != ?` predicate is what makes the
    /// whole migration idempotent: re-running it leaves correctly classified
    /// rows untouched.
    private func applyProviderUpdates(migrations: [(msgId: String, providerRaw: String)]) throws -> Int {
        try ensureOpen()
        guard let db else { return 0 }
        let sql = """
            UPDATE token_events
            SET provider = ?
            WHERE source = 'opencode'
              AND source_id LIKE ?
              AND provider != ?
        """
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var totalUpdated = 0
        for migration in migrations {
            var stmt: OpaquePointer?
            let prepareCode = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            guard prepareCode == SQLITE_OK, let stmt else { continue }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, migration.providerRaw, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, "%:\(migration.msgId)", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, migration.providerRaw, -1, SQLITE_TRANSIENT)
            let stepCode = sqlite3_step(stmt)
            guard stepCode == SQLITE_DONE else {
                throw SQLiteError.stepFailed(sql: sql, code: stepCode, message: errorMessage(at: stepCode))
            }
            totalUpdated += Int(sqlite3_changes(db))
        }
        return totalUpdated
    }

    /// Re-derive `month_aggregates` and `day_aggregates` for every distinct
    /// (year_month, day) present in `token_events`. Used by the OpenCode
    /// providerID migration so the per-provider rollup reflects reclassified
    /// rows across history, not just the current UTC month.
    private func refreshAllAggregates() throws {
        try ensureOpen()
        guard let db else { return }

        let months = try collectDistinctMonths(db: db)
        for ym in months {
            try refreshMonthAggregates(for: ym)
        }

        let days = try collectDistinctDays(db: db)
        let dayFormatter = DateFormatter()
        dayFormatter.timeZone = .utc
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
        for day in days {
            guard let date = dayFormatter.date(from: day) else { continue }
            try refreshDayAggregates(for: date)
        }
    }

    private func collectDistinctMonths(db: OpaquePointer) throws -> [String] {
        let sql = """
            SELECT DISTINCT strftime('%Y-%m', ts_ms / 1000, 'unixepoch') AS ym
            FROM token_events
            WHERE ts_ms IS NOT NULL
            ORDER BY ym
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        var months: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let ymC = sqlite3_column_text(stmt, 0) {
                months.append(String(cString: ymC))
            }
        }
        return months
    }

    private func collectDistinctDays(db: OpaquePointer) throws -> [String] {
        let sql = """
            SELECT DISTINCT strftime('%Y-%m-%d', ts_ms / 1000, 'unixepoch') AS d
            FROM token_events
            WHERE ts_ms IS NOT NULL
            ORDER BY d
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        var days: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let dC = sqlite3_column_text(stmt, 0) {
                days.append(String(cString: dC))
            }
        }
        return days
    }
}

// MARK: - Private helpers

private extension TokenUsageStore {
    /// Returns "YYYY-MM-DD" for a given Date in UTC.
    func dayString(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeZone = .utc
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    func ensureOpen() throws {
        if let initError {
            throw SQLiteError.storeUninitialized(underlying: initError)
        }
        guard db != nil else {
            throw SQLiteError.storeClosed
        }
    }

    nonisolated func errorMessage(at code: Int32) -> String {
        if let msg = sqlite3_errmsg(db) {
            return String(cString: msg)
        }
        if code != SQLITE_OK {
            return String(cString: sqlite3_errstr(code))
        }
        return "unknown SQLite error"
    }

    func execute(_ sql: String, parameters: [String] = []) throws {
        try ensureOpen()
        var stmt: OpaquePointer?
        let prepareCode = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard prepareCode == SQLITE_OK, let stmt else {
            throw SQLiteError.prepareFailed(sql: sql, code: prepareCode, message: errorMessage(at: prepareCode))
        }
        defer { sqlite3_finalize(stmt) }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, parameter) in parameters.enumerated() {
            let idx = Int32(index + 1)
            let code = sqlite3_bind_text(stmt, idx, parameter, -1, SQLITE_TRANSIENT)
            guard code == SQLITE_OK else {
                throw SQLiteError.bindFailed(index: idx, code: code, message: errorMessage(at: code))
            }
        }

        let stepCode = sqlite3_step(stmt)
        guard stepCode == SQLITE_DONE else {
            throw SQLiteError.stepFailed(sql: sql, code: stepCode, message: errorMessage(at: stepCode))
        }
    }

    func bindText(_ stmt: OpaquePointer, index: Int32, text: String, destructor: @convention(c) (UnsafeMutableRawPointer?) -> Void) throws {
        let code = sqlite3_bind_text(stmt, index, text, -1, destructor)
        guard code == SQLITE_OK else {
            throw SQLiteError.bindFailed(index: index, code: code, message: errorMessage(at: code))
        }
    }

    func bindInt64(_ stmt: OpaquePointer, index: Int32, value: Int64) throws {
        let code = sqlite3_bind_int64(stmt, index, value)
        guard code == SQLITE_OK else {
            throw SQLiteError.bindFailed(index: index, code: code, message: errorMessage(at: code))
        }
    }
}

struct MonthAggregate {
    let provider: String
    let model: String
    let tokens: TokenBreakdown
    let yearMonth: String
}

struct DayAggregate {
    let provider: String
    let model: String
    let day: String
    let tokens: TokenBreakdown
}

struct QuotaSnapshot: Hashable, Sendable {
    let provider: String
    let window: String         // "5h" or "7d"
    let usagePercent: Double
    let resetAt: Date?
    let snapshotTs: Date
}
