import XCTest
@testable import OpenCode_Bar

@MainActor
final class StatusBarControllerTestingModeTests: XCTestCase {
    private let braveRefreshKey = "searchEngines.brave.refreshMode"
    private let githubStarDismissedKey = "githubStarPromptDismissed"

    // snapshot/restore pair for keys setUp() may need to mutate.
    // Without restore the test would corrupt the developer's real
    // UserDefaults.standard on `removeObject(...)`.
    private var savedBraveRefresh: Any?
    private var savedGithubStarDismissed: Any?
    private var savedBraveRefreshExists: Bool = false
    private var savedGithubStarDismissedExists: Bool = false

    override func setUp() {
        super.setUp()
        // Snapshot existing values so tearDown can restore exactly.
        if let v = UserDefaults.standard.object(forKey: braveRefreshKey) {
            savedBraveRefresh = v
            savedBraveRefreshExists = true
        }
        if let v = UserDefaults.standard.object(forKey: githubStarDismissedKey) {
            savedGithubStarDismissed = v
            savedGithubStarDismissedExists = true
        }
        // Clean slate: erase state that default init() would mutate so we can
        // detect production-style writes to UserDefaults.standard.
        UserDefaults.standard.removeObject(forKey: braveRefreshKey)
        UserDefaults.standard.removeObject(forKey: githubStarDismissedKey)
    }

    override func tearDown() {
        // Restore exactly to pre-test state.
        if savedBraveRefreshExists {
            UserDefaults.standard.set(savedBraveRefresh, forKey: braveRefreshKey)
        } else {
            UserDefaults.standard.removeObject(forKey: braveRefreshKey)
        }
        if savedGithubStarDismissedExists {
            UserDefaults.standard.set(savedGithubStarDismissed, forKey: githubStarDismissedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: githubStarDismissedKey)
        }
        super.tearDown()
    }

    // MARK: - Init with .testing does not pollute UserDefaults.standard

    func testInitWithTestingOptionsDoesNotWriteToUserDefaultsStandard() {
        // Known key that production init touches; expected absence in .standard
        // proves the testing path uses the injected suite instead.
        let suiteName = "B09.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        defer { suite.removePersistentDomain(forName: suiteName) }

        _ = StatusBarController(
            options: .testing(userDefaults: suite)
        )

        XCTAssertNil(
            UserDefaults.standard.object(forKey: braveRefreshKey),
            "Testing-mode init must not write braveRefreshKey into UserDefaults.standard"
        )
        XCTAssertNil(
            UserDefaults.standard.object(forKey: githubStarDismissedKey),
            "Testing-mode init must not write githubStarPromptDismissed into UserDefaults.standard"
        )
    }

    // MARK: - Init with .testing writes the default to the injected suite

    func testInitWithTestingOptionsWritesDefaultToInjectedSuite() {
        let suiteName = "B09.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        defer { suite.removePersistentDomain(forName: suiteName) }

        _ = StatusBarController(
            options: .testing(userDefaults: suite)
        )

        XCTAssertNotNil(
            suite.object(forKey: braveRefreshKey),
            "Testing-mode init should still populate the braveRefreshKey default — into the injected suite"
        )
    }

    // MARK: - Production options stay observable (back-compat)

    func testProductionOptionsLookLikeCurrentBehavior() {
        XCTAssertTrue(
            StatusBarController.InitOptions.production.runBackgroundTasks,
            "Production options must continue starting background tasks"
        )
        XCTAssertTrue(
            StatusBarController.InitOptions.production.promptGitHubStar,
            "Production options must continue prompting GitHub star"
        )
        XCTAssertEqual(
            StatusBarController.InitOptions.production.userDefaults,
            UserDefaults.standard,
            "Production options should target UserDefaults.standard"
        )
    }

    // MARK: - B44-followup followup: recover from missing anchor separator
    //
    // Symptom in production (2026-07-06 user feedback): after clicking a
    // duplicate-subscription delete row, the menu's anchor separator
    // (added in setupMenu() with no tag → tag = 0) disappears. Once missing,
    // every subsequent updateMultiProviderMenu() early-returns with
    // "no separator found, returning" and the menu is stuck in a stale
    // state — user sees a permanent loading spinner and the old 1-delete
    // line warning that never updates.
    //
    // This test simulates that broken state by stripping the anchor
    // separator from a freshly-built menu and then calling
    // injectProviderStateForTesting (which invokes updateMultiProviderMenu).
    // The recovery path should call setupMenu() to recreate the anchor
    // and the menu should once again have a separator at a stable index.

