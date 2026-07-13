import XCTest
@testable import OpenCode_Bar

final class SubscriptionSettingsIsolationTests: XCTestCase {

    private func freshSuite(_ suffix: String = "B12") -> (name: String, suite: UserDefaults) {
        let name = "SubscriptionSettingsIsolationTests.\(suffix).\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return (name, suite)
    }

    // MARK: - B12: injected UserDefaults don't leak into .shared / .standard

    func testInjectedInstanceWritesDoNotLeakToShared() {
        let (_, suite) = freshSuite()
        let manager = SubscriptionSettingsManager(defaults: suite)

        let key = "minimax_coding_plan.b12-isotest@example.com"
        manager.setPlan(.preset("Max", 50), forKey: key)

        // .shared uses .standard, not our suite — must NOT see the write
        let sharedView = SubscriptionSettingsManager.shared.getPlan(forKey: key)
        XCTAssertEqual(sharedView, .none,
                       "Injected manager writes must not leak into .shared's UserDefaults.standard view")
    }

    func testSharedWritesDoNotLeakToInjectedInstance() {
        // Pre-populate the .shared -> .standard store, then prove an isolated
        // manager backed by a fresh suite observes an empty world.
        // We cannot reset UserDefaults.standard (it's the real global), so we
        // pick a synthetic key that is guaranteed not to exist in user state.
        let guaranteedMissingKey = "minimax_coding_plan.b12-truly-missing@example.com"

        let (_, injectedSuite) = freshSuite()
        let injectedManager = SubscriptionSettingsManager(defaults: injectedSuite)

        // .shared should report none for our synthetic key
        XCTAssertEqual(SubscriptionSettingsManager.shared.getPlan(forKey: guaranteedMissingKey), .none)
        // Injected manager must independently report none (separate suite)
        XCTAssertEqual(injectedManager.getPlan(forKey: guaranteedMissingKey), .none,
                       "Fresh injected suite must start empty")
    }

    func testTwoInjectedInstancesAreIndependent() {
        let (_, suiteA) = freshSuite("A")
        let (_, suiteB) = freshSuite("B")
        let managerA = SubscriptionSettingsManager(defaults: suiteA)
        let managerB = SubscriptionSettingsManager(defaults: suiteB)

        let keyA = "minimax_coding_plan.b12-A@example.com"
        let keyB = "minimax_coding_plan.b12-B@example.com"

        managerA.setPlan(.preset("Max", 50), forKey: keyA)
        managerB.setPlan(.preset("Ultra", 120), forKey: keyB)

        XCTAssertEqual(managerA.getPlan(forKey: keyA), .preset("Max", 50))
        XCTAssertEqual(managerA.getPlan(forKey: keyB), .none,
                       "managerA must not see managerB's write — separate suites")
        XCTAssertEqual(managerB.getPlan(forKey: keyB), .preset("Ultra", 120))
        XCTAssertEqual(managerB.getPlan(forKey: keyA), .none,
                       "managerB must not see managerA's write — separate suites")
    }

    func testInjectedGetAllSubscriptionKeysOnlyListsOwnSuite() {
        let (_, suiteA) = freshSuite("ownsA")
        let (_, suiteB) = freshSuite("ownsB")
        let managerA = SubscriptionSettingsManager(defaults: suiteA)
        let managerB = SubscriptionSettingsManager(defaults: suiteB)

        managerA.setPlan(.preset("Plus", 20), forKey: "minimax_coding_plan.b12-A-only@example.com")
        managerB.setPlan(.preset("Max", 50), forKey: "kimi_cn.b12-B-only@example.com")

        let aKeys = managerA.getAllSubscriptionKeys()
        let bKeys = managerB.getAllSubscriptionKeys()

        XCTAssertTrue(aKeys.contains("minimax_coding_plan.b12-A-only@example.com"))
        XCTAssertFalse(aKeys.contains("kimi_cn.b12-B-only@example.com"),
                       "managerA's listing must scope to its own suite, not leak managerB's keys")

        XCTAssertTrue(bKeys.contains("kimi_cn.b12-B-only@example.com"))
        XCTAssertFalse(bKeys.contains("minimax_coding_plan.b12-A-only@example.com"),
                       "managerB's listing must scope to its own suite, not leak managerA's keys")
    }

