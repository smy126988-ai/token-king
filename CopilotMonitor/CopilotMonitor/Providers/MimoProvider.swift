import Foundation

final class MimoProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .mimo
    let type: ProviderType = .quotaBased

    private let apiKey: String?

    init(tokenManager: TokenManager = .shared) {
        self.apiKey = tokenManager.getMimoAPIKey()
    }

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    func fetch() async throws -> ProviderResult {
        guard let apiKey, !apiKey.isEmpty else {
            throw ProviderError.authenticationFailed("MiMo API key not available")
        }

        let usage = ProviderUsage.quotaBased(
            remaining: 100,
            entitlement: 100,
            overagePermitted: false
        )

        return ProviderResult(
            usage: usage,
            details: DetailedUsage(authSource: "~/.local/share/opencode/auth.json")
        )
    }
}
