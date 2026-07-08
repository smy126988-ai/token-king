import XCTest
@testable import OpenCode_Bar

/// F1: RefreshActor must call refreshDayAggregates in addition to refreshMonthAggregates.
/// Uses a no-op stub extractor to avoid touching real files.
final class RefreshActorDayAggregatesTests: XCTestCase {

    func testTickCallsRefreshDayAggregates() async throws {
        let dbPath = "\(NSTemporaryDirectory())/refresh-day-test-\(UUID().uuidString).sqlite"
        let store = TokenUsageStore(dbPath: dbPath)
        let actor = RefreshActor(
            store: store,
            extractors: [StubExtractor(event: makeEvent())]
        )

        await actor.tickNow()

        let ym = await store.currentYearMonth()
        let day = await store.fetchDayAggregates(yearMonth: ym)
        XCTAssertFalse(day.isEmpty, "RefreshActor.tick should call refreshDayAggregates and produce at least one day_aggregates row")
        try? await store.close()
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    private func makeEvent() -> TokenEvent {
        TokenEvent(
            provider: .kimi,
            model: "kimi-k2.5",
            source: .opencode,
            sessionId: "test",
            timestamp: Date(),
            tokens: TokenBreakdown(input: 100, output: 50),
            sourceId: "test:\(UUID().uuidString)"
        )
    }
}

private struct StubExtractor: TokenExtractorProtocol {
    let event: TokenEvent
    func extractAll() async throws -> [TokenEvent] { [event] }
}