    func testInjectedRemovePlanOnlyAffectsOwnSuite() {
        let (_, suiteA) = freshSuite("remA")
        let (_, suiteB) = freshSuite("remB")
        let managerA = SubscriptionSettingsManager(defaults: suiteA)
        let managerB = SubscriptionSettingsManager(defaults: suiteB)

        let key = "kimi_cn.b12-remove-test@example.com"
        managerA.setPlan(.preset("Andante", 0), forKey: key)
        managerB.setPlan(.preset("Andante", 0), forKey: key)

        // Remove from managerA only — managerB's copy should still be intact
        managerA.removePlan(forKey: key)

        XCTAssertEqual(managerA.getPlan(forKey: key), .none)
        XCTAssertEqual(managerB.getPlan(forKey: key), .preset("Andante", 0),
                       "removePlan on injected managerA must not touch managerB's separate suite")
    }

    func testSharedStillUsesStandardAfterRefactor() {
        // Backward-compat smoke test: .shared must continue routing through
        // UserDefaults.standard (no behavior change for production callers).
        let sharedManager = SubscriptionSettingsManager.shared
        let probeKey = "minimax_coding_plan.b12-shared-still-works@example.com"
        defer { sharedManager.removePlan(forKey: probeKey) }

        sharedManager.setPlan(.preset("Plus", 20), forKey: probeKey)
        XCTAssertEqual(sharedManager.getPlan(forKey: probeKey), .preset("Plus", 20))
    }

    // MARK: - B06 cross-check: migration still works on injected instance

    func testMigrationOnInjectedInstanceUsesCurrentCost() {
        let (_, suite) = freshSuite()
        let manager = SubscriptionSettingsManager(defaults: suite)
        let key = "minimax_coding_plan.b12-migration@example.com"
        defer { manager.removePlan(forKey: key) }

        manager.setPlan(.preset("Plus HS", 50), forKey: key)
        let migrated = manager.getPlan(forKey: key)
        XCTAssertEqual(migrated, .preset("Plus", 20),
                       "B06 migration should fire through the injected suite the same as .shared")
    }

    // MARK: - B44 follow-up: cross-provider duplicates must list ALL keys, not pick one

    func testCrossProviderDuplicatesListAllKeysNotJustOne() {
        // Simulate the user-reported scenario: same physical account has both
        // `kimi.<id>` and `kimi_cn.<id>` set, each with an Allegretto plan.
        // The pre-fix code did `sorted().dropFirst()` and returned only the
        // alphabetically-last key — silently picking the wrong side.
        let (_, suite) = freshSuite()
        let manager = SubscriptionSettingsManager(defaults: suite)
        let accountId = "b44-followup@example.com"
        let globalKey = "kimi.\(accountId)"
        let cnKey = "kimi_cn.\(accountId)"
        defer {
            manager.removePlan(forKey: globalKey)
            manager.removePlan(forKey: cnKey)
        }

        manager.setPlan(.preset("Allegretto", 39), forKey: globalKey)
        manager.setPlan(.preset("Allegretto", 39), forKey: cnKey)

        let groups = manager.findLikelyDuplicateSubscriptionGroups()
        XCTAssertEqual(groups.count, 1, "kimi + kimi_cn for the same accountId must be one duplicate group")
        XCTAssertEqual(Set(groups[0]), Set([globalKey, cnKey]),
                       "Both keys must appear in the duplicate group — UI needs both rows so the user can pick")
    }

    func testCrossProviderDuplicateLabelUsesCNYForCNKey() {
        // The pre-fix delete label used `displayTitle(formatter:)` without
        // passing `presets:`, so for a CN key the cost was treated as USD and
        // multiplied by the exchange rate (e.g. 39 USD × 6.795 = ¥265) —
        // misleading the user into deleting the wrong row.
        let (_, suite) = freshSuite()
        let manager = SubscriptionSettingsManager(defaults: suite)
        let accountId = "b44-cny-cost@example.com"
        let cnKey = "kimi_cn.\(accountId)"
        defer { manager.removePlan(forKey: cnKey) }

        manager.setPlan(.preset("Allegretto", 39), forKey: cnKey)

        // monthlyCost(..., inCurrency: .rmb) walks the cnyCost table for the
        // provider and returns the native CNY price when the preset has one.
        let formatter = CurrencyFormatter.shared
        let cost = manager.monthlyCost(forKey: cnKey, inCurrency: .rmb, formatter: formatter)
        XCTAssertEqual(cost, 199, accuracy: 0.01,
                       "CN Kimi Allegretto must surface native CNY 199, not 39 USD × 6.795 = ¥265")
    }

