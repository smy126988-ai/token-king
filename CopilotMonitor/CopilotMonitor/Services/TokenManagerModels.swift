import Foundation

// MARK: - Data Structures for JSON Parsing

/// OpenCode Auth structure for ~/.local/share/opencode/auth.json
struct OpenCodeAuth: Codable {
    struct OAuth: Codable {
        let type: String
        let access: String
        let refresh: String
        let expires: Int64
        let accountId: String?
        let idToken: String?
        let accountIdOverride: String?
        let organizationIdOverride: String?
        let accountIdSource: String?
        let accountLabel: String?
        let multiAccount: Bool?

        enum CodingKeys: String, CodingKey {
            case type, access, refresh, expires
            case accountId = "accountId"
            case idToken
            case accountIdOverride
            case organizationIdOverride
            case accountIdSource
            case accountLabel
            case multiAccount
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            type = (try? container.decode(String.self, forKey: .type)) ?? "oauth"

            let rawAccess = try container.decode(String.self, forKey: .access)
            let trimmedAccess = rawAccess.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedAccess.isEmpty {
                throw DecodingError.dataCorruptedError(
                    forKey: .access,
                    in: container,
                    debugDescription: "OAuth access token is empty"
                )
            }
            access = trimmedAccess

            refresh = (try? container.decode(String.self, forKey: .refresh))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""

            expires = Self.decodeFlexibleInt64(from: container, forKey: .expires) ?? 0
            accountId = Self.decodeFlexibleString(from: container, forKey: .accountId)
            idToken = Self.decodeFlexibleString(from: container, forKey: .idToken)
            accountIdOverride = Self.decodeFlexibleString(from: container, forKey: .accountIdOverride)
            organizationIdOverride = Self.decodeFlexibleString(from: container, forKey: .organizationIdOverride)
            accountIdSource = Self.decodeFlexibleString(from: container, forKey: .accountIdSource)
            accountLabel = Self.decodeFlexibleString(from: container, forKey: .accountLabel)
            multiAccount = Self.decodeFlexibleBool(from: container, forKey: .multiAccount)
        }