    @MainActor
    func testMenuRecoversWhenAnchorSeparatorIsMissing() {
        let suiteName = "B44-followup-recover.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        defer { suite.removePersistentDomain(forName: suiteName) }

        let controller = StatusBarController(options: .testing(userDefaults: suite))

        // Trigger initial menu build so the anchor is in place.
        controller.injectProviderStateForTesting()
        guard let initialMenu = controller.topMenuForTesting else {
            XCTFail("Menu should be built by injectProviderStateForTesting")
            return
        }
        let initialSeparatorIndex = initialMenu.items.firstIndex(where: { $0.isSeparatorItem })
        XCTAssertNotNil(initialSeparatorIndex,
                         "Anchor separator should exist after a fresh menu build")

        // Simulate the production bug: strip the anchor separator (the
        // only separator in the menu, at tag=0) by mutating menu.items.
        guard let sepIndex = initialSeparatorIndex,
              sepIndex < initialMenu.items.count else { return }
        let anchor = initialMenu.items[sepIndex]
        XCTAssertEqual(anchor.tag, 0,
                       "Anchor separator should have no tag (tag=0) — that's the invariant the recovery depends on")
        initialMenu.removeItem(at: sepIndex)

        let afterStrip = initialMenu.items.firstIndex(where: { $0.isSeparatorItem })
        XCTAssertNil(afterStrip,
                     "After strip, no separator should exist — simulates the broken production state")

        // Trigger a rebuild — the recovery path should re-add the anchor
        // separator via setupMenu(). self.menu now points to a NEW NSMenu
        // instance, so re-fetch topMenuForTesting.
        controller.injectProviderStateForTesting()

        guard let recoveredMenu = controller.topMenuForTesting else {
            XCTFail("topMenuForTesting should return the recovered menu after strip+rebuild")
            return
        }
        let afterRecover = recoveredMenu.items.firstIndex(where: { $0.isSeparatorItem })
        XCTAssertNotNil(afterRecover,
                         "After recovery, the anchor separator should be back — without this, every subsequent rebuild early-returns and the menu is stuck")
    }

    // MARK: - B44-followup-2 followup: drive the full delete flow end-to-end

