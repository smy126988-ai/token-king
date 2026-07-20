import XCTest
@testable import OpenCode_Bar

/// F1: day-level aggregation. Reuses F2b's real SQLite store (no mock).
/// All tests use a fresh temp DB to isolate from each other.
final class TokenUsageStoreDayAggregatesTests: XCTestCase {

    private var store: TokenUsageStore!
    private var dbPath: String!

    override func setUp() async throws {
        dbPath = "\(NSTemporaryDirectory())/day-agg-test-\(UUID().uuidString).sqlite"
        store = TokenUsageStore(dbPath: dbPath)
    }

    override func tearDown() async throws {
        try? await store.close()
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - refreshDayAggregates

    func testRefreshDayAggregatesAggregatesSingleProviderSingleModelSingleDay() async throws {
        let today = Date()
        let ym = await store.currentYearMonth(for: today)
        try await store.upsertEvent(await makeEvent(provider: "kimi", model: "kimi-k2.5", day: today, input: 100, output: 50))
        try await store.refreshDayAggregates()
        let rows = await store.fetchDayAggregates(provider: "kimi", yearMonth: ym)
        XCTAssertEqual(rows.count, 1)
        let expectedDay = ym + "-" + Self.dayComponent(today)
        XCTAssertEqual(rows.first?.day, expectedDay)
        XCTAssertEqual(rows.first?.tokens.input, 100)
        XCTAssertEqual(rows.first?.tokens.output, 50)
    }

    func testRefreshDayAggregatesAggregatesMultipleDays() async throws {
        let day1 = Self.date(year: 2026, month: 7, day: 1)
        let day2 = Self.date(year: 2026, month: 7, day: 2)
        try await store.upsertEvent(await makeEvent(provider: "claude", model: "claude-sonnet-4-5", day: day1, input: 100, output: 50))
        try await store.upsertEvent(await makeEvent(provider: "claude", model: "claude-sonnet-4-5", day: day2, input: 200, output: 100))
        try await store.refreshDayAggregates(for: day1)
        try await store.refreshDayAggregates(for: day2)
        let rows = await store.fetchDayAggregates(provider: "claude", yearMonth: "2026-07")
        XCTAssertEqual(rows.count, 2)
    }

    func testRefreshDayAggregatesForMonthRepairsAllHistoricalDays() async throws {
        let day1 = Self.date(year: 2026, month: 7, day: 1)
        let day2 = Self.date(year: 2026, month: 7, day: 18)
        try await store.upsertEvent(await makeEvent(provider: "kimi", model: "kimi-k2.6", day: day1, input: 100))
        try await store.upsertEvent(await makeEvent(provider: "kimi", model: "kimi-k2.6", day: day2, input: 200))

        try await store.refreshDayAggregates(forYearMonth: "2026-07")

        let rows = await store.fetchDayAggregates(provider: "kimi", yearMonth: "2026-07")
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map { $0.tokens.input }.reduce(0, +), 300)
    }

    func testRefreshDayAggregatesSeparatesProvidersAndModels() async throws {
        let today = Date()
        try await store.upsertEvent(await makeEvent(provider: "kimi", model: "kimi-k2.5", day: today, input: 100))
        try await store.upsertEvent(await makeEvent(provider: "kimi", model: "kimi-k2.6", day: today, input: 200))
        try await store.upsertEvent(await makeEvent(provider: "claude", model: "claude-sonnet-4-5", day: today, input: 300))
        try await store.refreshDayAggregates()
        let rows = await store.fetchDayAggregates(yearMonth: await store.currentYearMonth(for: today))
        XCTAssertEqual(rows.count, 3, "Expected 3 distinct (provider, model, day) rows")
    }

    func testRefreshDayAggregatesIsIdempotent() async throws {
        let today = Date()
        try await store.upsertEvent(await makeEvent(provider: "kimi", model: "kimi-k2.5", day: today, input: 100))
        try await store.refreshDayAggregates()
        try await store.refreshDayAggregates()
        let rows = await store.fetchDayAggregates(provider: "kimi", yearMonth: await store.currentYearMonth(for: today))
        XCTAssertEqual(rows.first?.tokens.input, 100, "Refresh should not double-count")
    }

    // MARK: - fetchDayAggregates

    func testFetchDayAggregatesEmptyDatabaseReturnsEmpty() async {
        let rows = await store.fetchDayAggregates(yearMonth: "2026-07")
        XCTAssertTrue(rows.isEmpty)
    }

    func testFetchDayAggregatesFiltersByProvider() async throws {
        let today = Date()
        try await store.upsertEvent(await makeEvent(provider: "kimi", model: "kimi-k2.5", day: today, input: 100))
        try await store.upsertEvent(await makeEvent(provider: "claude", model: "claude-sonnet-4-5", day: today, input: 200))
        try await store.refreshDayAggregates()
        let kimiRows = await store.fetchDayAggregates(provider: "kimi", yearMonth: await store.currentYearMonth(for: today))
        XCTAssertEqual(kimiRows.count, 1)
        XCTAssertEqual(kimiRows.first?.provider, "kimi")
    }

    // MARK: - fetchMonthTotalTokens

    func testFetchMonthTotalTokensSumsAllProvidersAndModels() async throws {
        let today = Date()
        try await store.upsertEvent(await makeEvent(provider: "kimi", model: "kimi-k2.5", day: today, input: 100, output: 50))
        try await store.upsertEvent(await makeEvent(provider: "claude", model: "claude-sonnet-4-5", day: today, input: 200, output: 100))
        try await store.refreshDayAggregates()
        let total = await store.fetchMonthTotalTokens(yearMonth: await store.currentYearMonth(for: today))
        XCTAssertEqual(total.input, 300)
        XCTAssertEqual(total.output, 150)
        XCTAssertEqual(total.total, 450)
    }

    func testFetchMonthTotalTokensEmptyDatabaseReturnsZero() async {
        let total = await store.fetchMonthTotalTokens(yearMonth: "2026-07")
        XCTAssertEqual(total, TokenBreakdown.zero)
    }

    // MARK: - Helpers

    private func makeEvent(provider: String, model: String, day: Date, input: Int = 0, output: Int = 0) async -> TokenEvent {
        let dayString = await store.currentYearMonth(for: day) + "-" + Self.dayComponent(day)
        return TokenEvent(
            provider: Provider(rawValue: provider) ?? .nanoGpt,
            model: model,
            source: .opencode,
            sessionId: "test-\(UUID().uuidString)",
            timestamp: day,
            tokens: TokenBreakdown(input: input, output: output),
            sourceId: "test:\(dayString):\(provider):\(model):\(UUID().uuidString)"
        )
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day; comps.hour = 12
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.utc
        return cal.date(from: comps) ?? Date(timeIntervalSince1970: 0)
    }

    private static func dayComponent(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.timeZone = TimeZone.utc
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "dd"
        return fmt.string(from: date)
    }
}