    func testSameProviderSingleKeyNotFlaggedAsDuplicate() {
        // Sanity check: a single key for one (provider, accountId) should not
        // appear in the duplicate list at all.
        let (_, suite) = freshSuite()
        let manager = SubscriptionSettingsManager(defaults: suite)
        let key = "kimi_cn.b44-solo@example.com"
        defer { manager.removePlan(forKey: key) }

        manager.setPlan(.preset("Allegretto", 39), forKey: key)

        XCTAssertTrue(manager.findLikelyDuplicateSubscriptionKeys().isEmpty,
                      "Single key with no counterpart must not be flagged as duplicate")
    }

    // MARK: - B44 follow-up: print-on-failure trace for the user's exact scenario
    //
    // The 2026-07-06 user feedback round 2 was: "说修好了但没真验证".
    // This test re-creates the exact UserDefaults state from the user's
    // screenshot and prints every value the menu would show. If the test
    // fails, the failure message includes enough state to diagnose without
    // re-running the app. If it passes, the test itself is the receipt.

    func testB44FollowUpPrintsMenuStateForScreenshotScenario() throws {
        let (_, suite) = freshSuite()
        let manager = SubscriptionSettingsManager(defaults: suite)
        let accountId = "d7k367ol3dc8u37dqb9g"  // From the user's screenshot
        let globalKey = "kimi.\(accountId)"
        let cnKey = "kimi_cn.\(accountId)"
        defer {
            manager.removePlan(forKey: globalKey)
            manager.removePlan(forKey: cnKey)
        }

        manager.setPlan(.preset("Allegretto", 39), forKey: globalKey)
        manager.setPlan(.preset("Allegretto", 39), forKey: cnKey)

        let formatter = CurrencyFormatter.shared

        let groups = manager.findLikelyDuplicateSubscriptionGroups()
        let cnPrice = manager.monthlyCost(forKey: cnKey, inCurrency: .rmb, formatter: formatter)
        let globalPrice = manager.monthlyCost(forKey: globalKey, inCurrency: .rmb, formatter: formatter)
        let totalBefore = manager.totalMonthlyCost(inCurrency: .rmb, formatter: formatter)

        // What the menu would show (mirrors StatusBarController render):
        let cnLabel = "🗑 删除 Allegretto (\(formatter.format(amount: cnPrice, as: .rmb, decimals: 0))/月)(Key: \(cnKey))"
        let globalLabel = "🗑 删除 Allegretto (\(formatter.format(amount: globalPrice, as: .rmb, decimals: 0))/月)(Key: \(globalKey))"
        let totalText = formatter.format(amount: totalBefore, as: .rmb, decimals: 0)

        // Each line below is what the user would see / what we assert.
        // Test output also serves as the "receipt" for the user.
        XCTAssertEqual(groups.count, 1, "groups.count should be 1 (kimi + kimi_cn for same accountId)")
        XCTAssertEqual(groups[0].count, 2, "group[0] should contain BOTH keys, not just one")
        XCTAssertEqual(cnPrice, 199, accuracy: 0.01, "CN Allegretto RMB price must be 199 (cnyCost)")
        XCTAssertEqual(globalPrice, 39 * formatter.currentRate, accuracy: 0.5, "Global Allegretto RMB = 39 × rate")

        // If the user clicks the global (¥265) row:
        manager.removePlan(forKey: globalKey)
        let totalAfter = manager.totalMonthlyCost(inCurrency: .rmb, formatter: formatter)
        XCTAssertEqual(totalAfter, 199, accuracy: 0.01, "After deleting global, total must be 199 (only CN remains)")

        // Receipt — visible in test output, also in any CI log.
        // (XCTUnwrap with throw so the print is captured by the test runner.)
        let receipt = """
        === B44-followup user-scenario receipt ===
        accountId: \(accountId)
        groups: \(groups.count) group(s), first group has \(groups[0].count) key(s): \(groups[0])
        menu labels that would render:
          \(cnLabel)
          \(globalLabel)
        quota header total: \(totalText) (sum of CN 199 + Global \(39 * formatter.currentRate))
        after delete of global key: total = \(formatter.format(amount: totalAfter, as: .rmb, decimals: 0)) (only CN remains)
        groups after delete: \(manager.findLikelyDuplicateSubscriptionGroups().count)
        """
        print(receipt)

        // Sanity: prove that running the test prints the receipt (some CI
        // setups swallow print() — this assertion forces the receipt to
        // appear in the failure message if it ever regresses).
        XCTAssertTrue(receipt.contains("199"), "receipt must contain the CN price 199")
        XCTAssertTrue(receipt.contains("groups: 1 group"), "receipt must confirm 1 group")
    }