    /// Drives the post-confirmation delete logic in a controlled test
    /// environment to verify the menu actually rebuilds after a duplicate
    /// subscription is removed — without the user having to click through
    /// an alert.
    ///
    /// StatusBarController uses the injected `subscriptionManager` from
    /// `InitOptions`. We route the controller through `.testing(userDefaults:
    /// .standard)` so its injected manager targets `UserDefaults.standard`.
    /// For setup/teardown this test uses a fresh
    /// `SubscriptionSettingsManager(defaults: .standard)` (constructed
    /// explicitly to avoid the deprecated `.shared` static) — both the
    /// controller's manager and this local one resolve to the same backing
    /// UserDefaults, so the snapshot/restore pattern still works. It
    /// snapshots and restores the developer's existing keys for the same
    /// accountId to keep the test self-contained.
    ///
    /// Uses a non-email accountId so the duplicate-detection grouping
    /// (which splits on "." after the provider prefix) groups correctly.
    @MainActor
    func testRemoveDuplicateRebuildsMenuEndToEnd() {
        let accountId = "b44-e2e-driver-test"
        let globalKey = "subscription_v2.kimi.\(accountId)"
        let cnKey = "subscription_v2.kimi_cn.\(accountId)"

        // Construct an explicit instance targeting UserDefaults.standard so
        // the test no longer touches the deprecated `.shared` static.
        let manager = SubscriptionSettingsManager(defaults: .standard)
        let savedGlobal = manager.getPlan(forKey: "kimi.\(accountId)")
        let savedCN = manager.getPlan(forKey: "kimi_cn.\(accountId)")
        defer {
            // Restore the developer's real state after the test.
            if savedGlobal.isSet {
                manager.setPlan(savedGlobal, forKey: "kimi.\(accountId)")
            } else {
                manager.removePlan(forKey: "kimi.\(accountId)")
            }
            if savedCN.isSet {
                manager.setPlan(savedCN, forKey: "kimi_cn.\(accountId)")
            } else {
                manager.removePlan(forKey: "kimi_cn.\(accountId)")
            }
        }

        // Set up the user's exact scenario.
        manager.setPlan(.preset("Allegretto", 39), forKey: "kimi.\(accountId)")
        manager.setPlan(.preset("Allegretto", 39), forKey: "kimi_cn.\(accountId)")

        // Provide some provider results so updateMultiProviderMenu doesn't
        // bail out at the `providerResults.isEmpty` guard.
        let providerResult = ProviderResult(
            usage: .quotaBased(remaining: 80, entitlement: 100, overagePermitted: false),
            details: nil
        )

        let controller = StatusBarController(options: .testing(userDefaults: .standard))
        controller.injectProviderStateForTesting(
            results: [.kimi: providerResult]
        )
        guard let initialMenu = controller.topMenuForTesting else {
            XCTFail("Initial menu should be built")
            return
        }

        // 1. Initial state: anchor present, exactly 2 duplicate delete items
        // (one for kimi, one for kimi_cn — both for this accountId).
        XCTAssertNotNil(initialMenu.items.firstIndex(where: { $0.isSeparatorItem }),
                        "Initial menu should have the anchor separator")
        let initialAllegrettoItems = initialMenu.items.filter {
            $0.title.hasPrefix("🗑 删除 Allegretto") &&
            ($0.representedObject as? String)?.hasPrefix("kimi") == true &&
            ($0.representedObject as? String)?.contains(accountId) == true
        }
        XCTAssertEqual(initialAllegrettoItems.count, 2,
                       "Initial menu should show 2 duplicate delete items for our accountId, got: \(initialAllegrettoItems.map(\.title))")

        // 2. Simulate the user clicking the global (¥265) row — bypass the
        // alert by calling the extracted post-confirmation method.
        controller.performRemoveDuplicateSubscription(forKey: "kimi.\(accountId)")

        // 3. After the delete: the menu should still be rebuildable. We
        // call injectProviderStateForTesting to force a rebuild — the
        // recovery path should kick in if the anchor is missing.
        controller.injectProviderStateForTesting(
            results: [.kimi: providerResult]
        )
        guard let afterMenu = controller.topMenuForTesting else {
            XCTFail("Menu should still be queryable after delete")
            return
        }
        XCTAssertNotNil(afterMenu.items.firstIndex(where: { $0.isSeparatorItem }),
                        "After delete + rebuild, the anchor separator should still be present (or recovered)")
        XCTAssertNotNil(afterMenu.items.firstIndex(where: { $0.isSeparatorItem }),
                        "After delete + rebuild, the anchor separator should still be present (or recovered)")

        // 4. After deleting global, only the CN key remains for our accountId.
        // A single key is NOT a "duplicate" (the warning requires keys.count > 1),
        // so the menu's Allegretto delete items for our accountId should be empty.
        // The CN plan itself is still in UserDefaults — verified at the end.
        let remainingDeleteItems = afterMenu.items.filter {
            $0.title.hasPrefix("🗑 删除 Allegretto") &&
            ($0.representedObject as? String)?.contains(accountId) == true
        }
        XCTAssertEqual(remainingDeleteItems.count, 0,
                       "After deleting global, CN alone is not a duplicate, so no Allegretto delete items should remain for our accountId; got: \(remainingDeleteItems.map(\.title))")

        // 5. The CN plan is still preserved in storage — that's what the
        // user actually cares about (the bug was that clicking delete on
        // the wrong row wiped out the user's selected plan).
        let cnPlanAfterFirstDelete = manager.getPlan(forKey: "kimi_cn.\(accountId)")
        XCTAssertEqual(cnPlanAfterFirstDelete, .preset("Allegretto", 39),
                       "After deleting global, the CN plan the user chose must still be in UserDefaults")

        // 6. After deleting the remaining CN, no delete items for our accountId.
        controller.performRemoveDuplicateSubscription(forKey: "kimi_cn.\(accountId)")
        controller.injectProviderStateForTesting(
            results: [.kimi: providerResult]
        )
        guard let finalMenu = controller.topMenuForTesting else {
            XCTFail("Menu should still be queryable after second delete")
            return
        }
        XCTAssertNotNil(finalMenu.items.firstIndex(where: { $0.isSeparatorItem }),
                        "After second delete, anchor should still be present (or recovered)")
        let finalDeleteItems = finalMenu.items.filter {
            $0.title.hasPrefix("🗑 删除 Allegretto") &&
            ($0.representedObject as? String)?.contains(accountId) == true
        }
        XCTAssertTrue(finalDeleteItems.isEmpty,
                      "After deleting both, no delete items for our accountId should remain")
    }
}