        private static func decodeFlexibleInt64(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> Int64? {
            if let value = decodeLossyIfPresent(Int64.self, from: container, forKey: key) {
                return value
            }
            if let value = decodeLossyIfPresent(Int.self, from: container, forKey: key) {
                return Int64(value)
            }
            if let value = decodeLossyIfPresent(Double.self, from: container, forKey: key) {
                return Int64(value)
            }
            if let value = decodeLossyIfPresent(String.self, from: container, forKey: key) {
                return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return nil
        }

        private static func decodeFlexibleString(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> String? {
            if let value = decodeLossyIfPresent(String.self, from: container, forKey: key) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let value = decodeLossyIfPresent(Int.self, from: container, forKey: key) {
                return String(value)
            }
            if let value = decodeLossyIfPresent(Int64.self, from: container, forKey: key) {
                return String(value)
            }
            if let value = decodeLossyIfPresent(Double.self, from: container, forKey: key) {
                let asInt = Int64(value)
                return String(asInt)
            }
            return nil
        }

        private static func decodeFlexibleBool(
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> Bool? {
            if let value = decodeLossyIfPresent(Bool.self, from: container, forKey: key) {
                return value
            }
            if let value = decodeLossyIfPresent(Int.self, from: container, forKey: key) {
                return value != 0
            }
            if let value = decodeLossyIfPresent(String.self, from: container, forKey: key) {
                switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "yes", "1":
                    return true
                case "false", "no", "0":
                    return false
                default:
                    return nil
                }
            }
            return nil
        }

        private static func decodeLossyIfPresent<T: Decodable>(
            _ type: T.Type,
            from container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> T? {
            do {
                return try container.decodeIfPresent(T.self, forKey: key)
            } catch {
                return nil
            }
        }
    }

    struct APIKey: Codable {
        let type: String
        let key: String

        enum CodingKeys: String, CodingKey {
            case type
            case key
            case access
            case token
            case apiKey
            case value
        }

        init(from decoder: Decoder) throws {
            if let singleValue = try? decoder.singleValueContainer(),
               let rawKey = try? singleValue.decode(String.self) {
                let trimmed = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    throw DecodingError.dataCorruptedError(
                        in: singleValue,
                        debugDescription: "API key value is empty"
                    )
                }
                type = "apiKey"
                key = trimmed
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = (try? container.decode(String.self, forKey: .type)) ?? "apiKey"

            let candidateKeys: [CodingKeys] = [.key, .access, .token, .apiKey, .value]
            var resolvedKey: String?
            for candidate in candidateKeys {
                let value: String?
                do {
                    value = try container.decodeIfPresent(String.self, forKey: candidate)
                } catch {
                    value = nil
                }
                if let value {
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        resolvedKey = trimmed
                        break
                    }
                }
            }

            guard let resolvedKey else {
                throw DecodingError.keyNotFound(
                    CodingKeys.key,
                    DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: "No API key field found (expected one of: key/access/token/apiKey/value)"
                    )
                )
            }
            key = resolvedKey
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            try container.encode(key, forKey: .key)
        }
    }

    let anthropic: OAuth?
    let openai: OAuth?
    /// When `openai` in auth.json is not a valid OAuth object, it may be stored
    /// as an API key object (e.g. `{"type":"apiKey","key":"sk-..."}`). This field
    /// captures that alternative representation so CodexProvider can still send
    /// `Authorization: Bearer <key>` without requiring OAuth or ~/.codex/auth.json.
    let openaiAPIKey: APIKey?
    let githubCopilot: OAuth?
    let openrouter: APIKey?
    let opencode: APIKey?
    let openCodeGo: APIKey?
    let kimiForCoding: APIKey?
    let kimiForCodingCN: APIKey?
    let minimaxCodingPlan: APIKey?
    let minimaxCodingPlanCN: APIKey?
    let minimaxCodingPlanGlobal: APIKey?
    let zaiCodingPlan: APIKey?
    let nanoGpt: APIKey?
    let synthetic: APIKey?
    let chutes: APIKey?
    let mimoForCoding: APIKey?
    let volcanoArk: APIKey?
    let hunyuan: APIKey?
    let zhipuGLM: APIKey?

    enum CodingKeys: String, CodingKey {
        case anthropic, openai, openrouter, opencode, synthetic, chutes
        case openCodeGo = "opencode-go"
        case githubCopilot = "github-copilot"
        case kimiForCoding = "kimi-for-coding"
        case kimiForCodingCN = "kimi-for-coding-cn"
        case minimaxCodingPlan = "minimax-coding-plan"
        case minimaxCodingPlanCN = "minimax-coding-plan-cn"
        case minimaxCodingPlanGlobal = "minimax-coding-plan-global"
        case zaiCodingPlan = "zai-coding-plan"
        case nanoGpt = "nano-gpt"
        case mimoForCoding = "mimo-for-coding"
        case volcanoArk = "volcano-ark"
        case hunyuan
        case zhipuGLM = "zhipu-glm"
    }

    init(
        anthropic: OAuth?,
        openai: OAuth?,
        openaiAPIKey: APIKey?,
        githubCopilot: OAuth?,
        openrouter: APIKey?,
        opencode: APIKey?,
        openCodeGo: APIKey?,
        kimiForCoding: APIKey?,
        kimiForCodingCN: APIKey?,
        minimaxCodingPlan: APIKey?,
        minimaxCodingPlanCN: APIKey? = nil,
        minimaxCodingPlanGlobal: APIKey? = nil,
        zaiCodingPlan: APIKey?,
        nanoGpt: APIKey?,
        synthetic: APIKey?,
        chutes: APIKey? = nil,
        mimoForCoding: APIKey? = nil,
        volcanoArk: APIKey? = nil,
        hunyuan: APIKey? = nil,
        zhipuGLM: APIKey? = nil
    ) {
        self.anthropic = anthropic
        self.openai = openai
        self.openaiAPIKey = openaiAPIKey
        self.githubCopilot = githubCopilot
        self.openrouter = openrouter
        self.opencode = opencode
        self.openCodeGo = openCodeGo
        self.kimiForCoding = kimiForCoding
        self.kimiForCodingCN = kimiForCodingCN
        self.minimaxCodingPlan = minimaxCodingPlan
        self.minimaxCodingPlanCN = minimaxCodingPlanCN
        self.minimaxCodingPlanGlobal = minimaxCodingPlanGlobal
        self.zaiCodingPlan = zaiCodingPlan
        self.nanoGpt = nanoGpt
        self.synthetic = synthetic
        self.chutes = chutes
        self.mimoForCoding = mimoForCoding
        self.volcanoArk = volcanoArk
        self.hunyuan = hunyuan
        self.zhipuGLM = zhipuGLM
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        anthropic = Self.decodeLossyIfPresent(OAuth.self, from: container, forKey: .anthropic)
        openai = Self.decodeLossyIfPresent(OAuth.self, from: container, forKey: .openai)
        // When openai is not a valid OAuth object, try decoding it as an API key.
        openaiAPIKey = (openai == nil)
            ? Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .openai)
            : nil
        githubCopilot = Self.decodeLossyIfPresent(OAuth.self, from: container, forKey: .githubCopilot)
        openrouter = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .openrouter)
        opencode = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .opencode)
        openCodeGo = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .openCodeGo)
        kimiForCoding = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .kimiForCoding)
        kimiForCodingCN = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .kimiForCodingCN)
        minimaxCodingPlan = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .minimaxCodingPlan)
        minimaxCodingPlanCN = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .minimaxCodingPlanCN)
        minimaxCodingPlanGlobal = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .minimaxCodingPlanGlobal)
        zaiCodingPlan = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .zaiCodingPlan)
        nanoGpt = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .nanoGpt)
        synthetic = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .synthetic)
        chutes = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .chutes)
        mimoForCoding = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .mimoForCoding)
        volcanoArk = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .volcanoArk)
        hunyuan = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .hunyuan)
        zhipuGLM = Self.decodeLossyIfPresent(APIKey.self, from: container, forKey: .zhipuGLM)

        if anthropic == nil,
           openai == nil,
           openaiAPIKey == nil,
           githubCopilot == nil,
           openrouter == nil,
           opencode == nil,
           openCodeGo == nil,
           kimiForCoding == nil,
           kimiForCodingCN == nil,
           minimaxCodingPlan == nil,
           minimaxCodingPlanCN == nil,
           minimaxCodingPlanGlobal == nil,
           zaiCodingPlan == nil,
           nanoGpt == nil,
           synthetic == nil,
           chutes == nil,
           mimoForCoding == nil,
           volcanoArk == nil,
           hunyuan == nil,
           zhipuGLM == nil {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "No valid auth entries found in auth.json"
                )
            )
        }
    }

    private static func decodeLossyIfPresent<T: Decodable>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> T? {
        do {
            return try container.decodeIfPresent(T.self, forKey: key)
        } catch {
            return nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(anthropic, forKey: .anthropic)
        try container.encodeIfPresent(openai, forKey: .openai)
        // Encode openaiAPIKey only when OAuth openai is nil to avoid duplicate key
        if openai == nil { try container.encodeIfPresent(openaiAPIKey, forKey: .openai) }
        try container.encodeIfPresent(githubCopilot, forKey: .githubCopilot)
        try container.encodeIfPresent(openrouter, forKey: .openrouter)
        try container.encodeIfPresent(opencode, forKey: .opencode)
        try container.encodeIfPresent(openCodeGo, forKey: .openCodeGo)
        try container.encodeIfPresent(kimiForCoding, forKey: .kimiForCoding)
        try container.encodeIfPresent(kimiForCodingCN, forKey: .kimiForCodingCN)
        try container.encodeIfPresent(minimaxCodingPlan, forKey: .minimaxCodingPlan)
        try container.encodeIfPresent(minimaxCodingPlanCN, forKey: .minimaxCodingPlanCN)
        try container.encodeIfPresent(zaiCodingPlan, forKey: .zaiCodingPlan)
        try container.encodeIfPresent(nanoGpt, forKey: .nanoGpt)
        try container.encodeIfPresent(synthetic, forKey: .synthetic)
        try container.encodeIfPresent(chutes, forKey: .chutes)
        try container.encodeIfPresent(mimoForCoding, forKey: .mimoForCoding)
        try container.encodeIfPresent(volcanoArk, forKey: .volcanoArk)
        try container.encodeIfPresent(hunyuan, forKey: .hunyuan)
        try container.encodeIfPresent(zhipuGLM, forKey: .zhipuGLM)
    }
}

