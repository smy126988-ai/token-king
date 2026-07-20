import Foundation
import os.log

/// Pure-function mapper: `[ProviderIdentifier: ProviderResult]` → `WidgetSnapshot`.
///
/// Stateless and side-effect free — testable in isolation. The mapper does
/// not encode the snapshot itself; encoding is the writer's job and uses
/// `JSONEncoder` with `dateEncodingStrategy = .iso8601` per the schema v1
/// contract documented on `WidgetSnapshot`.
///
/// Errors are never silently swallowed: any branch that can't produce a
/// faithful mapping logs at `.error` and the provider is dropped from the
/// snapshot. The widget prefers a missing provider over a wrong one.
enum WidgetSnapshotMapper {
    // MARK: - Logging

    static let logger = Logger(subsystem: "com.tokenking", category: "widget.mapper")

    // MARK: - Public API

    /// Build a snapshot from the latest provider results and optional monthly cost.
    ///
    /// - Parameters:
    ///   - providerResults: Latest results keyed by `ProviderIdentifier`.
    ///   - monthlyCost: Optional USD (+ optional RMB) total for the current month.
    ///   - providerErrors: Errors from the current fetch, including cached fallback.
    ///   - providerLastSuccessfulFetchAt: Completion time of each real successful fetch.
    ///   - now: Timestamp written as `snapshotAt`. Injected for deterministic tests.
    /// - Returns: A v1 snapshot with providers sorted by highest `usedPercent`
    ///   first so the menu/widget sees the tightest quota at the top.
    static func makeSnapshot(
        providerResults: [ProviderIdentifier: ProviderResult],
        monthlyCost: MonthlyCost?,
        providerErrors: [ProviderIdentifier: String] = [:],
        providerLastSuccessfulFetchAt: [ProviderIdentifier: Date] = [:],
        now: Date = Date()
    ) -> WidgetSnapshot {
        logger.debug("Mapping \(providerResults.count) providers at \(now, privacy: .public)")

        let providers = providerResults
            .compactMap { identifier, result -> ProviderSnapshot? in
                mapProvider(
                    identifier: identifier,
                    result: result,
                providerError: providerErrors[identifier],
                fetchedAt: providerLastSuccessfulFetchAt[identifier]
                )
            }
            // Display order follows the data-layer-ranked primary metric. For
            // usage providers this is their single window; quota providers use
            // the first explicit quota window by priority. Use stable comparison
            // so ties don't flip ordering due to floating-point noise.
            .sorted { lhs, rhs in
                let leftPercent = primaryUsedPercent(of: lhs)
                let rightPercent = primaryUsedPercent(of: rhs)
                if isEssentiallyEqual(leftPercent, rightPercent) {
                    return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
                }
                return leftPercent > rightPercent
            }

        return WidgetSnapshot(
            version: 1,
            snapshotAt: now,
            providers: providers,
            monthlyCost: monthlyCost
        )
    }

    // MARK: - Per-provider mapping

    private static func mapProvider(
        identifier: ProviderIdentifier,
        result: ProviderResult,
        providerError: String?,
        fetchedAt: Date?
    ) -> ProviderSnapshot? {
        let details = result.details
        let usage = result.usage
        let accounts = identifier == .codex
            ? CodexWidgetSnapshotBuilder.makeAccounts(
                from: result,
                providerError: providerError,
                fetchedAt: fetchedAt
            )
            : nil
        let status = providerStatus(
            providerError: providerError,
            fetchedAt: fetchedAt,
            authError: details?.authErrorMessage
        )

        switch usage {
        case let .quotaBased(remaining, entitlement, _):
            // Guard against degenerate entitlement (avoids 0% math). Anything
            // <= 0 entitlement is unusable for a percentage so drop the row
            // and log — the widget prefers missing to misleading.
            guard entitlement > 0 else {
                logger.error("Dropping \(identifier.rawValue, privacy: .public): quotaBased with non-positive entitlement \(entitlement)")
                return nil
            }

            if identifier == .codex {
                let windows = CodexWidgetSnapshotBuilder.makeProviderMetrics(from: result)
                guard let primary = rankedPrimaryWindow(from: windows) else {
                    logger.error("Dropping codex: no valid quota windows")
                    return nil
                }
                return ProviderSnapshot(
                    id: identifier.rawValue,
                    displayName: identifier.displayName,
                    compactDisplayName: identifier.shortDisplayName,
                    kind: .quota,
                    primaryWindowId: primary.id,
                    windows: windows,
                    spendUSD: nil,
                    fetchedAt: fetchedAt,
                    status: status,
                    accounts: accounts
                )
            }

            var windows: [UsageWindow] = []
            let basePercent = usage.usagePercentage
            let baseUsed = entitlement - remaining
            windows.append(UsageWindow(
                id: "primary",
                label: "Primary",
                usedPercent: basePercent,
                resetsAt: nil,
                used: baseUsed,
                limit: entitlement,
                priority: details?.fiveHourUsage == nil ? 0 : 1
            ))
            appendMultiWindows(from: details, into: &windows, provider: identifier)
            let primary = rankedPrimaryWindow(from: windows)
            return ProviderSnapshot(
                id: identifier.rawValue,
                displayName: identifier.displayName,
                compactDisplayName: identifier.shortDisplayName,
                kind: .quota,
                primaryWindowId: primary?.id,
                windows: windows,
                spendUSD: nil,
                fetchedAt: fetchedAt,
                status: status,
                accounts: accounts
            )

        case let .payAsYouGo(utilization, cost, resetsAt):
            let window = UsageWindow(
                id: "primary",
                label: "Usage",
                usedPercent: utilization,
                resetsAt: resetsAt,
                used: nil,
                limit: nil
            )
            return ProviderSnapshot(
                id: identifier.rawValue,
                displayName: identifier.displayName,
                compactDisplayName: identifier.shortDisplayName,
                kind: .usage,
                primaryWindowId: "primary",
                windows: [window],
                spendUSD: cost,
                fetchedAt: fetchedAt,
                status: status,
                accounts: accounts
            )
        }
    }

