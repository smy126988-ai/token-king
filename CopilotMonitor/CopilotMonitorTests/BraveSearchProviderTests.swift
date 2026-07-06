import XCTest
@testable import OpenCode_Bar

final class BraveSearchProviderTests: XCTestCase {

    private let refreshModeKey = "searchEngines.brave.refreshMode"
    private let eventEstimatedUsedKey = "searchEngines.brave.eventEstimatedUsed"
    private let eventCursorKey = "searchEngines.brave.eventCursor"
    private let eventMonthKey = "searchEngines.brave.eventMonth"
    private let eventLastScanAtKey = "searchEngines.brave.eventLastScanAt"
    private let lastApiSyncAtKey = "searchEngines.brave.lastApiSyncAt"
    private let lastUsedKey = "searchEngines.brave.lastUsed"
    private let lastRemainingKey = "searchEngines.brave.lastRemaining"
    private let lastLimitKey = "searchEngines.brave.lastLimit"
    private let lastResetSecondsKey = "searchEngines.brave.lastResetSeconds"

    /// All Brave-related keys this test class touches.
    private var allKeys: [String] {
        [
            refreshModeKey,
            eventEstimatedUsedKey,
            eventCursorKey,
            eventMonthKey,
            eventLastScanAtKey,
            lastApiSyncAtKey,
            lastUsedKey,
            lastRemainingKey,
            lastLimitKey,
            lastResetSecondsKey
        ]
    }

    // B13: snapshot the existing values for every key this test may mutate, so
    // tearDown can restore the developer's real state instead of silently
    // deleting whatever they had configured.
    private struct Snapshot {
        var exists: Bool
        var value: Any?
    }
    private var snapshot: [String: Snapshot] = [:]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for key in allKeys {
            if let value = defaults.object(forKey: key) {
                snapshot[key] = Snapshot(exists: true, value: value)
            } else {
                snapshot[key] = Snapshot(exists: false, value: nil)
            }
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in allKeys {
            if let entry = snapshot[key], entry.exists {
                defaults.set(entry.value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        snapshot.removeAll()
        super.tearDown()
    }

    func testEventOnlyModeWithoutAPIKeyReturnsValidResult() async throws {
        let tokenManager = MockBraveSearchTokenManager()
        tokenManager.braveSearchAPIKey = nil

        UserDefaults.standard.set(0, forKey: refreshModeKey)

        let provider = BraveSearchProvider(tokenManager: tokenManager)

        let result = try await provider.fetch()

        if case .quotaBased(_, _, _) = result.usage {
            // Expected
        } else {
            XCTFail("Expected quotaBased usage, got \(result.usage)")
        }

        XCTAssertNotNil(result.details)
        XCTAssertEqual(result.details?.authUsageSummary, "Estimated (event-based)")
        XCTAssertNil(result.details?.authSource)
    }

    func testEventOnlyModeIgnoresStaleAPISnapshotWithoutKey() async throws {
        // Simulate a previous hybrid/API fetch that cached API-derived numbers,
        // then the user switched to event-only mode and removed the API key.
        let tokenManager = MockBraveSearchTokenManager()
        tokenManager.braveSearchAPIKey = nil

        let defaults = UserDefaults.standard
        defaults.set(0, forKey: refreshModeKey)
        defaults.set(5, forKey: eventEstimatedUsedKey)
        defaults.set(1900, forKey: lastRemainingKey)
        defaults.set(2000, forKey: lastLimitKey)
        defaults.set(100, forKey: lastUsedKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastApiSyncAtKey)
        defaults.set(3600, forKey: lastResetSecondsKey)

        let provider = BraveSearchProvider(tokenManager: tokenManager)
        let result = try await provider.fetch()

        guard case .quotaBased(let remaining, let entitlement, _) = result.usage else {
            XCTFail("Expected quotaBased usage, got \(result.usage)")
            return
        }

        // Event-only must use the local estimate (5) instead of the cached API snapshot (100 used).
        XCTAssertEqual(entitlement, 2000)
        XCTAssertEqual(remaining, 1995)
        XCTAssertEqual(result.details?.monthlyUsage, 5)
        XCTAssertEqual(result.details?.limitRemaining, 1995)
        XCTAssertNil(result.details?.resetPeriod)
    }

    func testEventOnlyModeWithNoKeyAndNoEventsShowsZeroUsage() async throws {
        let tokenManager = MockBraveSearchTokenManager()
        tokenManager.braveSearchAPIKey = nil

        UserDefaults.standard.set(0, forKey: refreshModeKey)

        let provider = BraveSearchProvider(tokenManager: tokenManager)
        let result = try await provider.fetch()

        guard case .quotaBased(let remaining, let entitlement, _) = result.usage else {
            XCTFail("Expected quotaBased usage, got \(result.usage)")
            return
        }

        XCTAssertEqual(entitlement, 2000)
        XCTAssertEqual(remaining, 2000)
        XCTAssertEqual(result.details?.monthlyUsage, 0)
        XCTAssertEqual(result.details?.authUsageSummary, "Estimated (event-based)")
        XCTAssertNil(result.details?.authSource)
    }

    // MARK: - B13 regression: setUp/tearDown must restore original values

    func testSetUpAndTearDownPreservePreExistingValues() {
        // Simulate a developer who has configured Brave Search: the refresh
        // mode is 1 (API) and they have an API snapshot with 200 remaining.
        let defaults = UserDefaults.standard
        defaults.set(1, forKey: refreshModeKey)
        defaults.set(200, forKey: lastRemainingKey)
        defer {
            defaults.removeObject(forKey: refreshModeKey)
            defaults.removeObject(forKey: lastRemainingKey)
        }

        // setUp must snapshot both keys then erase them (so the test starts clean).
        // We invoke the lifecycle methods explicitly so we can verify the
        // post-tearDown state matches the pre-test state.
        setUp()
        XCTAssertNil(defaults.object(forKey: refreshModeKey),
                     "setUp should have cleared refreshModeKey")
        XCTAssertNil(defaults.object(forKey: lastRemainingKey),
                     "setUp should have cleared lastRemainingKey")
        // Simulate a test that writes a new value mid-flight.
        defaults.set(7, forKey: refreshModeKey)
        tearDown()

        XCTAssertEqual(
            defaults.integer(forKey: refreshModeKey), 1,
            "tearDown must restore the developer's pre-test refreshModeKey value"
        )
        XCTAssertEqual(
            defaults.integer(forKey: lastRemainingKey), 200,
            "tearDown must restore the developer's pre-test lastRemainingKey value"
        )
    }
}

final class MockBraveSearchTokenManager: BraveSearchTokenManaging {
    var braveSearchAPIKey: (key: String, source: String)?

    func getBraveSearchAPIKeyWithSource() -> (key: String, source: String)? {
        return braveSearchAPIKey
    }
}
