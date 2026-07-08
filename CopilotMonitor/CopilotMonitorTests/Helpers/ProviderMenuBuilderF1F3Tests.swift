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
        let menu = NSMenu()
        controller.appendF1TokenBlocks(to: menu, identifier: .nanoGpt, dayAggregates: [])
        let texts = extractText(from: menu)
        XCTAssertFalse(texts.contains(where: { $0.contains("Token 用量") }), "Should not render F1 block without F2b data; got: \(texts)")
    }

    func testF1BlockIsHiddenWhenDayAggregatesIsEmpty() async throws {
        let menu = NSMenu()
        controller.appendF1TokenBlocks(to: menu, identifier: .kimi, dayAggregates: [])
        let texts = extractText(from: menu)
        XCTAssertFalse(texts.contains(where: { $0.contains("Token 用量") }), "F1 block should be hidden when dayAggregates is empty")
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
