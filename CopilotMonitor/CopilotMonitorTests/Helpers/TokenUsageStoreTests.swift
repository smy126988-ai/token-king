import XCTest
import SQLite3
@testable import OpenCode_Bar

/// F2b Task 4 — TokenUsageStore actor + SQLite 8 tests.
final class TokenUsageStoreTests: XCTestCase {

    private var tempDBPath: String!

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDBPath = dir.appendingPathComponent("f2b.sqlite").path
    }

    override func tearDown() {
        if let path = tempDBPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        super.tearDown()
    }

    private func makeEvent(
        provider: Provider = .claude,
        model: String = "claude-sonnet-4-5",
        source: TokenSource = .claudeCode,
        sourceId: String,
        tokens: TokenBreakdown = TokenBreakdown(input: 10, output: 5),
        timestamp: Date = Date()
    ) -> TokenEvent {
        TokenEvent(
            provider: provider,
            model: model,
            source: source,
            sessionId: "sess-\(sourceId)",
            timestamp: timestamp,
            tokens: tokens,
            sourceId: sourceId
        )
    }

    // MARK: - 1. dedup

    func testUpsertAndDedup() async throws {
        let store = TokenUsageStore(dbPath: tempDBPath)
        let e1 = makeEvent(sourceId: "dup-1")
        let e2 = makeEvent(sourceId: "dup-1")
        try await store.upsertEvent(e1)
        try await store.upsertEvent(e2)
        let count = try await countRows(in: "token_events")
        XCTAssertEqual(count, 1, "Same sourceId should dedup to 1 row")
    }

    // MARK: - 2. aggregate correctness

    func testMonthAggregateCorrectness() async throws {
        let store = TokenUsageStore(dbPath: tempDBPath)
        try await store.upsertEvent(makeEvent(
            provider: .claude, model: "claude-sonnet", sourceId: "a",
            tokens: TokenBreakdown(input: 100, output: 50)
        ))
        try await store.upsertEvent(makeEvent(
            provider: .claude, model: "claude-sonnet", sourceId: "b",
            tokens: TokenBreakdown(input: 200, output: 80)
        ))
        try await store.upsertEvent(makeEvent(
            provider: .kimi, model: "kimi-k2", sourceId: "c",
            tokens: TokenBreakdown(input: 500, output: 100)
        ))
        try await store.refreshMonthAggregates()
        let aggregates = await store.fetchMonthAggregates()
        let claude = aggregates.first { $0.provider == "claude" && $0.model == "claude-sonnet" }
        XCTAssertEqual(claude?.tokens.input, 300)
        XCTAssertEqual(claude?.tokens.output, 130)
        let kimi = aggregates.first { $0.provider == "kimi" && $0.model == "kimi-k2" }
        XCTAssertEqual(kimi?.tokens.input, 500)
        XCTAssertEqual(kimi?.tokens.output, 100)
    }

    // MARK: - 3. calendar month window

    func testCalendarMonthWindow() async throws {
        let store = TokenUsageStore(dbPath: tempDBPath)
        let pastDate = Date(timeIntervalSince1970: 1_577_836_800)  // 2020-01-01
        try await store.upsertEvent(makeEvent(
            provider: .claude, sourceId: "past", timestamp: pastDate
        ))
        try await store.upsertEvent(makeEvent(
            provider: .claude, sourceId: "now", timestamp: Date()
        ))
        try await store.refreshMonthAggregates()
        let aggregates = await store.fetchMonthAggregates()
        let claude = aggregates.first { $0.provider == "claude" }
        XCTAssertNotNil(claude)
        XCTAssertEqual(claude?.tokens.input, 10, "Only current month events should aggregate")
    }

    // MARK: - 4. schema version

    func testSchemaVersionCreated() async throws {
        _ = TokenUsageStore(dbPath: tempDBPath)
        var db: OpaquePointer?
        sqlite3_open(tempDBPath, &db)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT version FROM schema_version", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int64(stmt, 0), 1)
    }

    // MARK: - 5. empty db

    func testNoDataReturnsEmpty() async throws {
        let store = TokenUsageStore(dbPath: tempDBPath)
        try await store.refreshMonthAggregates()
        let aggregates = await store.fetchMonthAggregates()
        XCTAssertTrue(aggregates.isEmpty)
    }

    // MARK: - 6. idempotent 10x

    func testIdempotentUpsert() async throws {
        let store = TokenUsageStore(dbPath: tempDBPath)
        for _ in 0..<10 {
            try await store.upsertEvent(makeEvent(sourceId: "idempotent-1"))
        }
        let count = try await countRows(in: "token_events")
        XCTAssertEqual(count, 1)
    }

    // MARK: - 7. concurrent

    func testConcurrentUpsert() async throws {
        let store = TokenUsageStore(dbPath: tempDBPath)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    try? await store.upsertEvent(
                        self.makeEvent(sourceId: "concurrent-\(i)")
                    )
                }
            }
        }
        let count = try await countRows(in: "token_events")
        XCTAssertEqual(count, 10, "10 distinct sourceIds should yield 10 rows")
    }

    // MARK: - 8. restart persistence

    func testRefreshAfterRestart() async throws {
        let store1 = TokenUsageStore(dbPath: tempDBPath)
        try await store1.upsertEvent(makeEvent(
            provider: .codex, model: "gpt-4o", sourceId: "restart-1",
            tokens: TokenBreakdown(input: 999, output: 333)
        ))
        try await store1.refreshMonthAggregates()
        let store2 = TokenUsageStore(dbPath: tempDBPath)
        let aggregates = await store2.fetchMonthAggregates()
        let codex = aggregates.first { $0.provider == "codex" && $0.model == "gpt-4o" }
        XCTAssertEqual(codex?.tokens.input, 999)
        XCTAssertEqual(codex?.tokens.output, 333)
    }

    // MARK: - helpers

    private func countRows(in table: String) async throws -> Int {
        let path = tempDBPath!
        return try await Task.detached {
            var db: OpaquePointer?
            sqlite3_open(path, &db)
            defer { sqlite3_close(db) }
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM \(table)", -1, &stmt, nil)
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(stmt, 0))
        }.value
    }
}