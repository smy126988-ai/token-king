import Foundation
import SQLite3

/// Persistence layer (SQLite, schema 1).
/// 3 tables:
/// - token_events: raw event (cross-tool normalized, source_id UNIQUE for dedup)
/// - month_aggregates: per provider x model x year_month, materialized
/// - model_pricing_cache: mirrors F2a PricingTable
actor TokenUsageStore {
    private let dbPath: String
    private var db: OpaquePointer?

    init(dbPath: String? = nil) {
        self.dbPath = dbPath ?? "\(NSHomeDirectory())/Library/Application Support/TokenKing/f2b.sqlite"
        try? FileManager.default.createDirectory(atPath: "\(NSHomeDirectory())/Library/Application Support/TokenKing", withIntermediateDirectories: true)
        openDB()
        createSchema()
    }

    deinit { sqlite3_close(db) }

    private func openDB() {
        sqlite3_open(dbPath, &db)
    }

    private func createSchema() {
        let sqls = [
            "CREATE TABLE IF NOT EXISTS token_events (id INTEGER PRIMARY KEY AUTOINCREMENT, provider TEXT NOT NULL, model TEXT NOT NULL, source TEXT NOT NULL, session_id TEXT NOT NULL, ts_ms INTEGER NOT NULL, input INTEGER DEFAULT 0, output INTEGER DEFAULT 0, cache_read INTEGER DEFAULT 0, cache_write INTEGER DEFAULT 0, reasoning INTEGER DEFAULT 0, source_id TEXT UNIQUE NOT NULL, inserted_at INTEGER DEFAULT (strftime('%s','now')))",
            "CREATE TABLE IF NOT EXISTS month_aggregates (provider TEXT NOT NULL, model TEXT NOT NULL, year_month TEXT NOT NULL, input INTEGER DEFAULT 0, output INTEGER DEFAULT 0, cache_read INTEGER DEFAULT 0, cache_write INTEGER DEFAULT 0, reasoning INTEGER DEFAULT 0, last_updated INTEGER, PRIMARY KEY (provider, model, year_month))",
            "CREATE TABLE IF NOT EXISTS model_pricing_cache (provider TEXT NOT NULL, model TEXT NOT NULL, input_rate REAL, output_rate REAL, cache_read_rate REAL, source TEXT, fetched_at INTEGER, PRIMARY KEY (provider, model))",
            "CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY)",
            "INSERT OR IGNORE INTO schema_version VALUES (1)",
            "CREATE INDEX IF NOT EXISTS idx_token_events_provider_ts ON token_events(provider, ts_ms)",
            "CREATE INDEX IF NOT EXISTS idx_token_events_session ON token_events(session_id)"
        ]
        for sql in sqls { sqlite3_exec(db, sql, nil, nil, nil) }
    }

    /// Insert raw event (dedup by source_id UNIQUE).
    func upsertEvent(_ event: TokenEvent) throws {
        let sql = "INSERT OR IGNORE INTO token_events (provider, model, source, session_id, ts_ms, input, output, cache_read, cache_write, reasoning, source_id) VALUES (?,?,?,?,?,?,?,?,?,?,?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else { return }
        defer { sqlite3_finalize(stmt) }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, event.provider.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, event.model, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, event.source.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, event.sessionId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 5, Int64(event.timestamp.timeIntervalSince1970 * 1000))
        sqlite3_bind_int64(stmt, 6, Int64(event.tokens.input))
        sqlite3_bind_int64(stmt, 7, Int64(event.tokens.output))
        sqlite3_bind_int64(stmt, 8, Int64(event.tokens.cacheRead))
        sqlite3_bind_int64(stmt, 9, Int64(event.tokens.cacheWrite))
        sqlite3_bind_int64(stmt, 10, Int64(event.tokens.reasoning))
        sqlite3_bind_text(stmt, 11, event.sourceId, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    /// Re-aggregate month_aggregates (current month).
    func refreshMonthAggregates() throws {
        let yearMonth = currentYearMonth()
        sqlite3_exec(db, "DELETE FROM month_aggregates WHERE year_month = '\(yearMonth)'", nil, nil, nil)
        let sql = """
            INSERT INTO month_aggregates
            (provider, model, year_month, input, output, cache_read, cache_write, reasoning, last_updated)
            SELECT provider, model, '\(yearMonth)',
                   SUM(input), SUM(output), SUM(cache_read), SUM(cache_write),
                   SUM(reasoning), strftime('%s','now')
            FROM token_events
            WHERE strftime('%Y-%m', ts_ms / 1000, 'unixepoch') = '\(yearMonth)'
            GROUP BY provider, model
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func currentYearMonth() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return fmt.string(from: Date())
    }

    /// Query month aggregates (for UI consumption).
    func fetchMonthAggregates(yearMonth: String? = nil) -> [MonthAggregate] {
        let ym = yearMonth ?? currentYearMonth()
        var stmt: OpaquePointer?
        let sql = "SELECT provider, model, input, output, cache_read, cache_write, reasoning FROM month_aggregates WHERE year_month = ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt = stmt else { return [] }
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
}

struct MonthAggregate {
    let provider: String
    let model: String
    let tokens: TokenBreakdown
    let yearMonth: String
}