/// Codex CLI native auth structure for ~/.codex/auth.json
/// Different format from OpenCode auth - used as fallback when OpenCode has no OpenAI token
struct CodexAuth: Codable {
    struct Tokens: Codable {
        let accessToken: String?
        let accountId: String?
        let idToken: String?
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accountId = "account_id"
            case idToken = "id_token"
            case refreshToken = "refresh_token"
        }
    }

    let openaiAPIKey: String?
    let tokens: Tokens?
    let lastRefresh: String?

    enum CodingKeys: String, CodingKey {
        case openaiAPIKey = "OPENAI_API_KEY"
        case tokens
        case lastRefresh = "last_refresh"
    }
}

/// codex-lb row payload from store.db/accounts table
struct CodexLBEncryptedAccount {
    let accountId: String?
    let chatGPTAccountId: String?
    let email: String?
    let planType: String?
    let status: String?
    let accessTokenEncrypted: Data
    let refreshTokenEncrypted: Data?
    let idTokenEncrypted: Data?
    let lastRefresh: String?
}

struct CodexCachedUsageWindow {
    let utilization: Double
    let resetsAt: Date?
    let label: String?
    let windowMs: Int?
}

struct CodexCachedUsageSnapshot {
    let fetchedAt: Date?
    let planType: String?
    let primary: CodexCachedUsageWindow?
    let secondary: CodexCachedUsageWindow?
    let sparkPrimary: CodexCachedUsageWindow?
    let sparkSecondary: CodexCachedUsageWindow?
    let creditsBalance: Double?
    let creditsUnlimited: Bool?
}

