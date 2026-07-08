import XCTest
@testable import OpenCode_Bar

/// F2b Task 6 — RefreshActor 30s tick orchestrator (injection-based tests).
///
/// All tests use stub extractors to avoid touching real session files or APIs.
final class RefreshActorTests: XCTestCase {

    private var tempDBPath: String!
    private var store: TokenUsageStore!

    override func setUp() async throws {
        try await super.setUp()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tk-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDBPath = dir.appendingPathComponent("f2b.sqlite").path
        store = TokenUsageStore(dbPath: tempDBPath)
    }

    override func tearDown() async throws {
        if let path = tempDBPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        try await super.tearDown()
    }

    // MARK: - 1. start/stop lifecycle

    func testStartStop() async {
        let actor = RefreshActor(store: store, extractors: [], intervalSeconds: 1)
        let start = Date()
        await actor.start()
        try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        await actor.stop()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0, "start + 100ms wait + stop must complete in < 1s")
    }

    // MARK: - 2. single tick completes without throwing; store remains queryable

    func testTickProcessesEvents() async {
        let extractor = StubExtractor(events: [
            TokenEvent(
                provider: .claude, model: "claude-test",
                source: .claudeCode, sessionId: "s1",
                timestamp: Date(),
                tokens: TokenBreakdown(input: 10, output: 5),
                sourceId: "tk:test:1"
            )
        ])
        let actor = RefreshActor(store: store, extractors: [extractor])
        await actor.tickNow()

        let aggregates = await store.fetchMonthAggregates()
        XCTAssertNotNil(aggregates, "store must remain queryable after a single tick")
        XCTAssertEqual(aggregates.count, 1)
        XCTAssertEqual(aggregates.first?.tokens.input, 10)
    }

    // MARK: - 3. extractors run concurrently (wall time < serial time)

    func testConcurrentExtractors() async {
        // Three extractors each sleep for 100ms. Serial execution would take ~300ms.
        let sleepDuration: UInt64 = 100_000_000
        let extractors: [StubExtractor] = (0..<3).map { _ in
            StubExtractor(events: [
                TokenEvent(
                    provider: .kimi, model: "kimi-concurrent",
                    source: .kimiCode, sessionId: "concurrent",
                    timestamp: Date(),
                    tokens: TokenBreakdown(input: 1, output: 1),
                    sourceId: "tk:concurrent:\(UUID().uuidString)"
                )
            ], delayNanoseconds: sleepDuration)
        }
        let actor = RefreshActor(store: store, extractors: extractors)

        let start = Date()
        await actor.tickNow()
        let elapsed = Date().timeIntervalSince(start)

        // Concurrency proof: total wall time must be less than sum of individual sleeps.
        // Allow a small margin for scheduling overhead.
        let serialTime = Double(sleepDuration * UInt64(extractors.count)) / 1_000_000_000
        XCTAssertLessThan(elapsed, serialTime,
                          "extractors must run concurrently (elapsed \(elapsed)s < serial \(serialTime)s)")
    }

    // MARK: - 4. tick does not throw even when an extractor throws

    func testExtractorErrorLoggedAndTickSurvives() async {
        let goodExtractor = StubExtractor(events: [
            TokenEvent(
                provider: .codex, model: "codex-good",
                source: .codexCli, sessionId: "good",
                timestamp: Date(),
                tokens: TokenBreakdown(input: 7, output: 3),
                sourceId: "tk:good:1"
            )
        ])
        let badExtractor = StubExtractor(events: [], error: NSError(domain: "tk.test", code: 1, userInfo: nil))
        let actor = RefreshActor(store: store, extractors: [badExtractor, goodExtractor])

        await actor.tickNow()

        let aggregates = await store.fetchMonthAggregates()
        XCTAssertEqual(aggregates.count, 1)
        XCTAssertEqual(aggregates.first?.tokens.input, 7)
    }

    // MARK: - 5. calendar month reset — past events excluded from current month

    func testCalendarMonthReset() async throws {
        let extractor = StubExtractor(events: [])
        let actor = RefreshActor(store: store, extractors: [extractor])

        // Insert an event from January 2020 with a UNIQUE model name so it can
        // never collide with real data inserted by the 7 extractors during the tick.
        let pastDate = Date(timeIntervalSince1970: 1_577_836_800)  // 2020-01-01 UTC
        let pastModel = "tk-test-past-model-\(UUID().uuidString)"
        try await store.upsertEvent(TokenEvent(
            provider: .claude,
            model: pastModel,
            source: .claudeCode,
            sessionId: "sess-past",
            timestamp: pastDate,
            tokens: TokenBreakdown(input: 999_999_999, output: 888_888_888),
            sourceId: "tk-test-past-event-\(UUID().uuidString)"
        ))

        await actor.tickNow()

        let aggregates = await store.fetchMonthAggregates()
        let pastLeaked = aggregates.contains { $0.model == pastModel }
        XCTAssertFalse(pastLeaked,
                       "Past-month event (model=\(pastModel)) must not appear in current month aggregates")
    }

    // MARK: - 6. stable sourceId prevents duplicate inserts across ticks

    func testStableSourceIdDeduplicatesAcrossTicks() async {
        let extractor = StubExtractor(events: [
            TokenEvent(
                provider: .zai, model: "glm-4.6",
                source: .zaiApi, sessionId: "zai-api-monthly-snapshot",
                timestamp: Date(),
                tokens: TokenBreakdown(input: 100, output: 50),
                sourceId: "zai:api:snapshot:month"
            )
        ])
        let actor = RefreshActor(store: store, extractors: [extractor])

        await actor.tickNow()
        await actor.tickNow()

        let aggregates = await store.fetchMonthAggregates()
        XCTAssertEqual(aggregates.count, 1)
        XCTAssertEqual(aggregates.first?.tokens.input, 100, "stable sourceId must deduplicate repeated snapshots")
    }
}

// MARK: - Test helper

private actor StubExtractor: TokenExtractorProtocol {
    private let events: [TokenEvent]
    private let error: Error?
    private let delayNanoseconds: UInt64

    init(events: [TokenEvent], error: Error? = nil, delayNanoseconds: UInt64 = 0) {
        self.events = events
        self.error = error
        self.delayNanoseconds = delayNanoseconds
    }

    func extractAll() async throws -> [TokenEvent] {
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        if let error = error {
            throw error
        }
        return events
    }
}