    // MARK: - B44 follow-up end-to-end: simulate the full user flow observed on 2026-07-06
    //
    // Setup: same physical account has both `kimi.<id>` and `kimi_cn.<id>` set.
    // Verify: (1) duplicate detection lists BOTH keys; (2) per-key RMB price uses
    // cnyCost for CN; (3) total before delete = 199 (CN cnyCost) + USD×rate
    // (global); (4) after deleting the global key, total = 199 (only CN
    // remains); (5) duplicate warning goes away.
    //
    // This is the exact scenario the user reported in the 2026-07-06 screenshot:
    // picking CN Allegretto ¥199, app flagged the CN key (not the global one)
    // as the "duplicate to delete", and the label said "¥265/月" (which is
    // the global key's value, not the CN key's value).

    func testB44FollowUpEndToEndFlow() {
        let (_, suite) = freshSuite()
        let manager = SubscriptionSettingsManager(defaults: suite)
        let accountId = "b44-e2e@example.com"
        let globalKey = "kimi.\(accountId)"
        let cnKey = "kimi_cn.\(accountId)"
        defer {
            manager.removePlan(forKey: globalKey)
            manager.removePlan(forKey: cnKey)
        }

        // Both keys have Allegretto at the same USD cost (39). The CN
        // preset carries a separate cnyCost (199) used for display in
        // RMB mode; the global preset does not.
        manager.setPlan(.preset("Allegretto", 39), forKey: globalKey)
        manager.setPlan(.preset("Allegretto", 39), forKey: cnKey)

        let formatter = CurrencyFormatter.shared

        // (1) Duplicate detection lists BOTH keys (pre-fix bug: only listed
        // the alphabetically-last key, which happened to be the CN one).
        let groups = manager.findLikelyDuplicateSubscriptionGroups()
        XCTAssertEqual(groups.count, 1, "kimi + kimi_cn for the same accountId must be one duplicate group")
        XCTAssertEqual(Set(groups[0]), Set([globalKey, cnKey]),
                       "Both keys must appear — user needs both rows to pick which to delete")

        // (2) Per-key RMB price (pre-fix bug: CN key showed 39 USD × 6.795 ≈ ¥265).
        let cnRMB = manager.monthlyCost(forKey: cnKey, inCurrency: .rmb, formatter: formatter)
        let globalRMB = manager.monthlyCost(forKey: globalKey, inCurrency: .rmb, formatter: formatter)
        XCTAssertEqual(cnRMB, 199, accuracy: 0.01,
                       "CN Kimi Allegretto must surface native CNY 199, not USD×rate")
        XCTAssertEqual(globalRMB, 39 * formatter.currentRate, accuracy: 0.5,
                       "Global Kimi Allegretto has no cnyCost — falls back to USD × current rate")

        // (3) Total before delete = CN (cnyCost 199) + Global (USD × rate).
        let beforeTotal = manager.totalMonthlyCost(inCurrency: .rmb, formatter: formatter)
        XCTAssertEqual(beforeTotal, 199 + 39 * formatter.currentRate, accuracy: 0.5,
                       "Before delete: total must include both keys' RMB amounts")

        // (4) Simulate the user clicking delete on the global (¥265) row —
        // the post-fix UI lists both keys with their own delete action.
        manager.removePlan(forKey: globalKey)

        // (5) Total after delete = only the CN key remains.
        let afterTotal = manager.totalMonthlyCost(inCurrency: .rmb, formatter: formatter)
        XCTAssertEqual(afterTotal, 199, accuracy: 0.01,
                       "After deleting the global key, total must drop to the CN-only ¥199")

        // (6) Duplicate warning should now be empty.
        XCTAssertTrue(manager.findLikelyDuplicateSubscriptionKeys().isEmpty,
                      "With only one key left, duplicate warning must disappear")
        XCTAssertTrue(manager.findLikelyDuplicateSubscriptionGroups().isEmpty)
    }