/// Auth source types for OpenAI (Codex) account discovery
enum OpenAIAuthSource {
    case opencodeAuth
    case openCodeMultiAuth
    case openCodeAnthropicAuthCodexCache
    case codexLB
    case codexAuth
}

enum OpenAICredentialType {
    case oauthBearer
    case apiKey
}

/// Unified OpenAI account model used by the provider layer
struct OpenAIAuthAccount {
    let accessToken: String
    let accountId: String?
    let externalUsageAccountId: String?
    let email: String?
    let authSource: String
    let sourceLabels: [String]
    let source: OpenAIAuthSource
    let credentialType: OpenAICredentialType
    let refreshToken: String?
    let expiresAt: Date?
    let idToken: String?
    let cachedCodexUsage: CodexCachedUsageSnapshot?

    init(
        accessToken: String,
        accountId: String?,
        externalUsageAccountId: String?,
        email: String?,
        authSource: String,
        sourceLabels: [String],
        source: OpenAIAuthSource,
        credentialType: OpenAICredentialType,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        idToken: String? = nil,
        cachedCodexUsage: CodexCachedUsageSnapshot? = nil
    ) {
        self.accessToken = accessToken
        self.accountId = accountId
        self.externalUsageAccountId = externalUsageAccountId
        self.email = email
        self.authSource = authSource
        self.sourceLabels = sourceLabels
        self.source = source
        self.credentialType = credentialType
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.idToken = idToken
        self.cachedCodexUsage = cachedCodexUsage
    }
}

enum CodexEndpointMode: Equatable {
    case directChatGPT
    case external(usageURL: URL)
}

struct CodexEndpointConfiguration: Equatable {
    let mode: CodexEndpointMode
    let source: String
    let usesOpenAIProviderBaseURL: Bool

    var externalServiceDisplayName: String? {
        guard usesOpenAIProviderBaseURL,
              case .external(let usageURL) = mode,
              let host = usageURL.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else {
            return nil
        }

        return Self.displayName(forExternalHost: host)
    }

    static func displayName(forExternalHost host: String) -> String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedHost = trimmedHost.lowercased()
        if lowercasedHost.hasPrefix("codex.") {
            return "Codex" + String(trimmedHost.dropFirst("codex".count))
        }

        return trimmedHost
    }
}

/// Auth source types for Claude account discovery
enum ClaudeAuthSource {
    case opencodeAuth
    case claudeCodeConfig
    case claudeCodeKeychain
    case claudeLegacyCredentials
}

/// Unified Claude account model used by the provider layer
struct ClaudeAuthAccount {
    let accessToken: String
    let accountId: String?
    let email: String?
    let refreshToken: String?
    let expiresAt: Date?
    let authSource: String
    let sourceLabels: [String]
    let source: ClaudeAuthSource

    init(
        accessToken: String,
        accountId: String?,
        email: String?,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        authSource: String,
        sourceLabels: [String],
        source: ClaudeAuthSource
    ) {
        self.accessToken = accessToken
        self.accountId = accountId
        self.email = email
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.authSource = authSource
        self.sourceLabels = sourceLabels
        self.source = source
    }
}

/// Auth source types for GitHub Copilot token discovery
enum CopilotAuthSource: CustomStringConvertible {
    case opencodeAuth
    case copilotCliKeychain
    case vscodeHosts
    case vscodeApps

    var priority: Int {
        switch self {
        case .opencodeAuth:       return 3
        case .copilotCliKeychain: return 2
        case .vscodeHosts:        return 1
        case .vscodeApps:         return 0
        }
    }

