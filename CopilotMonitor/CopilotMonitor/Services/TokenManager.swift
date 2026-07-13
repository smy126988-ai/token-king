import Foundation
import Security
import SQLite3
import CommonCrypto
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "TokenManager")

// MARK: - Shared JSON Helper Types

struct GeminiIDTokenPayload: Decodable {
    let sub: String?
    let email: String?
    let audience: String?

    enum CodingKeys: String, CodingKey {
        case sub
        case email
        case aud
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sub = try? container.decode(String.self, forKey: .sub)
        email = try? container.decode(String.self, forKey: .email)

        if let aud = try? container.decode(String.self, forKey: .aud) {
            audience = aud
        } else if let audArray = try? container.decode([String].self, forKey: .aud) {
            audience = audArray.first
        } else {
            audience = nil
        }
    }
}

struct OpenAIIDTokenPayload: Decodable {
    let email: String?
}

struct OpenAIAccessTokenPayload: Decodable {
    struct AuthClaims: Decodable {
        let chatGPTAccountId: String?

        enum CodingKeys: String, CodingKey {
            case chatGPTAccountId = "chatgpt_account_id"
        }
    }

    struct ProfileClaims: Decodable {
        let email: String?
    }

    let auth: AuthClaims?
    let profile: ProfileClaims?

    enum CodingKeys: String, CodingKey {
        case auth = "https://api.openai.com/auth"
        case profile = "https://api.openai.com/profile"
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - TokenManager Singleton

final class TokenManager: @unchecked Sendable {
    static let shared = TokenManager()
    
    /// Serial queue for thread-safe file access
    let queue = DispatchQueue(label: "com.opencodeproviders.TokenManager")

    /// Cached auth data with timestamp
    var cachedAuth: OpenCodeAuth?
    var cacheTimestamp: Date?
    let cacheValiditySeconds: TimeInterval = 30 // Cache for 30 seconds
    
    /// Cached antigravity accounts
    var cachedAntigravityAccounts: AntigravityAccounts?
    var antigravityCacheTimestamp: Date?
    
    /// Cached Gemini OAuth auth payload (OpenCode auth.json)
    var cachedGeminiOAuthAuth: GeminiOAuthAuth?
    var geminiOAuthCacheTimestamp: Date?

    /// Path where Gemini OAuth auth was found (OpenCode auth.json)
    var lastFoundGeminiOAuthPath: URL?

    /// Cached Gemini OAuth creds payload (~/.gemini/oauth_creds.json)
    var cachedGeminiOAuthCreds: GeminiOAuthCreds?
    var geminiOAuthCredsCacheTimestamp: Date?

    /// Path where Gemini oauth_creds.json was found
    var lastFoundGeminiOAuthCredsPath: URL?

    /// Cached Claude accounts (OpenCode + Claude Code)
    var cachedClaudeAccounts: [ClaudeAuthAccount]?
    var claudeAccountsCacheTimestamp: Date?

    /// Cached oc-chatgpt-multi-auth OpenAI accounts
    var cachedOpenCodeMultiAuthAccounts: [OpenAIAuthAccount]?
    var openCodeMultiAuthAccountsCacheTimestamp: Date?

    /// Paths where oc-chatgpt-multi-auth account files were found
    internal(set) var lastFoundOpenCodeMultiAuthPaths: [URL] = []

    /// Cached opencode-anthropic-auth Codex usage accounts
    var cachedOpenCodeAnthropicCodexAccounts: [OpenAIAuthAccount]?
    var openCodeAnthropicCodexAccountsCacheTimestamp: Date?

    /// Paths where opencode-anthropic-auth Codex account files were found
    internal(set) var lastFoundOpenCodeAnthropicCodexAccountPaths: [URL] = []

    /// Cached GitHub Copilot token accounts (OpenCode + VS Code)
    var cachedCopilotAccounts: [CopilotAuthAccount]?
    var copilotAccountsCacheTimestamp: Date?

    /// Cached OpenCode config JSON (opencode.json)
    var cachedOpenCodeConfigJSON: [String: Any]?
    var openCodeConfigCacheTimestamp: Date?

    /// Path where opencode.json was found
    internal(set) var lastFoundOpenCodeConfigPath: URL?

    /// Cached fallback search key JSON (search-keys.json)
    var cachedSearchKeysJSON: [String: Any]?
    var searchKeysCacheTimestamp: Date?

    /// Path where search-keys.json was found
    internal(set) var lastFoundSearchKeysPath: URL?

    /// Path where OpenCode auth.json was last found (or nil)
    internal(set) var lastFoundAuthPath: URL?

    /// Cached Codex native auth payload (~/.codex/auth.json)
    var cachedCodexAuth: CodexAuth?
    var codexCacheTimestamp: Date?

    /// Cached codex-lb OpenAI accounts
    var cachedCodexLBAccounts: [OpenAIAuthAccount]?
    var codexLBCacheTimestamp: Date?

    /// Paths where the codex-lb store.db / encryption.key were last resolved
    internal(set) var lastFoundCodexLBStorePath: URL?
    internal(set) var lastFoundCodexLBKeyPath: URL?

    private init() {
        logger.info("TokenManager initialized")
    }

    #if DEBUG
    /// Resets cached OpenCode auth so tests can swap auth.json locations.
    func resetCachedAuthForTesting() {
        queue.sync {
            cachedAuth = nil
            cacheTimestamp = nil
        }
    }
    #endif

    // OpenCode / Codex / codex-lb auth readers and shared JSON helpers are
    // defined in `TokenManagerOpenCodeCodexAuth.swift` as an extension of this
    // class. See the matching `// MARK: -` sections in that file.

    // Provider-specific auth readers, token accessors, OAuth token refresh, and
    // debug environment info helpers are defined in `TokenManagerProviderAuth.swift`
    // as a separate extension of this class. See the matching `// MARK: -` sections
    // in that file.
}