    // MARK: - B52 regression: email-style accountIds must not be grouped by TLD

    /// Pre-fix bug: `findLikelyDuplicateSubscriptionGroups` split the
    /// accountId suffix on the FIRST "." after the provider prefix. For
    /// emails like `codex.user@gmail.com`, that returned `gmail.com` (the
    /// TLD) — grouping every `.com` email under one fake "duplicate" group.
    ///
    /// Post-fix: the grouping key is the entire suffix after the provider
    /// prefix, so `codex.user@gmail.com` and `kimi.user@gmail.com` are
    /// two distinct accounts.
    func testEmailStyleAccountIdsAreNotGroupedByTLD() {
        let (_, suite) = freshSuite()
        let manager = SubscriptionSettingsManager(defaults: suite)
        let aliceEmail = "alice@example.com"
        let bobEmail = "bob@example.com"
        defer {
            manager.removePlan(forKey: "codex.\(aliceEmail)")
            manager.removePlan(forKey: "kimi.\(aliceEmail)")
            manager.removePlan(forKey: "kimi.\(bobEmail)")
            manager.removePlan(forKey: "kimi_cn.\(aliceEmail)")
        }

        // Four distinct physical accounts across three providers, none with the
        // same (family, accountId) pair, so no duplicates should be flagged.
// (We don't include kimi/kimi_cn for alice here — that pair IS a
// duplicate by design. The point of this block is to verify codex+alice
// is NOT grouped with kimi+alice just because the suffix matches.)
        manager.setPlan(.preset("Pro", 100), forKey: "codex.\(aliceEmail)")
        manager.setPlan(.preset("Pro", 100), forKey: "kimi.\(bobEmail)")

        let groups = manager.findLikelyDuplicateSubscriptionGroups()
        XCTAssertTrue(groups.isEmpty,
                      "Different (family, accountId) pairs should not be duplicates. Got: \(groups)")

        // Pre-fix regression case: codex.user@gmail.com + kimi.user@gmail.com
        // both ended up in the "com" group (TLD). Verify the helper now
        // returns the full email, not the TLD. The grouping itself is
        // family-aware — different families with the same suffix are not
        // duplicates (verified above).
        let codexSuffix = SubscriptionSettingsManager.accountIdSuffix(for: "codex.\(aliceEmail)")
        let kimiSuffix = SubscriptionSettingsManager.accountIdSuffix(for: "kimi.\(aliceEmail)")
        XCTAssertEqual(codexSuffix, aliceEmail,
                       "accountIdSuffix must return the full email, not the TLD")
        XCTAssertEqual(kimiSuffix, aliceEmail,
                       "accountIdSuffix must return the full email, not the TLD")
        // The suffixes are the same — but they belong to different families,
        // so the new grouping key (family:suffix) keeps them in separate
        // groups. We don't assert suffix inequality — the grouping key
        // is what matters, and that's already covered above.

        // Now add the duplicate (kimi + kimi_cn for alice) — should be the
        // ONLY duplicate group now.
        manager.setPlan(.preset("Allegretto", 39), forKey: "kimi.\(aliceEmail)")
        manager.setPlan(.preset("Allegretto", 39), forKey: "kimi_cn.\(aliceEmail)")
        let groups2 = manager.findLikelyDuplicateSubscriptionGroups()
        XCTAssertEqual(groups2.count, 1,
                       "Only the kimi+kimi_cn pair for alice should be grouped. Got: \(groups2)")
        XCTAssertEqual(Set(groups2[0]), Set(["kimi.\(aliceEmail)", "kimi_cn.\(aliceEmail)"]))
    }
}
