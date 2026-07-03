import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "VolcanoArkProvider")

final class VolcanoArkProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .volcanoArk
    let type: ProviderType = .quotaBased
    let fetchTimeout: TimeInterval = 15.0

    private let tokenManager: TokenManager?
    private let explicitCredentials: (accessKey: String, secretKey: String)?
    private let session: URLSession
    private let baseURL = "https://ark.cn-beijing.volces.com/?Action=GetAFPUsage&Version=2024-01-01"

    init(tokenManager: TokenManager = .shared, session: URLSession = .shared) {
        self.tokenManager = tokenManager
        self.explicitCredentials = nil
        self.session = session
    }

    /// Internal initializer for tests that inject credentials directly.
    init(accessKey: String, secretKey: String, session: URLSession = .shared) {
        self.tokenManager = nil
        self.explicitCredentials = (accessKey, secretKey)
        self.session = session
    }

    func fetch() async throws -> ProviderResult {
        guard let (accessKey, secretKey) = explicitCredentials ?? tokenManager?.getVolcanoArkCredentials() else {
            logger.error("Volcano Ark credentials not found")
            throw ProviderError.authenticationFailed("Volcano Ark credentials not available (expected \"volcano-ark\": \"AK:SK\")")
        }

        guard let url = URL(string: baseURL),
              var request = VolcanoArkSigner.signedRequest(url: url, accessKey: accessKey, secretKey: secretKey) else {
            throw ProviderError.networkError("Invalid Volcano Ark endpoint")
        }
        request.httpBody = Data()

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.networkError("Invalid response type")
        }

        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw ProviderError.authenticationFailed("Volcano Ark credentials invalid")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw ProviderError.networkError("HTTP \(httpResponse.statusCode)")
        }

        let decoded = try JSONDecoder().decode(VolcanoArkUsageResponse.self, from: data)
        guard let result = decoded.result else {
            throw ProviderError.decodingError("Missing Volcano Ark usage result")
        }

        let fiveHourUsage = usagePercent(from: result.afpFiveHour)
        let weeklyUsage = usagePercent(from: result.afpWeekly)

        guard fiveHourUsage != nil || weeklyUsage != nil else {
            throw ProviderError.decodingError("Volcano Ark missing quota windows")
        }

        let overallUsed = max(fiveHourUsage ?? 0, weeklyUsage ?? 0)
        let aggregateUsedPercent = UsagePercentDisplayFormatter.wholePercent(from: overallUsed)
        let remainingPercent = max(0, 100 - aggregateUsedPercent)

        let usage = ProviderUsage.quotaBased(
            remaining: remainingPercent,
            entitlement: 100,
            overagePermitted: false
        )

        let details = DetailedUsage(
            fiveHourUsage: fiveHourUsage,
            fiveHourReset: resetDate(from: result.afpFiveHour?.resetTime),
            sevenDayUsage: weeklyUsage,
            sevenDayReset: resetDate(from: result.afpWeekly?.resetTime),
            authSource: "~/.local/share/opencode/auth.json"
        )

        logger.info(
            "Volcano Ark usage fetched: 5h=\(fiveHourUsage?.description ?? "n/a")%, weekly=\(weeklyUsage?.description ?? "n/a")%"
        )

        return ProviderResult(usage: usage, details: details)
    }
}
