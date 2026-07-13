import XCTest
import AppKit
@testable import OpenCode_Bar

/// F1 / F3: per-provider detail submenu blocks.
/// Tests call the helper methods directly with pre-fetched data (decouples
/// from async data fetch).
@MainActor
final class ProviderMenuBuilderF1F3Tests: XCTestCase {

    private var store: TokenUsageStore!
    private var dbPath: String!
    private var controller: StatusBarController!
    private var suiteName: String!

    override func setUp() async throws {
        dbPath = "\(NSTemporaryDirectory())/f1f3-test-\(UUID().uuidString).sqlite"
        store = TokenUsageStore(dbPath: dbPath)
        suiteName = "f1f3-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        controller = StatusBarController(options: .testing(userDefaults: defaults))
    }

    override func tearDown() async throws {
        try? await store.close()
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    // MARK: - F1 monthly token block

    func testF1MonthlyTokenBlockRendersForProviderWithF2bData() async throws {
        try await seedKimiEvent()
        let dayAggregates = await store.fetchDayAggregates(provider: "kimi", yearMonth: store.currentYearMonth())
        XCTAssertFalse(dayAggregates.isEmpty)
        let menu = NSMenu()
        controller.appendF1TokenBlocks(to: menu, identifier: .kimi, dayAggregates: dayAggregates)
        let texts = extractText(from: menu)
        XCTAssertTrue(texts.contains(where: { $0.contains("Token 用量 (本月)") }), "F1 monthly header missing in \(texts)")
    }

    func testF1DailyTokenBlockRendersAfterMonthly() async throws {
        try await seedKimiEvent()
        let dayAggregates = await store.fetchDayAggregates(provider: "kimi", yearMonth: store.currentYearMonth())
        let menu = NSMenu()
        controller.appendF1TokenBlocks(to: menu, identifier: .kimi, dayAggregates: dayAggregates)
        let texts = extractText(from: menu)
        XCTAssertTrue(texts.contains(where: { $0.contains("Token 用量 (本月每日)") }), "F1 daily header missing in \(texts)")
    }

    func testF1BlockIsHiddenForProviderWithoutF2bData() async throws {
        // .openRouter is NOT a F2b provider (no F2b Provider enum case).
        // Pass non-empty dayAggregates so the empty-aggregates guard passes
        // and only the f2bProviderRaw(for:) guard can hide the block.
        let menu = NSMenu()
        let fakeAggregates = [
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-07-08",
                         tokens: TokenBreakdown(input: 100))
        ]
        controller.appendF1TokenBlocks(to: menu, identifier: .openRouter, dayAggregates: fakeAggregates)
        let texts = extractText(from: menu)
        XCTAssertFalse(texts.contains(where: { $0.contains("Token 用量") }), "Should not render F1 block without F2b data; got: \(texts)")
    }

    func testF1BlockIsHiddenWhenDayAggregatesIsEmpty() async throws {
        let menu = NSMenu()
        controller.appendF1TokenBlocks(to: menu, identifier: .kimi, dayAggregates: [])
        let texts = extractText(from: menu)
        XCTAssertFalse(texts.contains(where: { $0.contains("Token 用量") }), "F1 block should be hidden when dayAggregates is empty")
    }

    /// F2b Kimi CN split: F1 block must render for .kimiCN when dayAggregates
    /// contains rows with provider="kimiCN". Previously the helper used
    /// `f2bProviderRaw` which collapsed both into "kimi" and missed kimiCN rows.
    func testF1BlockRendersForKimiCNWithMatchingAggregates() {
        let aggregates = [
            DayAggregate(provider: "kimiCN", model: "kimi-k2.5", day: "2026-07-08", tokens: TokenBreakdown(input: 100))
        ]
        let menu = NSMenu()
        controller.appendF1TokenBlocks(to: menu, identifier: .kimiCN, dayAggregates: aggregates)
        let texts = extractText(from: menu)
        XCTAssertTrue(texts.contains(where: { $0.contains("Token 用量 (本月)") }), "F1 monthly header missing for .kimiCN; got \(texts)")
        XCTAssertTrue(texts.contains(where: { $0.contains("Token 用量 (本月每日)") }), "F1 daily header missing for .kimiCN; got \(texts)")
    }

    /// F2b Kimi CN split: F1 block must NOT render for .kimiCN if aggregates
    /// only have provider="kimi" rows (Kimi Global events). This documents the
    /// intentional split — the two buckets are kept separate.
    func testF1BlockHiddenForKimiCNWithKimiGlobalAggregates() {
        let aggregates = [
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-07-08", tokens: TokenBreakdown(input: 100))
        ]
        let menu = NSMenu()
        controller.appendF1TokenBlocks(to: menu, identifier: .kimiCN, dayAggregates: aggregates)
        let texts = extractText(from: menu)
        XCTAssertFalse(texts.contains(where: { $0.contains("Token 用量") }), "F1 block should be hidden for .kimiCN when aggregates are only kimi (Global); got \(texts)")
    }

