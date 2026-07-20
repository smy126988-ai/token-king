import XCTest
@testable import OpenCode_Bar

final class WidgetSnapshotMapperTests: XCTestCase {

    // MARK: - Additive schema compatibility

    func testDecodeLegacySnapshotWithoutAccountsOrMetricMetadata() throws {
        let json = """
        {
          "version": 1,
          "snapshotAt": "2026-07-18T08:00:00Z",
          "providers": [
            {
              "id": "claude",
              "displayName": "Claude",
              "kind": "quota",
              "primaryWindowId": "primary",
              "windows": [
                {
                  "id": "primary",
                  "label": "Primary",
                  "usedPercent": 25,
                  "resetsAt": null,
                  "used": 25,
                  "limit": 100
                }
              ],
              "spendUSD": null,
              "fetchedAt": null
            }
          ],
          "monthlyCost": null
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))

        XCTAssertNil(snapshot.providers[0].accounts)
        XCTAssertNil(snapshot.providers[0].compactDisplayName)
        XCTAssertNil(snapshot.providers[0].windows[0].windowSeconds)
        XCTAssertNil(snapshot.providers[0].windows[0].priority)
    }

    // MARK: - Multi-window quotaBased (Claude-style)

    /// Claude-style quotaBased with 5h + 7d windows. Verifies:
    /// - Three windows total (`primary` + `5h` + `7d`)
    /// - `kind == .quota`
    /// - `primaryWindowId` follows the explicit data-layer priority (5h first)
    /// - `used` and `limit` are populated on the primary window
    func testMapProviderWithMultipleWindows() {
        let details = DetailedUsage(
            fiveHourUsage: 30.0,
            fiveHourReset: Date(timeIntervalSinceNow: 18000),
            sevenDayUsage: 80.0,
            sevenDayReset: Date(timeIntervalSinceNow: 604800)
        )
        let result = ProviderResult(
            usage: .quotaBased(remaining: 25, entitlement: 100, overagePermitted: false),
            details: details
        )

        let snapshot = WidgetSnapshotMapper.makeSnapshot(
            providerResults: [.claude: result],
            monthlyCost: nil
        )

        XCTAssertEqual(snapshot.providers.count, 1)
        XCTAssertEqual(snapshot.version, 1)

        let p = snapshot.providers[0]
        XCTAssertEqual(p.id, "claude")
        XCTAssertEqual(p.compactDisplayName, "Claude")
        XCTAssertEqual(p.kind, .quota)
        XCTAssertEqual(p.windows.count, 3) // primary + 5h + 7d
        XCTAssertEqual(p.primaryWindowId, "5h")

        // Verify primary window carries the absolute used/limit derived from the
        // remaining/entitlement pair (100 - 25 = 75 used, 100 limit).
        let primary = p.windows.first(where: { $0.id == "primary" })
        XCTAssertEqual(primary?.used, 75)
        XCTAssertEqual(primary?.limit, 100)
    }

    /// The automatic widget must rank providers by their displayed metric,
    /// not by a synthetic aggregate that has no label or reset timestamp.
    func testProviderOrderingUsesRankedExplicitQuotaWindow() {
        let codex = ProviderResult(
            usage: .quotaBased(remaining: 29, entitlement: 100, overagePermitted: false),
            details: DetailedUsage(
                primaryReset: Date(timeIntervalSince1970: 604_800),
                codexPrimaryWindowLabel: "Weekly",
                codexPrimaryWindowHours: 168
            )
        )
        let kimi = ProviderResult(
            usage: .quotaBased(remaining: 24, entitlement: 100, overagePermitted: false),
            details: DetailedUsage(
                fiveHourUsage: 0,
                fiveHourReset: Date(timeIntervalSince1970: 18_000),
                sevenDayUsage: 76,
                sevenDayReset: Date(timeIntervalSince1970: 604_800)
            )
        )

        let snapshot = WidgetSnapshotMapper.makeSnapshot(
            providerResults: [.codex: codex, .kimiCN: kimi],
            monthlyCost: nil
        )

        XCTAssertEqual(snapshot.providers.map(\.id), ["codex", "kimi_cn"])
        let mappedKimi = snapshot.providers.first { $0.id == "kimi_cn" }
        XCTAssertEqual(mappedKimi?.primaryWindowId, "5h")
        XCTAssertEqual(mappedKimi?.compactDisplayName, "Kimi")
    }

    // MARK: - Pay-as-you-go

    /// Pay-as-you-go provider (usage kind). Verifies:
    /// - `kind == .usage`
    /// - Single window with `id = "primary"`
    /// - `spendUSD` is round-tripped from cost
    func testMapUsageProvider() {
        let reset = Date(timeIntervalSinceNow: 86400)
        let result = ProviderResult(
            usage: .payAsYouGo(utilization: 42.5, cost: 12.34, resetsAt: reset),
            details: nil
        )

        let snapshot = WidgetSnapshotMapper.makeSnapshot(
            providerResults: [.openRouter: result],
            monthlyCost: nil
        )

        XCTAssertEqual(snapshot.providers.count, 1)
        let p = snapshot.providers[0]
        XCTAssertEqual(p.id, "openrouter")
        XCTAssertEqual(p.kind, .usage)
        XCTAssertEqual(p.spendUSD, 12.34)
        XCTAssertEqual(p.primaryWindowId, "primary")
        XCTAssertEqual(p.windows.count, 1)
        XCTAssertEqual(p.windows[0].usedPercent, 42.5)
        XCTAssertEqual(p.windows[0].resetsAt, reset)
        XCTAssertNil(p.accounts)
    }

    // MARK: - Codex accounts

    func testCodexProviderPublishesFiveHourAndWeeklyWindowsAtTopLevel() throws {
        let fiveHourReset = Date(timeIntervalSince1970: 1_800)
        let weeklyReset = Date(timeIntervalSince1970: 604_800)
        let account = ProviderAccountResult(
            accountIndex: 0,
            accountId: "account-123",
            usage: .quotaBased(remaining: 72, entitlement: 100, overagePermitted: false),
            details: DetailedUsage(
                secondaryUsage: 64,
                secondaryReset: weeklyReset,
                primaryReset: fiveHourReset,
                codexPrimaryWindowLabel: "5 hours",
                codexPrimaryWindowHours: 5,
                codexSecondaryWindowLabel: "Weekly",
                codexSecondaryWindowHours: 168,
                planType: "Plus",
                email: "person@example.com"
            )
        )
        let result = ProviderResult(
            usage: account.usage,
            details: account.details,
            accounts: [account]
        )
        let fetchedAt = Date(timeIntervalSince1970: 500)

        let snapshot = WidgetSnapshotMapper.makeSnapshot(
            providerResults: [.codex: result],
            monthlyCost: nil,
            providerLastSuccessfulFetchAt: [.codex: fetchedAt],
            now: Date(timeIntervalSince1970: 600)
        )

        let provider = try XCTUnwrap(snapshot.providers.first)
        XCTAssertEqual(provider.primaryWindowId, "window-18000")
        XCTAssertEqual(provider.windows.map(\.id), ["window-18000", "window-604800"])
        XCTAssertEqual(provider.windows.map(\.label), ["5 hours", "Weekly"])
        XCTAssertEqual(provider.windows.map(\.resetsAt), [fiveHourReset, weeklyReset])
        XCTAssertEqual(provider.windows.map(\.windowSeconds), [18_000, 604_800])
        XCTAssertEqual(provider.windows.map(\.priority), [0, 1])
        XCTAssertEqual(provider.windows[0].usedPercent, 28, accuracy: 0.0001)
        XCTAssertEqual(provider.windows[1].usedPercent, 64, accuracy: 0.0001)

        let mappedAccount = try XCTUnwrap(provider.accounts?.first)
        XCTAssertEqual(provider.windows, mappedAccount.metrics)
        XCTAssertEqual(mappedAccount.plan, "Plus")
        XCTAssertEqual(mappedAccount.metrics.map(\.windowSeconds), [18_000, 604_800])
        let primaryUsedPercent = try XCTUnwrap(mappedAccount.metrics.first?.usedPercent)
        XCTAssertEqual(primaryUsedPercent, 28, accuracy: 0.0001)
        XCTAssertEqual(mappedAccount.status, .available)
        XCTAssertEqual(mappedAccount.fetchedAt, fetchedAt)
    }

    func testCodexProviderPublishesWeeklyOnlyWindowAsPrimary() throws {
        let weeklyReset = Date(timeIntervalSince1970: 604_800)
        let details = DetailedUsage(
            primaryReset: weeklyReset,
            codexPrimaryWindowLabel: "Weekly",
            codexPrimaryWindowHours: 168,
            planType: "Plus",
            email: "weekly@example.com"
        )
        let result = ProviderResult(
            usage: .quotaBased(remaining: 40, entitlement: 100, overagePermitted: false),
            details: details
        )

        let snapshot = WidgetSnapshotMapper.makeSnapshot(
            providerResults: [.codex: result],
            monthlyCost: nil
        )

        let provider = try XCTUnwrap(snapshot.providers.first)
        let weekly = try XCTUnwrap(provider.windows.first)
        XCTAssertEqual(provider.windows.count, 1)
        XCTAssertEqual(provider.primaryWindowId, "window-604800")
        XCTAssertEqual(weekly.id, "window-604800")
        XCTAssertEqual(weekly.label, "Weekly")
        XCTAssertEqual(weekly.usedPercent, 60, accuracy: 0.0001)
        XCTAssertEqual(weekly.resetsAt, weeklyReset)
        XCTAssertEqual(weekly.windowSeconds, 604_800)
        XCTAssertEqual(weekly.priority, 0)
    }

    func testCodexCachedResultWithCurrentProviderErrorIsStale() throws {
        let details = DetailedUsage(
            codexPrimaryWindowLabel: "Weekly",
            codexPrimaryWindowHours: 168,
            email: "cached@example.com"
        )
        let result = ProviderResult(
            usage: .quotaBased(remaining: 40, entitlement: 100, overagePermitted: false),
            details: details
        )
        let fetchedAt = Date(timeIntervalSince1970: 500)

        let snapshot = WidgetSnapshotMapper.makeSnapshot(
            providerResults: [.codex: result],
            monthlyCost: nil,
            providerErrors: [.codex: "Network unavailable"],
            providerLastSuccessfulFetchAt: [.codex: fetchedAt]
        )

        let account = try XCTUnwrap(snapshot.providers.first?.accounts?.first)
        XCTAssertEqual(account.status, .stale)
        XCTAssertEqual(account.fetchedAt, fetchedAt)
        let usedPercent = try XCTUnwrap(account.metrics.first?.usedPercent)
        XCTAssertEqual(usedPercent, 60, accuracy: 0.0001)
    }

    func testNonCodexProviderKeepsAggregateWindowAndDoesNotAttachAccounts() throws {
        let account = ProviderAccountResult(
            accountIndex: 0,
            accountId: "claude-account",
            usage: .quotaBased(remaining: 50, entitlement: 100, overagePermitted: false),
            details: DetailedUsage(email: "claude@example.com")
        )
        let result = ProviderResult(
            usage: account.usage,
            details: account.details,
            accounts: [account]
        )

        let snapshot = WidgetSnapshotMapper.makeSnapshot(
            providerResults: [.claude: result],
            monthlyCost: nil
        )

        let provider = try XCTUnwrap(snapshot.providers.first)
        let primary = try XCTUnwrap(provider.windows.first)
        XCTAssertNil(provider.accounts)
        XCTAssertEqual(provider.primaryWindowId, "primary")
        XCTAssertEqual(provider.windows.count, 1)
        XCTAssertEqual(primary.id, "primary")
        XCTAssertEqual(primary.label, "Primary")
        XCTAssertEqual(primary.usedPercent, 50, accuracy: 0.0001)
        XCTAssertEqual(primary.used, 50)
        XCTAssertEqual(primary.limit, 100)
        XCTAssertNil(primary.windowSeconds)
        XCTAssertEqual(primary.priority, 0)
    }

    func testContentEqualityTracksAccountContentButIgnoresFetchedAt() {
        let metric = UsageWindow(
            id: "window-18000",
            label: "5 hours",
            usedPercent: 25,
            resetsAt: nil,
            used: nil,
            limit: nil,
            windowSeconds: 18_000,
            priority: 0
        )
        let lhsAccount = ProviderAccountSnapshot(
            id: "codex-opaque",
            displayName: "p•••@example.com",
            plan: "Plus",
            status: .available,
            metrics: [metric],
            fetchedAt: Date(timeIntervalSince1970: 100)
        )
        let rhsAccount = ProviderAccountSnapshot(
            id: "codex-opaque",
            displayName: "p•••@example.com",
            plan: "Plus",
            status: .available,
            metrics: [metric],
            fetchedAt: Date(timeIntervalSince1970: 200)
        )
        let changedAccount = ProviderAccountSnapshot(
            id: "codex-opaque",
            displayName: "p•••@example.com",
            plan: "Plus",
            status: .unavailable,
            metrics: [metric],
            fetchedAt: Date(timeIntervalSince1970: 200)
        )
        let lhs = providerSnapshot(accounts: [lhsAccount])
        let rhs = providerSnapshot(accounts: [rhsAccount])
        let changed = providerSnapshot(accounts: [changedAccount])

        XCTAssertTrue(lhs.isContentEqual(to: rhs))
        XCTAssertFalse(lhs.isContentEqual(to: changed))
    }

    // MARK: - Empty results

    /// Empty provider dictionary produces a valid but empty snapshot.
    func testEmptyResults() {
        let snapshot = WidgetSnapshotMapper.makeSnapshot(
            providerResults: [:],
            monthlyCost: nil
        )
        XCTAssertEqual(snapshot.providers.count, 0)
        XCTAssertEqual(snapshot.version, 1)
    }

    private func providerSnapshot(accounts: [ProviderAccountSnapshot]) -> ProviderSnapshot {
        ProviderSnapshot(
            id: "codex",
            displayName: "ChatGPT",
            kind: .quota,
            primaryWindowId: nil,
            windows: [],
            spendUSD: nil,
            fetchedAt: nil,
            accounts: accounts
        )
    }
}
