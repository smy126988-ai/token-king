import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "MiniMaxGlobalProvider")

final class MiniMaxGlobalProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .minimaxCodingPlan
    let type: ProviderType = .quotaBased

    private let tokenManager: TokenManager
    private let session: URLSession
    private let baseURL = "https://api.minimax.io/v1/api/openplatform/coding_plan/remains"

    init(tokenManager: TokenManager = .shared, session: URLSession = .shared) {
        self.tokenManager = tokenManager
        self.session = session
    }

    func fetch() async throws -> ProviderResult {
        guard let apiKey = tokenManager.getMiniMaxCodingPlanAPIKey() else {
            logger.error("MiniMax Coding Plan API key not found")
            throw ProviderError.authenticationFailed("MiniMax Coding Plan API key not available")
        }

        return try await fetchMiniMaxCodingPlanUsage(
            apiKey: apiKey,
            baseURL: baseURL,
            identifier: identifier,
            logger: logger,
            session: session
        )
    }
}
