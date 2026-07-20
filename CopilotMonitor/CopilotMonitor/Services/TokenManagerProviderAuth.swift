//
//  TokenManagerProviderAuth.swift
//  CopilotMonitor
//
//  Token King — extension split of TokenManager.
//  Holds provider-specific auth readers, token accessors, OAuth token refresh,
//  and the debug environment info helpers that previously lived at the bottom
//  of TokenManager.swift (lines 3246-5519). All members remain on the same
//  TokenManager class via a Swift extension.
//

import Foundation
import Security
import os.log

private let logger = Logger(
    subsystem: "com.opencodeproviders",
    category: "TokenManager.ProviderAuth"
)

extension TokenManager {
    // MARK: - Antigravity Accounts File Reading

    private func antigravityAccountsPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("opencode")
            .appendingPathComponent("antigravity-accounts.json")
    }

    /// Thread-safe read of Antigravity accounts with caching
    func readAntigravityAccounts() -> AntigravityAccounts? {
        return queue.sync {
            if let cached = cachedAntigravityAccounts,
               let timestamp = antigravityCacheTimestamp,
               Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
                return cached
            }
            
            let fileManager = FileManager.default
            let accountsPath = antigravityAccountsPath()
            
            guard fileManager.fileExists(atPath: accountsPath.path) else {
                return nil
            }
            guard fileManager.isReadableFile(atPath: accountsPath.path) else {
                logger.warning("Antigravity accounts file not readable at \(accountsPath.path)")
                return nil
            }
            
            do {
                let data = try Data(contentsOf: accountsPath)
                let accounts = try JSONDecoder().decode(AntigravityAccounts.self, from: data)
                cachedAntigravityAccounts = accounts
                antigravityCacheTimestamp = Date()
                logger.info("Successfully loaded Antigravity accounts")
                return accounts
            } catch let decodingError as DecodingError {
                logger.error("Failed to decode Antigravity accounts: \(String(describing: decodingError))")
                return nil
            } catch {
                logger.error("Failed to read Antigravity accounts: \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: - Claude Code Auth Discovery

    private func claudeCodeAuthPaths() -> [URL] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return [
            homeDir
                .appendingPathComponent(".config")
                .appendingPathComponent("claude-code")
                .appendingPathComponent("auth.json")
        ]
    }

    /// Possible opencode-anthropic-auth accounts.json locations in priority order:
    /// 1. $XDG_CONFIG_HOME/opencode/opencode-anthropic-auth/accounts.json (if XDG_CONFIG_HOME is set)
    /// 2. ~/.config/opencode/opencode-anthropic-auth/accounts.json (plugin default)
    private func claudeAnthropicAuthPaths() -> [URL] {
        buildOpenCodeFilePaths(
            envVarName: "XDG_CONFIG_HOME",
            envRelativePathComponents: ["opencode", "opencode-anthropic-auth", "accounts.json"],
            fallbackRelativePathComponents: [
                [".config", "opencode", "opencode-anthropic-auth", "accounts.json"]
            ]
        )
    }

    func readClaudeAnthropicAuthFiles(at paths: [URL]) -> [ClaudeAuthAccount] {
        var accounts: [ClaudeAuthAccount] = []

        for path in paths {
            guard let dict = readJSONDictionary(at: path) else { continue }
            let rawAccounts = valueForNormalizedKey("accounts", in: dict) as? [Any] ?? [dict]
            var pathAccounts: [ClaudeAuthAccount] = []

            for rawAccount in rawAccounts {
                guard let accountDict = rawAccount as? [String: Any] else { continue }
                if let enabled = valueForNormalizedKey("enabled", in: accountDict) as? Bool,
                   enabled == false {
                    logger.info("Including disabled Claude account from opencode-anthropic-auth")
                }
                guard let payload = extractClaudeOAuthPayload(from: accountDict) else { continue }

                pathAccounts.append(
                    ClaudeAuthAccount(
                        accessToken: payload.accessToken,
                        accountId: payload.accountId,
                        email: payload.email,
                        refreshToken: payload.refreshToken,
                        expiresAt: payload.expiresAt,
                        authSource: path.path,
                        sourceLabels: [claudeSourceLabel(for: .opencodeAuth)],
                        source: .opencodeAuth
                    )
                )
            }

            if !pathAccounts.isEmpty {
                logger.info("Loaded \(pathAccounts.count) Claude account(s) from opencode-anthropic-auth at \(path.path)")
                accounts.append(contentsOf: pathAccounts)
            }
        }

        return accounts
    }

    private func readClaudeAnthropicAuthFiles() -> [ClaudeAuthAccount] {
        readClaudeAnthropicAuthFiles(at: claudeAnthropicAuthPaths())
    }

    private func readClaudeCodeAuthFiles() -> [ClaudeAuthAccount] {
        var accounts: [ClaudeAuthAccount] = []
        for path in claudeCodeAuthPaths() {
            guard let dict = readJSONDictionary(at: path) else { continue }
            guard let payload = extractClaudeOAuthPayload(from: dict) else { continue }

            accounts.append(
                ClaudeAuthAccount(
                    accessToken: payload.accessToken,
                    accountId: payload.accountId,
                    email: payload.email,
                    refreshToken: payload.refreshToken,
                    expiresAt: payload.expiresAt,
                    authSource: path.path,
                    sourceLabels: [claudeSourceLabel(for: .claudeCodeConfig)],
                    source: .claudeCodeConfig
                )
            )
        }
        return accounts
    }

    private func readClaudeCodeKeychainAccounts() -> [ClaudeAuthAccount] {
        let services = [
            "Claude Code-credentials",
            "Claude Code"
        ]

        var accounts: [ClaudeAuthAccount] = []
        for service in services {
            guard let dict = readKeychainJSON(service: service) else { continue }
            guard let payload = extractClaudeOAuthPayload(from: dict) else { continue }

            accounts.append(
                ClaudeAuthAccount(
                    accessToken: payload.accessToken,
                    accountId: payload.accountId,
                    email: payload.email,
                    refreshToken: payload.refreshToken,
                    expiresAt: payload.expiresAt,
                    authSource: "Keychain (\(service))",
                    sourceLabels: [claudeSourceLabel(for: .claudeCodeKeychain)],
                    source: .claudeCodeKeychain
                )
            )
        }
        return accounts
    }

    /// Gets all Claude accounts (OpenCode auth + Claude Code local auth)
    func getClaudeAccounts() -> [ClaudeAuthAccount] {
        if let cached = queue.sync(execute: {
            if let cached = cachedClaudeAccounts,
               let timestamp = claudeAccountsCacheTimestamp,
               Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
                return cached
            }
            return nil
        }) {
            return cached
        }

        var accounts: [ClaudeAuthAccount] = []

        if let auth = readOpenCodeAuth(),
           let access = auth.anthropic?.access,
           !access.isEmpty {
            let authSource = lastFoundAuthPath?.path ?? "~/.local/share/opencode/auth.json"
            accounts.append(
                ClaudeAuthAccount(
                    accessToken: access,
                    accountId: auth.anthropic?.accountId,
                    email: nil,
                    refreshToken: normalizedNonEmpty(auth.anthropic?.refresh),
                    expiresAt: dateFromEpoch(auth.anthropic?.expires),
                    authSource: authSource,
                    sourceLabels: [claudeSourceLabel(for: .opencodeAuth)],
                    source: .opencodeAuth
                )
            )
        }

        accounts.append(contentsOf: readClaudeAnthropicAuthFiles())

        let keychainAccounts = readClaudeCodeKeychainAccounts()
        accounts.append(contentsOf: keychainAccounts)
        if keychainAccounts.isEmpty {
            logger.info("Claude keychain credentials unavailable; using Claude Code auth file fallback")
            accounts.append(contentsOf: readClaudeCodeAuthFiles())
        }

        let deduped = dedupeClaudeAccounts(accounts)
        logger.info("Claude accounts discovered: \(deduped.count)")
        queue.sync {
            cachedClaudeAccounts = deduped
            claudeAccountsCacheTimestamp = Date()
        }
        return deduped
    }

    private func dedupeClaudeAccounts(_ accounts: [ClaudeAuthAccount]) -> [ClaudeAuthAccount] {
        func priority(for source: ClaudeAuthSource) -> Int {
            switch source {
            case .opencodeAuth: return 3
            case .claudeCodeKeychain: return 2
            case .claudeCodeConfig: return 1
            case .claudeLegacyCredentials: return 0
            }
        }

        var byToken: [String: ClaudeAuthAccount] = [:]
        for account in accounts {
            if let existing = byToken[account.accessToken] {
                let accountPriority = priority(for: account.source)
                let existingPriority = priority(for: existing.source)
                if accountPriority > existingPriority {
                    byToken[account.accessToken] = mergeClaudeAccount(primary: account, fallback: existing)
                } else if existingPriority > accountPriority {
                    byToken[account.accessToken] = mergeClaudeAccount(primary: existing, fallback: account)
                } else {
                    byToken[account.accessToken] = mergeClaudeAccount(primary: existing, fallback: account)
                }
            } else {
                byToken[account.accessToken] = account
            }
        }
        return Array(byToken.values)
    }

    private func mergeClaudeAccount(primary: ClaudeAuthAccount, fallback: ClaudeAuthAccount) -> ClaudeAuthAccount {
        let primaryAccountId = primary.accountId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackAccountId = fallback.accountId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryEmail = primary.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackEmail = fallback.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedSourceLabels = mergeSourceLabels(primary.sourceLabels, fallback.sourceLabels)
        let primaryRefreshToken = normalizedNonEmpty(primary.refreshToken)
        let fallbackRefreshToken = normalizedNonEmpty(fallback.refreshToken)
        let mergedRefreshToken = primaryRefreshToken ?? fallbackRefreshToken

        let mergedExpiresAt: Date?
        if let primaryExpires = primary.expiresAt,
           let fallbackExpires = fallback.expiresAt {
            mergedExpiresAt = max(primaryExpires, fallbackExpires)
        } else {
            mergedExpiresAt = primary.expiresAt ?? fallback.expiresAt
        }

        return ClaudeAuthAccount(
            accessToken: primary.accessToken,
            accountId: (primaryAccountId?.isEmpty == false) ? primaryAccountId : fallbackAccountId,
            email: (primaryEmail?.isEmpty == false) ? primaryEmail : fallbackEmail,
            refreshToken: mergedRefreshToken,
            expiresAt: mergedExpiresAt,
            authSource: primary.authSource,
            sourceLabels: mergedSourceLabels,
            source: primary.source
        )
    }

    // MARK: - GitHub Copilot Token Discovery

    private func copilotTokenPaths() -> [URL] {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        var paths: [URL] = []

        if let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdgConfigHome.isEmpty {
            let xdgBase = URL(fileURLWithPath: xdgConfigHome).appendingPathComponent("github-copilot")
            paths.append(xdgBase.appendingPathComponent("hosts.json"))
            paths.append(xdgBase.appendingPathComponent("apps.json"))
        }

        let linuxBase = homeDir
            .appendingPathComponent(".config")
            .appendingPathComponent("github-copilot")
        paths.append(linuxBase.appendingPathComponent("hosts.json"))
        paths.append(linuxBase.appendingPathComponent("apps.json"))

        let macBase = homeDir
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("github-copilot")
        paths.append(macBase.appendingPathComponent("hosts.json"))
        paths.append(macBase.appendingPathComponent("apps.json"))

        var uniquePaths: [URL] = []
        var seen = Set<String>()
        for path in paths {
            if seen.insert(path.path).inserted {
                uniquePaths.append(path)
            }
        }
        return uniquePaths
    }

    private func copilotAccountFromEntry(_ entry: [String: Any], source: CopilotAuthSource, authSource: String) -> CopilotAuthAccount? {
        let tokenKeys: Set<String> = ["oauthtoken", "accesstoken", "token"]
        let accountKeys: Set<String> = ["accountid", "userid", "id"]
        let loginKeys: Set<String> = ["login", "user", "username", "email"]

        guard let accessToken = findStringValue(in: entry, matching: tokenKeys) else { return nil }

        let accountIdString = findStringValue(in: entry, matching: accountKeys)
        let accountIdInt = findIntValue(in: entry, matching: accountKeys)
        let accountId = accountIdString ?? accountIdInt.map { String($0) }

        let login = findStringValue(in: entry, matching: loginKeys)

        return CopilotAuthAccount(
            accessToken: accessToken,
            accountId: accountId,
            login: login,
            authSource: authSource,
            source: source
        )
    }

    private func parseCopilotAccounts(from dict: [String: Any], source: CopilotAuthSource, authSource: String) -> [CopilotAuthAccount] {
        var accounts: [CopilotAuthAccount] = []

        if let account = copilotAccountFromEntry(dict, source: source, authSource: authSource) {
            accounts.append(account)
        }

        for value in dict.values {
            if let entry = value as? [String: Any],
               let account = copilotAccountFromEntry(entry, source: source, authSource: authSource) {
                accounts.append(account)
            }
        }

        return accounts
    }

    /// Read GitHub Copilot CLI credentials from macOS Keychain
    /// Service name: "copilot-cli", class: kSecClassGenericPassword
    /// Account format: "https://github.com:username"
    /// Password: GitHub OAuth token
    private func readCopilotCliKeychainAccounts() -> [CopilotAuthAccount] {
        let service = "copilot-cli"

        // Step 1: Query for all matching items to get their accounts
        let listQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var listResult: AnyObject?
        let listStatus = SecItemCopyMatching(listQuery as CFDictionary, &listResult)

        guard listStatus == errSecSuccess else {
            if listStatus == errSecItemNotFound {
                logger.debug("[CopilotKeychain] No Keychain items found for service '\(service)'")
            } else {
                logger.warning("[CopilotKeychain] Failed to list Keychain items for '\(service)', status: \(listStatus)")
            }
            return []
        }

        // Get array of account attributes
        let items: [[String: Any]]
        if let dict = listResult as? [String: Any] {
            items = [dict]
        } else if let array = listResult as? [[String: Any]] {
            items = array
        } else {
            logger.warning("[CopilotKeychain] Unexpected result type when listing items")
            return []
        }

        var accounts: [CopilotAuthAccount] = []

        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else {
                continue
            }

            guard let passwordData = readKeychainPasswordData(service: service, account: account),
                  let token = String(data: passwordData, encoding: .utf8),
                  !token.isEmpty else {
                logger.debug("[CopilotKeychain] Failed to get token for account '\(account)'")
                continue
            }

            // Parse username from account field (format: "https://github.com:username")
            var login: String?
            if let lastColon = account.lastIndex(of: ":") {
                let afterColon = account.index(after: lastColon)
                let candidate = String(account[afterColon...])
                if !candidate.isEmpty {
                    login = candidate
                }
            }

            accounts.append(
                CopilotAuthAccount(
                    accessToken: token,
                    accountId: nil,
                    login: login,
                    authSource: "Keychain (copilot-cli)",
                    source: .copilotCliKeychain
                )
            )
        }

        return accounts
    }

    /// Gets all GitHub Copilot token accounts (OpenCode auth + Copilot CLI Keychain + VS Code Copilot tokens)
    func getGitHubCopilotAccounts() -> [CopilotAuthAccount] {
        if let cached = queue.sync(execute: {
            if let cached = cachedCopilotAccounts,
               let timestamp = copilotAccountsCacheTimestamp,
               Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
                return cached
            }
            return nil
        }) {
            return cached
        }

        var accounts: [CopilotAuthAccount] = []

        if let auth = readOpenCodeAuth(),
           let access = auth.githubCopilot?.access,
           !access.isEmpty {
            let authSource = lastFoundAuthPath?.path ?? "~/.local/share/opencode/auth.json"
            accounts.append(
                CopilotAuthAccount(
                    accessToken: access,
                    accountId: auth.githubCopilot?.accountId,
                    login: nil,
                    authSource: authSource,
                    source: .opencodeAuth
                )
            )
        }

        // Add Copilot CLI Keychain accounts
        accounts.append(contentsOf: readCopilotCliKeychainAccounts())

        for path in copilotTokenPaths() {
            guard let dict = readJSONDictionary(at: path) else { continue }
            let source: CopilotAuthSource = path.lastPathComponent == "apps.json" ? .vscodeApps : .vscodeHosts
            accounts.append(contentsOf: parseCopilotAccounts(from: dict, source: source, authSource: path.path))
        }

        let deduped = dedupeCopilotAccounts(accounts)
        
        logger.info("GitHub Copilot token accounts discovered: \(deduped.count)")
        queue.sync {
            cachedCopilotAccounts = deduped
            copilotAccountsCacheTimestamp = Date()
        }
        return deduped
    }

    private func dedupeCopilotAccounts(_ accounts: [CopilotAuthAccount]) -> [CopilotAuthAccount] {
        var byToken: [String: CopilotAuthAccount] = [:]
        for account in accounts {
            if let existing = byToken[account.accessToken] {
                let existingPriority = existing.source.priority
                let newPriority = account.source.priority
                if newPriority > existingPriority {
                    byToken[account.accessToken] = account
                }
            } else {
                byToken[account.accessToken] = account
            }
        }
        return Array(byToken.values)
    }

    // MARK: - OpenAI Account Discovery

    /// Gets all OpenAI accounts (OpenCode auth + codex-lb + Codex native auth)
    func getOpenAIAccounts() -> [OpenAIAuthAccount] {
        var accounts: [OpenAIAuthAccount] = []

        if let auth = readOpenCodeAuth(),
           let access = auth.openai?.access,
           !access.isEmpty {
            let authSource = lastFoundAuthPath?.path ?? "~/.local/share/opencode/auth.json"
            let metadata = resolvedOpenAIAuthMetadata(from: auth.openai)
            accounts.append(
                OpenAIAuthAccount(
                    accessToken: access,
                    accountId: metadata.accountId,
                    externalUsageAccountId: metadata.overrideAccountId != metadata.accountId ? metadata.overrideAccountId : nil,
                    email: metadata.email,
                    authSource: authSource,
                    sourceLabels: [openAISourceLabel(for: .opencodeAuth)],
                    source: .opencodeAuth,
                    credentialType: .oauthBearer
                )
            )
        }

        if let auth = readOpenCodeAuth(),
           let apiKey = auth.openaiAPIKey,
           !apiKey.key.isEmpty {
            let authSource = lastFoundAuthPath?.path ?? "~/.local/share/opencode/auth.json"
            accounts.append(
                OpenAIAuthAccount(
                    accessToken: apiKey.key,
                    accountId: nil,
                    externalUsageAccountId: nil,
                    email: nil,
                    authSource: authSource,
                    sourceLabels: ["OpenCode (API Key)"],
                    source: .opencodeAuth,
                    credentialType: .apiKey
                )
            )
        }

        let openCodeMultiAuthAccounts = readOpenAIMultiAuthFiles()
        if !openCodeMultiAuthAccounts.isEmpty {
            accounts.append(contentsOf: openCodeMultiAuthAccounts)
        }

        let openCodeAnthropicCodexAccounts = readOpenCodeAnthropicCodexAccountFiles()
        if !openCodeAnthropicCodexAccounts.isEmpty {
            accounts.append(contentsOf: openCodeAnthropicCodexAccounts)
        }

        let codexLBAccounts = readCodexLBOpenAIAccounts()
        if !codexLBAccounts.isEmpty {
            accounts.append(contentsOf: codexLBAccounts)
        }

        if let codexAuth = readCodexAuth(),
           let access = codexAuth.tokens?.accessToken,
           !access.isEmpty {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let authSource = homeDir
                .appendingPathComponent(".codex")
                .appendingPathComponent("auth.json")
                .path
            let idTokenPayload = decodeOpenAIIDTokenPayload(codexAuth.tokens?.idToken)
            let codexEmail = normalizedNonEmpty(idTokenPayload?.email)
            accounts.append(
                OpenAIAuthAccount(
                    accessToken: access,
                    accountId: codexAuth.tokens?.accountId,
                    externalUsageAccountId: nil,
                    email: codexEmail,
                    authSource: authSource,
                    sourceLabels: [openAISourceLabel(for: .codexAuth)],
                    source: .codexAuth,
                    credentialType: .oauthBearer
                )
            )
        }

        if let codexAuth = readCodexAuth(),
           codexAuth.tokens?.accessToken?.isEmpty != false,
           let apiKey = codexAuth.openaiAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty {
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let authSource = homeDir
                .appendingPathComponent(".codex")
                .appendingPathComponent("auth.json")
                .path
            accounts.append(
                OpenAIAuthAccount(
                    accessToken: apiKey,
                    accountId: nil,
                    externalUsageAccountId: nil,
                    email: nil,
                    authSource: authSource,
                    sourceLabels: ["Codex (API Key)"],
                    source: .codexAuth,
                    credentialType: .apiKey
                )
            )
        }

        let deduped = dedupeOpenAIAccounts(accounts)
        logger.info("OpenAI accounts discovered: \(deduped.count)")
        return deduped
    }

    // MARK: - Gemini OAuth Auth File Reading (jenslys/opencode-gemini-auth)

    private struct GeminiRefreshParts {
        let refreshToken: String
        let projectId: String?
        let managedProjectId: String?
    }

    private func parseGeminiRefreshParts(_ refresh: String) -> GeminiRefreshParts {
        let trimmed = refresh.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = trimmed.split(separator: "|", omittingEmptySubsequences: false)
        let refreshToken = segments.indices.contains(0) ? String(segments[0]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let projectRaw = segments.indices.contains(1) ? String(segments[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let managedRaw = segments.indices.contains(2) ? String(segments[2]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return GeminiRefreshParts(
            refreshToken: refreshToken,
            projectId: projectRaw.isEmpty ? nil : projectRaw,
            managedProjectId: managedRaw.isEmpty ? nil : managedRaw
        )
    }

    private func geminiOAuthClientCredentials(for audience: String?) -> (clientId: String, clientSecret: String) {
        let normalizedAudience = normalizedNonEmpty(audience)
        if normalizedAudience == TokenManager.geminiAuthPluginClientId {
            return (TokenManager.geminiAuthPluginClientId, TokenManager.geminiAuthPluginClientSecret)
        }
        if normalizedAudience == TokenManager.geminiClientId {
            return (TokenManager.geminiClientId, TokenManager.geminiClientSecret)
        }
        return (TokenManager.geminiClientId, TokenManager.geminiClientSecret)
    }

    /// Thread-safe read of Gemini OAuth auth stored under "google" in OpenCode auth.json (jenslys/opencode-gemini-auth)
    func readGeminiOAuthAuth() -> GeminiOAuthAuth? {
        return queue.sync {
            if let cached = cachedGeminiOAuthAuth,
               let timestamp = geminiOAuthCacheTimestamp,
               Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
                return cached
            }

            let fileManager = FileManager.default
            let paths = getAuthFilePaths()

            for authPath in paths {
                guard fileManager.fileExists(atPath: authPath.path) else {
                    continue
                }

                do {
                    let data = try Data(contentsOf: authPath)
                    let container = try JSONDecoder().decode(OpenCodeGeminiAuthContainer.self, from: data)
                    guard let geminiAuth = container.google else {
                        continue
                    }
                    guard geminiAuth.type?.lowercased() == "oauth" else {
                        continue
                    }
                    let refresh = geminiAuth.refresh?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !refresh.isEmpty else {
                        logger.warning("Gemini OAuth entry exists but refresh token is empty in \(authPath.path)")
                        continue
                    }

                    lastFoundGeminiOAuthPath = authPath
                    cachedGeminiOAuthAuth = geminiAuth
                    geminiOAuthCacheTimestamp = Date()
                    logger.info("Successfully loaded Gemini OAuth auth from: \(authPath.path)")
                    return geminiAuth
                } catch {
                    logger.warning("Failed to parse Gemini OAuth auth at \(authPath.path): \(error.localizedDescription)")
                    continue
                }
            }

            lastFoundGeminiOAuthPath = nil
            cachedGeminiOAuthAuth = nil
            geminiOAuthCacheTimestamp = nil
            return nil
        }
    }

    private func geminiOAuthCredsPath() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini")
            .appendingPathComponent("oauth_creds.json")
    }

    /// Thread-safe read of Gemini CLI OAuth creds (~/.gemini/oauth_creds.json)
    func readGeminiOAuthCreds() -> GeminiOAuthCreds? {
        return queue.sync {
            if let cached = cachedGeminiOAuthCreds,
               let timestamp = geminiOAuthCredsCacheTimestamp,
               Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
                return cached
            }

            let credsPath = geminiOAuthCredsPath()
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: credsPath.path) else {
                lastFoundGeminiOAuthCredsPath = nil
                cachedGeminiOAuthCreds = nil
                geminiOAuthCredsCacheTimestamp = nil
                return nil
            }
            guard fileManager.isReadableFile(atPath: credsPath.path) else {
                logger.warning("Gemini oauth_creds.json is not readable at \(credsPath.path)")
                lastFoundGeminiOAuthCredsPath = nil
                cachedGeminiOAuthCreds = nil
                geminiOAuthCredsCacheTimestamp = nil
                return nil
            }

            do {
                let data = try Data(contentsOf: credsPath)
                let creds = try JSONDecoder().decode(GeminiOAuthCreds.self, from: data)
                lastFoundGeminiOAuthCredsPath = credsPath
                cachedGeminiOAuthCreds = creds
                geminiOAuthCredsCacheTimestamp = Date()
                logger.info("Successfully loaded Gemini OAuth creds from: \(credsPath.path)")
                return creds
            } catch {
                logger.warning("Failed to parse Gemini OAuth creds at \(credsPath.path): \(error.localizedDescription)")
                lastFoundGeminiOAuthCredsPath = nil
                cachedGeminiOAuthCreds = nil
                geminiOAuthCredsCacheTimestamp = nil
                return nil
            }
        }
    }

    private func decodeGeminiIDTokenPayload(_ idToken: String?) -> GeminiIDTokenPayload? {
        guard let token = normalizedNonEmpty(idToken) else {
            return nil
        }

        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }

        let payload = String(parts[1])
        do {
            let data = try decodeBase64URL(payload)
            return try JSONDecoder().decode(GeminiIDTokenPayload.self, from: data)
        } catch {
            logger.warning("Failed to decode Gemini id_token payload: \(error.localizedDescription)")
            return nil
        }
    }

    func decodeOpenAIIDTokenPayload(_ idToken: String?) -> OpenAIIDTokenPayload? {
        guard let token = normalizedNonEmpty(idToken) else {
            return nil
        }

        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }

        let payload = String(parts[1])
        do {
            let data = try decodeBase64URL(payload)
            return try JSONDecoder().decode(OpenAIIDTokenPayload.self, from: data)
        } catch {
            logger.warning("Failed to decode OpenAI id_token payload: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Token Accessors

    /// Gets Anthropic (Claude) access token from OpenCode auth
    /// - Returns: Access token string if available, nil otherwise
    func getAnthropicAccessToken() -> String? {
        if let auth = readOpenCodeAuth(), let access = auth.anthropic?.access {
            return access
        }
        return getClaudeAccounts().first?.accessToken
    }

    /// Gets OpenAI access token, first from OpenCode auth, then falling back to Codex CLI native auth (~/.codex/auth.json)
    func getOpenAIAccessToken() -> String? {
        // Primary: OpenCode auth
        if let auth = readOpenCodeAuth(), let access = auth.openai?.access {
            return access
        }
        if let auth = readOpenCodeAuth(), let apiKey = auth.openaiAPIKey?.key {
            return apiKey
        }
        // Fallback: Codex CLI native auth (~/.codex/auth.json)
        if let codexAuth = readCodexAuth(), let access = codexAuth.tokens?.accessToken {
            logger.info("Using Codex native auth (~/.codex/auth.json) as fallback for OpenAI access token")
            return access
        }
        if let codexAuth = readCodexAuth(), let apiKey = codexAuth.openaiAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
            logger.info("Using Codex native auth API key (~/.codex/auth.json) as fallback for OpenAI access token")
            return apiKey
        }
        return nil
    }

    /// Gets OpenAI account ID, first from OpenCode auth, then falling back to Codex CLI native auth
    func getOpenAIAccountId() -> String? {
        // Primary: OpenCode auth
        if let auth = readOpenCodeAuth(),
           let accountId = resolvedOpenAIAuthMetadata(from: auth.openai).accountId {
            return accountId
        }
        // Fallback: Codex CLI native auth (~/.codex/auth.json)
        if let codexAuth = readCodexAuth(), let accountId = codexAuth.tokens?.accountId {
            logger.info("Using Codex native auth (~/.codex/auth.json) as fallback for OpenAI account ID")
            return accountId
        }
        return nil
    }

    /// Gets GitHub Copilot access token from OpenCode auth
    /// - Returns: Access token string if available, nil otherwise
    func getGitHubCopilotAccessToken() -> String? {
        if let auth = readOpenCodeAuth(), let access = auth.githubCopilot?.access {
            return access
        }
        return getGitHubCopilotAccounts().first?.accessToken
    }

    /// Fetches Copilot plan and quota info from GitHub internal API
    /// - Returns: CopilotPlanInfo if successful, nil otherwise
    func fetchCopilotPlanInfo(accessToken: String) async -> CopilotPlanInfo? {
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else {
            logger.error("Invalid Copilot API URL")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("token \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response type from Copilot API")
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("Copilot API returned status: \(httpResponse.statusCode)")
                if let responseBody = String(data: data, encoding: .utf8) {
                    let truncated = String(responseBody.prefix(256))
                    logger.debug("Copilot API error body (truncated): \(truncated)")
                }
                return nil
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.error("Failed to parse Copilot API response")
                return nil
            }

            let plan = json["copilot_plan"] as? String ?? json["plan"] as? String
            let userIdString = json["user_id"] as? String
            let userIdInt = json["user_id"] as? Int ?? (json["id"] as? Int)
            let userId = userIdString ?? userIdInt.map { String($0) }

            var resetDate: Date?

            // Parse quota_reset_date_utc (format: "2026-03-01T00:00:00.000Z")
            if let resetDateStr = json["quota_reset_date_utc"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                resetDate = formatter.date(from: resetDateStr)

                if resetDate == nil {
                    let fallbackFormatter = ISO8601DateFormatter()
                    fallbackFormatter.formatOptions = [.withInternetDateTime]
                    resetDate = fallbackFormatter.date(from: resetDateStr)
                }
            }

            // Fallback to quota_reset_date (format: "2026-03-01")
            if resetDate == nil, let resetDateStr = json["quota_reset_date"] as? String {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                dateFormatter.timeZone = TimeZone(identifier: "UTC")
                resetDate = dateFormatter.date(from: resetDateStr)
            }

            // Additional fallback: limited_user_reset_date
            if resetDate == nil, let limitedReset = json["limited_user_reset_date"] as? String {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                resetDate = formatter.date(from: limitedReset)
                if resetDate == nil {
                    let fallbackFormatter = ISO8601DateFormatter()
                    fallbackFormatter.formatOptions = [.withInternetDateTime]
                    resetDate = fallbackFormatter.date(from: limitedReset)
                }
            }

            // Try multiple quota sources for different API versions
            let limitedUserQuotas = json["limited_user_quotas"] as? [String: Any]
            let monthlyQuotas = json["monthly_quotas"] as? [String: Any]
            let quotaSnapshots = json["quota_snapshots"] as? [String: Any]

            func quotaValue(_ dict: [String: Any]?, key: String) -> Int? {
                guard let dict = dict else { return nil }
                if let value = dict[key] as? Int { return value }
                if let value = dict[key] as? NSNumber { return value.intValue }
                if let value = dict[key] as? Double { return Int(value) }
                if let value = dict[key] as? String, let intValue = Int(value) { return intValue }
                return nil
            }

            // Legacy API format: monthly_quotas and limited_user_quotas
            let monthlyCompletions = quotaValue(monthlyQuotas, key: "completions")
            let monthlyChat = quotaValue(monthlyQuotas, key: "chat")
            let limitedCompletions = quotaValue(limitedUserQuotas, key: "completions")
            let limitedChat = quotaValue(limitedUserQuotas, key: "chat")

            // New API format: quota_snapshots (contains entitlement/remaining for each quota type)
            var snapshotEntitlement: Int?
            var snapshotRemaining: Int?
            if let snapshots = quotaSnapshots {
                // Sum up entitlement and remaining from all quota types
                var totalEntitlement = 0
                var totalRemaining = 0
                var hasUnlimited = false
                
                for (_, value) in snapshots {
                    if let quota = value as? [String: Any] {
                        // Check if this quota type is unlimited
                        if let unlimited = quota["unlimited"] as? Bool, unlimited {
                            hasUnlimited = true
                        }
                        
                        // Add entitlement and remaining
                        if let entitlement = quotaValue(quota, key: "entitlement"), entitlement > 0 {
                            totalEntitlement += entitlement
                        }
                        if let remaining = quotaValue(quota, key: "remaining") {
                            totalRemaining += remaining
                        }
                    }
                }
                
                if totalEntitlement > 0 {
                    snapshotEntitlement = totalEntitlement
                    snapshotRemaining = totalRemaining
                } else if hasUnlimited {
                    // Sentinel value so downstream guard (limit > 0) passes
                    // and usage = (Int.max - Int.max) / Int.max ≈ 0%
                    snapshotEntitlement = Int.max
                    snapshotRemaining = Int.max
                }
            }

            // Combine all quota sources with priority: snapshots > monthly > legacy
            let quotaLimit = snapshotEntitlement ?? monthlyCompletions ?? monthlyChat
                ?? ((monthlyCompletions != nil || monthlyChat != nil) ? (monthlyCompletions ?? 0) + (monthlyChat ?? 0) : nil)
            let quotaRemaining = snapshotRemaining ?? limitedCompletions ?? limitedChat
                ?? ((limitedCompletions != nil || limitedChat != nil) ? (limitedCompletions ?? 0) + (limitedChat ?? 0) : nil)

            if let resetDate = resetDate {
                logger.info("Copilot plan info fetched: \(plan ?? "unknown"), reset: \(resetDate)")
            } else {
                logger.warning("Copilot plan fetched but no reset date: \(plan ?? "unknown")")
            }

            return CopilotPlanInfo(
                plan: plan,
                quotaResetDateUTC: resetDate,
                quotaLimit: quotaLimit,
                quotaRemaining: quotaRemaining,
                userId: userId
            )
        } catch {
            logger.error("Failed to fetch Copilot plan info: \(error.localizedDescription)")
            return nil
        }
    }

    /// Fetches Copilot plan info using the primary token
    func fetchCopilotPlanInfo() async -> CopilotPlanInfo? {
        guard let accessToken = getGitHubCopilotAccessToken() else {
            logger.warning("No GitHub Copilot token available for plan info fetch")
            return nil
        }
        return await fetchCopilotPlanInfo(accessToken: accessToken)
    }

    /// Gets OpenRouter API key from OpenCode auth
    /// - Returns: API key string if available, nil otherwise
    func getOpenRouterAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.openrouter?.key
    }

    func getOpenCodeAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.opencode?.key
    }

    func getOpenCodeGoAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.openCodeGo?.key
    }

    func getKimiAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        // When only the global key exists, the CN provider claims it via
        // fallback. Yield here so the same auth key is not surfaced twice.
        if auth.kimiForCodingCN == nil && auth.kimiForCoding != nil {
            return nil
        }
        return auth.kimiForCoding?.key
    }

    func getKimiCNAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        // CN-specific key wins; otherwise fall back to the legacy global key name
        // (`kimi-for-coding`) which existing CN users often have under the global slot.
        return auth.kimiForCodingCN?.key ?? auth.kimiForCoding?.key
    }

    func getMiniMaxCodingPlanAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.minimaxCodingPlanGlobal?.key
    }

    func getMiniMaxCodingPlanCNAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.minimaxCodingPlanCN?.key ?? auth.minimaxCodingPlan?.key
    }

    func getZaiCodingPlanAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.zaiCodingPlan?.key
    }

    func getNanoGptAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.nanoGpt?.key
    }

    func getSyntheticAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.synthetic?.key
    }

    func getChutesAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.chutes?.key
    }

    func getMimoAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.mimoForCoding?.key
    }

    func getVolcanoArkCredentials() -> (accessKey: String, secretKey: String)? {
        guard let auth = readOpenCodeAuth(), let raw = auth.volcanoArk?.key else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return (parts[0], parts[1])
    }

    func getHunyuanAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.hunyuan?.key
    }

    func getZhipuGLMAPIKey() -> String? {
        guard let auth = readOpenCodeAuth() else { return nil }
        return auth.zhipuGLM?.key
    }

    func getTavilyAPIKey() -> String? {
        return getTavilyAPIKeyWithSource()?.key
    }

    func getBraveSearchAPIKey() -> String? {
        return getBraveSearchAPIKeyWithSource()?.key
    }

    func getTavilyAPIKeyWithSource() -> (key: String, source: String)? {
        let config = readOpenCodeConfigJSON()
        let searchKeys = readSearchKeysJSON()

        return resolvedSearchAPIKey(
            configSource: SearchAPIKeyLookupSource(
                dictionary: config,
                sourcePath: lastFoundOpenCodeConfigPath?.path,
                paths: [
                    ["mcp", "tavily-search", "environment", "TAVILY_API_KEY"],
                    ["mcp", "tavily-search", "headers", "Authorization"],
                    ["mcp", "tavily-search", "headers", "X-API-Key"],
                    ["mcp", "tavily", "environment", "TAVILY_API_KEY"],
                    ["mcp", "tavily", "headers", "Authorization"],
                    ["mcp", "tavily", "headers", "X-API-Key"]
                ],
                fallbackSourceName: "opencode.json"
            ),
            searchKeysSource: SearchAPIKeyLookupSource(
                dictionary: searchKeys,
                sourcePath: lastFoundSearchKeysPath?.path,
                paths: [
                    ["tavily", "apiKey"],
                    ["tavily", "authorization"],
                    ["tavily", "xApiKey"],
                    ["TAVILY_API_KEY"]
                ],
                fallbackSourceName: "search-keys.json"
            ),
            directEnvironmentVariable: "TAVILY_API_KEY"
        )
    }

    func getBraveSearchAPIKeyWithSource() -> (key: String, source: String)? {
        let config = readOpenCodeConfigJSON()
        let searchKeys = readSearchKeysJSON()

        return resolvedSearchAPIKey(
            configSource: SearchAPIKeyLookupSource(
                dictionary: config,
                sourcePath: lastFoundOpenCodeConfigPath?.path,
                paths: [
                    ["mcp", "brave-search", "environment", "BRAVE_API_KEY"],
                    ["mcp", "brave-search", "headers", "X-Subscription-Token"]
                ],
                fallbackSourceName: "opencode.json"
            ),
            searchKeysSource: SearchAPIKeyLookupSource(
                dictionary: searchKeys,
                sourcePath: lastFoundSearchKeysPath?.path,
                paths: [
                    ["brave-search", "apiKey"],
                    ["brave-search", "subscriptionToken"],
                    ["BRAVE_API_KEY"]
                ],
                fallbackSourceName: "search-keys.json"
            ),
            directEnvironmentVariable: "BRAVE_API_KEY"
        )
    }

    /// Gets Gemini refresh token from discovered Gemini account sources
    /// - Returns: Refresh token string if available, nil otherwise
    func getGeminiRefreshToken() -> String? {
        return getAllGeminiAccounts().first?.refreshToken
    }

    /// Gets Gemini account email from discovered Gemini account sources
    /// - Returns: Email string if available, nil otherwise
    func getGeminiAccountEmail() -> String? {
        return getAllGeminiAccounts().first?.email
    }

    /// Gets all Gemini accounts (NoeFabris/opencode-antigravity-auth + jenslys/opencode-gemini-auth)
    /// and enriches account identity metadata from ~/.gemini/oauth_creds.json when available.
    func getAllGeminiAccounts() -> [GeminiAuthAccount] {
        var accounts: [GeminiAuthAccount] = []
        let oauthCreds = readGeminiOAuthCreds()
        let oauthCredsPayload = decodeGeminiIDTokenPayload(oauthCreds?.idToken)
        let oauthCredsAccountId = normalizedNonEmpty(oauthCredsPayload?.sub)
        let oauthCredsEmail = normalizedNonEmpty(oauthCredsPayload?.email)
        let oauthCredsRefreshToken = normalizedNonEmpty(oauthCreds?.refreshToken)
        let oauthCredsAudience = normalizedNonEmpty(oauthCredsPayload?.audience)
        let oauthCredsClient = geminiOAuthClientCredentials(for: oauthCredsAudience)
        let geminiOAuthCredsSource = lastFoundGeminiOAuthCredsPath?.path ?? geminiOAuthCredsPath().path

        if oauthCreds != nil {
            logger.info(
                """
                Gemini oauth_creds.json discovered: refresh=\(oauthCredsRefreshToken != nil ? "YES" : "NO"), \
                accountId=\(oauthCredsAccountId != nil ? "YES" : "NO"), \
                email=\(oauthCredsEmail != nil ? "YES" : "NO"), \
                audience=\(oauthCredsAudience ?? "unknown")
                """
            )
        }

        if let geminiAuth = readGeminiOAuthAuth() {
            let refresh = geminiAuth.refresh?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts = parseGeminiRefreshParts(refresh)
            if !parts.refreshToken.isEmpty {
                let projectId = parts.projectId ?? parts.managedProjectId ?? ""
                if projectId.isEmpty {
                    logger.warning("Gemini OAuth auth found but project ID is missing")
                }
                let authSource = lastFoundGeminiOAuthPath?.path ?? "auth.json"
                accounts.append(
                    GeminiAuthAccount(
                        index: 0,
                        accountId: nil,
                        email: nil,
                        refreshToken: parts.refreshToken,
                        projectId: projectId,
                        authSource: authSource,
                        sourceLabels: [geminiSourceLabel(for: .opencodeAuth)],
                        clientId: TokenManager.geminiAuthPluginClientId,
                        clientSecret: TokenManager.geminiAuthPluginClientSecret,
                        source: .opencodeAuth
                    )
                )
            } else {
                logger.warning("Gemini OAuth refresh token missing or empty")
            }
        }

        if let antigravity = readAntigravityAccounts(), !antigravity.accounts.isEmpty {
            let authSource = antigravityAccountsPath().path
            let antigravityAccounts = antigravity.accounts.enumerated().compactMap { index, account -> GeminiAuthAccount? in
                if account.enabled == false {
                    logger.info("Skipping disabled Antigravity account at index \(index)")
                    return nil
                }

                let refreshToken = account.refreshToken?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if refreshToken.isEmpty {
                    logger.warning("Skipping Antigravity account at index \(index): missing refresh token")
                    return nil
                }

                let primaryProjectId = account.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let fallbackProjectId = account.managedProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let projectId = primaryProjectId.isEmpty ? fallbackProjectId : primaryProjectId
                if projectId.isEmpty {
                    logger.warning("Skipping Antigravity account at index \(index): missing project ID")
                    return nil
                }

                let normalizedEmail = normalizedNonEmpty(account.email)
                let isRefreshTokenMatch = oauthCredsRefreshToken == refreshToken
                let isEmailMatch: Bool = {
                    guard let lhs = normalizedEmail?.lowercased(),
                          let rhs = oauthCredsEmail?.lowercased() else {
                        return false
                    }
                    return lhs == rhs
                }()
                let matchedOAuthCreds = isRefreshTokenMatch || isEmailMatch

                var sourceLabels = [geminiSourceLabel(for: .antigravity)]
                let mergedAccountId: String?
                let mergedEmail: String?
                if matchedOAuthCreds {
                    sourceLabels = mergeSourceLabels(sourceLabels, [geminiSourceLabel(for: .oauthCreds)])
                    mergedAccountId = oauthCredsAccountId
                    mergedEmail = normalizedEmail ?? oauthCredsEmail
                } else {
                    mergedAccountId = nil
                    mergedEmail = normalizedEmail
                }

                return GeminiAuthAccount(
                    index: index,
                    accountId: mergedAccountId,
                    email: mergedEmail,
                    refreshToken: refreshToken,
                    projectId: projectId,
                    authSource: authSource,
                    sourceLabels: sourceLabels,
                    clientId: TokenManager.geminiClientId,
                    clientSecret: TokenManager.geminiClientSecret,
                    source: .antigravity
                )
            }
            accounts.append(contentsOf: antigravityAccounts)
        }

        if accounts.isEmpty,
           let refreshToken = oauthCredsRefreshToken {
            let standaloneProjectId = normalizedNonEmpty(oauthCreds?.projectId)
                ?? normalizedNonEmpty(oauthCreds?.quotaProjectId)
                ?? normalizedNonEmpty(ProcessInfo.processInfo.environment["GEMINI_PROJECT_ID"])

            if let projectId = standaloneProjectId {
                accounts.append(
                    GeminiAuthAccount(
                        index: 0,
                        accountId: oauthCredsAccountId,
                        email: oauthCredsEmail,
                        refreshToken: refreshToken,
                        projectId: projectId,
                        authSource: geminiOAuthCredsSource,
                        sourceLabels: [geminiSourceLabel(for: .oauthCreds)],
                        clientId: oauthCredsClient.clientId,
                        clientSecret: oauthCredsClient.clientSecret,
                        source: .oauthCreds
                    )
                )
                logger.info("Gemini oauth_creds.json used as standalone account source")
            } else {
                logger.info("Gemini oauth_creds.json found but project ID is missing; skipping standalone account source")
            }
        }

        if accounts.isEmpty {
            return []
        }

        return accounts.enumerated().map { index, account in
            GeminiAuthAccount(
                index: index,
                accountId: account.accountId,
                email: account.email,
                refreshToken: account.refreshToken,
                projectId: account.projectId,
                authSource: account.authSource,
                sourceLabels: account.sourceLabels,
                clientId: account.clientId,
                clientSecret: account.clientSecret,
                source: account.source
            )
        }
    }

    /// Gets the count of registered Gemini accounts
    func getGeminiAccountCount() -> Int {
        return getAllGeminiAccounts().count
    }

    // MARK: - Gemini OAuth Token Refresh

    /// Public Google OAuth client credentials for CLI/installed apps
    /// These are NOT secrets - they are public client IDs/secrets for installed applications
    /// See: https://developers.google.com/identity/protocols/oauth2/native-app
    private static let geminiClientId = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    private static let geminiClientSecret = "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"
    
    /// OAuth client used by jenslys/opencode-gemini-auth plugin
    private static let geminiAuthPluginClientId = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com"
    private static let geminiAuthPluginClientSecret = "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"

    /// Refreshes Gemini OAuth access token using refresh token
    /// - Parameters:
    ///   - refreshToken: The refresh token from Antigravity accounts
    ///   - clientId: Google OAuth client ID (default: public CLI client ID)
    ///   - clientSecret: Google OAuth client secret (default: public CLI client secret)
    /// - Returns: New access token if successful, nil otherwise
    func refreshGeminiAccessToken(
        refreshToken: String,
        clientId: String = TokenManager.geminiClientId,
        clientSecret: String = TokenManager.geminiClientSecret
    ) async -> String? {
        let endpoint = "https://oauth2.googleapis.com/token"

        guard let url = URL(string: endpoint) else {
            logger.error("Invalid OAuth endpoint URL")
            return nil
        }

        // Build request body
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "grant_type", value: "refresh_token")
        ]

        guard let bodyString = components.query else {
            logger.error("Failed to build request body")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyString.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid response type")
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                logger.error("OAuth token refresh failed with status: \(httpResponse.statusCode)")
                return nil
            }

            let tokenResponse = try JSONDecoder().decode(GeminiTokenResponse.self, from: data)
            logger.info("Successfully refreshed Gemini access token")
            return tokenResponse.access_token
        } catch {
            logger.error("Failed to refresh Gemini token: \(error.localizedDescription)")
            return nil
        }
    }

    /// Convenience method to refresh Gemini token using stored refresh token
    /// - Returns: New access token if successful, nil otherwise
    func refreshGeminiAccessTokenFromStorage() async -> String? {
        guard let account = getAllGeminiAccounts().first else {
            logger.warning("No Gemini refresh token found in storage")
            return nil
        }

        return await refreshGeminiAccessToken(
            refreshToken: account.refreshToken,
            clientId: account.clientId,
            clientSecret: account.clientSecret
        )
    }

    // MARK: - Debug Environment Info

    private func gitHubCopilotTokenStatusLine() -> String {
        let discovered = getGitHubCopilotAccounts()
        if !discovered.isEmpty {
            var labels: [String] = []
            for account in discovered {
                let raw =
                    account.login?.nilIfEmpty
                    ?? account.accountId?.nilIfEmpty
                    ?? "unknown"
                if !raw.isEmpty, !labels.contains(raw) {
                    labels.append(raw)
                }
            }
            let suffix = labels.isEmpty ? "" : ": " + labels.joined(separator: ", ")
            return "  [GitHub Copilot] CONFIGURED (\(discovered.count) account(s)\(suffix))"
        }
        if let auth = readOpenCodeAuth(),
           let token = auth.githubCopilot?.access.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return "  [GitHub Copilot] CONFIGURED (auth.json)"
        }
        return "  [GitHub Copilot] NOT CONFIGURED"
    }

    private func effectiveGitHubCopilotDiscoverySummary() -> String {
        let discovered = getGitHubCopilotAccounts()
        guard !discovered.isEmpty else { return "NOT FOUND" }
        let parts = discovered.map { account in
            let id =
                account.login?.nilIfEmpty
                ?? account.accountId?.nilIfEmpty
                ?? "unknown"
            return "\(id) via \(account.source.description)"
        }
        return "FOUND (\(discovered.count) account(s): \(parts.joined(separator: ", ")))"
    }

    private func authDiscoverySummaryLines() -> [String] {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let openCodeAuth = readOpenCodeAuth()
        let openCodePath = lastFoundAuthPath?.path ?? "~/.local/share/opencode/auth.json"

        var lines: [String] = []
        lines.append("Auth Discovery Summary:")
        lines.append(String(repeating: "─", count: 40))

        func shortPath(_ path: String) -> String {
            let homePath = homeDir.path
            if path.hasPrefix(homePath) {
                let suffix = path.dropFirst(homePath.count)
                return "~\(suffix)"
            }
            return path
        }

        func tokenStatus(hasAuth: Bool, token: String?, accountId: String?) -> String {
            guard hasAuth else { return "NOT FOUND" }
            guard let token = token, !token.isEmpty else { return "MISSING TOKEN" }
            let accountIdStatus = (accountId == nil || accountId?.isEmpty == true) ? "NO" : "YES"
            return "FOUND (token, accountId: \(accountIdStatus))"
        }

        func fileStatus(path: URL, tokenKeys: Set<String>) -> String {
            if !fileManager.fileExists(atPath: path.path) {
                return "NOT FOUND"
            }
            guard let dict = readJSONDictionary(at: path) else {
                return "UNREADABLE"
            }
            let hasToken = findStringValue(in: dict, matching: tokenKeys) != nil
            return hasToken ? "FOUND" : "MISSING TOKEN"
        }

        func keychainStatus(service: String, tokenKeys: Set<String>) -> String {
            guard let dict = readKeychainJSON(service: service) else { return "NOT FOUND" }
            let hasToken = findStringValue(in: dict, matching: tokenKeys) != nil
            return hasToken ? "FOUND" : "MISSING TOKEN"
        }

        func copilotFileStatus(path: URL) -> String {
            if !fileManager.fileExists(atPath: path.path) {
                return "NOT FOUND"
            }
            guard let dict = readJSONDictionary(at: path) else {
                return "UNREADABLE"
            }
            let source: CopilotAuthSource = path.lastPathComponent == "apps.json" ? .vscodeApps : .vscodeHosts
            let accounts = parseCopilotAccounts(from: dict, source: source, authSource: path.path)
            if accounts.isEmpty {
                return "FOUND (no token entries)"
            }
            return "FOUND (\(accounts.count) account(s))"
        }

        func browserCookieStatus() -> String {
            do {
                _ = try BrowserCookieService.shared.getGitHubCookies()
                return "AVAILABLE"
            } catch {
                return "NOT AVAILABLE"
            }
        }

        lines.append("[ChatGPT]")
        let openCodeOpenAIMetadata = resolvedOpenAIAuthMetadata(from: openCodeAuth?.openai)
        let openAIStatus = tokenStatus(
            hasAuth: openCodeAuth?.openai != nil || openCodeAuth?.openaiAPIKey != nil,
            token: openCodeAuth?.openai?.access ?? openCodeAuth?.openaiAPIKey?.key,
            accountId: openCodeOpenAIMetadata.accountId ?? openCodeOpenAIMetadata.overrideAccountId
        )
        lines.append("  OpenCode auth.json (\(shortPath(openCodePath))): \(openAIStatus)")

        let openCodeMultiAuthPaths = openCodeMultiAuthPaths()
        let existingOpenCodeMultiAuthPaths = openCodeMultiAuthPaths.filter { fileManager.fileExists(atPath: $0.path) }
        if existingOpenCodeMultiAuthPaths.isEmpty {
            let defaultOpenCodeAuth = homeDir.appendingPathComponent(".opencode").appendingPathComponent("auth").appendingPathComponent("openai.json")
            let defaultOpenCodeAccounts = homeDir.appendingPathComponent(".opencode").appendingPathComponent("openai-codex-accounts.json")
            lines.append("  oc-chatgpt-multi-auth auth (\(shortPath(defaultOpenCodeAuth.path))): NOT FOUND")
            lines.append("  oc-chatgpt-multi-auth accounts (\(shortPath(defaultOpenCodeAccounts.path))): NOT FOUND")
        } else {
            for path in existingOpenCodeMultiAuthPaths {
                let accountCount = readOpenAIMultiAuthFiles(at: [path]).count
                let label = path.lastPathComponent == "openai.json"
                    ? "oc-chatgpt-multi-auth auth"
                    : "oc-chatgpt-multi-auth accounts"
                lines.append("  \(label) (\(shortPath(path.path))): FOUND (\(accountCount) account(s))")
            }
        }

        let codexAuthPath = homeDir.appendingPathComponent(".codex").appendingPathComponent("auth.json")
        if fileManager.fileExists(atPath: codexAuthPath.path) {
            if let codexAuth = readCodexAuth() {
                let status = tokenStatus(
                    hasAuth: true,
                    token: codexAuth.tokens?.accessToken,
                    accountId: codexAuth.tokens?.accountId
                )
                lines.append("  Codex auth.json (\(shortPath(codexAuthPath.path))): \(status)")
            } else {
                lines.append("  Codex auth.json (\(shortPath(codexAuthPath.path))): PARSE FAILED")
            }
        } else {
            lines.append("  Codex auth.json (\(shortPath(codexAuthPath.path))): NOT FOUND")
        }

        let codexLBAccounts = readCodexLBOpenAIAccounts()
        let codexLBCandidates = codexLBStorageCandidates()
        let codexLBExistingCandidate = codexLBCandidates.first {
            fileManager.fileExists(atPath: $0.databaseURL.path) || fileManager.fileExists(atPath: $0.keyURL.path)
        }
        if let storePath = lastFoundCodexLBStorePath,
           let keyPath = lastFoundCodexLBKeyPath {
            lines.append(
                "  codex-lb store.db (\(shortPath(storePath.path))): FOUND (\(codexLBAccounts.count) account(s))"
            )
            lines.append("  codex-lb encryption.key (\(shortPath(keyPath.path))): FOUND")
        } else if let candidate = codexLBExistingCandidate {
            let dbStatus: String
            if !fileManager.fileExists(atPath: candidate.databaseURL.path) {
                dbStatus = "NOT FOUND"
            } else if !fileManager.isReadableFile(atPath: candidate.databaseURL.path) {
                dbStatus = "UNREADABLE"
            } else {
                dbStatus = "FOUND"
            }

            let keyStatus: String
            if !fileManager.fileExists(atPath: candidate.keyURL.path) {
                keyStatus = "NOT FOUND"
            } else if !fileManager.isReadableFile(atPath: candidate.keyURL.path) {
                keyStatus = "UNREADABLE"
            } else {
                keyStatus = "FOUND"
            }

            lines.append("  codex-lb store.db (\(shortPath(candidate.databaseURL.path))): \(dbStatus)")
            lines.append("  codex-lb encryption.key (\(shortPath(candidate.keyURL.path))): \(keyStatus)")
            if dbStatus == "FOUND", keyStatus == "FOUND" {
                lines.append("  codex-lb accounts: 0 decryptable account(s)")
            }
        } else {
            let defaultCodexLBStore = homeDir.appendingPathComponent(".codex-lb").appendingPathComponent("store.db")
            let defaultCodexLBKey = homeDir.appendingPathComponent(".codex-lb").appendingPathComponent("encryption.key")
            lines.append("  codex-lb store.db (\(shortPath(defaultCodexLBStore.path))): NOT FOUND")
            lines.append("  codex-lb encryption.key (\(shortPath(defaultCodexLBKey.path))): NOT FOUND")
        }

        lines.append("")
        lines.append("[Claude]")
        lines.append("  OpenCode auth.json (\(shortPath(openCodePath))): \(tokenStatus(hasAuth: openCodeAuth != nil, token: openCodeAuth?.anthropic?.access, accountId: openCodeAuth?.anthropic?.accountId))")
        let claudeTokenKeys: Set<String> = ["accesstoken", "access", "oauthtoken", "token"]
        let claudeKeychainPrimary = "Claude Code-credentials"
        let claudeKeychainSecondary = "Claude Code"
        lines.append("  Claude Code Keychain (\(claudeKeychainPrimary)): \(keychainStatus(service: claudeKeychainPrimary, tokenKeys: claudeTokenKeys))")
        lines.append("  Claude Code Keychain (\(claudeKeychainSecondary)): \(keychainStatus(service: claudeKeychainSecondary, tokenKeys: claudeTokenKeys))")

        if let anthropicAuthPath = claudeAnthropicAuthPaths().first {
            let anthropicAccounts = readClaudeAnthropicAuthFiles(at: [anthropicAuthPath])
            if anthropicAccounts.isEmpty {
                lines.append("  opencode-anthropic-auth accounts.json (\(shortPath(anthropicAuthPath.path))): \(fileStatus(path: anthropicAuthPath, tokenKeys: claudeTokenKeys))")
            } else {
                lines.append("  opencode-anthropic-auth accounts.json (\(shortPath(anthropicAuthPath.path))): FOUND (\(anthropicAccounts.count) account(s))")
            }
        }

        let claudePaths = claudeCodeAuthPaths()
        if let configPath = claudePaths.first {
            lines.append("  Claude Code auth.json (\(shortPath(configPath.path))): \(fileStatus(path: configPath, tokenKeys: claudeTokenKeys))")
        }

        lines.append("")
        lines.append("[GitHub Copilot]")
        lines.append("  OpenCode auth.json (\(shortPath(openCodePath))): \(tokenStatus(hasAuth: openCodeAuth != nil, token: openCodeAuth?.githubCopilot?.access, accountId: openCodeAuth?.githubCopilot?.accountId))")

        // Copilot CLI Keychain status
        let copilotCliKeychainAccounts = readCopilotCliKeychainAccounts()
        let copilotCliStatus = copilotCliKeychainAccounts.isEmpty ? "NOT FOUND" : "FOUND (\(copilotCliKeychainAccounts.count) account(s))"
        lines.append("  Copilot CLI Keychain (copilot-cli): \(copilotCliStatus)")

        let copilotBase = homeDir
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("github-copilot")
        let copilotHosts = copilotBase.appendingPathComponent("hosts.json")
        let copilotApps = copilotBase.appendingPathComponent("apps.json")
        lines.append("  VS Code hosts.json (\(shortPath(copilotHosts.path))): \(copilotFileStatus(path: copilotHosts))")
        lines.append("  VS Code apps.json (\(shortPath(copilotApps.path))): \(copilotFileStatus(path: copilotApps))")
        lines.append("  Browser Cookies: \(browserCookieStatus())")
        lines.append("  Effective Copilot Discovery: \(effectiveGitHubCopilotDiscoverySummary())")

        lines.append("")
        lines.append("[Gemini CLI]")
        let geminiAuth = readGeminiOAuthAuth()
        let geminiAuthPath = lastFoundGeminiOAuthPath?.path ?? "auth.json"
        if let geminiAuth = geminiAuth, let refresh = geminiAuth.refresh, !refresh.isEmpty {
            lines.append("  OpenCode auth.json (google.oauth, jenslys/opencode-gemini-auth, \(shortPath(geminiAuthPath))): FOUND")
        } else {
            lines.append("  OpenCode auth.json (google.oauth, jenslys/opencode-gemini-auth, \(shortPath(geminiAuthPath))): NOT FOUND")
        }
        let geminiOAuthCreds = readGeminiOAuthCreds()
        let geminiOAuthCredsPath = lastFoundGeminiOAuthCredsPath?.path ?? geminiOAuthCredsPath().path
        if let geminiOAuthCreds {
            let refreshStatus = normalizedNonEmpty(geminiOAuthCreds.refreshToken) == nil ? "MISSING REFRESH TOKEN" : "FOUND"
            let payload = decodeGeminiIDTokenPayload(geminiOAuthCreds.idToken)
            let accountIdStatus = normalizedNonEmpty(payload?.sub) == nil ? "NO" : "YES"
            let emailStatus = normalizedNonEmpty(payload?.email) == nil ? "NO" : "YES"
            lines.append("  Gemini oauth_creds.json (\(shortPath(geminiOAuthCredsPath))): \(refreshStatus) (accountId: \(accountIdStatus), email: \(emailStatus))")
        } else {
            lines.append("  Gemini oauth_creds.json (\(shortPath(geminiOAuthCredsPath))): NOT FOUND")
        }
        if let accounts = readAntigravityAccounts() {
            lines.append("  Antigravity accounts (NoeFabris/opencode-antigravity-auth, \(shortPath(antigravityAccountsPath().path))): FOUND (\(accounts.accounts.count) account(s))")
        } else {
            lines.append("  Antigravity accounts (NoeFabris/opencode-antigravity-auth, \(shortPath(antigravityAccountsPath().path))): NOT FOUND")
        }

        lines.append(String(repeating: "─", count: 40))
        return lines
    }

    /// Returns debug environment info as a string for error dialogs
    func getDebugEnvironmentInfo() -> String {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser

        var debugLines: [String] = []
        debugLines.append("Environment Info:")
        debugLines.append(String(repeating: "─", count: 40))

        // 0. XDG_DATA_HOME environment variable
        let hasXdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]?.isEmpty == false
        if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdgDataHome.isEmpty {
            debugLines.append("[XDG_DATA_HOME] SET: \(xdgDataHome)")
        } else {
            debugLines.append("[XDG_DATA_HOME] NOT SET (using default ~/.local/share)")
        }

        // 1. Check all possible auth.json paths (fallback order)
        debugLines.append("")
        debugLines.append("Auth File Search:")
        let authPaths = getAuthFilePaths()
        var foundAuthPath: URL?

        for (index, authPath) in authPaths.enumerated() {
            let priority = index + 1
            let pathLabel: String
            if hasXdgDataHome {
                switch index {
                case 0:
                    pathLabel = "$XDG_DATA_HOME/opencode"
                case 1:
                    pathLabel = "~/.local/share/opencode"
                default:
                    pathLabel = "~/Library/Application Support/opencode"
                }
            } else {
                switch index {
                case 0:
                    pathLabel = "~/.local/share/opencode"
                default:
                    pathLabel = "~/Library/Application Support/opencode"
                }
            }

            if fileManager.fileExists(atPath: authPath.path) {
                if let content = try? String(contentsOf: authPath, encoding: .utf8) {
                    let lineCount = content.components(separatedBy: .newlines).count
                    let byteCount = content.utf8.count
                    let marker = foundAuthPath == nil ? "ACTIVE" : "SHADOWED"
                    debugLines.append("  [\(priority)] [\(marker)] \(pathLabel)/auth.json")
                    debugLines.append("      Path: \(authPath.path)")
                    debugLines.append("      Lines: \(lineCount), Bytes: \(byteCount)")
                    if foundAuthPath == nil {
                        foundAuthPath = authPath
                    }
                } else {
                    debugLines.append("  [\(priority)] [UNREADABLE] \(pathLabel)/auth.json")
                    debugLines.append("      Path: \(authPath.path)")
                }
            } else {
                debugLines.append("  [\(priority)] [NOT FOUND] \(pathLabel)/auth.json")
                debugLines.append("      Path: \(authPath.path)")
            }
        }

        if let activePath = foundAuthPath {
            debugLines.append("  [Result] Using: \(activePath.path)")
        } else {
            debugLines.append("  [Result] NO VALID auth.json FOUND")
        }

        // 2. Check ~/.config/opencode directory (antigravity-accounts.json)
        debugLines.append("")
        debugLines.append("Config Directory (~/.config/opencode):")
        let configDir = homeDir
            .appendingPathComponent(".config")
            .appendingPathComponent("opencode")

        if fileManager.fileExists(atPath: configDir.path) {
            if let contents = try? fileManager.contentsOfDirectory(atPath: configDir.path) {
                debugLines.append("  [EXISTS] \(contents.count) item(s)")
                for item in contents.sorted() {
                    var isDir: ObjCBool = false
                    let itemPath = configDir.appendingPathComponent(item).path
                    fileManager.fileExists(atPath: itemPath, isDirectory: &isDir)
                    let typeIndicator = isDir.boolValue ? "[DIR]" : "[FILE]"
                    debugLines.append("    \(typeIndicator) \(item)")
                }
            } else {
                debugLines.append("  [UNREADABLE] Unable to list contents (permission denied or error)")
            }
        } else {
            debugLines.append("  [NOT FOUND]")
        }

        // 3. Token availability summary (without revealing actual tokens)
        debugLines.append("")
        debugLines.append("Token Status:")
        if let auth = readOpenCodeAuth() {
            debugLines.append("  [Anthropic] \(auth.anthropic != nil ? "CONFIGURED" : "NOT CONFIGURED")")
            debugLines.append("  [OpenAI] \((auth.openai != nil || auth.openaiAPIKey != nil) ? "CONFIGURED" : "NOT CONFIGURED")")
            debugLines.append(gitHubCopilotTokenStatusLine())
            debugLines.append("  [OpenRouter] \(auth.openrouter != nil ? "CONFIGURED" : "NOT CONFIGURED")")
            debugLines.append("  [OpenCode] \(auth.opencode != nil ? "CONFIGURED" : "NOT CONFIGURED")")
            debugLines.append("  [OpenCode Go] \(auth.openCodeGo != nil ? "CONFIGURED" : "NOT CONFIGURED")")
            debugLines.append("  [Kimi] \(auth.kimiForCoding != nil ? "CONFIGURED" : "NOT CONFIGURED")")
            debugLines.append("  [Kimi CN] \(auth.kimiForCodingCN != nil ? "CONFIGURED" : "NOT CONFIGURED")")
            debugLines.append("  [MiniMax Coding Plan] \(auth.minimaxCodingPlan != nil ? "CONFIGURED" : "NOT CONFIGURED")")
            debugLines.append("  [MiniMax Coding Plan CN] \(auth.minimaxCodingPlanCN != nil ? "CONFIGURED" : "NOT CONFIGURED")")
            debugLines.append("  [Z.AI Coding Plan] \(auth.zaiCodingPlan != nil ? "CONFIGURED" : "NOT CONFIGURED")")
            debugLines.append("  [Nano-GPT] \(auth.nanoGpt != nil ? "CONFIGURED" : "NOT CONFIGURED")")
        } else {
            debugLines.append("  [auth.json] PARSE FAILED or NOT FOUND")
        }

        // 4. Antigravity accounts
        if let accounts = readAntigravityAccounts() {
            let activeIndexText: String
            if let activeIndex = accounts.activeIndex {
                let invalidMarker = activeIndex < 0 || activeIndex >= accounts.accounts.count ? " (INVALID)" : ""
                activeIndexText = "\(activeIndex)\(invalidMarker)"
            } else {
                activeIndexText = "n/a"
            }
            debugLines.append("  [Antigravity] \(accounts.accounts.count) account(s), active index: \(activeIndexText)")
        } else {
            debugLines.append("  [Antigravity] NOT CONFIGURED")
        }
        if let geminiOAuthCreds = readGeminiOAuthCreds() {
            let refreshStatus = normalizedNonEmpty(geminiOAuthCreds.refreshToken) == nil ? "NO" : "YES"
            let payload = decodeGeminiIDTokenPayload(geminiOAuthCreds.idToken)
            let accountIdStatus = normalizedNonEmpty(payload?.sub) == nil ? "NO" : "YES"
            debugLines.append("  [Gemini oauth_creds] refreshToken: \(refreshStatus), accountId: \(accountIdStatus)")
        } else {
            debugLines.append("  [Gemini oauth_creds] NOT CONFIGURED")
        }

        // 5. Codex native auth (~/.codex/auth.json) - fallback for OpenAI token
        debugLines.append("")
        debugLines.append("Codex Native Auth (~/.codex/auth.json):")
        let codexAuthPath = homeDir.appendingPathComponent(".codex").appendingPathComponent("auth.json")
        if fileManager.fileExists(atPath: codexAuthPath.path) {
            if let codexAuth = readCodexAuth() {
                let hasToken = codexAuth.tokens?.accessToken != nil
                let hasAccountId = codexAuth.tokens?.accountId != nil
                let hasAPIKey = codexAuth.openaiAPIKey != nil
                debugLines.append("  [EXISTS] token: \(hasToken ? "YES" : "NO"), accountId: \(hasAccountId ? "YES" : "NO"), apiKey: \(hasAPIKey ? "YES" : "NO")")
            } else {
                debugLines.append("  [PARSE FAILED]")
            }
        } else {
            debugLines.append("  [NOT FOUND]")
        }

        // 6. codex-lb multi-account auth (~/.codex-lb/store.db + encryption.key)
        debugLines.append("")
        debugLines.append("codex-lb Auth (~/.codex-lb):")
        let codexLBAccounts = readCodexLBOpenAIAccounts()
        if let storePath = lastFoundCodexLBStorePath,
           let keyPath = lastFoundCodexLBKeyPath {
            debugLines.append("  [FOUND] store.db: \(storePath.path)")
            debugLines.append("  [FOUND] encryption.key: \(keyPath.path)")
            debugLines.append("  [ACCOUNTS] \(codexLBAccounts.count) decryptable account(s)")
        } else {
            let candidates = codexLBStorageCandidates()
            if let candidate = candidates.first(where: {
                fileManager.fileExists(atPath: $0.databaseURL.path) || fileManager.fileExists(atPath: $0.keyURL.path)
            }) {
                let dbState = fileManager.fileExists(atPath: candidate.databaseURL.path) ? "FOUND" : "NOT FOUND"
                let keyState = fileManager.fileExists(atPath: candidate.keyURL.path) ? "FOUND" : "NOT FOUND"
                debugLines.append("  [\(dbState)] store.db: \(candidate.databaseURL.path)")
                debugLines.append("  [\(keyState)] encryption.key: \(candidate.keyURL.path)")
                debugLines.append("  [ACCOUNTS] 0 decryptable account(s)")
            } else {
                let defaultStore = homeDir.appendingPathComponent(".codex-lb").appendingPathComponent("store.db")
                let defaultKey = homeDir.appendingPathComponent(".codex-lb").appendingPathComponent("encryption.key")
                debugLines.append("  [NOT FOUND] store.db: \(defaultStore.path)")
                debugLines.append("  [NOT FOUND] encryption.key: \(defaultKey.path)")
            }
        }

        debugLines.append("")
        debugLines.append(contentsOf: authDiscoverySummaryLines())

        debugLines.append(String(repeating: "─", count: 40))

        return debugLines.joined(separator: "\n")
    }

    func logDebugEnvironmentInfo() {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser

        var debugLines: [String] = []
        debugLines.append("========== Environment Debug Info ==========")

        // 0. XDG_DATA_HOME environment variable
        let hasXdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]?.isEmpty == false
        if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], !xdgDataHome.isEmpty {
            debugLines.append("[XDG_DATA_HOME] SET: \(xdgDataHome)")
        } else {
            debugLines.append("[XDG_DATA_HOME] NOT SET (using default ~/.local/share)")
        }

        // 1. Check all possible auth.json paths (fallback order)
        debugLines.append("---------- Auth File Search ----------")
        let authPaths = getAuthFilePaths()
        var foundAuthPath: URL?

        for (index, authPath) in authPaths.enumerated() {
            let priority = index + 1
            let pathLabel: String
            if hasXdgDataHome {
                switch index {
                case 0:
                    pathLabel = "$XDG_DATA_HOME/opencode"
                case 1:
                    pathLabel = "~/.local/share/opencode"
                default:
                    pathLabel = "~/Library/Application Support/opencode"
                }
            } else {
                switch index {
                case 0:
                    pathLabel = "~/.local/share/opencode"
                default:
                    pathLabel = "~/Library/Application Support/opencode"
                }
            }

            if fileManager.fileExists(atPath: authPath.path) {
                if let content = try? String(contentsOf: authPath, encoding: .utf8) {
                    let lineCount = content.components(separatedBy: .newlines).count
                    let byteCount = content.utf8.count
                    let marker = foundAuthPath == nil ? "ACTIVE" : "SHADOWED"
                    debugLines.append("[\(priority)] [\(marker)] \(pathLabel)/auth.json")
                    debugLines.append("    Path: \(authPath.path)")
                    debugLines.append("    Lines: \(lineCount), Bytes: \(byteCount)")
                    if foundAuthPath == nil {
                        foundAuthPath = authPath
                    }
                } else {
                    debugLines.append("[\(priority)] [UNREADABLE] \(pathLabel)/auth.json")
                    debugLines.append("    Path: \(authPath.path)")
                }
            } else {
                debugLines.append("[\(priority)] [NOT FOUND] \(pathLabel)/auth.json")
                debugLines.append("    Path: \(authPath.path)")
            }
        }

        if let activePath = foundAuthPath {
            debugLines.append("[Result] Using auth from: \(activePath.path)")
        } else {
            debugLines.append("[Result] NO VALID auth.json FOUND IN ANY LOCATION")
        }

        // 2. ~/.local/share/opencode directory contents
        debugLines.append("---------- Directory Contents ----------")
        let opencodeDir = homeDir
            .appendingPathComponent(".local")
            .appendingPathComponent("share")
            .appendingPathComponent("opencode")

        if fileManager.fileExists(atPath: opencodeDir.path) {
            if let contents = try? fileManager.contentsOfDirectory(atPath: opencodeDir.path) {
                let fileCount = contents.filter { !$0.hasPrefix(".") }.count
                debugLines.append("[~/.local/share/opencode] EXISTS")
                debugLines.append("  - Items: \(fileCount)")
                for item in contents.sorted() {
                    var isDir: ObjCBool = false
                    let itemPath = opencodeDir.appendingPathComponent(item).path
                    fileManager.fileExists(atPath: itemPath, isDirectory: &isDir)
                    let typeIndicator = isDir.boolValue ? "[DIR]" : "[FILE]"
                    debugLines.append("    \(typeIndicator) \(item)")
                }
            }
        } else {
            debugLines.append("[~/.local/share/opencode] NOT FOUND")
        }

        // 3. ~/Library/Application Support/opencode directory (macOS fallback)
        let macOSDir = homeDir
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("opencode")

        if fileManager.fileExists(atPath: macOSDir.path) {
            if let contents = try? fileManager.contentsOfDirectory(atPath: macOSDir.path) {
                let fileCount = contents.filter { !$0.hasPrefix(".") }.count
                debugLines.append("[~/Library/Application Support/opencode] EXISTS")
                debugLines.append("  - Items: \(fileCount)")
                for item in contents.sorted() {
                    var isDir: ObjCBool = false
                    let itemPath = macOSDir.appendingPathComponent(item).path
                    fileManager.fileExists(atPath: itemPath, isDirectory: &isDir)
                    let typeIndicator = isDir.boolValue ? "[DIR]" : "[FILE]"
                    debugLines.append("    \(typeIndicator) \(item)")
                }
            }
        } else {
            debugLines.append("[~/Library/Application Support/opencode] NOT FOUND")
        }

        // 4. ~/.config/opencode directory (antigravity-accounts.json)
        let configDir = homeDir
            .appendingPathComponent(".config")
            .appendingPathComponent("opencode")

        if fileManager.fileExists(atPath: configDir.path) {
            if let contents = try? fileManager.contentsOfDirectory(atPath: configDir.path) {
                let fileCount = contents.filter { !$0.hasPrefix(".") }.count
                debugLines.append("[~/.config/opencode] EXISTS")
                debugLines.append("  - Items: \(fileCount)")
                for item in contents.sorted() {
                    var isDir: ObjCBool = false
                    let itemPath = configDir.appendingPathComponent(item).path
                    fileManager.fileExists(atPath: itemPath, isDirectory: &isDir)
                    let typeIndicator = isDir.boolValue ? "[DIR]" : "[FILE]"
                    debugLines.append("    \(typeIndicator) \(item)")
                }
            }
        } else {
            debugLines.append("[~/.config/opencode] NOT FOUND")
        }

        // 4. OpenCode CLI existence
        let opencodeCLI = homeDir.appendingPathComponent(".opencode/bin/opencode")
        if fileManager.fileExists(atPath: opencodeCLI.path) {
            debugLines.append("[OpenCode CLI] EXISTS at \(opencodeCLI.path)")
        } else {
            debugLines.append("[OpenCode CLI] NOT FOUND at \(opencodeCLI.path)")
        }

        debugLines.append(contentsOf: authDiscoverySummaryLines())

        // 5. Token existence and lengths (masked for security)
        debugLines.append("---------- Token Status ----------")

        if let auth = readOpenCodeAuth() {
            // Anthropic (Claude)
            if let anthropic = auth.anthropic {
                debugLines.append("[Anthropic] OAuth Present")
                debugLines.append("  - Access Token: \(anthropic.access.count) chars")
                debugLines.append("  - Refresh Token: \(anthropic.refresh.count) chars")
                debugLines.append("  - Account ID: \(anthropic.accountId ?? "nil")")
                let expiresDate = Date(timeIntervalSince1970: TimeInterval(anthropic.expires))
                let isExpired = expiresDate < Date()
                debugLines.append("  - Expires: \(expiresDate) (\(isExpired ? "EXPIRED" : "valid"))")
            } else {
                debugLines.append("[Anthropic] NOT CONFIGURED")
            }

            // OpenAI
            if let openai = auth.openai {
                let metadata = resolvedOpenAIAuthMetadata(from: openai)
                debugLines.append("[OpenAI] OAuth Present")
                debugLines.append("  - Access Token: \(openai.access.count) chars")
                debugLines.append("  - Refresh Token: \(openai.refresh.count) chars")
                let expiresDate = Date(timeIntervalSince1970: TimeInterval(openai.expires))
                let isExpired = expiresDate < Date()
                debugLines.append("  - Expires: \(expiresDate) (\(isExpired ? "EXPIRED" : "valid"))")
                debugLines.append("  - Account ID: \(metadata.accountId ?? "nil")")
                if let overrideAccountId = metadata.overrideAccountId,
                   overrideAccountId != metadata.accountId {
                    debugLines.append("  - Account Override: \(overrideAccountId)")
                }
                debugLines.append("  - Email: \(metadata.email ?? "nil")")
            } else if let openaiAPIKey = auth.openaiAPIKey {
                debugLines.append("[OpenAI] API Key Present")
                debugLines.append("  - Key Length: \(openaiAPIKey.key.count) chars")
                debugLines.append("  - Key Preview: \(maskToken(openaiAPIKey.key))")
            } else {
                debugLines.append("[OpenAI] NOT CONFIGURED")
            }

            // GitHub Copilot
            let discoveredCopilotAccounts = getGitHubCopilotAccounts()
            let copilotStatusLine = gitHubCopilotTokenStatusLine().trimmingCharacters(in: .whitespaces)
            debugLines.append(copilotStatusLine)
            if !discoveredCopilotAccounts.isEmpty {
                for account in discoveredCopilotAccounts {
                    let accountLabel =
                        account.login?.nilIfEmpty
                        ?? account.accountId?.nilIfEmpty
                        ?? "unknown"
                    debugLines.append("  - Account: \(accountLabel)")
                    debugLines.append("  - Source: \(account.source.description)")
                }
            }

            // OpenRouter
            if let openrouter = auth.openrouter {
                debugLines.append("[OpenRouter] API Key Present")
                debugLines.append("  - Key Length: \(openrouter.key.count) chars")
                debugLines.append("  - Key Preview: \(maskToken(openrouter.key))")
            } else {
                debugLines.append("[OpenRouter] NOT CONFIGURED")
            }

            // OpenCode
            if let opencode = auth.opencode {
                debugLines.append("[OpenCode] API Key Present")
                debugLines.append("  - Key Length: \(opencode.key.count) chars")
                debugLines.append("  - Key Preview: \(maskToken(opencode.key))")
            } else {
                debugLines.append("[OpenCode] NOT CONFIGURED")
            }

            if let openCodeGo = auth.openCodeGo {
                debugLines.append("[OpenCode Go] API Key Present")
                debugLines.append("  - Key Length: \(openCodeGo.key.count) chars")
                debugLines.append("  - Key Preview: \(maskToken(openCodeGo.key))")
            } else {
                debugLines.append("[OpenCode Go] NOT CONFIGURED")
            }

            // Kimi for Coding
            if let kimi = auth.kimiForCoding {
                debugLines.append("[Kimi for Coding] API Key Present")
                debugLines.append("  - Key Length: \(kimi.key.count) chars")
                debugLines.append("  - Key Preview: \(maskToken(kimi.key))")
            } else {
                debugLines.append("[Kimi for Coding] NOT CONFIGURED")
            }

            if let kimiCN = auth.kimiForCodingCN {
                debugLines.append("[Kimi for Coding CN] API Key Present")
                debugLines.append("  - Key Length: \(kimiCN.key.count) chars")
                debugLines.append("  - Key Preview: \(maskToken(kimiCN.key))")
            } else {
                debugLines.append("[Kimi for Coding CN] NOT CONFIGURED")
            }

            if let minimaxCodingPlan = auth.minimaxCodingPlan {
                debugLines.append("[MiniMax Coding Plan] API Key Present")
                debugLines.append("  - Key Length: \(minimaxCodingPlan.key.count) chars")
                debugLines.append("  - Key Preview: \(maskToken(minimaxCodingPlan.key))")
            } else {
                debugLines.append("[MiniMax Coding Plan] NOT CONFIGURED")
            }

            if let minimaxCodingPlanCN = auth.minimaxCodingPlanCN {
                debugLines.append("[MiniMax Coding Plan CN] API Key Present")
                debugLines.append("  - Key Length: \(minimaxCodingPlanCN.key.count) chars")
                debugLines.append("  - Key Preview: \(maskToken(minimaxCodingPlanCN.key))")
            } else {
                debugLines.append("[MiniMax Coding Plan CN] NOT CONFIGURED")
            }

            if let zaiCodingPlan = auth.zaiCodingPlan {
                debugLines.append("[Z.AI Coding Plan] API Key Present")
                debugLines.append("  - Key Length: \(zaiCodingPlan.key.count) chars")
                debugLines.append("  - Key Preview: \(maskToken(zaiCodingPlan.key))")
            } else {
                debugLines.append("[Z.AI Coding Plan] NOT CONFIGURED")
            }

            if let nanoGpt = auth.nanoGpt {
                debugLines.append("[Nano-GPT] API Key Present")
                debugLines.append("  - Key Length: \(nanoGpt.key.count) chars")
                debugLines.append("  - Key Preview: \(maskToken(nanoGpt.key))")
            } else {
                debugLines.append("[Nano-GPT] NOT CONFIGURED")
            }
        } else {
            debugLines.append("[auth.json] PARSE FAILED or NOT FOUND")
        }

        // 6. Antigravity accounts
        if let accounts = readAntigravityAccounts() {
            debugLines.append("[Antigravity Accounts] \(accounts.accounts.count) account(s)")
            debugLines.append("  - Active Index: \(accounts.activeIndex.map { String($0) } ?? "n/a")")
            for (index, account) in accounts.accounts.enumerated() {
                let activeMarker = index == accounts.activeIndex ? " (ACTIVE)" : ""
                debugLines.append("  - [\(index)] \(account.email ?? "unknown")\(activeMarker)")
                debugLines.append("    - Enabled: \(account.enabled == false ? "NO" : "YES")")
                debugLines.append("    - Refresh Token: \(account.refreshToken?.count ?? 0) chars")
                debugLines.append("    - Project ID: \(account.projectId ?? account.managedProjectId ?? "missing")")
            }
        } else {
            debugLines.append("[Antigravity Accounts] NOT FOUND or PARSE FAILED")
        }

        if let geminiOAuthCreds = readGeminiOAuthCreds() {
            debugLines.append("[Gemini oauth_creds] FOUND at \(lastFoundGeminiOAuthCredsPath?.path ?? geminiOAuthCredsPath().path)")
            debugLines.append("  - Refresh Token: \(normalizedNonEmpty(geminiOAuthCreds.refreshToken) != nil ? "YES" : "NO")")
            let payload = decodeGeminiIDTokenPayload(geminiOAuthCreds.idToken)
            debugLines.append("  - Account ID: \(normalizedNonEmpty(payload?.sub) ?? "nil")")
            debugLines.append("  - Email: \(normalizedNonEmpty(payload?.email) ?? "nil")")
        } else {
            debugLines.append("[Gemini oauth_creds] NOT FOUND or PARSE FAILED")
        }

        // 7. Codex native auth (~/.codex/auth.json)
        debugLines.append("---------- Codex Native Auth ----------")
        let codexAuthPath = homeDir.appendingPathComponent(".codex").appendingPathComponent("auth.json")
        if fileManager.fileExists(atPath: codexAuthPath.path) {
            if let codexAuth = readCodexAuth() {
                debugLines.append("[Codex Auth] EXISTS at \(codexAuthPath.path)")
                if let tokens = codexAuth.tokens {
                    debugLines.append("  - Access Token: \(tokens.accessToken != nil ? "\(tokens.accessToken!.count) chars" : "nil")")
                    debugLines.append("  - Account ID: \(tokens.accountId ?? "nil")")
                    debugLines.append("  - Refresh Token: \(tokens.refreshToken != nil ? "\(tokens.refreshToken!.count) chars" : "nil")")
                } else {
                    debugLines.append("  - Tokens: nil")
                }
                debugLines.append("  - OPENAI_API_KEY: \(codexAuth.openaiAPIKey != nil ? "SET" : "nil")")
                debugLines.append("  - Last Refresh: \(codexAuth.lastRefresh ?? "nil")")
            } else {
                debugLines.append("[Codex Auth] PARSE FAILED at \(codexAuthPath.path)")
            }
        } else {
            debugLines.append("[Codex Auth] NOT FOUND at \(codexAuthPath.path)")
        }

        // 8. oc-chatgpt-multi-auth (~/.opencode/*.json)
        debugLines.append("---------- oc-chatgpt-multi-auth ----------")
        let openCodeMultiAuthPaths = openCodeMultiAuthPaths()
        let openCodeMultiAuthAccounts = readOpenAIMultiAuthFiles()
        let existingOpenCodeMultiAuthPaths = openCodeMultiAuthPaths.filter { fileManager.fileExists(atPath: $0.path) }
        if existingOpenCodeMultiAuthPaths.isEmpty {
            debugLines.append("[oc-chatgpt-multi-auth] auth/openai.json: NOT FOUND")
            debugLines.append("[oc-chatgpt-multi-auth] openai-codex-accounts.json: NOT FOUND")
        } else {
            for path in existingOpenCodeMultiAuthPaths {
                let accountCount = readOpenAIMultiAuthFiles(at: [path]).count
                debugLines.append("[oc-chatgpt-multi-auth] \(path.path): \(accountCount) account(s)")
            }
            debugLines.append("[oc-chatgpt-multi-auth] Total parsed accounts: \(openCodeMultiAuthAccounts.count)")
        }

        // 9. codex-lb auth (~/.codex-lb/store.db + encryption.key)
        debugLines.append("---------- codex-lb Auth ----------")
        let codexLBAccounts = readCodexLBOpenAIAccounts()
        if let storePath = lastFoundCodexLBStorePath,
           let keyPath = lastFoundCodexLBKeyPath {
            debugLines.append("[codex-lb] store.db: \(storePath.path)")
            debugLines.append("[codex-lb] encryption.key: \(keyPath.path)")
            debugLines.append("[codex-lb] Accounts: \(codexLBAccounts.count) decryptable")
        } else {
            let candidates = codexLBStorageCandidates()
            if let candidate = candidates.first(where: {
                fileManager.fileExists(atPath: $0.databaseURL.path) || fileManager.fileExists(atPath: $0.keyURL.path)
            }) {
                let dbState = fileManager.fileExists(atPath: candidate.databaseURL.path) ? "FOUND" : "NOT FOUND"
                let keyState = fileManager.fileExists(atPath: candidate.keyURL.path) ? "FOUND" : "NOT FOUND"
                debugLines.append("[codex-lb] store.db: \(candidate.databaseURL.path) (\(dbState))")
                debugLines.append("[codex-lb] encryption.key: \(candidate.keyURL.path) (\(keyState))")
                debugLines.append("[codex-lb] Accounts: 0 decryptable")
            } else {
                debugLines.append("[codex-lb] store.db: NOT FOUND")
                debugLines.append("[codex-lb] encryption.key: NOT FOUND")
            }
        }

        debugLines.append("================================================")

        let fullDebugLog = debugLines.joined(separator: "\n")
        logger.info("Authentication environment diagnostics collected")
        #if !CLI_TARGET
        DiagnosticsLogger.shared.log(fullDebugLog, category: "TokenManagerProviderAuth")
        #endif
    }

    /// Masks a token for secure logging (shows first 4 and last 4 chars)
    private func maskToken(_ token: String) -> String {
        guard token.count > 8 else { return "***" }
        let prefix = String(token.prefix(4))
        let suffix = String(token.suffix(4))
        return "\(prefix)...\(suffix)"
    }

}