    var description: String {
        switch self {
        case .opencodeAuth:
            return "opencodeAuth"
        case .copilotCliKeychain:
            return "copilotCliKeychain"
        case .vscodeHosts:
            return "vscodeHosts"
        case .vscodeApps:
            return "vscodeApps"
        }
    }
}

/// Unified GitHub Copilot token model used by the provider layer
struct CopilotAuthAccount {
    let accessToken: String
    let accountId: String?
    let login: String?
    let authSource: String
    let source: CopilotAuthSource
}

struct CopilotPlanInfo {
    let plan: String?
    let quotaResetDateUTC: Date?
    let quotaLimit: Int?
    let quotaRemaining: Int?
    let userId: String?
}

/// Antigravity Accounts structure for NoeFabris/opencode-antigravity-auth (~/.config/opencode/antigravity-accounts.json)
struct AntigravityAccounts: Codable {
    struct Account: Codable {
        let email: String?
        let refreshToken: String?
        let projectId: String?
        let managedProjectId: String?
        let enabled: Bool?
    }

    let version: Int?
    let accounts: [Account]
    let activeIndex: Int?
    let activeIndexByFamily: [String: Int]?
}

/// Auth source types for Gemini CLI token discovery
enum GeminiAuthSource {
    /// NoeFabris/opencode-antigravity-auth (~/.config/opencode/antigravity-accounts.json)
    case antigravity
    /// jenslys/opencode-gemini-auth (OpenCode auth.json google.oauth)
    case opencodeAuth
    /// Gemini CLI OAuth credentials (~/.gemini/oauth_creds.json)
    case oauthCreds
}

/// Unified Gemini account model used by the provider layer
struct GeminiAuthAccount {
    let index: Int
    let accountId: String?
    let email: String?
    let refreshToken: String
    let projectId: String
    let authSource: String
    let sourceLabels: [String]
    let clientId: String
    let clientSecret: String
    let source: GeminiAuthSource
}

/// Minimal OpenCode auth payload for jenslys/opencode-gemini-auth stored under "google"
struct OpenCodeGeminiAuthContainer: Decodable {
    let google: GeminiOAuthAuth?
}

/// Gemini OAuth payload as stored in OpenCode auth.json
struct GeminiOAuthAuth: Decodable {
    let type: String?
    let refresh: String?
    let access: String?
    let expires: Int64?

    enum CodingKeys: String, CodingKey {
        case type, refresh, access, expires
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decode(String.self, forKey: .type)
        refresh = try? container.decode(String.self, forKey: .refresh)
        access = try? container.decode(String.self, forKey: .access)

        if let expiresValue = try? container.decode(Int64.self, forKey: .expires) {
            expires = expiresValue
        } else if let expiresValue = try? container.decode(Double.self, forKey: .expires) {
            expires = Int64(expiresValue)
        } else if let expiresValue = try? container.decode(String.self, forKey: .expires),
                  let numericValue = Int64(expiresValue) {
            expires = numericValue
        } else {
            expires = nil
        }
    }
}

/// Gemini CLI OAuth credentials from ~/.gemini/oauth_creds.json
struct GeminiOAuthCreds: Decodable {
    let expiryDate: Int64?
    let tokenType: String?
    let accessToken: String?
    let refreshToken: String?
    let scope: String?
    let idToken: String?
    let projectId: String?
    let quotaProjectId: String?

    enum CodingKeys: String, CodingKey {
        case expiryDate = "expiry_date"
        case tokenType = "token_type"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case scope
        case idToken = "id_token"
        case projectId = "project_id"
        case quotaProjectId = "quota_project_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try? container.decode(Int64.self, forKey: .expiryDate) {
            expiryDate = value
        } else if let value = try? container.decode(Double.self, forKey: .expiryDate) {
            expiryDate = Int64(value)
        } else if let value = try? container.decode(String.self, forKey: .expiryDate),
                  let numeric = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            expiryDate = numeric
        } else {
            expiryDate = nil
        }

        tokenType = try? container.decode(String.self, forKey: .tokenType)
        accessToken = try? container.decode(String.self, forKey: .accessToken)
        refreshToken = try? container.decode(String.self, forKey: .refreshToken)
        scope = try? container.decode(String.self, forKey: .scope)
        idToken = try? container.decode(String.self, forKey: .idToken)
        projectId = try? container.decode(String.self, forKey: .projectId)
        quotaProjectId = try? container.decode(String.self, forKey: .quotaProjectId)
    }
}

/// Gemini OAuth token response structure
struct GeminiTokenResponse: Codable {
    let access_token: String
    let expires_in: Int
    let token_type: String?
}
