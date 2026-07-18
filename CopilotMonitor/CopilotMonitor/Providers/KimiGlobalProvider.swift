import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "KimiGlobalProvider")

final class KimiGlobalProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .kimi
    let type: ProviderType = .quotaBased

    private let tokenManager: KimiCredentialProviding
    private let session: URLSession

    init(tokenManager: KimiCredentialProviding = TokenManager.shared, session: URLSession = .shared) {
        self.tokenManager = tokenManager
        self.session = session
    }

    func fetch() async throws -> ProviderResult {
        guard let apiKey = tokenManager.getKimiAPIKey() else {
            logger.error("Kimi API key not found")
            throw ProviderError.authenticationFailed("Kimi API key not available")
        }

        return try await fetchKimiUsage(
            apiKey: apiKey,
            identifier: identifier,
            logger: logger,
            session: session
        )
    }
}
