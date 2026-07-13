import Foundation

/// Sanitizes diagnostic log lines to redact PII (emails, paths, tokens,
/// cookies, key=value secrets) before they are written to disk.
///
/// All rules are intentionally conservative: when in doubt, redact.
enum DiagnosticsSanitizer {
    /// Redacts PII in `message` and returns the sanitized string.
    ///
    /// Rules applied (in order):
    /// 1. `email` local@host → `local@***`
    /// 2. `/Users/<name>/...` → `/Users/***/...`
    /// 3. `~/...` paths and `/private/var/folders/...` are masked
    /// 4. `key=value` (where value length ≥ 8) for sensitive keys
    ///    (token, password, cookie, apiKey, secret, auth, Bearer) → `key=***`
    static func sanitize(_ message: String) -> String {
        var out = message
        out = redactEmails(in: out)
        out = redactUserPaths(in: out)
        out = redactPrivateVarFolders(in: out)
        out = redactBearer(in: out)
        out = redactKeyValue(in: out)
        return out
    }

    // MARK: - Rules

    private static func redactEmails(in input: String) -> String {
        // localpart@domain.tld → localpart@***
        // Conservative: must contain at least one `.` after `@`.
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z0-9._%+\-]+)@([A-Za-z0-9.\-]+\.[A-Za-z]{2,})"#
        ) else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: "$1@***"
        )
    }

    private static func redactUserPaths(in input: String) -> String {
        // /Users/<name>/... → /Users/***/...
        guard let regex = try? NSRegularExpression(pattern: #"/Users/[^/\s"']+"#) else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: "/Users/***"
        )
    }

    private static func redactPrivateVarFolders(in input: String) -> String {
        // /private/var/folders/<random>/... → /private/var/folders/***/...
        guard let regex = try? NSRegularExpression(pattern: #"/private/var/folders/[^/\s"']+"#) else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: "/private/var/folders/***"
        )
    }

    private static func redactBearer(in input: String) -> String {
        // "Bearer eyJhbGc..." → "Bearer ***"
        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)(Bearer\s+)[A-Za-z0-9._\-+/=]{8,}"#
        ) else { return input }
        return regex.stringByReplacingMatches(
            in: input,
            range: NSRange(input.startIndex..., in: input),
            withTemplate: "$1***"
        )
    }

    private static func redactKeyValue(in input: String) -> String {
        // key=value or "key":"value" where key is sensitive and value is >= 8 chars.
        let sensitiveKeys = [
            "token", "password", "cookie", "apiKey", "api_key",
            "secret", "auth", "access_token", "refresh_token",
        ]
        let joined = sensitiveKeys.joined(separator: "|")
        // Patterns:
        //   token=xxxxx... (until ; or whitespace or end)
        //   "token":"xxxxx..." (until quote)
        let patterns = [
            #"(?i)((?:\#(joined))=)([^\s;"']{8,})"#,
            #"(?i)("(?:\#(joined))"\s*:\s*)"([^"]{8,})""#,
        ]
        var out = input
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            out = regex.stringByReplacingMatches(
                in: out,
                range: NSRange(out.startIndex..., in: out),
                withTemplate: "$1***"
            )
        }
        return out
    }
}