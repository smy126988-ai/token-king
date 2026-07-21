import XCTest
@testable import OpenCode_Bar

final class ProviderSelectionTests: XCTestCase {
    func testNoProvidersReturnsAutomaticEmptyResult() {
        let snapshot = makeSnapshot(providers: [])

        let result = ProviderSelectionResolver.selectProvider(snapshot, selectedProviderId: nil)

        XCTAssertNil(result.provider)
        XCTAssertTrue(result.isAutomatic)
        XCTAssertNil(result.selectedProviderId)
    }

    func testAutomaticSelectionChoosesHighestUsageProvider() throws {
        let snapshot = makeSnapshot(providers: [
            makeProvider(id: "claude", usedPercent: 40),
            makeProvider(id: "codex", usedPercent: 85),
            makeProvider(id: "kimi", usedPercent: 60)
        ])

        let result = ProviderSelectionResolver.selectProvider(snapshot, selectedProviderId: nil)

        XCTAssertEqual(try XCTUnwrap(result.provider).id, "codex")
        XCTAssertTrue(result.isAutomatic)
    }

    func testExplicitSelectionStaysOnRequestedProvider() throws {
        let snapshot = makeSnapshot(providers: [
            makeProvider(id: "claude", usedPercent: 40),
            makeProvider(id: "codex", usedPercent: 85)
        ])

        let result = ProviderSelectionResolver.selectProvider(snapshot, selectedProviderId: "claude")

        XCTAssertEqual(try XCTUnwrap(result.provider).id, "claude")
        XCTAssertEqual(result.selectedProviderId, "claude")
        XCTAssertFalse(result.isAutomatic)
    }

    func testMissingExplicitSelectionDoesNotFallBackToAnotherProvider() {
        let snapshot = makeSnapshot(providers: [
            makeProvider(id: "codex", usedPercent: 100)
        ])

        let result = ProviderSelectionResolver.selectProvider(snapshot, selectedProviderId: "removed")

        XCTAssertNil(result.provider)
        XCTAssertEqual(result.selectedProviderId, "removed")
        XCTAssertFalse(result.isAutomatic)
    }

    func testAutomaticSelectionSkipsUnavailableUsedUpProvider() throws {
        let snapshot = makeSnapshot(providers: [
            makeProvider(id: "codex", usedPercent: 100, status: .unavailable),
            makeProvider(id: "claude", usedPercent: 75)
        ])

        let result = ProviderSelectionResolver.selectProvider(snapshot, selectedProviderId: nil)

        XCTAssertEqual(try XCTUnwrap(result.provider).id, "claude")
    }

    func testAutomaticSelectionCanChooseAvailableQuotaAtFullUsage() throws {
        let snapshot = makeSnapshot(providers: [
            makeProvider(id: "codex", usedPercent: 100),
            makeProvider(id: "claude", usedPercent: 25)
        ])

        let result = ProviderSelectionResolver.selectProvider(snapshot, selectedProviderId: nil)

        XCTAssertEqual(try XCTUnwrap(result.provider).id, "codex")
    }

    private func makeSnapshot(providers: [ProviderSnapshot]) -> WidgetSnapshot {
        WidgetSnapshot(
            version: 1,
            snapshotAt: Date(timeIntervalSince1970: 1_000_000),
            providers: providers,
            monthlyCost: nil
        )
    }

    private func makeProvider(
        id: String,
        usedPercent: Double,
        status: WidgetDataStatus? = .available
    ) -> ProviderSnapshot {
        ProviderSnapshot(
            id: id,
            displayName: id.capitalized,
            kind: .quota,
            primaryWindowId: "primary",
            windows: [
                UsageWindow(
                    id: "primary",
                    label: "Primary",
                    usedPercent: usedPercent,
                    resetsAt: nil,
                    used: nil,
                    limit: nil
                )
            ],
            spendUSD: nil,
            fetchedAt: nil,
            status: status
        )
    }
}
