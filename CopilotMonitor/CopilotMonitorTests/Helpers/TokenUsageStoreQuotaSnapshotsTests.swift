import XCTest
@testable import OpenCode_Bar

/// F4 redesign: quota snapshot persistence for 5h/weekly quota history.
/// Tests use real SQLite (no mocks) with isolated temp DBs.
final class TokenUsageStoreQuotaSnapshotsTests: XCTestCase {

    private var store: TokenUsageStore!
    private var dbPath: String!

    override func setUp() async throws {
        dbPath = "\(NSTemporaryDirectory())/quota-snapshot-test-\(UUID().uuidString).sqlite"
        store = TokenUsageStore(dbPath: dbPath)
    }

    override func tearDown() async throws {
        try? await store.close()
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - upsertQuotaSnapshot

    func testUpsertSingleSnapshot() async throws {
        let snapshot = QuotaSnapshot(
            provider: "kimi", window: "5h",
            usagePercent: 35.0, resetAt: nil, snapshotTs: Date()
        )
        try await store.upsertQuotaSnapshot(snapshot)
        let results = await store.fetchQuotaSnapshots(provider: "kimi", window: "5h", since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.usagePercent, 35.0)
        XCTAssertNil(results.first?.resetAt)
    }

    func testUpsertIsIdempotentOnDuplicateTimestamp() async throws {
        let ts = Date()
        let s1 = QuotaSnapshot(provider: "kimi", window: "5h", usagePercent: 10.0, resetAt: nil, snapshotTs: ts)
        let s2 = QuotaSnapshot(provider: "kimi", window: "5h", usagePercent: 20.0, resetAt: nil, snapshotTs: ts)
        try await store.upsertQuotaSnapshot(s1)
        try await store.upsertQuotaSnapshot(s2)
        // INSERT OR IGNORE on duplicate PK → first one wins, count = 1
        let results = await store.fetchQuotaSnapshots(provider: "kimi", window: "5h", since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(results.count, 1, "Duplicate PK should be ignored")
        XCTAssertEqual(results.first?.usagePercent, 10.0)
    }

    func testUpsertDistinctKeysAreIndependent() async throws {
        try await store.upsertQuotaSnapshot(QuotaSnapshot(provider: "kimi", window: "5h", usagePercent: 10, resetAt: nil, snapshotTs: Date()))
        try await store.upsertQuotaSnapshot(QuotaSnapshot(provider: "claude", window: "5h", usagePercent: 20, resetAt: nil, snapshotTs: Date()))
        try await store.upsertQuotaSnapshot(QuotaSnapshot(provider: "kimi", window: "7d", usagePercent: 30, resetAt: nil, snapshotTs: Date()))
        let epoch = Date(timeIntervalSince1970: 0)
        let kimi5h = await store.fetchQuotaSnapshots(provider: "kimi", window: "5h", since: epoch)
        let claude5h = await store.fetchQuotaSnapshots(provider: "claude", window: "5h", since: epoch)
        let kimi7d = await store.fetchQuotaSnapshots(provider: "kimi", window: "7d", since: epoch)
        XCTAssertEqual(kimi5h.count, 1)
        XCTAssertEqual(claude5h.count, 1)
        XCTAssertEqual(kimi7d.count, 1)
    }

    // MARK: - fetchQuotaSnapshots

    func testFetchEmptyDatabaseReturnsEmpty() async {
        let results = await store.fetchQuotaSnapshots(provider: "kimi", window: "5h", since: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(results.isEmpty)
    }

    func testFetchFiltersBySince() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_001_000)
        let t2 = Date(timeIntervalSince1970: 1_700_002_000)
        try await store.upsertQuotaSnapshot(QuotaSnapshot(provider: "kimi", window: "5h", usagePercent: 10, resetAt: nil, snapshotTs: t0))
        try await store.upsertQuotaSnapshot(QuotaSnapshot(provider: "kimi", window: "5h", usagePercent: 20, resetAt: nil, snapshotTs: t1))
        try await store.upsertQuotaSnapshot(QuotaSnapshot(provider: "kimi", window: "5h", usagePercent: 30, resetAt: nil, snapshotTs: t2))
        let results = await store.fetchQuotaSnapshots(provider: "kimi", window: "5h", since: t1, limit: 100)
        XCTAssertEqual(results.count, 2, "Should return t1 and t2 only")
        XCTAssertEqual(results.first?.usagePercent, 30.0, "Most recent first")
        XCTAssertEqual(results.last?.usagePercent, 20.0)
    }

    func testFetchLimitCapsResultCount() async throws {
        for i in 0..<5 {
            try await store.upsertQuotaSnapshot(QuotaSnapshot(
                provider: "kimi", window: "5h", usagePercent: Double(i), resetAt: nil,
                snapshotTs: Date(timeIntervalSince1970: Double(1_700_000_000 + i * 100))
            ))
        }
        let results = await store.fetchQuotaSnapshots(provider: "kimi", window: "5h", since: Date(timeIntervalSince1970: 0), limit: 3)
        XCTAssertEqual(results.count, 3)
    }

    func testFetchFiltersByProviderAndWindow() async throws {
        let t = Date()
        try await store.upsertQuotaSnapshot(QuotaSnapshot(provider: "kimi", window: "5h", usagePercent: 10, resetAt: nil, snapshotTs: t))
        try await store.upsertQuotaSnapshot(QuotaSnapshot(provider: "kimi", window: "7d", usagePercent: 20, resetAt: nil, snapshotTs: t))
        try await store.upsertQuotaSnapshot(QuotaSnapshot(provider: "claude", window: "5h", usagePercent: 30, resetAt: nil, snapshotTs: t))
        let kimi5h = await store.fetchQuotaSnapshots(provider: "kimi", window: "5h", since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(kimi5h.count, 1)
        XCTAssertEqual(kimi5h.first?.provider, "kimi")
        XCTAssertEqual(kimi5h.first?.window, "5h")
    }

    func testResetAtPersistedCorrectly() async throws {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.upsertQuotaSnapshot(QuotaSnapshot(
            provider: "kimi", window: "5h", usagePercent: 50, resetAt: reset, snapshotTs: Date()
        ))
        let results = await store.fetchQuotaSnapshots(provider: "kimi", window: "5h", since: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(results.first?.resetAt, reset)
    }
}