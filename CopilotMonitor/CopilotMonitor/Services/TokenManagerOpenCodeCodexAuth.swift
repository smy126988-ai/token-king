//
//  TokenManagerOpenCodeCodexAuth.swift
//  CopilotMonitor
//
//  Token King — extension split of TokenManager.
//  Holds the OpenCode / Codex / codex-lb auth readers and shared JSON helpers.
//  All members remain on the same TokenManager class via Swift extensions.
//

import Foundation
import Security
import SQLite3
import CommonCrypto
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "TokenManager")

extension TokenManager {
    // MARK: - OpenCode Auth File Reading

    func buildOpenCodeFilePaths(
        envVarName: String,
        envRelativePathComponents: [String],
        fallbackRelativePathComponents: [[String]]
    ) -> [URL] {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        var candidates: [URL] = []

        if let envBasePath = ProcessInfo.processInfo.environment[envVarName],
           !envBasePath.isEmpty {
            let envURL = envRelativePathComponents.reduce(URL(fileURLWithPath: envBasePath)) { partial, component in
                partial.appendingPathComponent(component)
            }
            candidates.append(envURL)
        }

        for relativeComponents in fallbackRelativePathComponents {
            let fallbackURL = relativeComponents.reduce(homeDir) { partial, component in
                partial.appendingPathComponent(component)
            }
            candidates.append(fallbackURL)
        }

        var deduped: [URL] = []
        var visited = Set<String>()
        for candidate in candidates {
            let normalizedPath = candidate.standardizedFileURL.path
            if visited.insert(normalizedPath).inserted {
                deduped.append(candidate)
            }
        }
        return deduped
    }

    /// Possible auth.json locations in priority order:
    /// 1. $XDG_DATA_HOME/opencode/auth.json (if XDG_DATA_HOME is set)
    /// 2. ~/.local/share/opencode/auth.json (XDG default, used by OpenCode)
    /// 3. ~/Library/Application Support/opencode/auth.json (macOS convention fallback)
    func getAuthFilePaths() -> [URL] {
        return buildOpenCodeFilePaths(
            envVarName: "XDG_DATA_HOME",
            envRelativePathComponents: ["opencode", "auth.json"],
            fallbackRelativePathComponents: [
                [".local", "share", "opencode", "auth.json"],
                ["Library", "Application Support", "opencode", "auth.json"]
            ]
        )
    }

    /// Possible opencode.json/opencode.jsonc locations in priority order.
    /// For each directory, opencode.jsonc is preferred over opencode.json
    /// (matching copilothydra behavior):
    /// 1. $XDG_CONFIG_HOME/opencode/opencode.jsonc (if XDG_CONFIG_HOME is set)
    /// 2. $XDG_CONFIG_HOME/opencode/opencode.json  (if XDG_CONFIG_HOME is set)
    /// 3. ~/.config/opencode/opencode.jsonc (XDG default on macOS/Linux)
    /// 4. ~/.config/opencode/opencode.json  (XDG default on macOS/Linux)
    /// 5. ~/.local/share/opencode/opencode.jsonc (fallback)
    /// 6. ~/.local/share/opencode/opencode.json  (fallback)
    /// 7. ~/Library/Application Support/opencode/opencode.jsonc (macOS fallback)
    /// 8. ~/Library/Application Support/opencode/opencode.json  (macOS fallback)
    func getOpenCodeConfigFilePaths() -> [URL] {
        let jsoncPaths = buildOpenCodeFilePaths(
            envVarName: "XDG_CONFIG_HOME",
            envRelativePathComponents: ["opencode", "opencode.jsonc"],
            fallbackRelativePathComponents: [
                [".config", "opencode", "opencode.jsonc"],
                [".local", "share", "opencode", "opencode.jsonc"],
                ["Library", "Application Support", "opencode", "opencode.jsonc"]
            ]
        )
        let jsonPaths = buildOpenCodeFilePaths(
            envVarName: "XDG_CONFIG_HOME",
            envRelativePathComponents: ["opencode", "opencode.json"],
            fallbackRelativePathComponents: [
                [".config", "opencode", "opencode.json"],
                [".local", "share", "opencode", "opencode.json"],
                ["Library", "Application Support", "opencode", "opencode.json"]
            ]
        )

        assert(
            jsoncPaths.count == jsonPaths.count,
            "OpenCode jsonc/json path arrays must remain equal length for correct interleaving"
        )

        return zip(jsoncPaths, jsonPaths).flatMap { [$0, $1] }
    }

    /// Possible search-keys.json locations in priority order:
    /// 1. $XDG_CONFIG_HOME/opencode/search-keys.json (if XDG_CONFIG_HOME is set)
    /// 2. ~/.config/opencode/search-keys.json (XDG default on macOS/Linux)
    /// 3. ~/.local/share/opencode/search-keys.json (fallback)
    /// 4. ~/Library/Application Support/opencode/search-keys.json (macOS fallback)
    func getSearchKeyFilePaths() -> [URL] {
        return buildOpenCodeFilePaths(
            envVarName: "XDG_CONFIG_HOME",
            envRelativePathComponents: ["opencode", "search-keys.json"],
            fallbackRelativePathComponents: [
                [".config", "opencode", "search-keys.json"],
                [".local", "share", "opencode", "search-keys.json"],
                ["Library", "Application Support", "opencode", "search-keys.json"]
            ]
        )
    }

    func readJSONDictionaryAllowingComments(
        from paths: [URL],
        cache: inout [String: Any]?,
        timestamp: inout Date?,
        foundPath: inout URL?,
        warningPrefix: String
    ) -> [String: Any]? {
        if let cache,
           let timestamp,
           Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
            return cache
        }

        let fileManager = FileManager.default
        for candidatePath in paths {
            guard fileManager.fileExists(atPath: candidatePath.path) else {
                continue
            }
            guard fileManager.isReadableFile(atPath: candidatePath.path) else {
                logger.warning("\(warningPrefix) file not readable at \(candidatePath.path)")
                continue
            }

            do {
                let data = try Data(contentsOf: candidatePath)
                let normalizedData = stripJSONComments(from: data)
                let jsonObject = try JSONSerialization.jsonObject(with: normalizedData)
                guard let dict = jsonObject as? [String: Any] else {
                    logger.warning("\(warningPrefix) is not a JSON object at \(candidatePath.path)")
                    continue
                }

                foundPath = candidatePath
                cache = dict
                timestamp = Date()
                return dict
            } catch {
                logger.warning("Failed to parse \(warningPrefix) at \(candidatePath.path): \(error.localizedDescription)")
            }
        }

