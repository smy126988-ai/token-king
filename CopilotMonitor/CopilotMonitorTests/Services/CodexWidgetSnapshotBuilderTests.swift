import XCTest
@testable import OpenCode_Bar

final class CodexWidgetSnapshotBuilderTests: XCTestCase {
    func testOrdersFiveHourBeforeWeeklyAndAssignsPriorities() throws {
        let result = makeResult(
            primaryUsed: 32,
            primaryHours: 5,
            secondaryUsed: 68,
            secondaryHours: 168
        )

        let account = try XCTUnwrap(CodexWidgetSnapshotBuilder.makeAccounts(from: result).first)

        XCTAssertEqual(account.metrics.map(\.windowSeconds), [18_000, 604_800])
        XCTAssertEqual(account.metrics.map(\.priority), [0, 1])
        XCTAssertEqual(account.metrics.map(\.usedPercent), [32, 68])
    }

    func testWeeklyOnlyBecomesFirstMetric() throws {
        let result = makeResult(
            primaryUsed: 44,
            primaryLabel: "Weekly",
            primaryHours: 168,
            secondaryUsed: nil,
            secondaryHours: nil
        )

        let account = try XCTUnwrap(CodexWidgetSnapshotBuilder.makeAccounts(from: result).first)

        XCTAssertEqual(account.metrics.count, 1)
        XCTAssertEqual(account.metrics[0].label, "Weekly")
        XCTAssertEqual(account.metrics[0].priority, 0)
    }

    func testExcludesSparkWindows() throws {
        let details = DetailedUsage(
            secondaryUsage: 61,
            codexPrimaryWindowLabel: "5 hours",
            codexPrimaryWindowHours: 5,
            codexSecondaryWindowLabel: "Weekly",
            codexSecondaryWindowHours: 168,
            sparkUsage: 91,
            sparkSecondaryUsage: 83,
            sparkPrimaryWindowLabel: "Spark 5 hours",
            sparkPrimaryWindowHours: 5,
            sparkSecondaryWindowLabel: "Spark weekly",
            sparkSecondaryWindowHours: 168,
            email: "person@example.com"
        )
        let result = ProviderResult(
            usage: Self.quotaUsage(usedPercent: 25),
            details: details,
            accounts: [
                ProviderAccountResult(
                    accountIndex: 0,
                    accountId: "account-123",
                    usage: Self.quotaUsage(usedPercent: 25),
                    details: details
                )
            ]
        )

        let account = try XCTUnwrap(CodexWidgetSnapshotBuilder.makeAccounts(from: result).first)

        XCTAssertEqual(account.metrics.count, 2)
        XCTAssertFalse(account.metrics.contains { $0.label.localizedCaseInsensitiveContains("spark") })
        XCTAssertFalse(account.metrics.contains { $0.usedPercent == 91 || $0.usedPercent == 83 })
    }

    func testOpaqueIdAndDisplayNameDoNotExposeRawEmail() throws {
        let email = "person.long@example.com"
        let result = makeResult(primaryUsed: 20, email: email)

        let account = try XCTUnwrap(CodexWidgetSnapshotBuilder.makeAccounts(from: result).first)

        XCTAssertFalse(account.id.localizedCaseInsensitiveContains(email))
        XCTAssertFalse(account.displayName.localizedCaseInsensitiveContains("person.long"))
        XCTAssertEqual(account.displayName, "p•••@example.com")
        XCTAssertTrue(account.id.hasPrefix("codex-"))
    }

    func testFiltersInvalidPercentagesAndDuplicateDurations() throws {
        let invalidDetails = DetailedUsage(
            secondaryUsage: .infinity,
            codexPrimaryWindowLabel: "5 hours",
            codexPrimaryWindowHours: 5,
            codexSecondaryWindowLabel: "Weekly",
            codexSecondaryWindowHours: 168,
            email: "invalid@example.com"
        )
        let invalid = ProviderResult(
            usage: .payAsYouGo(utilization: -1, cost: nil, resetsAt: nil),
            details: invalidDetails
        )
        let duplicate = makeResult(
            primaryUsed: 20,
            primaryHours: 5,
            secondaryUsed: 40,
            secondaryHours: 5
        )

        let invalidAccount = try XCTUnwrap(CodexWidgetSnapshotBuilder.makeAccounts(from: invalid).first)
        let duplicateAccount = try XCTUnwrap(CodexWidgetSnapshotBuilder.makeAccounts(from: duplicate).first)

        XCTAssertTrue(invalidAccount.metrics.isEmpty)
        XCTAssertEqual(duplicateAccount.metrics.count, 1)
        XCTAssertEqual(duplicateAccount.metrics[0].usedPercent, 20)
    }

