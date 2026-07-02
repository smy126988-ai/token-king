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

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: refreshModeKey)
        defaults.removeObject(forKey: eventEstimatedUsedKey)
        defaults.removeObject(forKey: eventCursorKey)
        defaults.removeObject(forKey: eventMonthKey)
        defaults.removeObject(forKey: eventLastScanAtKey)
        defaults.removeObject(forKey: lastApiSyncAtKey)
        defaults.removeObject(forKey: lastUsedKey)
        defaults.removeObject(forKey: lastRemainingKey)
        defaults.removeObject(forKey: lastLimitKey)
        defaults.removeObject(forKey: lastResetSecondsKey)
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: refreshModeKey)
        defaults.removeObject(forKey: eventEstimatedUsedKey)
        defaults.removeObject(forKey: eventCursorKey)
        defaults.removeObject(forKey: eventMonthKey)
        defaults.removeObject(forKey: eventLastScanAtKey)
        defaults.removeObject(forKey: lastApiSyncAtKey)
        defaults.removeObject(forKey: lastUsedKey)
        defaults.removeObject(forKey: lastRemainingKey)
        defaults.removeObject(forKey: lastLimitKey)
        defaults.removeObject(forKey: lastResetSecondsKey)
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
}

final class MockBraveSearchTokenManager: BraveSearchTokenManaging {
    var braveSearchAPIKey: (key: String, source: String)?

    func getBraveSearchAPIKeyWithSource() -> (key: String, source: String)? {
        return braveSearchAPIKey
    }
}