    /// Append additional windows from `DetailedUsage` if non-nil.
    ///
    /// Each field is independent: missing = skip that window. Mapping is
    /// opt-in per field so a provider without a 7d window simply produces a
    /// shorter snapshot.
    private static func appendMultiWindows(
        from details: DetailedUsage?,
        into windows: inout [UsageWindow],
        provider: ProviderIdentifier
    ) {
        guard let details else { return }

        // Claude: 5h + 7d
        if let percent = details.fiveHourUsage {
            windows.append(UsageWindow(
                id: "5h",
                label: "5h",
                usedPercent: percent,
                resetsAt: details.fiveHourReset,
                used: nil,
                limit: nil,
                priority: 0
            ))
        }
        if let percent = details.sevenDayUsage {
            windows.append(UsageWindow(
                id: "7d",
                label: "7d",
                usedPercent: percent,
                resetsAt: details.sevenDayReset,
                used: nil,
                limit: nil,
                priority: 1
            ))
        }
        // Codex: secondary window uses the provider-defined label.
        if let percent = details.secondaryUsage {
            let label = details.codexSecondaryWindowLabel ?? "Secondary"
            windows.append(UsageWindow(
                id: "secondary",
                label: label,
                usedPercent: percent,
                resetsAt: details.secondaryReset,
                used: nil,
                limit: nil,
                priority: 1
            ))
        }
        // Z.ai: token + mcp
        if let percent = details.tokenUsagePercent {
            windows.append(UsageWindow(
                id: "token",
                label: "Token",
                usedPercent: percent,
                resetsAt: nil,
                used: nil,
                limit: nil,
                priority: 0
            ))
        }
        if let percent = details.mcpUsagePercent {
            windows.append(UsageWindow(
                id: "mcp",
                label: "MCP",
                usedPercent: percent,
                resetsAt: nil,
                used: nil,
                limit: nil,
                priority: 1
            ))
        }
        // OpenCode Go: monthly
        if let percent = details.openCodeGoMonthlyUsage {
            windows.append(UsageWindow(
                id: "monthly",
                label: "Monthly",
                usedPercent: percent,
                resetsAt: nil,
                used: nil,
                limit: nil,
                priority: 0
            ))
        }

        // Logger context kept implicit — provider id is recoverable via the
        // outer caller if needed.
        _ = provider
    }

    // MARK: - Stable comparison helpers

    /// Epsilon used to stabilise `Double` percent comparisons across the widget.
    /// Differences below this threshold are treated as equal, eliminating
    /// `28.999999999999996` vs `29` flips that otherwise shuffle `primaryWindowId`.
    private static let percentEpsilon: Double = 1e-9

    private static func isEssentiallyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < percentEpsilon
    }

    /// Prefer real quota windows over the synthetic aggregate. This keeps
    /// labels and resets faithful (for example, `5h` instead of `Primary`)
    /// while preserving the aggregate window for absolute used/limit values.
    private static func rankedPrimaryWindow(from windows: [UsageWindow]) -> UsageWindow? {
        let explicitWindows = windows.filter { $0.id != "primary" }
        let candidates = explicitWindows.isEmpty ? windows : explicitWindows
        return candidates.enumerated()
            .min { lhs, rhs in
                let leftPriority = lhs.element.priority ?? Int.max
                let rightPriority = rhs.element.priority ?? Int.max
                return leftPriority == rightPriority ? lhs.offset < rhs.offset : leftPriority < rightPriority
            }?
            .element
    }

    private static func providerStatus(
        providerError: String?,
        fetchedAt: Date?,
        authError: String?
    ) -> WidgetDataStatus {
        if authError != nil {
            return .unavailable
        }
        if providerError != nil || fetchedAt == nil {
            return .stale
        }
        return .available
    }

    // MARK: - Helpers

    /// Compute the "primary" usedPercent for sorting. Falls back to 0 if the
    /// snapshot has no windows (which would only happen on a dropped row, but
    /// be defensive).
    private static func primaryUsedPercent(of snapshot: ProviderSnapshot) -> Double {
        if let id = snapshot.primaryWindowId,
           let window = snapshot.windows.first(where: { $0.id == id }) {
            return window.usedPercent
        }
        return snapshot.windows.first?.usedPercent ?? 0
    }
}
