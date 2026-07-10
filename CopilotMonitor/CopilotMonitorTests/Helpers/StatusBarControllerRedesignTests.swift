import XCTest
import AppKit
@testable import OpenCode_Bar

/// F4 redesign: tests for the top-level per-period token submenu and the
/// per-provider quota history submenu. Decoupled from actor / store I/O so
/// every test passes precomputed data directly into the synchronous view
/// builders.
@MainActor
final class StatusBarControllerRedesignTests: XCTestCase {

    private var controller: StatusBarController!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "redesign-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        controller = StatusBarController(options: .testing(userDefaults: defaults))
    }

    // MARK: - Top-level per-provider submenu

    func testPerProviderTokenSubmenuRendersInputOutputCacheTotal() {
        let totals = [
            PerPeriodTokenAggregator.ProviderTotal(
                providerRaw: "kimi", displayName: "Kimi",
                input: 100, output: 50, cacheRead: 30, cacheWrite: 20, reasoning: 0
            ),
            PerPeriodTokenAggregator.ProviderTotal(
                providerRaw: "claude", displayName: "Claude",
                input: 200, output: 100, cacheRead: 60, cacheWrite: 40, reasoning: 0
            ),
        ]
        let menu = controller.buildPerProviderTokenSubmenu(period: .today, totals: totals)
        let texts = extractText(from: menu)
        // 2 providers × (1 header + 4 field rows + 1 trailing separator) = 12 items
        XCTAssertEqual(menu.items.count, 12, "Expected 12 items; got \(menu.items.count)")
        XCTAssertTrue(texts.contains(where: { $0.contains("Kimi") }), "Kimi header missing in \(texts)")
        XCTAssertTrue(texts.contains(where: { $0.contains("Input:") && $0.contains("100") }), "Kimi Input:100 row missing in \(texts)")
        XCTAssertTrue(texts.contains(where: { $0.contains("Cache:") && $0.contains("50") }), "Kimi Cache: 30+20=50 row missing in \(texts)")
        XCTAssertTrue(texts.contains(where: { $0.contains("Claude") }), "Claude header missing in \(texts)")
        // Billable total excludes cacheRead (free/cheap cache hits):
        // Claude: input(200) + output(100) + cacheWrite(40) = 340
        // Kimi:   input(100) + output(50)  + cacheWrite(20) = 170
        XCTAssertTrue(texts.contains(where: { $0.contains("Total:") && $0.contains("340") }), "Claude billable Total:340 row missing in \(texts)")
        XCTAssertTrue(texts.contains(where: { $0.contains("Total:") && $0.contains("170") }), "Kimi billable Total:170 row missing in \(texts)")
    }

    func testPerProviderTokenSubmenuEmptyReturnsEmpty() {
        let menu = controller.buildPerProviderTokenSubmenu(period: .today, totals: [])
        XCTAssertTrue(menu.items.isEmpty, "Empty totals should produce empty menu (caller hides)")
    }

    func testPerProviderTokenSubmenuTotalExcludesCacheRead() {
        // Cache row shows cacheRead+cacheWrite (separately tracked for visibility),
        // but Total: row is billable — cache hits are free/cheap, not "tokens spent".
        let totals = [
            PerPeriodTokenAggregator.ProviderTotal(
                providerRaw: "kimi", displayName: "Kimi",
                input: 10, output: 5, cacheRead: 999_999, cacheWrite: 2, reasoning: 1
            ),
        ]
        let menu = controller.buildPerProviderTokenSubmenu(period: .today, totals: totals)
        let texts = extractText(from: menu)
        // Billable = 10 + 5 + 2 + 1 = 18 (NOT 1000017)
        XCTAssertTrue(texts.contains(where: { $0.contains("Total:") && $0.contains("18") }), "Submenu Total: must be billable, excluding cacheRead; got \(texts)")
        // Cache row still shows cacheRead+cacheWrite (= 1000001, formatted as "100.0万")
        XCTAssertTrue(texts.contains(where: { $0.contains("Cache:") }), "Cache row should still exist for visibility; got \(texts)")
        XCTAssertFalse(texts.contains(where: { $0.contains("Total:") && $0.contains("100") }), "Total: row must NOT include the cache hits; got \(texts)")
    }

    func testPerProviderTokenSubmenuSumsCacheReadAndCacheWrite() {
        // Cache row should sum cacheRead + cacheWrite (50+20=70)
        let totals = [
            PerPeriodTokenAggregator.ProviderTotal(
                providerRaw: "kimi", displayName: "Kimi",
                input: 1, output: 2, cacheRead: 50, cacheWrite: 20, reasoning: 0
            ),
        ]
        let menu = controller.buildPerProviderTokenSubmenu(period: .week, totals: totals)
        let texts = extractText(from: menu)
        XCTAssertTrue(texts.contains(where: { $0.contains("Cache:") && $0.contains("70") }), "Cache row should sum cacheRead+cacheWrite; got \(texts)")
    }

    func testPerProviderTokenSubmenuIncludesReasoningInBillableTotal() {
        let totals = [
            PerPeriodTokenAggregator.ProviderTotal(
                providerRaw: "kimi", displayName: "Kimi",
                input: 100, output: 50, cacheRead: 30, cacheWrite: 20, reasoning: 7
            ),
        ]
        let menu = controller.buildPerProviderTokenSubmenu(period: .month, totals: totals)
        let texts = extractText(from: menu)
        // Billable = input(100) + output(50) + cacheWrite(20) + reasoning(7) = 177.
        // cacheRead(30) is excluded because cache hits are free/cheap.
        XCTAssertTrue(texts.contains(where: { $0.contains("Total:") && $0.contains("177") }), "Billable Total should include reasoning but exclude cacheRead; got \(texts)")
    }

    // MARK: - Quota history submenu

    func testQuotaHistorySubmenuRendersAllSnapshots() {
        let snapshots = [
            QuotaSnapshot(provider: "kimi", window: "5h", usagePercent: 35, resetAt: nil, snapshotTs: Date()),
            QuotaSnapshot(provider: "kimi", window: "5h", usagePercent: 12, resetAt: nil, snapshotTs: Date(timeIntervalSinceNow: -3600)),
        ]
        let menu = controller.createProviderQuotaHistorySubmenu(
            title: "每日记录", symbolName: "clock.arrow.circlepath", snapshots: snapshots
        )
        XCTAssertEqual(menu.items.count, 2)
        let texts = extractText(from: menu)
        XCTAssertTrue(texts.contains(where: { $0.contains("35%") }), "35% row missing in \(texts)")
        XCTAssertTrue(texts.contains(where: { $0.contains("12%") }), "12% row missing in \(texts)")
        XCTAssertTrue(texts.contains(where: { $0.contains("5h:") }), "5h: label missing in \(texts)")
    }

    func testQuotaHistorySubmenuEmptyShowsPlaceholder() {
        let menu = controller.createProviderQuotaHistorySubmenu(
            title: "每日记录", symbolName: "clock.arrow.circlepath", snapshots: []
        )
        XCTAssertEqual(menu.items.count, 1, "Empty should render a placeholder, not hide")
        let texts = extractText(from: menu)
        XCTAssertTrue(texts.contains(where: { $0.contains("暂无记录") }), "Empty placeholder missing in \(texts)")
    }

    func testQuotaHistorySubmenuRendersResetTimeInLocalTimezone() {
        // reset = 2026-07-09 14:30:00 UTC; in any local zone, should render HH:mm
        let resetUTC = Date(timeIntervalSince1970: 1_778_525_400)  // arbitrary
        let snapshots = [
            QuotaSnapshot(provider: "kimi", window: "5h", usagePercent: 50, resetAt: resetUTC, snapshotTs: Date()),
        ]
        let menu = controller.createProviderQuotaHistorySubmenu(
            title: "每日记录", symbolName: "clock.arrow.circlepath", snapshots: snapshots
        )
        let texts = extractText(from: menu)
        XCTAssertTrue(texts.contains(where: { $0.contains("reset") }), "Reset label missing in \(texts)")
    }

    // MARK: - Helpers

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
        var results: [String] = []
        if let textField = view as? NSTextField {
            results.append(textField.stringValue)
        }
        for subview in view.subviews {
            results.append(contentsOf: extractStrings(from: subview))
        }
        return results
    }
}