    func testF1MonthlyAndDailyAggregateByModelAndDay() {
        // 4 rows: 2 models on day1, 2 models on day2
        // - Monthly should show 2 rows (one per model, summed across days).
        //   The implementation renders `tokens.total` (sum of all 5 fields),
        //   so kimi-k2.5 monthly = (100+50) + (200+100) = 450
        //   and kimi-k2.6 monthly = (300+150) + (400+200) = 1050 → "1.1k"
        // - Daily should show 2 rows (one per day, summed across models).
        //   2026-07-08 daily = (100+50) + (300+150) = 600
        //   2026-07-09 daily = (200+100) + (400+200) = 900
        let aggregates = [
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-07-08", tokens: TokenBreakdown(input: 100, output: 50)),
            DayAggregate(provider: "kimi", model: "kimi-k2.5", day: "2026-07-09", tokens: TokenBreakdown(input: 200, output: 100)),
            DayAggregate(provider: "kimi", model: "kimi-k2.6", day: "2026-07-08", tokens: TokenBreakdown(input: 300, output: 150)),
            DayAggregate(provider: "kimi", model: "kimi-k2.6", day: "2026-07-09", tokens: TokenBreakdown(input: 400, output: 200))
        ]
        let menu = NSMenu()
        controller.appendF1TokenBlocks(to: menu, identifier: .kimi, dayAggregates: aggregates)
        let texts = extractText(from: menu)
        let itemCount = menu.items.count

        // Expected items: 1 monthly header + 2 monthly rows + 1 separator + 1 daily header + 2 daily rows = 7 items
        XCTAssertEqual(itemCount, 7, "Expected 7 items (1 monthly header + 2 monthly rows + 1 sep + 1 daily header + 2 daily rows); got \(itemCount)")

        // Monthly per-model sums (total tokens, formatted)
        XCTAssertTrue(texts.contains(where: { $0.contains("kimi-k2.5") && $0.contains("450") }), "kimi-k2.5 monthly should sum 100+50+200+100=450 total tokens; got \(texts)")
        XCTAssertTrue(texts.contains(where: { $0.contains("kimi-k2.6") && $0.contains("1.1k") }), "kimi-k2.6 monthly should sum 300+150+400+200=1050 → format '1.1k'; got \(texts)")

        // Daily per-day sums
        XCTAssertTrue(texts.contains(where: { $0.contains("2026-07-08") && $0.contains("600") }), "2026-07-08 daily should sum 100+50+300+150=600 total; got \(texts)")
        XCTAssertTrue(texts.contains(where: { $0.contains("2026-07-09") && $0.contains("900") }), "2026-07-09 daily should sum 200+100+400+200=900 total; got \(texts)")
    }

    // MARK: - F3 5h + weekly block

    func testF3BlockRenders5hAndWeekly() {
        let details = DetailedUsage(
            fiveHourUsage: 35, fiveHourReset: Date(),
            sevenDayUsage: 54, sevenDayReset: nil
        )
        let menu = NSMenu()
        controller.appendF3UsageRecordBlock(to: menu, details: details)
        let texts = extractText(from: menu)
        XCTAssertTrue(texts.contains(where: { $0.contains("使用记录") }), "F3 header missing in \(texts)")
        XCTAssertTrue(texts.contains(where: { $0.contains("5h:") }), "5h row missing in \(texts)")
        XCTAssertTrue(texts.contains(where: { $0.contains("本周：") }), "Weekly row missing in \(texts)")
    }

    func testF3BlockIsHiddenForProviderWithout5hOr7d() {
        let details = DetailedUsage()
        let menu = NSMenu()
        controller.appendF3UsageRecordBlock(to: menu, details: details)
        let texts = extractText(from: menu)
        XCTAssertFalse(texts.contains(where: { $0.contains("使用记录") }), "F3 block should be hidden when no 5h/7d data; got: \(texts)")
    }

    // MARK: - Helpers

    private func seedKimiEvent() async throws {
        let today = Date()
        try await store.upsertEvent(TokenEvent(
            provider: .kimi, model: "kimi-k2.5", source: .opencode,
            sessionId: "t1", timestamp: today,
            tokens: TokenBreakdown(input: 100, output: 50),
            sourceId: "test:t1:kimi:k2.5:\(UUID().uuidString)"
        ))
        try await store.refreshMonthAggregates()
        try await store.refreshDayAggregates()
    }

    private func extractText(from menu: NSMenu) -> [String] {
        var results: [String] = []
        for item in menu.items {
            if let view = item.view {
                results.append(contentsOf: extractStrings(from: view))
            }
        }
        return results
    }

    private func extractStrings(from view: NSView) -> [String] {
        var results = [String]()
        if let textField = view as? NSTextField {
            results.append(textField.stringValue)
        }
        for subview in view.subviews {
            results.append(contentsOf: extractStrings(from: subview))
        }
        return results
    }
}
