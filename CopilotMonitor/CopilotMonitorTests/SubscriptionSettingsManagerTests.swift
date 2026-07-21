import XCTest
@testable import OpenCode_Bar

final class SubscriptionSettingsManagerTests: XCTestCase {
    private var suiteName: String = ""
    private var defaults: UserDefaults = .standard
    // Initial value placeholder — setUp() reassigns this to an injected
    // instance pointing at a per-test UserDefaults suite. Constructing a
    // fresh `SubscriptionSettingsManager(defaults: .standard)` here avoids
    // touching the deprecated `.shared` static while we wait for setUp().
    private var manager: SubscriptionSettingsManager = SubscriptionSettingsManager(defaults: .standard)

    override func setUp() {
        super.setUp()
        suiteName = "SubscriptionSettingsManagerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        manager = SubscriptionSettingsManager(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Isolated UserDefaults

    func testInjectedManagerDoesNotPolluteSharedDefaults() {
        // Set a value via injected manager — should NOT appear in .standard
        manager.setPlan(.preset("Plus", 20), forKey: "minimax_coding_plan.test@example.com")

        XCTAssertNil(UserDefaults.standard.data(forKey: "subscription_v2.minimax_coding_plan.test@example.com"),
                     "Injected manager must not write to UserDefaults.standard")
    }

    func testInjectedManagerReadsBackOwnWrites() {
        manager.setPlan(.preset("Max", 50), forKey: "minimax_coding_plan.test@example.com")
        let plan = manager.getPlan(forKey: "minimax_coding_plan.test@example.com")
        XCTAssertEqual(plan, .preset("Max", 50))
    }

    func testInjectedManagerDoesNotReadSharedDefaults() {
        // Simulate pollution from another process via a separate
        // `SubscriptionSettingsManager` instance targeting UserDefaults.standard.
        // Constructing it explicitly (instead of touching the deprecated
        // `.shared` static) keeps the test honest about the abstraction and
        // also keeps it compile-safe if `.shared` is removed in a later phase.
        // The injected `manager` (from setUp) targets a per-test suite, so
        // it must NOT observe the .standard write below.
        let sharedKey = "minimax_coding_plan.shared-test@example.com"
        let polluter = SubscriptionSettingsManager(defaults: .standard)
        polluter.setPlan(.preset("Plus", 20), forKey: sharedKey)
        defer { polluter.removePlan(forKey: sharedKey) }

        // Injected manager should NOT see this
        XCTAssertEqual(manager.getPlan(forKey: sharedKey), .none,
                       "Injected manager must not read from UserDefaults.standard")
    }

    // MARK: - Original shared behavior preserved

    func testSharedInstanceStillUsesStandardDefaults() {
        let shared = SubscriptionSettingsManager.shared
        // Sanity check that .shared writes to .standard
        let bareKey = "minimax_coding_plan.shared-probe-\(UUID().uuidString)"
        let probeKey = "subscription_v2.\(bareKey)"
        defer {
            shared.removePlan(forKey: bareKey)
            UserDefaults.standard.removeObject(forKey: probeKey)
        }

        shared.setPlan(.preset("Plus", 20), forKey: bareKey)

        XCTAssertNotNil(UserDefaults.standard.data(forKey: probeKey),
                        ".shared must continue to use UserDefaults.standard")
    }
}
