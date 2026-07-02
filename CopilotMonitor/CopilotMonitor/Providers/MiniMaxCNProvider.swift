import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "MiniMaxCNProvider")

final class MiniMaxCNProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .minimaxCodingPlanCN
    let type: ProviderType = .quotaBased

    private let tokenManager: TokenManager
    private let session: URLSession
    private let baseURL = "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains"

    init(tokenManager: TokenManager = .shared, session: URLSession = .shared) {
        self.tokenManager = tokenManager
        self.session = session
    }

    func fetch() async throws -> ProviderResult {
        guard let apiKey = tokenManager.getMiniMaxCodingPlanCNAPIKey() else {
            logger.error("MiniMax Coding Plan CN API key not found")
            throw ProviderError.authenticationFailed("MiniMax Coding Plan CN API key not available")
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
