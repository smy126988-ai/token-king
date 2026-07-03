import Foundation

final class HunyuanProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .hunyuan
    let type: ProviderType = .quotaBased

    private let apiKey: String?

    init(tokenManager: TokenManager = .shared) {
        self.apiKey = tokenManager.getHunyuanAPIKey()
    }

    init(apiKey: String?) {
        self.apiKey = apiKey
    }

    func fetch() async throws -> ProviderResult {
        guard let apiKey, !apiKey.isEmpty else {
            throw ProviderError.authenticationFailed("Hunyuan API key not available")
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