        foundPath = nil
        cache = nil
        timestamp = nil
        return nil
    }

    func readOpenCodeConfigJSON() -> [String: Any]? {
        return queue.sync {
            return readJSONDictionaryAllowingComments(
                from: getOpenCodeConfigFilePaths(),
                cache: &cachedOpenCodeConfigJSON,
                timestamp: &openCodeConfigCacheTimestamp,
                foundPath: &lastFoundOpenCodeConfigPath,
                warningPrefix: "OpenCode config"
            )
        }
    }

    func readSearchKeysJSON() -> [String: Any]? {
        return queue.sync {
            return readJSONDictionaryAllowingComments(
                from: getSearchKeyFilePaths(),
                cache: &cachedSearchKeysJSON,
                timestamp: &searchKeysCacheTimestamp,
                foundPath: &lastFoundSearchKeysPath,
                warningPrefix: "Search keys config"
            )
        }
    }

    func stripJSONComments(from data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            return data
        }

        enum State {
            case normal
            case string
            case lineComment
            case blockComment
        }

        var result = String()
        result.reserveCapacity(text.count)

        var state: State = .normal
        var isEscaped = false
        let characters = Array(text)
        var index = 0

        while index < characters.count {
            let current = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            switch state {
            case .normal:
                if current == "/", next == "/" {
                    state = .lineComment
                    index += 2
                    continue
                }
                if current == "/", next == "*" {
                    state = .blockComment
                    index += 2
                    continue
                }
                result.append(current)
                if current == "\"" {
                    state = .string
                    isEscaped = false
                }

            case .string:
                result.append(current)
                if isEscaped {
                    isEscaped = false
                } else if current == "\\" {
                    isEscaped = true
                } else if current == "\"" {
                    state = .normal
                }

            case .lineComment:
                if current == "\n" || current == "\r" {
                    result.append(current)
                    state = .normal
                }

            case .blockComment:
                if current == "*", next == "/" {
                    state = .normal
                    index += 2
                    continue
                }
                if current == "\n" || current == "\r" {
                    result.append(current)
                }
            }

            index += 1
        }

        return Data(result.utf8)
    }

    func resolveConfigValue(_ rawValue: String?) -> String? {
        guard var value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("Bearer ") {
            value = String(value.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if value.hasPrefix("{env:"), value.hasSuffix("}") {
            let start = value.index(value.startIndex, offsetBy: 5)
            let end = value.index(before: value.endIndex)
            let envName = String(value[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !envName.isEmpty else { return nil }
            let envValue = ProcessInfo.processInfo.environment[envName]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (envValue?.isEmpty == false) ? envValue : nil
        }

        return value.isEmpty ? nil : value
    }

    func nestedString(
        in dictionary: [String: Any],
        path: [String]
    ) -> String? {
        guard !path.isEmpty else { return nil }
        var current: Any = dictionary
        for key in path {
            guard let nested = current as? [String: Any], let next = nested[key] else {
                return nil
            }
            current = next
        }
        return current as? String
    }

    func hasPlugin(named pluginIdentifier: String, in configDictionary: [String: Any]) -> Bool {
        guard let plugins = valueForNormalizedKey("plugin", in: configDictionary) as? [Any] else {
            return false
        }

        for plugin in plugins {
            guard let rawPlugin = plugin as? String else { continue }
            if rawPlugin.range(of: pluginIdentifier, options: .caseInsensitive) != nil {
                return true
            }
        }
        return false
    }

    func codexEndpointConfiguration(
        from configDictionary: [String: Any]?,
        sourcePath: String? = nil
    ) -> CodexEndpointConfiguration {
        let defaultConfiguration = CodexEndpointConfiguration(
            mode: .directChatGPT,
            source: "Default ChatGPT usage endpoint",
            usesOpenAIProviderBaseURL: false
        )

        guard let configDictionary else {
            return defaultConfiguration
        }

        if let explicitUsageURL = resolveConfigValue(
            nestedString(in: configDictionary, path: ["opencode-bar", "codex", "usageURL"])
        ) {
            if let resolvedURL = URL(string: explicitUsageURL),
               let scheme = resolvedURL.scheme?.lowercased(),
               scheme == "http" || scheme == "https",
               resolvedURL.host != nil {
                return CodexEndpointConfiguration(
                    mode: .external(usageURL: resolvedURL),
                    source: sourcePath ?? "opencode-bar.codex.usageURL",
                    usesOpenAIProviderBaseURL: false
                )
            }

            logger.warning(
                "Ignoring invalid Codex usage URL override '\(explicitUsageURL, privacy: .public)' from \(sourcePath ?? "opencode-bar.codex.usageURL", privacy: .public)"
            )
        }

        if hasPlugin(named: "oc-chatgpt-multi-auth", in: configDictionary) {
            return CodexEndpointConfiguration(
                mode: .directChatGPT,
                source: "oc-chatgpt-multi-auth direct ChatGPT usage endpoint",
                usesOpenAIProviderBaseURL: false
            )
        }

        if let baseURLString = resolveConfigValue(
            nestedString(in: configDictionary, path: ["provider", "openai", "options", "baseURL"])
        ) {
            if let baseURL = URL(string: baseURLString),
               let scheme = baseURL.scheme?.lowercased(),
               scheme == "http" || scheme == "https",
               let host = baseURL.host {
                var components = URLComponents()
                components.scheme = scheme
                components.host = host
                components.port = baseURL.port
                components.path = "/api/codex/usage"

                if let usageURL = components.url {
                    return CodexEndpointConfiguration(
                        mode: .external(usageURL: usageURL),
                        source: sourcePath ?? "provider.openai.options.baseURL",
                        usesOpenAIProviderBaseURL: true
                    )
                }
            }

            logger.warning(
                "Ignoring invalid OpenAI base URL '\(baseURLString, privacy: .public)' from \(sourcePath ?? "provider.openai.options.baseURL", privacy: .public)"
            )
        }

        return defaultConfiguration
    }

    func getCodexEndpointConfiguration() -> CodexEndpointConfiguration {
        let config = readOpenCodeConfigJSON()
        return codexEndpointConfiguration(
            from: config,
            sourcePath: lastFoundOpenCodeConfigPath?.path
        )
    }

    struct SearchAPIKeyLookupSource {
        let dictionary: [String: Any]?
        let sourcePath: String?
        let paths: [[String]]
        let fallbackSourceName: String
    }

    func resolvedSearchAPIKey(
        configSource: SearchAPIKeyLookupSource,
        searchKeysSource: SearchAPIKeyLookupSource,
        directEnvironmentVariable: String
    ) -> (key: String, source: String)? {
        if let configDictionary = configSource.dictionary {
            for path in configSource.paths {
                if let resolved = resolveConfigValue(nestedString(in: configDictionary, path: path)) {
                    return (resolved, configSource.sourcePath ?? configSource.fallbackSourceName)
                }
            }
        }

        if let searchKeysDictionary = searchKeysSource.dictionary {
            for path in searchKeysSource.paths {
                if let resolved = resolveConfigValue(nestedString(in: searchKeysDictionary, path: path)) {
                    return (resolved, searchKeysSource.sourcePath ?? searchKeysSource.fallbackSourceName)
                }
            }
        }

        if let envValue = ProcessInfo.processInfo.environment[directEnvironmentVariable],
           let resolved = resolveConfigValue(envValue) {
            return (resolved, "Environment variable \(directEnvironmentVariable)")
        }

        return nil
    }

    /// Thread-safe read of OpenCode auth tokens with caching
    func readOpenCodeAuth() -> OpenCodeAuth? {
        return queue.sync {
            // Return cached data if still valid
            if let cached = cachedAuth,
               let timestamp = cacheTimestamp,
               Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
                return cached
            }

            let fileManager = FileManager.default
            let paths = getAuthFilePaths()

            for authPath in paths {
                guard fileManager.fileExists(atPath: authPath.path) else {
                    continue
                }
                guard fileManager.isReadableFile(atPath: authPath.path) else {
                    logger.warning("Auth file not readable at \(authPath.path)")
                    continue
                }

                do {
                    let data = try Data(contentsOf: authPath)
                    let auth = try JSONDecoder().decode(OpenCodeAuth.self, from: data)
                    lastFoundAuthPath = authPath
                    cachedAuth = auth
                    cacheTimestamp = Date()
                    logger.info("Successfully loaded OpenCode auth from: \(authPath.path)")
                    return auth
                } catch {
                    logger.warning("Failed to parse auth at \(authPath.path): \(error.localizedDescription)")
                    continue
                }
            }

            lastFoundAuthPath = nil
            cachedAuth = nil
            cacheTimestamp = nil
            logger.error("No valid auth.json found in any location")
            return nil
        }
    }

    func clearOpenCodeAuthCacheForTesting() {
        queue.sync {
            cachedAuth = nil
            cacheTimestamp = nil
            lastFoundAuthPath = nil
            cachedOpenCodeAnthropicCodexAccounts = nil
            openCodeAnthropicCodexAccountsCacheTimestamp = nil
            lastFoundOpenCodeAnthropicCodexAccountPaths = []
        }
    }

    // MARK: - Codex Native Auth File Reading

    func readCodexAuth() -> CodexAuth? {
        return queue.sync {
            if let cached = cachedCodexAuth,
               let timestamp = codexCacheTimestamp,
               Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
                return cached
            }

            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let codexAuthPath = homeDir
                .appendingPathComponent(".codex")
                .appendingPathComponent("auth.json")

            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: codexAuthPath.path) else {
                return nil
            }
            guard fileManager.isReadableFile(atPath: codexAuthPath.path) else {
                logger.warning("Codex auth file not readable at \(codexAuthPath.path)")
                return nil
            }

            do {
                let data = try Data(contentsOf: codexAuthPath)
                let auth = try JSONDecoder().decode(CodexAuth.self, from: data)
                cachedCodexAuth = auth
                codexCacheTimestamp = Date()
                logger.info("Successfully loaded Codex native auth from: \(codexAuthPath.path)")
                return auth
            } catch {
                logger.warning("Failed to parse Codex auth at \(codexAuthPath.path): \(error.localizedDescription)")
                return nil
            }
        }
    }

    // MARK: - codex-lb SQLite Account Discovery

    private enum CodexLBError: LocalizedError {
        case invalidFernetKey
        case invalidFernetToken
        case invalidFernetSignature
        case sqliteOpenFailed
        case sqlitePrepareFailed(String)
        case sqliteStepFailed(Int32)
        case aesDecryptFailed(Int32)
        case invalidDecryptedToken

        var errorDescription: String? {
            switch self {
            case .invalidFernetKey:
                return "Invalid codex-lb Fernet key"
            case .invalidFernetToken:
                return "Invalid codex-lb Fernet token"
            case .invalidFernetSignature:
                return "Invalid codex-lb Fernet signature"
            case .sqliteOpenFailed:
                return "Failed to open codex-lb SQLite database"
            case .sqlitePrepareFailed(let message):
                return "Failed to prepare codex-lb SQLite query: \(message)"
            case .sqliteStepFailed(let status):
                return "Failed to read codex-lb SQLite rows (status \(status))"
            case .aesDecryptFailed(let status):
                return "codex-lb AES decryption failed (status \(status))"
            case .invalidDecryptedToken:
                return "codex-lb decrypted token is empty or invalid"
            }
        }
    }

    struct CodexLBStoragePaths {
        let databaseURL: URL
        let keyURL: URL
    }

    func codexLBStorageCandidates() -> [CodexLBStoragePaths] {
        var basePaths: [URL] = []
        if let customHome = ProcessInfo.processInfo.environment["CODEX_LB_HOME"],
           !customHome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            basePaths.append(URL(fileURLWithPath: customHome, isDirectory: true))
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        basePaths.append(homeDir.appendingPathComponent(".codex-lb", isDirectory: true))
        basePaths.append(URL(fileURLWithPath: "/var/lib/codex-lb", isDirectory: true))

        var visited = Set<String>()
        return basePaths.compactMap { baseURL in
            let normalizedBase = baseURL.standardizedFileURL.path
            guard visited.insert(normalizedBase).inserted else {
                return nil
            }
            return CodexLBStoragePaths(
                databaseURL: baseURL.appendingPathComponent("store.db"),
                keyURL: baseURL.appendingPathComponent("encryption.key")
            )
        }
    }

    func sqliteColumnString(_ statement: OpaquePointer?, index: Int32) -> String? {
        let type = sqlite3_column_type(statement, index)
        switch type {
        case SQLITE_NULL:
            return nil
        case SQLITE_INTEGER:
            return String(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return String(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let textPointer = sqlite3_column_text(statement, index) else { return nil }
            let value = String(cString: textPointer).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        default:
            if let data = sqliteColumnData(statement, index: index),
               let string = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !string.isEmpty {
                return string
            }
            return nil
        }
    }

    func sqliteColumnData(_ statement: OpaquePointer?, index: Int32) -> Data? {
        let type = sqlite3_column_type(statement, index)
        switch type {
        case SQLITE_NULL:
            return nil
        case SQLITE_BLOB:
            guard let blobPointer = sqlite3_column_blob(statement, index) else { return nil }
            let length = Int(sqlite3_column_bytes(statement, index))
            guard length > 0 else { return nil }
            return Data(bytes: blobPointer, count: length)
        case SQLITE_TEXT:
            guard let textPointer = sqlite3_column_text(statement, index) else { return nil }
            return String(cString: textPointer).data(using: .utf8)
        default:
            return nil
        }
    }

    func queryCodexLBEncryptedAccounts(databaseURL: URL) throws -> [CodexLBEncryptedAccount] {
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "opencode-bar-codex-lb-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let tempDBURL = tempDirectory.appendingPathComponent("store.db")
        try fileManager.copyItem(at: databaseURL, to: tempDBURL)

        let optionalSidecars = [
            (
                source: URL(fileURLWithPath: databaseURL.path + "-wal"),
                destination: tempDirectory.appendingPathComponent("store.db-wal")
            ),
            (
                source: URL(fileURLWithPath: databaseURL.path + "-shm"),
                destination: tempDirectory.appendingPathComponent("store.db-shm")
            )
        ]
        for sidecar in optionalSidecars where fileManager.fileExists(atPath: sidecar.source.path) {
            try? fileManager.copyItem(at: sidecar.source, to: sidecar.destination)
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(tempDBURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw CodexLBError.sqliteOpenFailed
        }
        defer { sqlite3_close(db) }

        let queries = [
            """
            SELECT
                id,
                chatgpt_account_id,
                email,
                plan_type,
                status,
                access_token_encrypted,
                refresh_token_encrypted,
                id_token_encrypted,
                last_refresh
            FROM accounts
            """,
            """
            SELECT
                id,
                chatgpt_account_id,
                email,
                NULL AS plan_type,
                NULL AS status,
                access_token_encrypted,
                NULL AS refresh_token_encrypted,
                NULL AS id_token_encrypted,
                NULL AS last_refresh
            FROM accounts
            """,
            """
            SELECT
                id,
                NULL AS chatgpt_account_id,
                email,
                plan_type,
                status,
                access_token_encrypted,
                refresh_token_encrypted,
                id_token_encrypted,
                last_refresh
            FROM accounts
            """,
            """
            SELECT
                id,
                NULL AS chatgpt_account_id,
                email,
                NULL AS plan_type,
                NULL AS status,
                access_token_encrypted,
                NULL AS refresh_token_encrypted,
                NULL AS id_token_encrypted,
                NULL AS last_refresh
            FROM accounts
            """
        ]

        var statement: OpaquePointer?
        var prepared = false
        var prepareError = "Unknown SQLite error"
        for query in queries {
            if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
                prepared = true
                break
            }
            if let errorMessage = sqlite3_errmsg(db) {
                prepareError = String(cString: errorMessage)
            }
        }
        guard prepared, let statement else {
            throw CodexLBError.sqlitePrepareFailed(prepareError)
        }
        defer { sqlite3_finalize(statement) }

        var accounts: [CodexLBEncryptedAccount] = []
        while true {
            let stepStatus = sqlite3_step(statement)
            if stepStatus == SQLITE_DONE {
                break
            }
            if stepStatus != SQLITE_ROW {
                throw CodexLBError.sqliteStepFailed(stepStatus)
            }

            guard let accessTokenEncrypted = sqliteColumnData(statement, index: 5), !accessTokenEncrypted.isEmpty else {
                continue
            }

            let account = CodexLBEncryptedAccount(
                accountId: sqliteColumnString(statement, index: 0),
                chatGPTAccountId: sqliteColumnString(statement, index: 1),
                email: sqliteColumnString(statement, index: 2),
                planType: sqliteColumnString(statement, index: 3),
                status: sqliteColumnString(statement, index: 4),
                accessTokenEncrypted: accessTokenEncrypted,
                refreshTokenEncrypted: sqliteColumnData(statement, index: 6),
                idTokenEncrypted: sqliteColumnData(statement, index: 7),
                lastRefresh: sqliteColumnString(statement, index: 8)
            )
            accounts.append(account)
        }

        return accounts
    }

    func decodeBase64URL(_ rawValue: String) throws -> Data {
        var sanitized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = sanitized.count % 4
        if remainder != 0 {
            sanitized += String(repeating: "=", count: 4 - remainder)
        }

        guard let decoded = Data(base64Encoded: sanitized) else {
            throw CodexLBError.invalidFernetToken
        }
        return decoded
    }

    func decodeCodexLBFernetKey(_ keyData: Data) throws -> Data {
        let keyString = String(data: keyData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        guard !keyString.isEmpty else {
            throw CodexLBError.invalidFernetKey
        }
        let decodedKey = try decodeBase64URL(keyString)
        guard decodedKey.count == 32 else {
            throw CodexLBError.invalidFernetKey
        }
        return decodedKey
    }

    func hmacSHA256(data: Data, key: Data) -> Data {
        var digest = Data(count: Int(CC_SHA256_DIGEST_LENGTH))
        digest.withUnsafeMutableBytes { digestBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyBytes.baseAddress,
                        key.count,
                        dataBytes.baseAddress,
                        data.count,
                        digestBytes.baseAddress
                    )
                }
            }
        }
        return digest
    }

    func aesCBCDecrypt(ciphertext: Data, key: Data, iv: Data) throws -> Data {
        let outputLength = ciphertext.count + kCCBlockSizeAES128
        var output = Data(count: outputLength)
        var decryptedLength: size_t = 0

        let cryptStatus = output.withUnsafeMutableBytes { outputBytes in
            ciphertext.withUnsafeBytes { cipherBytes in
                iv.withUnsafeBytes { ivBytes in
                    key.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress,
                            ciphertext.count,
                            outputBytes.baseAddress,
                            outputLength,
                            &decryptedLength
                        )
                    }
                }
            }
        }

        guard cryptStatus == kCCSuccess else {
            throw CodexLBError.aesDecryptFailed(cryptStatus)
        }

        return output.prefix(decryptedLength)
    }

    func decryptCodexLBFernetToken(_ encryptedToken: Data, key: Data) throws -> String {
        let tokenData: Data
        if encryptedToken.first == 0x80 {
            tokenData = encryptedToken
        } else {
            guard let tokenString = String(data: encryptedToken, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !tokenString.isEmpty else {
                throw CodexLBError.invalidFernetToken
            }
            tokenData = try decodeBase64URL(tokenString)
        }

        guard tokenData.count > 57, tokenData.first == 0x80 else {
            throw CodexLBError.invalidFernetToken
        }

        let signatureStart = tokenData.count - 32
        let signedData = tokenData.prefix(signatureStart)
        let signature = tokenData.suffix(32)

        let signingKey = key.prefix(16)
        let encryptionKey = key.suffix(16)
        let expectedSignature = hmacSHA256(data: Data(signedData), key: Data(signingKey))
        guard expectedSignature == signature else {
            throw CodexLBError.invalidFernetSignature
        }

        // Fernet payload layout: version(1) + timestamp(8) + iv(16) + ciphertext + hmac(32)
        let ivStart = 1 + 8
        let ivEnd = ivStart + 16
        guard signatureStart > ivEnd else {
            throw CodexLBError.invalidFernetToken
        }
        let iv = tokenData.subdata(in: ivStart..<ivEnd)
        let ciphertext = tokenData.subdata(in: ivEnd..<signatureStart)

        let decrypted = try aesCBCDecrypt(ciphertext: ciphertext, key: Data(encryptionKey), iv: iv)
        guard let token = String(data: decrypted, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !token.isEmpty else {
            throw CodexLBError.invalidDecryptedToken
        }

        return token
    }

    func makeCodexLBOpenAIAccount(
        from encryptedAccount: CodexLBEncryptedAccount,
        accessToken: String,
        authSourcePath: String
    ) -> OpenAIAuthAccount {
        let normalizedAccountId = encryptedAccount.accountId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedChatGPTAccountId = encryptedAccount.chatGPTAccountId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedEmail = encryptedAccount.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return OpenAIAuthAccount(
            accessToken: accessToken,
            accountId: normalizedAccountId?.isEmpty == true ? nil : normalizedAccountId,
            externalUsageAccountId: normalizedChatGPTAccountId?.isEmpty == true ? nil : normalizedChatGPTAccountId,
            email: normalizedEmail?.isEmpty == true ? nil : normalizedEmail,
            authSource: authSourcePath,
            sourceLabels: [openAISourceLabel(for: .codexLB)],
            source: .codexLB,
            credentialType: .oauthBearer
        )
    }

    func shouldIncludeCodexLBAccount(_ account: CodexLBEncryptedAccount) -> Bool {
        guard let status = normalizedNonEmpty(account.status)?.lowercased() else {
            return true
        }
        return status == "active"
    }

    func readCodexLBOpenAIAccounts() -> [OpenAIAuthAccount] {
        return queue.sync {
            if let cached = cachedCodexLBAccounts,
               let timestamp = codexLBCacheTimestamp,
               Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
                return cached
            }

            let fileManager = FileManager.default
            for candidate in codexLBStorageCandidates() {
                guard fileManager.fileExists(atPath: candidate.databaseURL.path),
                      fileManager.fileExists(atPath: candidate.keyURL.path) else {
                    continue
                }
                guard fileManager.isReadableFile(atPath: candidate.databaseURL.path),
                      fileManager.isReadableFile(atPath: candidate.keyURL.path) else {
                    logger.warning("codex-lb files are not readable (db: \(candidate.databaseURL.path), key: \(candidate.keyURL.path))")
                    continue
                }

                do {
                    let keyData = try Data(contentsOf: candidate.keyURL)
                    let fernetKey = try decodeCodexLBFernetKey(keyData)
                    let encryptedAccounts = try queryCodexLBEncryptedAccounts(databaseURL: candidate.databaseURL)

                    if encryptedAccounts.isEmpty {
                        logger.info("codex-lb account table is empty at \(candidate.databaseURL.path)")
                        continue
                    }

                    var decodedAccounts: [OpenAIAuthAccount] = []
                    for encryptedAccount in encryptedAccounts {
                        guard shouldIncludeCodexLBAccount(encryptedAccount) else {
                            logger.info(
                                "Skipping inactive codex-lb OpenAI account with status \(encryptedAccount.status ?? "unknown", privacy: .public)"
                            )
                            continue
                        }

                        do {
                            let accessToken = try decryptCodexLBFernetToken(
                                encryptedAccount.accessTokenEncrypted,
                                key: fernetKey
                            )
                            decodedAccounts.append(
                                makeCodexLBOpenAIAccount(
                                    from: encryptedAccount,
                                    accessToken: accessToken,
                                    authSourcePath: candidate.databaseURL.path
                                )
                            )
                            // PII fields (email, account ID) kept at debug level to avoid
                            // leaking personal info in production console logs.
                            logger.debug(
                                """
                                \(candidate.databaseURL.path, privacy: .public) codex-lb account loaded: \
                                id=\(encryptedAccount.accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "nil"), \
                                chatgpt_account_id=\(encryptedAccount.chatGPTAccountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "nil"), \
                                email=\(encryptedAccount.email ?? "unknown"), \
                                plan=\(encryptedAccount.planType ?? "unknown"), \
                                status=\(encryptedAccount.status ?? "unknown"), \
                                lastRefresh=\(encryptedAccount.lastRefresh ?? "unknown"), \
                                hasRefreshToken=\(encryptedAccount.refreshTokenEncrypted != nil ? "YES" : "NO"), \
                                hasIdToken=\(encryptedAccount.idTokenEncrypted != nil ? "YES" : "NO")
                                """
                            )
                        } catch {
                            logger.warning(
                                "Failed to decrypt codex-lb access token for account \(encryptedAccount.accountId ?? "unknown"): \(error.localizedDescription)"
                            )
                        }
                    }

                    let deduped = dedupeOpenAIAccounts(decodedAccounts)
                    if !deduped.isEmpty {
                        cachedCodexLBAccounts = deduped
                        codexLBCacheTimestamp = Date()
                        lastFoundCodexLBStorePath = candidate.databaseURL
                        lastFoundCodexLBKeyPath = candidate.keyURL
                        logger.info("Successfully loaded \(deduped.count) codex-lb OpenAI account(s) from: \(candidate.databaseURL.path)")
                        return deduped
                    }

                    logger.warning("codex-lb account rows found but no decryptable access token at \(candidate.databaseURL.path)")
                } catch {
                    logger.warning("Failed to read codex-lb accounts at \(candidate.databaseURL.path): \(error.localizedDescription)")
                }
            }

            cachedCodexLBAccounts = []
            codexLBCacheTimestamp = Date()
            lastFoundCodexLBStorePath = nil
            lastFoundCodexLBKeyPath = nil
            return []
        }
    }

    func openAISourceLabel(for source: OpenAIAuthSource) -> String {
        switch source {
        case .opencodeAuth:
            return "OpenCode"
        case .openCodeMultiAuth:
            return "OpenCode Multi Auth"
        case .openCodeAnthropicAuthCodexCache:
            return "OpenCode Anthropic Auth"
        case .codexLB:
            return "Codex LB"
        case .codexAuth:
            return "Codex"
        }
    }

    func claudeSourceLabel(for source: ClaudeAuthSource) -> String {
        switch source {
        case .opencodeAuth:
            return "OpenCode"
        case .claudeCodeConfig:
            return "Claude Code"
        case .claudeCodeKeychain:
            return "Claude Code (Keychain)"
        case .claudeLegacyCredentials:
            return "Claude Code (Legacy)"
        }
    }

    func geminiSourceLabel(for source: GeminiAuthSource) -> String {
        switch source {
        case .opencodeAuth:
            return "OpenCode"
        case .antigravity:
            return "Antigravity"
        case .oauthCreds:
            return "Gemini CLI"
        }
    }

    func mergeSourceLabels(_ primary: [String], _ fallback: [String]) -> [String] {
        var merged: [String] = []
        for label in primary + fallback {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !merged.contains(trimmed) else { continue }
            merged.append(trimmed)
        }
        return merged
    }

    func normalizedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    struct ResolvedOpenAIAuthMetadata {
        let accountId: String?
        let overrideAccountId: String?
        let email: String?
    }

    func resolvedOpenAIAuthMetadata(from oauth: OpenCodeAuth.OAuth?) -> ResolvedOpenAIAuthMetadata {
        let accessTokenPayload = decodeOpenAIAccessTokenPayload(oauth?.access)
        let idTokenPayload = decodeOpenAIIDTokenPayload(oauth?.idToken)
        let tokenAccountId = normalizedNonEmpty(accessTokenPayload?.auth?.chatGPTAccountId)
        let overrideAccountId = normalizedNonEmpty(oauth?.accountIdOverride)
            ?? normalizedNonEmpty(oauth?.organizationIdOverride)
            ?? normalizedNonEmpty(oauth?.accountId)
        let email = normalizedNonEmpty(idTokenPayload?.email)
            ?? normalizedNonEmpty(accessTokenPayload?.profile?.email)

        return ResolvedOpenAIAuthMetadata(
            accountId: tokenAccountId ?? overrideAccountId,
            overrideAccountId: overrideAccountId,
            email: email
        )
    }

    // Intentionally internal for unit coverage of source priority and cross-source account merging.
    func dedupeOpenAIAccounts(_ accounts: [OpenAIAuthAccount]) -> [OpenAIAuthAccount] {
        func priority(for source: OpenAIAuthSource) -> Int {
            switch source {
            case .opencodeAuth: return 3
            case .codexAuth: return 2
            case .openCodeMultiAuth: return 1
            case .openCodeAnthropicAuthCodexCache: return -1
            case .codexLB: return 0
            }
        }

        var accountsByKey: [String: OpenAIAuthAccount] = [:]
        var keyOrder: [String] = []

        for account in accounts {
            let normalizedAccountId = normalizedNonEmpty(account.accountId)
            let normalizedEmail = normalizedNonEmpty(account.email)?.lowercased()
            let dedupeKey: String
            if let normalizedAccountId, !normalizedAccountId.isEmpty {
                dedupeKey = "id:\(normalizedAccountId)"
            } else if let normalizedEmail, !normalizedEmail.isEmpty {
                dedupeKey = "email:\(normalizedEmail)"
            } else {
                dedupeKey = "token:\(account.accessToken)"
            }

            if let existing = accountsByKey[dedupeKey] {
                let accountPriority = priority(for: account.source)
                let existingPriority = priority(for: existing.source)
                if accountPriority > existingPriority {
                    accountsByKey[dedupeKey] = mergeOpenAIAccount(primary: account, fallback: existing)
                } else if existingPriority > accountPriority {
                    accountsByKey[dedupeKey] = mergeOpenAIAccount(primary: existing, fallback: account)
                } else {
                    accountsByKey[dedupeKey] = mergeOpenAIAccount(primary: existing, fallback: account)
                }
                continue
            }

            keyOrder.append(dedupeKey)
            accountsByKey[dedupeKey] = account
        }

        let primaryDeduped = keyOrder.compactMap { accountsByKey[$0] }

        // Secondary merge by email to bridge sources where one account is missing accountId
        // but can still be identified by id_token email (Codex auth vs codex-lb).
        var emailIndexMap: [String: Int] = [:]
        var mergedResults: [OpenAIAuthAccount] = []

        for account in primaryDeduped {
            guard let normalizedEmail = normalizedNonEmpty(account.email)?.lowercased(),
                  !normalizedEmail.isEmpty else {
                mergedResults.append(account)
                continue
            }

            if let existingIndex = emailIndexMap[normalizedEmail] {
                let existing = mergedResults[existingIndex]
                let accountPriority = priority(for: account.source)
                let existingPriority = priority(for: existing.source)
                if accountPriority > existingPriority {
                    mergedResults[existingIndex] = mergeOpenAIAccount(primary: account, fallback: existing)
                } else {
                    mergedResults[existingIndex] = mergeOpenAIAccount(primary: existing, fallback: account)
                }
                continue
            }

            emailIndexMap[normalizedEmail] = mergedResults.count
            mergedResults.append(account)
        }

        return mergedResults
    }

    func mergeOpenAIAccount(primary: OpenAIAuthAccount, fallback: OpenAIAuthAccount) -> OpenAIAuthAccount {
        let primaryAccountId = primary.accountId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackAccountId = fallback.accountId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryEmail = primary.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackEmail = fallback.email?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedSourceLabels = mergeSourceLabels(primary.sourceLabels, fallback.sourceLabels)
        if primary.source == .codexAuth, fallback.source != .codexAuth {
            logger.debug(
                "OpenAI account merge selected Codex native auth over \(self.openAISourceLabel(for: fallback.source), privacy: .public) for a matching account"
            )
        }

        // Token freshness fallback: if primary's token is expired but fallback has a fresher
        // valid token (e.g. anthropic-auth caches a new token that multi-auth missed), swap to
        // the fallback token + refresh chain. Without this, dedupe picks the high-priority
        // source even when its token is dead, and that account silently disappears after 401.
        let now = Date()
        let primaryExpired = primary.expiresAt.map { $0 <= now } ?? false
        let fallbackValid = (fallback.expiresAt.map { $0 > now } ?? false) && !fallback.accessToken.isEmpty
        let useFallbackToken = primaryExpired && fallbackValid

        return OpenAIAuthAccount(
            accessToken: useFallbackToken ? fallback.accessToken : primary.accessToken,
            accountId: (primaryAccountId?.isEmpty == false) ? primaryAccountId : fallbackAccountId,
            externalUsageAccountId: normalizedNonEmpty(primary.externalUsageAccountId) ?? normalizedNonEmpty(fallback.externalUsageAccountId),
            email: (primaryEmail?.isEmpty == false) ? primaryEmail : fallbackEmail,
            authSource: primary.authSource,
            sourceLabels: mergedSourceLabels,
            source: primary.source,
            credentialType: primary.credentialType,
            refreshToken: useFallbackToken
                ? (normalizedNonEmpty(fallback.refreshToken) ?? normalizedNonEmpty(primary.refreshToken))
                : (normalizedNonEmpty(primary.refreshToken) ?? normalizedNonEmpty(fallback.refreshToken)),
            expiresAt: useFallbackToken ? fallback.expiresAt : (primary.expiresAt ?? fallback.expiresAt),
            idToken: useFallbackToken
                ? (normalizedNonEmpty(fallback.idToken) ?? normalizedNonEmpty(primary.idToken))
                : (normalizedNonEmpty(primary.idToken) ?? normalizedNonEmpty(fallback.idToken)),
            cachedCodexUsage: primary.cachedCodexUsage ?? fallback.cachedCodexUsage
        )
    }

    // MARK: - Shared JSON Helpers

    func normalizedKey(_ key: String) -> String {
        return key.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    func readJSONDictionary(at url: URL) -> [String: Any]? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard fileManager.isReadableFile(atPath: url.path) else {
            logger.warning("JSON file not readable at \(url.path)")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            return json as? [String: Any]
        } catch {
            logger.warning("Failed to parse JSON at \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    func findStringValue(in object: Any?, matching keys: Set<String>) -> String? {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                let normalized = normalizedKey(key)
                if keys.contains(normalized), let stringValue = value as? String, !stringValue.isEmpty {
                    return stringValue
                }
                if let nested = findStringValue(in: value, matching: keys) {
                    return nested
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let nested = findStringValue(in: item, matching: keys) {
                    return nested
                }
            }
        }
        return nil
    }

    func findIntValue(in object: Any?, matching keys: Set<String>) -> Int? {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                let normalized = normalizedKey(key)
                if keys.contains(normalized) {
                    if let intValue = value as? Int {
                        return intValue
                    }
                    if let numberValue = value as? NSNumber {
                        return numberValue.intValue
                    }
                    if let stringValue = value as? String, let intValue = Int(stringValue) {
                        return intValue
                    }
                }
                if let nested = findIntValue(in: value, matching: keys) {
                    return nested
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let nested = findIntValue(in: item, matching: keys) {
                    return nested
                }
            }
        }
        return nil
    }

    func findInt64Value(in object: Any?, matching keys: Set<String>) -> Int64? {
        if let dict = object as? [String: Any] {
            for (key, value) in dict {
                let normalized = normalizedKey(key)
                if keys.contains(normalized) {
                    if let intValue = value as? Int64 {
                        return intValue
                    }
                    if let intValue = value as? Int {
                        return Int64(intValue)
                    }
                    if let numberValue = value as? NSNumber {
                        return numberValue.int64Value
                    }
                    if let stringValue = value as? String,
                       let intValue = Int64(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        return intValue
                    }
                }
                if let nested = findInt64Value(in: value, matching: keys) {
                    return nested
                }
            }
        } else if let array = object as? [Any] {
            for item in array {
                if let nested = findInt64Value(in: item, matching: keys) {
                    return nested
                }
            }
        }
        return nil
    }

    func findDirectStringValue(in dict: [String: Any], matching keys: Set<String>) -> String? {
        for (key, value) in dict {
            let normalized = normalizedKey(key)
            guard keys.contains(normalized),
                  let stringValue = value as? String else {
                continue
            }
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    func findDirectInt64Value(in dict: [String: Any], matching keys: Set<String>) -> Int64? {
        for (key, value) in dict {
            let normalized = normalizedKey(key)
            guard keys.contains(normalized) else { continue }
            if let intValue = value as? Int64 {
                return intValue
            }
            if let intValue = value as? Int {
                return Int64(intValue)
            }
            if let numberValue = value as? NSNumber {
                return numberValue.int64Value
            }
            if let stringValue = value as? String,
               let intValue = Int64(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return intValue
            }
        }
        return nil
    }

    func dateFromEpoch(_ rawValue: Int64?) -> Date? {
        guard let rawValue else { return nil }
        let seconds: Double
        // Heuristic: values with 13+ digits are milliseconds.
        if rawValue > 9_999_999_999 {
            seconds = Double(rawValue) / 1000.0
        } else {
            seconds = Double(rawValue)
        }
        return Date(timeIntervalSince1970: seconds)
    }

    func parseISO8601Date(_ value: String?) -> Date? {
        guard let value = normalizedNonEmpty(value) else { return nil }

        let formatterWithFrac = ISO8601DateFormatter()
        formatterWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFrac.date(from: value) {
            return date
        }

        let formatterWithoutFrac = ISO8601DateFormatter()
        formatterWithoutFrac.formatOptions = [.withInternetDateTime]
        return formatterWithoutFrac.date(from: value)
    }

    struct ClaudeOAuthPayload {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let accountId: String?
        let email: String?
    }

    struct OpenAIMultiAuthPayload {
        let accessToken: String
        let accountId: String?
        let email: String?
        let refreshToken: String?
        let expiresAt: Date?
        let idToken: String?
    }

    func valueForNormalizedKey(_ normalizedKeyName: String, in dict: [String: Any]) -> Any? {
        for (key, value) in dict where normalizedKey(key) == normalizedKeyName {
            return value
        }
        return nil
    }

    func extractClaudeOAuthPayload(from dict: [String: Any]) -> ClaudeOAuthPayload? {
        let accessKeys: Set<String> = ["accesstoken", "access", "oauthtoken", "token"]
        let refreshKeys: Set<String> = ["refreshtoken", "oauthrefreshtoken", "refresh"]
        let expiresKeys: Set<String> = ["expiresat", "expires", "expiration", "expiresin"]
        let accountKeys: Set<String> = ["accountid", "userid", "id"]
        let emailKeys: Set<String> = ["email", "useremail", "login", "username"]

        var candidates: [(object: Any, allowRecursive: Bool)] = []
        if let claudeAiOAuth = valueForNormalizedKey("claudeaioauth", in: dict) {
            candidates.append((claudeAiOAuth, true))
        }
        if let claudeOAuth = valueForNormalizedKey("claudeoauth", in: dict) {
            candidates.append((claudeOAuth, true))
        }
        if let oauth = valueForNormalizedKey("oauth", in: dict) {
            candidates.append((oauth, true))
        }
        // Last resort: only direct key lookup on the top-level object to avoid
        // accidentally picking unrelated nested MCP tokens.
        candidates.append((dict, false))

        for candidate in candidates {
            let accessToken: String?
            let refreshToken: String?
            let expiresRaw: Int64?
            let accountIdString: String?
            let accountIdNumeric: Int64?
            let email: String?

            if let candidateDict = candidate.object as? [String: Any] {
                accessToken = findDirectStringValue(in: candidateDict, matching: accessKeys)
                    ?? (candidate.allowRecursive ? findStringValue(in: candidateDict, matching: accessKeys) : nil)
                refreshToken = findDirectStringValue(in: candidateDict, matching: refreshKeys)
                    ?? (candidate.allowRecursive ? findStringValue(in: candidateDict, matching: refreshKeys) : nil)
                expiresRaw = findDirectInt64Value(in: candidateDict, matching: expiresKeys)
                    ?? (candidate.allowRecursive ? findInt64Value(in: candidateDict, matching: expiresKeys) : nil)
                accountIdString = findDirectStringValue(in: candidateDict, matching: accountKeys)
                    ?? (candidate.allowRecursive ? findStringValue(in: candidateDict, matching: accountKeys) : nil)
                accountIdNumeric = findDirectInt64Value(in: candidateDict, matching: accountKeys)
                    ?? (candidate.allowRecursive ? findInt64Value(in: candidateDict, matching: accountKeys) : nil)
                email = findDirectStringValue(in: candidateDict, matching: emailKeys)
                    ?? (candidate.allowRecursive ? findStringValue(in: candidateDict, matching: emailKeys) : nil)
            } else {
                accessToken = candidate.allowRecursive ? findStringValue(in: candidate.object, matching: accessKeys) : nil
                refreshToken = candidate.allowRecursive ? findStringValue(in: candidate.object, matching: refreshKeys) : nil
                expiresRaw = candidate.allowRecursive ? findInt64Value(in: candidate.object, matching: expiresKeys) : nil
                accountIdString = candidate.allowRecursive ? findStringValue(in: candidate.object, matching: accountKeys) : nil
                accountIdNumeric = candidate.allowRecursive ? findInt64Value(in: candidate.object, matching: accountKeys) : nil
                email = candidate.allowRecursive ? findStringValue(in: candidate.object, matching: emailKeys) : nil
            }

            guard let accessToken = normalizedNonEmpty(accessToken) else { continue }
            let accountId = normalizedNonEmpty(accountIdString) ?? accountIdNumeric.map { String($0) }
            let normalizedRefreshToken = normalizedNonEmpty(refreshToken)
            let expiresAt = expiresRaw.flatMap { rawValue -> Date? in
                if rawValue < 1_000_000_000 {
                    return Date().addingTimeInterval(TimeInterval(max(0, rawValue - 60)))
                }
                return dateFromEpoch(rawValue)
            } ?? parseISO8601Date(
                (candidate.object as? [String: Any]).flatMap { findDirectStringValue(in: $0, matching: expiresKeys) }
            )

            return ClaudeOAuthPayload(
                accessToken: accessToken,
                refreshToken: normalizedRefreshToken,
                expiresAt: expiresAt,
                accountId: accountId,
                email: normalizedNonEmpty(email)
            )
        }

        return nil
    }

    func openCodeMultiAuthPaths() -> [URL] {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser
        let openCodeRoot = homeDir.appendingPathComponent(".opencode", isDirectory: true)

        var paths: [URL] = [
            openCodeRoot.appendingPathComponent("auth").appendingPathComponent("openai.json"),
            openCodeRoot.appendingPathComponent("openai-codex-accounts.json")
        ]

        let projectsDir = openCodeRoot.appendingPathComponent("projects", isDirectory: true)
        if let projectDirectories = try? fileManager.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            let projectFiles = projectDirectories
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .map { $0.appendingPathComponent("openai-codex-accounts.json") }
            paths.append(contentsOf: projectFiles)
        }

        var deduped: [URL] = []
        var visited = Set<String>()
        for path in paths {
            let normalizedPath = path.standardizedFileURL.path
            if visited.insert(normalizedPath).inserted {
                deduped.append(path)
            }
        }
        return deduped
    }

    func decodeOpenAIAccessTokenPayload(_ accessToken: String?) -> OpenAIAccessTokenPayload? {
        guard let token = normalizedNonEmpty(accessToken) else {
            return nil
        }

        let parts = token.split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }

        let payload = String(parts[1])
        do {
            let data = try decodeBase64URL(payload)
            return try JSONDecoder().decode(OpenAIAccessTokenPayload.self, from: data)
        } catch {
            logger.warning("Failed to decode OpenAI access token payload: \(error.localizedDescription)")
            return nil
        }
    }

    func extractOpenAIMultiAuthPayload(from dict: [String: Any]) -> OpenAIMultiAuthPayload? {
        let accessKeys: Set<String> = ["accesstoken", "access", "oauthtoken", "token"]
        let refreshKeys: Set<String> = ["refreshtoken", "oauthrefreshtoken", "refresh"]
        let expiresKeys: Set<String> = ["expiresat", "expires", "expiration", "expiry"]
        let idTokenKeys: Set<String> = ["idtoken"]
        let accountKeys: Set<String> = ["accountid", "chatgptaccountid", "userid", "id"]
        let emailKeys: Set<String> = ["email", "useremail", "login", "username"]

        guard let accessToken = findDirectStringValue(in: dict, matching: accessKeys)
            ?? findStringValue(in: dict, matching: accessKeys) else {
            return nil
        }

        let accessTokenPayload = decodeOpenAIAccessTokenPayload(accessToken)
        let tokenAccountId = normalizedNonEmpty(accessTokenPayload?.auth?.chatGPTAccountId)
        let storedAccountId = findDirectStringValue(in: dict, matching: accountKeys)
            ?? findStringValue(in: dict, matching: accountKeys)
        let expiresRaw = findDirectInt64Value(in: dict, matching: expiresKeys)
            ?? findInt64Value(in: dict, matching: expiresKeys)
        let expiresAt = expiresRaw.flatMap { dateFromEpoch($0) } ?? parseISO8601Date(
            findDirectStringValue(in: dict, matching: expiresKeys)
                ?? findStringValue(in: dict, matching: expiresKeys)
        )
        let email = normalizedNonEmpty(accessTokenPayload?.profile?.email)
            ?? normalizedNonEmpty(findDirectStringValue(in: dict, matching: emailKeys)
            ?? findStringValue(in: dict, matching: emailKeys))

        return OpenAIMultiAuthPayload(
            accessToken: accessToken,
            accountId: tokenAccountId ?? normalizedNonEmpty(storedAccountId),
            email: email,
            refreshToken: normalizedNonEmpty(findDirectStringValue(in: dict, matching: refreshKeys)
                ?? findStringValue(in: dict, matching: refreshKeys)),
            expiresAt: expiresAt,
            idToken: normalizedNonEmpty(findDirectStringValue(in: dict, matching: idTokenKeys)
                ?? findStringValue(in: dict, matching: idTokenKeys))
        )
    }

    func openCodeAnthropicCodexAccountPaths() -> [URL] {
        buildOpenCodeFilePaths(
            envVarName: "XDG_CONFIG_HOME",
            envRelativePathComponents: ["opencode", "opencode-anthropic-auth", "codex-accounts.json"],
            fallbackRelativePathComponents: [
                [".config", "opencode", "opencode-anthropic-auth", "codex-accounts.json"]
            ]
        )
    }

    func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
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

    func directDoubleValue(in dict: [String: Any], matching keys: Set<String>) -> Double? {
        for (key, value) in dict where keys.contains(normalizedKey(key)) {
            if let double = value as? Double {
                return double
            }
            if let int = value as? Int {
                return Double(int)
            }
            if let number = value as? NSNumber {
                return number.doubleValue
            }
            if let string = value as? String {
                return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    func directBoolValue(in dict: [String: Any], matching keys: Set<String>) -> Bool? {
        for (key, value) in dict where keys.contains(normalizedKey(key)) {
            if let bool = boolValue(value) {
                return bool
            }
        }
        return nil
    }

    func parseOpenCodeAnthropicCodexUsageWindow(_ value: Any?) -> CodexCachedUsageWindow? {
        guard let dict = value as? [String: Any],
              let utilization = directDoubleValue(in: dict, matching: ["utilization", "usedpercent", "usagepercent"]) else {
            return nil
        }

        let resetDate = parseISO8601Date(findDirectStringValue(in: dict, matching: ["resetsat", "resetat"]))
            ?? dateFromEpoch(findDirectInt64Value(in: dict, matching: ["resetsat", "resetat"]))
        let label = normalizedNonEmpty(findDirectStringValue(in: dict, matching: ["label", "windowlabel"]))
        let windowMs = findDirectInt64Value(in: dict, matching: ["windowms"]).map { Int($0) }

        return CodexCachedUsageWindow(
            utilization: utilization,
            resetsAt: resetDate,
            label: label,
            windowMs: windowMs
        )
    }

    func parseOpenCodeAnthropicCodexUsage(_ value: Any?) -> CodexCachedUsageSnapshot? {
        guard let dict = value as? [String: Any] else {
            return nil
        }

        let primary = parseOpenCodeAnthropicCodexUsageWindow(valueForNormalizedKey("primary", in: dict))
        let secondary = parseOpenCodeAnthropicCodexUsageWindow(valueForNormalizedKey("secondary", in: dict))
        let sparkPrimary = parseOpenCodeAnthropicCodexUsageWindow(valueForNormalizedKey("sparkprimary", in: dict))
        let sparkSecondary = parseOpenCodeAnthropicCodexUsageWindow(valueForNormalizedKey("sparksecondary", in: dict))

        guard primary != nil || secondary != nil || sparkPrimary != nil || sparkSecondary != nil else {
            return nil
        }

        return CodexCachedUsageSnapshot(
            fetchedAt: dateFromEpoch(findDirectInt64Value(in: dict, matching: ["fetchedat"])),
            planType: normalizedNonEmpty(findDirectStringValue(in: dict, matching: ["plantype"])),
            primary: primary,
            secondary: secondary,
            sparkPrimary: sparkPrimary,
            sparkSecondary: sparkSecondary,
            creditsBalance: directDoubleValue(in: dict, matching: ["creditsbalance", "balance"]),
            creditsUnlimited: directBoolValue(in: dict, matching: ["creditsunlimited", "unlimited"])
        )
    }

    func shouldIncludeOpenCodeAnthropicCodexAccount(_ accountDict: [String: Any]) -> Bool {
        if let enabled = boolValue(valueForNormalizedKey("enabled", in: accountDict)), !enabled {
            return false
        }
        guard let status = normalizedNonEmpty(findDirectStringValue(in: accountDict, matching: ["status"]))?.lowercased() else {
            return true
        }
        return status == "active"
    }

    func readOpenCodeAnthropicCodexAccountFiles(at paths: [URL]) -> [OpenAIAuthAccount] {
        var accounts: [OpenAIAuthAccount] = []

        for path in paths {
            guard let dict = readJSONDictionary(at: path) else { continue }
            let rawAccounts = valueForNormalizedKey("accounts", in: dict) as? [Any] ?? [dict]
            var pathAccounts: [OpenAIAuthAccount] = []

            for rawAccount in rawAccounts {
                guard let accountDict = rawAccount as? [String: Any],
                      shouldIncludeOpenCodeAnthropicCodexAccount(accountDict),
                      let cachedUsage = parseOpenCodeAnthropicCodexUsage(valueForNormalizedKey("usage", in: accountDict)) else {
                    continue
                }

                // Prefer JWT chatgpt_account_id over file's accountId/id field, because plugin
                // stores its own internal id (e.g. "e13fb177-...") that does NOT match the
                // ChatGPT-Account-Id header OpenAI expects, breaking dedupe with other sources.
                let accessTokenStr = normalizedNonEmpty(findDirectStringValue(
                    in: accountDict,
                    matching: ["access", "accesstoken"]
                ))
                let jwtAccountId = normalizedNonEmpty(
                    decodeOpenAIAccessTokenPayload(accessTokenStr)?.auth?.chatGPTAccountId
                )
                let storedAccountId = normalizedNonEmpty(findDirectStringValue(
                    in: accountDict,
                    matching: ["accountid", "chatgptaccountid"]
                )) ?? normalizedNonEmpty(findDirectStringValue(in: accountDict, matching: ["id"]))
                let accountId = jwtAccountId ?? storedAccountId
                let email = normalizedNonEmpty(findDirectStringValue(
                    in: accountDict,
                    matching: ["email", "useremail", "login", "username"]
                ))
                guard accountId != nil || email != nil else {
                    continue
                }

                let refreshToken = normalizedNonEmpty(findDirectStringValue(
                    in: accountDict,
                    matching: ["refresh", "refreshtoken"]
                ))
                let idToken = normalizedNonEmpty(findDirectStringValue(
                    in: accountDict,
                    matching: ["idtoken"]
                ))
                let expiresAt = dateFromEpoch(findDirectInt64Value(
                    in: accountDict,
                    matching: ["expires", "expiresat"]
                ))

                pathAccounts.append(
                    OpenAIAuthAccount(
                        accessToken: accessTokenStr ?? "",
                        accountId: accountId,
                        externalUsageAccountId: nil,
                        email: email,
                        authSource: path.path,
                        sourceLabels: [openAISourceLabel(for: .openCodeAnthropicAuthCodexCache)],
                        source: .openCodeAnthropicAuthCodexCache,
                        credentialType: .oauthBearer,
                        refreshToken: refreshToken,
                        expiresAt: expiresAt,
                        idToken: idToken,
                        cachedCodexUsage: cachedUsage
                    )
                )
            }

            if !pathAccounts.isEmpty {
                logger.info("Loaded \(pathAccounts.count) cached Codex account(s) from opencode-anthropic-auth at \(path.path)")
                accounts.append(contentsOf: pathAccounts)
            }
        }

        return accounts
    }

    func readOpenAIMultiAuthFiles(at paths: [URL]) -> [OpenAIAuthAccount] {
        var accounts: [OpenAIAuthAccount] = []

        for path in paths {
            guard let dict = readJSONDictionary(at: path) else { continue }
            let rawAccounts = valueForNormalizedKey("accounts", in: dict) as? [Any] ?? [dict]
            var pathAccounts: [OpenAIAuthAccount] = []

            for rawAccount in rawAccounts {
                guard let accountDict = rawAccount as? [String: Any],
                      let payload = extractOpenAIMultiAuthPayload(from: accountDict) else {
                    continue
                }

                pathAccounts.append(
                    OpenAIAuthAccount(
                        accessToken: payload.accessToken,
                        accountId: payload.accountId,
                        externalUsageAccountId: nil,
                        email: payload.email,
                        authSource: path.path,
                        sourceLabels: [openAISourceLabel(for: .openCodeMultiAuth)],
                        source: .openCodeMultiAuth,
                        credentialType: .oauthBearer,
                        refreshToken: payload.refreshToken,
                        expiresAt: payload.expiresAt,
                        idToken: payload.idToken
                    )
                )
            }

            if !pathAccounts.isEmpty {
                logger.info("Loaded \(pathAccounts.count) OpenAI account(s) from oc-chatgpt-multi-auth at \(path.path)")
                accounts.append(contentsOf: pathAccounts)
            }
        }

        return accounts
    }

    func readOpenAIMultiAuthFiles() -> [OpenAIAuthAccount] {
        return queue.sync {
            if let cached = cachedOpenCodeMultiAuthAccounts,
               let timestamp = openCodeMultiAuthAccountsCacheTimestamp,
               Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
                return cached
            }

            let fileManager = FileManager.default
            let paths = openCodeMultiAuthPaths()
            let accounts = readOpenAIMultiAuthFiles(at: paths)
            let existingPaths = paths.filter { fileManager.fileExists(atPath: $0.path) }

            cachedOpenCodeMultiAuthAccounts = accounts
            openCodeMultiAuthAccountsCacheTimestamp = Date()
            lastFoundOpenCodeMultiAuthPaths = existingPaths
            return accounts
        }
    }

    func readOpenCodeAnthropicCodexAccountFiles() -> [OpenAIAuthAccount] {
        return queue.sync {
            if let cached = cachedOpenCodeAnthropicCodexAccounts,
               let timestamp = openCodeAnthropicCodexAccountsCacheTimestamp,
               Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
                return cached
            }

            let fileManager = FileManager.default
            let paths = openCodeAnthropicCodexAccountPaths()
            let accounts = readOpenCodeAnthropicCodexAccountFiles(at: paths)
            let existingPaths = paths.filter { fileManager.fileExists(atPath: $0.path) }

            cachedOpenCodeAnthropicCodexAccounts = accounts
            openCodeAnthropicCodexAccountsCacheTimestamp = Date()
            lastFoundOpenCodeAnthropicCodexAccountPaths = existingPaths
            return accounts
        }
    }

    private struct OpenAITokenRefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case idToken = "id_token"
        }
    }

    private enum OpenAITokenRefreshError: LocalizedError {
        case unsupportedSource
        case missingRefreshToken
        case invalidTokenURL
        case invalidResponse
        case httpStatus(Int)
        case missingAccessToken
        case storageUpdateFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedSource:
                return "OpenAI token refresh is only supported for OpenCode Multi Auth accounts"
            case .missingRefreshToken:
                return "OpenAI refresh token is missing"
            case .invalidTokenURL:
                return "OpenAI token refresh URL is invalid"
            case .invalidResponse:
                return "OpenAI token refresh returned an invalid response"
            case .httpStatus(let status):
                return "OpenAI token refresh failed with HTTP \(status)"
            case .missingAccessToken:
                return "OpenAI token refresh response did not include an access token"
            case .storageUpdateFailed:
                return "OpenAI multi-auth account storage could not be updated"
            }
        }
    }

    func canRefreshOpenAIMultiAuthAccount(_ account: OpenAIAuthAccount) -> Bool {
        account.source == .openCodeMultiAuth
            && normalizedNonEmpty(account.refreshToken) != nil
            && account.credentialType == .oauthBearer
    }

    func openAIMultiAuthAccountNeedsRefresh(_ account: OpenAIAuthAccount, skew: TimeInterval = 60) -> Bool {
        guard canRefreshOpenAIMultiAuthAccount(account),
              let expiresAt = account.expiresAt else {
            return false
        }

        return expiresAt <= Date().addingTimeInterval(max(0, skew))
    }

    func formURLEncodedBody(_ queryItems: [URLQueryItem]) -> Data {
        var components = URLComponents()
        components.queryItems = queryItems
        return components.percentEncodedQuery?.data(using: .utf8) ?? Data()
    }

    func refreshOpenAIMultiAuthAccount(_ account: OpenAIAuthAccount) async throws -> OpenAIAuthAccount {
        guard account.source == .openCodeMultiAuth else {
            throw OpenAITokenRefreshError.unsupportedSource
        }
        guard let refreshToken = normalizedNonEmpty(account.refreshToken) else {
            throw OpenAITokenRefreshError.missingRefreshToken
        }
        guard let tokenURL = URL(string: "https://auth.openai.com/oauth/token") else {
            throw OpenAITokenRefreshError.invalidTokenURL
        }

        logger.info("Refreshing OpenAI multi-auth token for Codex usage")

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncodedBody([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: "app_EMoamEEZ73f0CkXaXp7hrann")
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITokenRefreshError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            logger.warning("OpenAI multi-auth token refresh failed with status \(httpResponse.statusCode)")
            throw OpenAITokenRefreshError.httpStatus(httpResponse.statusCode)
        }

        let refreshResponse = try JSONDecoder().decode(OpenAITokenRefreshResponse.self, from: data)
        let accessToken = refreshResponse.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accessToken.isEmpty else {
            throw OpenAITokenRefreshError.missingAccessToken
        }

        let refreshedAccessPayload = decodeOpenAIAccessTokenPayload(accessToken)
        let refreshedIDPayload = decodeOpenAIIDTokenPayload(refreshResponse.idToken)
        let refreshedAccount = OpenAIAuthAccount(
            accessToken: accessToken,
            accountId: normalizedNonEmpty(refreshedAccessPayload?.auth?.chatGPTAccountId) ?? account.accountId,
            externalUsageAccountId: account.externalUsageAccountId,
            email: normalizedNonEmpty(refreshedIDPayload?.email)
                ?? normalizedNonEmpty(refreshedAccessPayload?.profile?.email)
                ?? account.email,
            authSource: account.authSource,
            sourceLabels: account.sourceLabels,
            source: account.source,
            credentialType: account.credentialType,
            refreshToken: normalizedNonEmpty(refreshResponse.refreshToken) ?? refreshToken,
            expiresAt: Date().addingTimeInterval(refreshResponse.expiresIn),
            idToken: normalizedNonEmpty(refreshResponse.idToken) ?? account.idToken
        )

        try persistOpenAIMultiAuthRefresh(original: account, refreshed: refreshedAccount)
        logger.info("OpenAI multi-auth token refresh succeeded for Codex usage")
        return refreshedAccount
    }

    func persistOpenAIMultiAuthRefresh(original: OpenAIAuthAccount, refreshed: OpenAIAuthAccount) throws {
        let storageURL = URL(fileURLWithPath: original.authSource)
        try queue.sync {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: storageURL.path),
                  fileManager.isReadableFile(atPath: storageURL.path) else {
                throw OpenAITokenRefreshError.storageUpdateFailed
            }

            let data = try Data(contentsOf: storageURL)
            guard var root = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw OpenAITokenRefreshError.storageUpdateFailed
            }

            var updated = false
            if var accounts = root["accounts"] as? [[String: Any]] {
                for index in accounts.indices where openAIMultiAuthStorageAccount(accounts[index], matches: original) {
                    updateOpenAIMultiAuthStorageAccount(&accounts[index], with: refreshed)
                    updated = true
                }
                root["accounts"] = accounts
            } else if openAIMultiAuthStorageAccount(root, matches: original) {
                updateOpenAIMultiAuthStorageAccount(&root, with: refreshed)
                updated = true
            }

            guard updated else {
                throw OpenAITokenRefreshError.storageUpdateFailed
            }

            let output = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try output.write(to: storageURL, options: .atomic)

            cachedOpenCodeMultiAuthAccounts = nil
            openCodeMultiAuthAccountsCacheTimestamp = nil
        }
    }

    func openAIMultiAuthStorageAccount(_ accountDict: [String: Any], matches account: OpenAIAuthAccount) -> Bool {
        let accessKeys: Set<String> = ["accesstoken", "access", "oauthtoken", "token"]
        let refreshKeys: Set<String> = ["refreshtoken", "oauthrefreshtoken", "refresh"]
        let accountKeys: Set<String> = ["accountid", "chatgptaccountid", "userid", "id"]
        let emailKeys: Set<String> = ["email", "useremail", "login", "username"]

        if let refreshToken = normalizedNonEmpty(account.refreshToken),
           normalizedNonEmpty(findDirectStringValue(in: accountDict, matching: refreshKeys)) == refreshToken {
            return true
        }

        if normalizedNonEmpty(findDirectStringValue(in: accountDict, matching: accessKeys)) == account.accessToken {
            return true
        }

        let storedAccountId = normalizedNonEmpty(findDirectStringValue(in: accountDict, matching: accountKeys))
        let storedEmail = normalizedNonEmpty(findDirectStringValue(in: accountDict, matching: emailKeys))?.lowercased()
        let accountIdMatches = storedAccountId != nil && storedAccountId == normalizedNonEmpty(account.accountId)
        let emailMatches = storedEmail != nil && storedEmail == normalizedNonEmpty(account.email)?.lowercased()
        return accountIdMatches && emailMatches
    }

    func updateOpenAIMultiAuthStorageAccount(_ accountDict: inout [String: Any], with account: OpenAIAuthAccount) {
        accountDict["accessToken"] = account.accessToken
        accountDict["refreshToken"] = account.refreshToken
        accountDict["expiresAt"] = account.expiresAt.map { Int64($0.timeIntervalSince1970 * 1000) }
        if let idToken = normalizedNonEmpty(account.idToken) {
            accountDict["idToken"] = idToken
        }
    }

    func parseJSONDictionary(from data: Data) -> [String: Any]? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = json as? [String: Any] else {
            return nil
        }
        return dict
    }

    func parseJSONDictionary(from string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8) else {
            return nil
        }
        return parseJSONDictionary(from: data)
    }

    func parseJSONStringCandidates(_ value: String) -> [String: Any]? {
        let trimmed = sanitizeJSONString(value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        var candidates: [String] = [trimmed]
        if let fragmentStartIndex = trimmed.firstIndex(where: { char in
            char == "{" || char == "\"" || char == "["
        }) {
            let fragment = String(trimmed[fragmentStartIndex...])
            candidates.append(fragment)
        }

        for candidate in candidates {
            if let dict = parseJSONDictionary(from: candidate) {
                return dict
            }

            if !candidate.hasPrefix("{"),
               !candidate.hasSuffix("}"),
               candidate.contains(":"),
               let dict = parseJSONDictionary(from: "{\(candidate)}") {
                logger.info("Decoded wrapped keychain JSON payload")
                return dict
            }
        }

        return nil
    }

    func extractQuotedValue(in payload: String, keys: [String]) -> String? {
        guard !keys.isEmpty else {
            return nil
        }

        let escapedKeys = keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = "\"(?:\(escapedKeys))\"\\s*:\\s*\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(payload.startIndex..<payload.endIndex, in: payload)
        guard let match = regex.firstMatch(in: payload, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: payload) else {
            return nil
        }
        let value = payload[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func extractNumericValue(in payload: String, keys: [String]) -> String? {
        guard !keys.isEmpty else {
            return nil
        }

        let escapedKeys = keys.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = "\"(?:\(escapedKeys))\"\\s*:\\s*([0-9]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(payload.startIndex..<payload.endIndex, in: payload)
        guard let match = regex.firstMatch(in: payload, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: payload) else {
            return nil
        }
        let value = payload[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func extractKeychainFieldsFromLoosePayload(_ payload: String) -> [String: Any]? {
        let sanitized = sanitizeJSONString(payload).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitized.isEmpty else {
            return nil
        }

        let tokenKeys = [
            "accessToken", "access_token",
            "oauthToken", "oauth_token",
            "token"
        ]
        let emailKeys = [
            "email", "userEmail", "user_email",
            "login", "username"
        ]
        let accountKeys = ["accountId", "account_id", "userId", "user_id", "id"]
        let refreshKeys = ["refreshToken", "refresh_token", "oauthRefreshToken", "oauth_refresh_token", "refresh"]
        let expiresKeys = ["expiresAt", "expires_at", "expires", "expiration", "expiry"]

        var recovered: [String: Any] = [:]
        if let token = extractQuotedValue(in: sanitized, keys: tokenKeys) {
            recovered["accessToken"] = token
        }
        if let email = extractQuotedValue(in: sanitized, keys: emailKeys) {
            recovered["email"] = email
        }

        let accountId = extractQuotedValue(in: sanitized, keys: accountKeys)
            ?? extractNumericValue(in: sanitized, keys: accountKeys)
        if let accountId {
            recovered["accountId"] = accountId
        }

        if let refreshToken = extractQuotedValue(in: sanitized, keys: refreshKeys) {
            recovered["refreshToken"] = refreshToken
        }

        if let expiresAt = extractNumericValue(in: sanitized, keys: expiresKeys) {
            recovered["expiresAt"] = expiresAt
        }

        if recovered["accessToken"] == nil {
            let plainToken = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if plainToken.hasPrefix("sk-ant-") || plainToken.hasPrefix("sk-") {
                recovered["accessToken"] = plainToken
            }
        }

        return recovered.isEmpty ? nil : recovered
    }

    func sanitizeJSONString(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter { scalar in
            if scalar.value == 9 || scalar.value == 10 || scalar.value == 13 {
                return true
            }
            return scalar.value >= 32
        }
        return String(String.UnicodeScalarView(scalars))
    }

    func decodeHexString(_ value: String) -> Data? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let compact = trimmed.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")
        var hexPayload = compact

        let isStrictHex = hexPayload.allSatisfy { $0.isHexDigit }
        if !isStrictHex {
            let filtered = String(hexPayload.filter { $0.isHexDigit })
            let minStrictMatch = Int(Double(hexPayload.count) * 0.9)
            guard filtered.count >= minStrictMatch else {
                return nil
            }
            hexPayload = filtered
        }

        guard hexPayload.count.isMultiple(of: 2) else {
            return nil
        }

        var bytes = Data(capacity: hexPayload.count / 2)
        var index = hexPayload.startIndex
        while index < hexPayload.endIndex {
            let nextIndex = hexPayload.index(index, offsetBy: 2)
            let byteString = hexPayload[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }
        return bytes
    }

    /// Runs a process with stdout redirected to a temporary file and returns the
    /// captured data only when the process exits successfully.
    ///
    /// This avoids the classic pipe deadlock: a `Pipe` buffer is ~64 KB, so if the
    /// child writes more than that and the parent calls `waitUntilExit()` before
    /// draining the pipe, both processes block forever. Writing to a file lets the
    /// child produce arbitrarily large output. The temporary file is removed in all
    /// paths.
    func runProcessCapturingStdout(executableURL: URL, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardError = FileHandle.nullDevice

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.opencodeproviders.TokenManager.\(UUID().uuidString).stdout", isDirectory: false)
        let stdoutHandle: FileHandle
        do {
            FileManager.default.createFile(atPath: tempURL.path, contents: nil, attributes: nil)
            stdoutHandle = try FileHandle(forWritingTo: tempURL)
        } catch {
            logger.debug("[runProcessCapturingStdout] Failed to create temporary stdout file: \(error.localizedDescription)")
            return nil
        }
        defer {
            try? stdoutHandle.close()
            try? FileManager.default.removeItem(at: tempURL)
        }
        process.standardOutput = stdoutHandle

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else {
            return nil
        }

        do {
            return try Data(contentsOf: tempURL)
        } catch {
            return nil
        }
    }

    // Uses /usr/bin/security instead of SecItemCopyMatching to avoid keychain
    // password prompts. The security binary matches `apple-tool:` partition_id.
    func readKeychainPasswordData(service: String, account: String? = nil) -> Data? {
        var args = ["find-generic-password", "-s", service]
        if let account = account {
            args += ["-a", account]
        }
        args.append("-w")

        guard let rawData = runProcessCapturingStdout(
            executableURL: URL(fileURLWithPath: "/usr/bin/security"),
            arguments: args
        ) else {
            return nil
        }

        guard let rawString = String(data: rawData, encoding: .utf8) else {
            // /usr/bin/security outputs text; non-UTF-8 data is unusable for
            // token/JSON consumers, so return nil instead of raw bytes.
            logger.debug("[Keychain] Output was not valid UTF-8 for service '\(service)'")
            return nil
        }
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.data(using: .utf8)
    }

    func readKeychainJSON(service: String) -> [String: Any]? {
        guard let data = readKeychainPasswordData(service: service) else {
            return nil
        }

        if let dict = parseJSONDictionary(from: data) {
            return dict
        }

        if let rawString = String(data: data, encoding: .utf8) {
            let sanitized = sanitizeJSONString(rawString).trimmingCharacters(in: .whitespacesAndNewlines)

            if let dict = parseJSONStringCandidates(sanitized) {
                logger.info("Decoded sanitized keychain JSON payload for service \(service)")
                return dict
            }

            if let decodedHexData = decodeHexString(sanitized),
               !decodedHexData.isEmpty {
                if let dict = parseJSONDictionary(from: decodedHexData) {
                    logger.info("Decoded hex-encoded keychain JSON payload for service \(service)")
                    return dict
                }

                if let decodedHexString = String(data: decodedHexData, encoding: .utf8) {
                    if let dict = parseJSONStringCandidates(decodedHexString) {
                        logger.info("Decoded hex-encoded keychain JSON string payload for service \(service)")
                        return dict
                    }

                    if let recovered = extractKeychainFieldsFromLoosePayload(decodedHexString) {
                        logger.info("Recovered keychain auth fields from hex-encoded loose payload for service \(service)")
                        return recovered
                    }
                }
            }

            if let recovered = extractKeychainFieldsFromLoosePayload(sanitized) {
                logger.info("Recovered keychain auth fields from loose payload for service \(service)")
                return recovered
            }
        }

        logger.warning("Keychain payload for service \(service) is not valid JSON")
        return nil
    }
}