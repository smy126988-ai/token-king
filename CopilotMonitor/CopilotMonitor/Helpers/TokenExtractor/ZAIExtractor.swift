import Foundation

/// Z.AI Coding Plan API caller (provider API 降级).
/// Endpoint: https://api.z.ai/api/coding/pa/v1/usage/quota/limit
/// Auth: OAuth access token from `~/.kimi/credentials/` (kimi-account) or env.
struct ZAIExtractor: TokenExtractorProtocol {
    let endpoint: URL
    let session: URLSession
    let bearerTokenProvider: () -> String?

    static var defaultEndpoint: URL {
        guard let url = URL(string: "https://api.z.ai/api/coding/pa/v1/usage/quota/limit") else {
            fatalError("Invalid default ZAI endpoint URL")
        }
        return url
    }

    init(
        endpoint: URL? = nil,
        session: URLSession = .shared,
        bearerTokenProvider: (() -> String?)? = nil
    ) {
        self.endpoint = endpoint ?? Self.defaultEndpoint
        self.session = session
        self.bearerTokenProvider = bearerTokenProvider ?? ZAIExtractor.defaultBearerToken
    }

    func extractAll() async throws -> [TokenEvent] {
        guard let token = bearerTokenProvider(), !token.isEmpty else { return [] }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, _) = try await session.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let sessionId = "zai-api-monthly-snapshot"
        let input = intValue(json["input_tokens"] ?? json["inputTokens"])
        let output = intValue(json["output_tokens"] ?? json["outputTokens"])
        let cacheRead = intValue(json["cached_input_tokens"] ?? json["cachedInputTokens"])
        let cacheWrite = intValue(json["cache_creation_tokens"] ?? json["cacheCreationTokens"])
        let reasoning = intValue(json["reasoning_tokens"] ?? json["reasoningTokens"])
        let model = (json["model"] as? String) ?? "glm-4.6"

        let tokens = TokenBreakdown(
            input: input, output: output,
            cacheRead: cacheRead, cacheWrite: cacheWrite,
            reasoning: reasoning
        )
        let provider = TokenNormalizer.matchProvider(model: model, providerID: "z-ai")
        return [TokenEvent(
            provider: provider, model: model, source: .zaiApi,
            sessionId: sessionId, timestamp: Date(),
            tokens: tokens,
            sourceId: "zai:api:snapshot:month"
        )]
    }

    static func defaultBearerToken() -> String? {
        if let env = ProcessInfo.processInfo.environment["ZAI_API_KEY"], !env.isEmpty {
            return env
        }
        let candidates = [
            "\(NSHomeDirectory())/.kimi/credentials/zai-token",
            "\(NSHomeDirectory())/.config/zai/token"
        ]
        for path in candidates {
            if let value = try? String(contentsOfFile: path, encoding: .utf8) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String, let i = Int(s) { return i }
        return 0
    }
}