    func testUsesAggregateFallbackWhenAccountsAreEmpty() throws {
        let details = DetailedUsage(
            codexPrimaryWindowLabel: "Weekly",
            codexPrimaryWindowHours: 168,
            planType: "Pro",
            email: "aggregate@example.com"
        )
        let result = ProviderResult(
            usage: Self.quotaUsage(usedPercent: 35),
            details: details,
            accounts: []
        )

        let accounts = CodexWidgetSnapshotBuilder.makeAccounts(from: result)

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].plan, "Pro")
        XCTAssertEqual(accounts[0].metrics.first?.label, "Weekly")
    }

    func testAuthenticationErrorMarksAccountUnavailable() throws {
        let details = DetailedUsage(
            codexPrimaryWindowLabel: "Weekly",
            codexPrimaryWindowHours: 168,
            email: "offline@example.com",
            authErrorMessage: "Authentication failed"
        )
        let result = ProviderResult(
            usage: Self.quotaUsage(usedPercent: 35),
            details: details
        )

        let account = try XCTUnwrap(CodexWidgetSnapshotBuilder.makeAccounts(
            from: result,
            fetchedAt: Date(timeIntervalSince1970: 100)
        ).first)

        XCTAssertEqual(account.status, .unavailable)
    }

    func testSuccessfulFetchTimestampMarksAccountAvailable() throws {
        let result = makeResult(primaryUsed: 35)
        let fetchedAt = Date(timeIntervalSince1970: 100)

        let account = try XCTUnwrap(CodexWidgetSnapshotBuilder.makeAccounts(
            from: result,
            fetchedAt: fetchedAt
        ).first)

        XCTAssertEqual(account.status, .available)
        XCTAssertEqual(account.fetchedAt, fetchedAt)
    }

    func testProviderErrorKeepsCachedMetricsButMarksAccountStale() throws {
        let result = makeResult(primaryUsed: 35)
        let fetchedAt = Date(timeIntervalSince1970: 100)

        let account = try XCTUnwrap(CodexWidgetSnapshotBuilder.makeAccounts(
            from: result,
            providerError: "Network unavailable",
            fetchedAt: fetchedAt
        ).first)

        XCTAssertEqual(account.status, .stale)
        XCTAssertEqual(account.fetchedAt, fetchedAt)
        XCTAssertFalse(account.metrics.isEmpty)
    }

    func testMissingSuccessfulFetchTimestampMarksAccountStale() throws {
        let result = makeResult(primaryUsed: 35)

        let account = try XCTUnwrap(CodexWidgetSnapshotBuilder.makeAccounts(from: result).first)

        XCTAssertEqual(account.status, .stale)
        XCTAssertNil(account.fetchedAt)
    }

    private func makeResult(
        primaryUsed: Double,
        primaryLabel: String = "5 hours",
        primaryHours: Int? = 5,
        secondaryUsed: Double? = nil,
        secondaryHours: Int? = nil,
        email: String = "person@example.com"
    ) -> ProviderResult {
        let details = DetailedUsage(
            secondaryUsage: secondaryUsed,
            codexPrimaryWindowLabel: primaryLabel,
            codexPrimaryWindowHours: primaryHours,
            codexSecondaryWindowLabel: secondaryUsed == nil ? nil : "Weekly",
            codexSecondaryWindowHours: secondaryHours,
            planType: "Plus",
            email: email
        )
        let usage = Self.quotaUsage(usedPercent: primaryUsed)
        let account = ProviderAccountResult(
            accountIndex: 0,
            accountId: "account-123",
            usage: usage,
            details: details
        )
        return ProviderResult(usage: usage, details: details, accounts: [account])
    }

    private static func quotaUsage(usedPercent: Double) -> ProviderUsage {
        let entitlement = 10_000
        let remainingRatio = (100 - usedPercent) / 100
        let remaining = Int((remainingRatio * Double(entitlement)).rounded())
        return .quotaBased(
            remaining: remaining,
            entitlement: entitlement,
            overagePermitted: false
        )
    }
}
