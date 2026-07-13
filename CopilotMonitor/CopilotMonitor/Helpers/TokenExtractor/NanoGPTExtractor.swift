import Foundation

/// NanoGPT API caller (provider API 降级).
/// OpenAI-compat: https://nano-gpt.com/api/v1/usage
/// Auth: API key from env (NANOGPT_API_KEY) or settings (UserDefaults).
struct NanoGPTExtractor: TokenExtractorProtocol {
    let endpoint: URL
    let session: URLSession
    let bearerTokenProvider: () -> String?
    let defaults: UserDefaults

    static var defaultEndpoint: URL {
        guard let url = URL(string: "https://nano-gpt.com/api/v1/usage") else {
            fatalError("Invalid default NanoGPT endpoint URL")
        }
        return url
    }

    init(
        endpoint: URL? = nil,
        session: URLSession = .shared,
        bearerTokenProvider: (() -> String?)? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.endpoint = endpoint ?? Self.defaultEndpoint
        self.session = session
        self.defaults = defaults
        self.bearerTokenProvider = bearerTokenProvider ?? { Self.defaultBearerToken(defaults: defaults) }
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

        let sessionId = "nanogpt-api-monthly-snapshot"
        let input = intValue(json["input_tokens"] ?? json["inputTokens"])
        let output = intValue(json["output_tokens"] ?? json["outputTokens"])
        let cacheRead = intValue(json["cached_input_tokens"] ?? json["cachedInputTokens"])
        let cacheWrite = intValue(json["cache_creation_tokens"] ?? json["cacheCreationTokens"])
        let model = (json["model"] as? String) ?? "gpt-4o"

        let tokens = TokenBreakdown(
            input: input, output: output,
            cacheRead: cacheRead, cacheWrite: cacheWrite
        )
        let provider = TokenNormalizer.matchProvider(model: model, providerID: "nanogpt")
        return [TokenEvent(
            provider: provider, model: model, source: .nanoGptApi,
            sessionId: sessionId, timestamp: Date(),
            tokens: tokens,
            sourceId: "nanogpt:api:snapshot:month"
        )]
    }

    static func defaultBearerToken(defaults: UserDefaults) -> String? {
        if let env = ProcessInfo.processInfo.environment["NANOGPT_API_KEY"], !env.isEmpty {
            return env
        }
        if let stored = defaults.string(forKey: "nanogpt.apiKey"),
           !stored.isEmpty {
            return stored
        }
        let candidates = [
            "\(NSHomeDirectory())/.nanogpt/token",
            "\(NSHomeDirectory())/.config/nanogpt/token"
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
