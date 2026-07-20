import CryptoKit
import Foundation

/// Builds the account-safe Codex presentation consumed by the widget.
///
/// This type deliberately reads only the base Codex quota fields. Model-specific
/// limits remain available to the menu but never cross into the widget account
/// contract.
enum CodexWidgetSnapshotBuilder {
    /// Builds the provider-level quota windows used by generic widgets.
    ///
    /// Keep this sourced from the same Codex metadata as account metrics so
    /// labels, reset dates, and priority never degrade to a synthetic
    /// `Primary` window in the generic provider cards.
    static func makeProviderMetrics(from result: ProviderResult) -> [UsageWindow] {
        makeMetrics(usage: result.usage, details: result.details)
    }

    static func makeAccounts(
        from result: ProviderResult,
        providerError: String? = nil,
        fetchedAt: Date? = nil
    ) -> [ProviderAccountSnapshot] {
        let sourceAccounts: [SourceAccount]
        if let accounts = result.accounts, !accounts.isEmpty {
            sourceAccounts = accounts.map {
                SourceAccount(
                    index: $0.accountIndex,
                    accountId: $0.accountId,
                    usage: $0.usage,
                    details: $0.details
                )
            }
        } else {
            sourceAccounts = [
                SourceAccount(
                    index: 0,
                    accountId: nil,
                    usage: result.usage,
                    details: result.details
                )
            ]
        }

        return sourceAccounts.map { account in
            ProviderAccountSnapshot(
                id: opaqueId(for: account),
                displayName: displayName(for: account),
                plan: normalized(account.details?.planType),
                status: status(
                    for: account,
                    providerError: providerError,
                    fetchedAt: fetchedAt
                ),
                metrics: makeMetrics(usage: account.usage, details: account.details),
                fetchedAt: fetchedAt
            )
        }
    }

    // MARK: - Metrics

    private static func makeMetrics(
        usage: ProviderUsage,
        details: DetailedUsage?
    ) -> [UsageWindow] {
        var candidates: [MetricCandidate] = []

        if let percent = validPrimaryPercent(from: usage) {
            candidates.append(MetricCandidate(
                label: metricLabel(
                    provided: details?.codexPrimaryWindowLabel,
                    hours: details?.codexPrimaryWindowHours,
                    fallback: "Primary"
                ),
                windowSeconds: seconds(fromHours: details?.codexPrimaryWindowHours),
                usedPercent: percent,
                resetsAt: details?.primaryReset,
                sourceOrder: 0
            ))
        }

        if let percent = validPercent(details?.secondaryUsage) {
            candidates.append(MetricCandidate(
                label: metricLabel(
                    provided: details?.codexSecondaryWindowLabel,
                    hours: details?.codexSecondaryWindowHours,
                    fallback: "Secondary"
                ),
                windowSeconds: seconds(fromHours: details?.codexSecondaryWindowHours),
                usedPercent: percent,
                resetsAt: details?.secondaryReset,
                sourceOrder: 1
            ))
        }

        var seenWindows = Set<String>()
        let uniqueCandidates = candidates.filter { candidate in
            seenWindows.insert(candidate.deduplicationKey).inserted
        }
        let orderedCandidates = uniqueCandidates.sorted { lhs, rhs in
            switch (lhs.windowSeconds, rhs.windowSeconds) {
            case let (lhsSeconds?, rhsSeconds?):
                if lhsSeconds != rhsSeconds { return lhsSeconds < rhsSeconds }
                return lhs.sourceOrder < rhs.sourceOrder
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.sourceOrder < rhs.sourceOrder
            }
        }

        return orderedCandidates.enumerated().map { priority, candidate in
            UsageWindow(
                id: candidate.stableId,
                label: candidate.label,
                usedPercent: candidate.usedPercent,
                resetsAt: candidate.resetsAt,
                used: nil,
                limit: nil,
                windowSeconds: candidate.windowSeconds,
                priority: priority
            )
        }
    }

    private static func validPrimaryPercent(from usage: ProviderUsage) -> Double? {
        switch usage {
        case let .quotaBased(_, entitlement, _):
            guard entitlement > 0 else { return nil }
            return validPercent(usage.usagePercentage)
        case let .payAsYouGo(utilization, _, _):
            return validPercent(utilization)
        }
    }

    private static func validPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    private static func seconds(fromHours hours: Int?) -> Int? {
        guard let hours, hours > 0, hours <= Int.max / 3_600 else { return nil }
        return hours * 3_600
    }

    private static func metricLabel(
        provided: String?,
        hours: Int?,
        fallback: String
    ) -> String {
        if let provided = normalized(provided) { return provided }
        guard let hours, hours > 0 else { return fallback }
        if hours == 168 { return "Weekly" }
        if hours % 24 == 0 { return "\(hours / 24)d" }
        return "\(hours)h"
    }

    // MARK: - Account privacy

    private static func opaqueId(for account: SourceAccount) -> String {
        let stableIdentity: String
        if let email = normalizedEmail(account.details?.email) {
            stableIdentity = "email:\(email)"
        } else if let accountId = normalized(account.accountId) {
            stableIdentity = "account:\(accountId)"
        } else {
            stableIdentity = "index:\(account.index)"
        }

        let digest = SHA256.hash(data: Data("codex-widget:\(stableIdentity)".utf8))
        return "codex-" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func displayName(for account: SourceAccount) -> String {
        guard let email = normalizedEmail(account.details?.email) else {
            return "Codex Account \(account.index + 1)"
        }
        let parts = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let first = parts[0].first, !parts[1].isEmpty else {
            return "Codex Account \(account.index + 1)"
        }
        return "\(first)•••@\(parts[1])"
    }

    private static func status(
        for account: SourceAccount,
        providerError: String?,
        fetchedAt: Date?
    ) -> ProviderAccountStatus {
        if normalized(account.details?.authErrorMessage) != nil {
            return .unavailable
        }
        if normalized(providerError) != nil || fetchedAt == nil {
            return .stale
        }
        return .available
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        normalized(value)?.lowercased()
    }
}

private extension CodexWidgetSnapshotBuilder {
    struct SourceAccount {
        let index: Int
        let accountId: String?
        let usage: ProviderUsage
        let details: DetailedUsage?
    }

    struct MetricCandidate {
        let label: String
        let windowSeconds: Int?
        let usedPercent: Double
        let resetsAt: Date?
        let sourceOrder: Int

        var stableId: String {
            if let windowSeconds { return "window-\(windowSeconds)" }
            return "window-source-\(sourceOrder)"
        }

        var deduplicationKey: String {
            if let windowSeconds { return "duration:\(windowSeconds)" }
            return "label:\(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        }
    }
}
