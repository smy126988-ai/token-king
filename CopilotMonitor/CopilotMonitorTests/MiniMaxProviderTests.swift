import XCTest
@testable import OpenCode_Bar

final class MiniMaxCNProviderTests: XCTestCase {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeCredentials() -> FakeProviderCredentialStore {
        let credentials = FakeProviderCredentialStore()
        credentials.miniMaxCodingPlanCNAPIKey = "test-minimax-cn-key"
        return credentials
    }

    override func tearDown() {
        TestURLProtocol.reset()
        super.tearDown()
    }

    func testProviderIdentifier() {
        let provider = MiniMaxCNProvider()
        XCTAssertEqual(provider.identifier, .minimaxCodingPlanCN)
    }

    func testProviderType() {
        let provider = MiniMaxCNProvider()
        XCTAssertEqual(provider.type, .quotaBased)
    }

    func testFetchUsesInjectedCNKeyWithoutTokenManager() async throws {
        let credentials = FakeProviderCredentialStore()
        credentials.miniMaxCodingPlanCNAPIKey = "injected-minimax-cn-key"
        let responseJSON = """
        {
          "model_remains": [{
            "current_interval_total_count": 100,
            "current_interval_usage_count": 25,
            "current_weekly_total_count": 1000,
            "current_weekly_usage_count": 250
          }],
          "base_resp": {"status_code": 0, "status_msg": "success"}
        }
        """

        TestURLProtocol.handler = { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer injected-minimax-cn-key"
            )
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(responseJSON.utf8))
        }

        let provider = MiniMaxCNProvider(tokenManager: credentials, session: makeSession())
        _ = try await provider.fetch()
    }

    func testCNPlanUsageDerivedFromRemainingPercentWhenCountsAreZero() throws {
        let responseJSON = """
        {
          "model_remains": [
            {
              "current_interval_total_count": 0,
              "current_interval_usage_count": 0,
              "current_interval_remaining_percent": 87,
              "current_weekly_remaining_percent": 98,
              "current_interval_status": 1,
              "weekly_boost_permille": 1500
            }
          ],
          "base_resp": {
            "status_code": 0,
            "status_msg": "success"
          }
        }
        """

        let decoded = try JSONDecoder().decode(MiniMaxCodingPlanResponse.self, from: Data(responseJSON.utf8))
        let row = try XCTUnwrap(decoded.modelRemains.first)
        XCTAssertTrue(row.hasQuotaData)
        XCTAssertEqual(row.fiveHourUsagePercent ?? -1, 13.0, accuracy: 0.001)
        XCTAssertEqual(row.weeklyUsagePercent ?? -1, 2.0, accuracy: 0.001)
    }

    func testCNPlanUsageFallsBackToCountBasedCalculation() throws {
        let responseJSON = """
        {
          "model_remains": [
            {
              "start_time": 1774587600000,
              "end_time": 1774605600000,
              "remains_time": 1715317,
              "current_interval_total_count": 1500,
              "current_interval_usage_count": 750,
              "model_name": "MiniMax-M*",
              "current_weekly_total_count": 15000,
              "current_weekly_usage_count": 6000,
              "weekly_start_time": 1774224000000,
              "weekly_end_time": 1774828800000,
              "weekly_remains_time": 224915317
            }
          ],
          "base_resp": {
            "status_code": 0,
            "status_msg": "success"
          }
        }
        """

        let decoded = try JSONDecoder().decode(MiniMaxCodingPlanResponse.self, from: Data(responseJSON.utf8))
        let row = try XCTUnwrap(decoded.modelRemains.first)
        XCTAssertTrue(row.hasQuotaData)
        XCTAssertEqual(row.fiveHourUsagePercent ?? -1, 50.0, accuracy: 0.001)
        XCTAssertEqual(row.weeklyUsagePercent ?? -1, 60.0, accuracy: 0.001)
    }

    func testResetDatePrefersEndTimeWhenAvailable() {
        let referenceDate = Date(timeIntervalSince1970: 1_774_603_884.703)
        let fiveHourReset = resetDateFromMiniMaxFields(
            endTime: 1_774_605_600_000,
            remainsTime: 1_715_317,
            referenceDate: referenceDate
        )
        let weeklyReset = resetDateFromMiniMaxFields(
            endTime: 1_774_828_800_000,
            remainsTime: 224_915_317,
            referenceDate: referenceDate
        )

        XCTAssertNotNil(fiveHourReset)
        XCTAssertEqual(fiveHourReset!.timeIntervalSince1970, 1_774_605_600.0, accuracy: 0.001)

        XCTAssertNotNil(weeklyReset)
        XCTAssertEqual(weeklyReset!.timeIntervalSince1970, 1_774_828_800.0, accuracy: 0.001)
    }

    func testResetDateFallsBackToEndTimeWhenRemainsTimeMissing() {
        let fiveHourReset = resetDateFromMiniMaxFields(
            endTime: 1_774_605_600_000,
            remainsTime: nil
        )
        let weeklyReset = resetDateFromMiniMaxFields(
            endTime: 1_774_828_800_000,
            remainsTime: nil
        )

        XCTAssertNotNil(fiveHourReset)
        XCTAssertEqual(fiveHourReset!.timeIntervalSince1970, 1_774_605_600.0, accuracy: 0.001)

        XCTAssertNotNil(weeklyReset)
        XCTAssertEqual(weeklyReset!.timeIntervalSince1970, 1_774_828_800.0, accuracy: 0.001)
    }

    func testResetDateFallsBackToRemainsTimeWhenEndTimeInvalid() {
        let referenceDate = Date(timeIntervalSince1970: 1_774_603_884.703)
        let reset = resetDateFromMiniMaxFields(
            endTime: 0,
            remainsTime: 1_715_317,
            referenceDate: referenceDate
        )
        XCTAssertNotNil(reset)
        XCTAssertEqual(reset!.timeIntervalSince(referenceDate), 1_715_317 / 1_000.0, accuracy: 0.001)
    }

    func testResetDateFallsBackToRemainsTimeWhenEndTimeMissing() {
        let referenceDate = Date(timeIntervalSince1970: 1_774_603_884.703)
        let reset = resetDateFromMiniMaxFields(
            endTime: nil,
            remainsTime: 1_715_317,
            referenceDate: referenceDate
        )
        XCTAssertNotNil(reset)
        XCTAssertEqual(reset!.timeIntervalSince(referenceDate), 1_715_317 / 1_000.0, accuracy: 0.001)
    }

    func testResetDateReturnsNilWhenBothFieldsMissing() {
        let reset = resetDateFromMiniMaxFields(
            endTime: nil,
            remainsTime: nil
        )
        XCTAssertNil(reset)
    }

    func testFetchUsesChinaEndpointOnly() async throws {
        let session = makeSession()
        let provider = MiniMaxCNProvider(tokenManager: makeCredentials(), session: session)
        let responseJSON = """
        {
          "model_remains": [
            {
              "start_time": 1774587600000,
              "end_time": 1774605600000,
              "remains_time": 1715317,
              "current_interval_total_count": 1500,
              "current_interval_usage_count": 750,
              "model_name": "MiniMax-M*",
              "current_weekly_total_count": 15000,
              "current_weekly_usage_count": 6000,
              "weekly_start_time": 1774224000000,
              "weekly_end_time": 1774828800000,
              "weekly_remains_time": 224915317
            }
          ],
          "base_resp": {
            "status_code": 0,
            "status_msg": "success"
          }
        }
        """

        var requestedURLs: [URL] = []
        TestURLProtocol.handler = { request in
            requestedURLs.append(request.url!)
            XCTAssertTrue((request.value(forHTTPHeaderField: "Authorization") ?? "").hasPrefix("Bearer "))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseJSON.utf8))
        }

        let result = try await provider.fetch()

        XCTAssertEqual(requestedURLs.count, 1)
        XCTAssertEqual(requestedURLs.first?.host, "api.minimaxi.com")

        switch result.usage {
        case .quotaBased(let remaining, let entitlement, let overagePermitted):
            XCTAssertEqual(remaining, 40)
            XCTAssertEqual(entitlement, 100)
            XCTAssertFalse(overagePermitted)
        default:
            XCTFail("Expected quota-based usage")
        }

        XCTAssertEqual(result.details?.fiveHourUsage ?? -1, 50.0, accuracy: 0.001)
        XCTAssertEqual(result.details?.sevenDayUsage ?? -1, 60.0, accuracy: 0.001)

        // Reset dates are derived from absolute end_time timestamps.
        XCTAssertNotNil(result.details?.fiveHourReset)
        XCTAssertEqual(
            result.details?.fiveHourReset?.timeIntervalSince1970 ?? 0,
            1_774_605_600.0,
            accuracy: 0.001
        )
        XCTAssertNotNil(result.details?.sevenDayReset)
        XCTAssertEqual(
            result.details?.sevenDayReset?.timeIntervalSince1970 ?? 0,
            1_774_828_800.0,
            accuracy: 0.001
        )
    }

    func testFetchDoesNotFallbackOnRegionMismatch() async throws {
        let session = makeSession()
        let provider = MiniMaxCNProvider(tokenManager: makeCredentials(), session: session)
        let regionMismatchJSON = """
        {
          "base_resp": {
            "status_code": 1004,
            "status_msg": "cookie is missing, log in again"
          }
        }
        """

        var requestedURLs: [URL] = []
        TestURLProtocol.handler = { request in
            requestedURLs.append(request.url!)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(regionMismatchJSON.utf8))
        }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected provider error after region mismatch")
        } catch let error as ProviderError {
            switch error {
            case .providerError:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(requestedURLs.count, 1)
        XCTAssertEqual(requestedURLs.first?.host, "api.minimaxi.com")
    }

    func testFetchReturnsAuthenticationErrorOn401() async throws {
        let session = makeSession()
        let provider = MiniMaxCNProvider(tokenManager: makeCredentials(), session: session)

        TestURLProtocol.handler = { request in
            let url = request.url ?? URL(string: "https://api.minimaxi.com")!
            let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected authentication failure")
        } catch let error as ProviderError {
            switch error {
            case .authenticationFailed:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

}

final class MiniMaxGlobalProviderTests: XCTestCase {
    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeCredentials() -> FakeProviderCredentialStore {
        let credentials = FakeProviderCredentialStore()
        credentials.miniMaxCodingPlanAPIKey = "test-minimax-global-key"
        return credentials
    }

    override func tearDown() {
        TestURLProtocol.reset()
        super.tearDown()
    }

    func testProviderIdentifier() {
        let provider = MiniMaxGlobalProvider()
        XCTAssertEqual(provider.identifier, .minimaxCodingPlan)
    }

    func testProviderType() {
        let provider = MiniMaxGlobalProvider()
        XCTAssertEqual(provider.type, .quotaBased)
    }

    func testFetchUsesGlobalEndpointOnly() async throws {
        let session = makeSession()
        let provider = MiniMaxGlobalProvider(tokenManager: makeCredentials(), session: session)
        let responseJSON = """
        {
          "model_remains": [
            {
              "start_time": 1774587600000,
              "end_time": 1774605600000,
              "remains_time": 1715317,
              "current_interval_total_count": 1500,
              "current_interval_usage_count": 750,
              "model_name": "MiniMax-M*",
              "current_weekly_total_count": 15000,
              "current_weekly_usage_count": 6000,
              "weekly_start_time": 1774224000000,
              "weekly_end_time": 1774828800000,
              "weekly_remains_time": 224915317
            }
          ],
          "base_resp": {
            "status_code": 0,
            "status_msg": "success"
          }
        }
        """

        var requestedURLs: [URL] = []
        TestURLProtocol.handler = { request in
            requestedURLs.append(request.url!)
            XCTAssertTrue((request.value(forHTTPHeaderField: "Authorization") ?? "").hasPrefix("Bearer "))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseJSON.utf8))
        }

        let result = try await provider.fetch()

        XCTAssertEqual(requestedURLs.count, 1)
        XCTAssertEqual(requestedURLs.first?.host, "api.minimax.io")

        switch result.usage {
        case .quotaBased(let remaining, let entitlement, let overagePermitted):
            XCTAssertEqual(remaining, 40)
            XCTAssertEqual(entitlement, 100)
            XCTAssertFalse(overagePermitted)
        default:
            XCTFail("Expected quota-based usage")
        }

        XCTAssertEqual(result.details?.fiveHourUsage ?? -1, 50.0, accuracy: 0.001)
        XCTAssertEqual(result.details?.sevenDayUsage ?? -1, 60.0, accuracy: 0.001)
    }

    func testFetchDoesNotFallbackOnRegionMismatch() async throws {
        let session = makeSession()
        let provider = MiniMaxGlobalProvider(tokenManager: makeCredentials(), session: session)
        let regionMismatchJSON = """
        {
          "base_resp": {
            "status_code": 1004,
            "status_msg": "cookie is missing, log in again"
          }
        }
        """

        var requestedURLs: [URL] = []
        TestURLProtocol.handler = { request in
            requestedURLs.append(request.url!)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(regionMismatchJSON.utf8))
        }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected provider error after region mismatch")
        } catch let error as ProviderError {
            switch error {
            case .providerError:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(requestedURLs.count, 1)
        XCTAssertEqual(requestedURLs.first?.host, "api.minimax.io")
    }

    func testFetchReturnsAuthenticationErrorOn401() async throws {
        let session = makeSession()
        let provider = MiniMaxGlobalProvider(tokenManager: makeCredentials(), session: session)

        TestURLProtocol.handler = { request in
            let url = request.url ?? URL(string: "https://api.minimax.io")!
            let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected authentication failure")
        } catch let error as ProviderError {
            switch error {
            case .authenticationFailed:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchPreservesSubOnePercentUsageForMiniMaxWindows() async throws {
        let session = makeSession()
        let provider = MiniMaxGlobalProvider(tokenManager: makeCredentials(), session: session)
        let responseJSON = """
        {
          "model_remains": [
            {
              "start_time": 1774587600000,
              "end_time": 1774605600000,
              "remains_time": 1715317,
              "current_interval_total_count": 1500,
              "current_interval_usage_count": 1494,
              "model_name": "MiniMax-M*",
              "current_weekly_total_count": 15000,
              "current_weekly_usage_count": 14940,
              "weekly_start_time": 1774224000000,
              "weekly_end_time": 1774828800000,
              "weekly_remains_time": 224915317
            }
          ],
          "base_resp": {
            "status_code": 0,
            "status_msg": "success"
          }
        }
        """

        TestURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseJSON.utf8))
        }

        let result = try await provider.fetch()

        switch result.usage {
        case .quotaBased(let remaining, let entitlement, let overagePermitted):
            XCTAssertEqual(remaining, 99)
            XCTAssertEqual(entitlement, 100)
            XCTAssertFalse(overagePermitted)
        default:
            XCTFail("Expected quota-based usage")
        }

        XCTAssertEqual(result.details?.fiveHourUsage ?? -1, 0.4, accuracy: 0.001)
        XCTAssertEqual(result.details?.sevenDayUsage ?? -1, 0.4, accuracy: 0.001)
    }

    func testFetchPrefersUsedQuotaRowOverHigherCapacityZeroUsageRow() async throws {
        let session = makeSession()
        let provider = MiniMaxGlobalProvider(tokenManager: makeCredentials(), session: session)
        let responseJSON = """
        {
          "model_remains": [
            {
              "start_time": 1774587600000,
              "end_time": 1774605600000,
              "remains_time": 1715317,
              "current_interval_total_count": 9000,
              "current_interval_usage_count": 9000,
              "model_name": "speech-hd",
              "current_weekly_total_count": 63000,
              "current_weekly_usage_count": 63000,
              "weekly_start_time": 1774224000000,
              "weekly_end_time": 1774828800000,
              "weekly_remains_time": 224915317
            },
            {
              "start_time": 1774587600000,
              "end_time": 1774605600000,
              "remains_time": 1715317,
              "current_interval_total_count": 4500,
              "current_interval_usage_count": 4469,
              "model_name": "MiniMax-M*",
              "current_weekly_total_count": 45000,
              "current_weekly_usage_count": 44659,
              "weekly_start_time": 1774224000000,
              "weekly_end_time": 1774828800000,
              "weekly_remains_time": 224915317
            }
          ],
          "base_resp": {
            "status_code": 0,
            "status_msg": "success"
          }
        }
        """

        TestURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data(responseJSON.utf8))
        }

        let result = try await provider.fetch()

        XCTAssertEqual(result.details?.fiveHourUsage ?? -1, (31.0 / 4500.0) * 100.0, accuracy: 0.0001)
        XCTAssertEqual(result.details?.sevenDayUsage ?? -1, (341.0 / 45000.0) * 100.0, accuracy: 0.0001)
    }

}
