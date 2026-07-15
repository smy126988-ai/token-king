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
    ///   - now: Timestamp written as `snapshotAt`. Injected for deterministic tests.
    /// - Returns: A v1 snapshot with providers sorted by highest `usedPercent`
    ///   first so the menu/widget sees the tightest quota at the top.
    static func makeSnapshot(
        providerResults: [ProviderIdentifier: ProviderResult],
        monthlyCost: MonthlyCost?,
        now: Date = Date()
    ) -> WidgetSnapshot {
        logger.debug("Mapping \(providerResults.count) providers at \(now, privacy: .public)")

        let providers = providerResults
            .compactMap { identifier, result -> ProviderSnapshot? in
                mapProvider(identifier: identifier, result: result)
            }
            // Display order: tightest quota first. For usage kind the single
            // window's usedPercent drives the order; for multi-window quota
            // providers we look at the primary window id (highest usedPercent)
            // and fall back to the first window. Use stable comparison so ties
            // don't flip ordering due to floating-point noise.
            .sorted { lhs, rhs in
                let l = primaryUsedPercent(of: lhs)
                let r = primaryUsedPercent(of: rhs)
                if isEssentiallyEqual(l, r) { return false }
                return l > r
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
        result: ProviderResult
    ) -> ProviderSnapshot? {
        let details = result.details
        let usage = result.usage

        switch usage {
        case let .quotaBased(remaining, entitlement, _):
            // Guard against degenerate entitlement (avoids 0% math). Anything
            // <= 0 entitlement is unusable for a percentage so drop the row
            // and log — the widget prefers missing to misleading.
            guard entitlement > 0 else {
                logger.error("Dropping \(identifier.rawValue, privacy: .public): quotaBased with non-positive entitlement \(entitlement)")
                return nil
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
                limit: entitlement
            ))
            appendMultiWindows(from: details, into: &windows, provider: identifier)
            let primary = primaryWindow(from: windows)
            return ProviderSnapshot(
                id: identifier.rawValue,
                displayName: identifier.displayName,
                kind: .quota,
                primaryWindowId: primary?.id,
                windows: windows,
                spendUSD: nil,
                fetchedAt: nil
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
                kind: .usage,
                primaryWindowId: "primary",
                windows: [window],
                spendUSD: cost,
                fetchedAt: nil
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
        if let p = details.fiveHourUsage {
            windows.append(UsageWindow(
                id: "5h",
                label: "5h",
                usedPercent: p,
                resetsAt: details.fiveHourReset,
                used: nil,
                limit: nil
            ))
        }
        if let p = details.sevenDayUsage {
            windows.append(UsageWindow(
                id: "7d",
                label: "7d",
                usedPercent: p,
                resetsAt: details.sevenDayReset,
                used: nil,
                limit: nil
            ))
        }
        // Codex: secondary window uses the provider-defined label.
        if let p = details.secondaryUsage {
            let label = details.codexSecondaryWindowLabel ?? "Secondary"
            windows.append(UsageWindow(
                id: "secondary",
                label: label,
                usedPercent: p,
                resetsAt: details.secondaryReset,
                used: nil,
                limit: nil
            ))
        }
        // Z.ai: token + mcp
        if let p = details.tokenUsagePercent {
            windows.append(UsageWindow(
                id: "token",
                label: "Token",
                usedPercent: p,
                resetsAt: nil,
                used: nil,
                limit: nil
            ))
        }
        if let p = details.mcpUsagePercent {
            windows.append(UsageWindow(
                id: "mcp",
                label: "MCP",
                usedPercent: p,
                resetsAt: nil,
                used: nil,
                limit: nil
            ))
        }
        // OpenCode Go: monthly
        if let p = details.openCodeGoMonthlyUsage {
            windows.append(UsageWindow(
                id: "monthly",
                label: "Monthly",
                usedPercent: p,
                resetsAt: nil,
                used: nil,
                limit: nil
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

    /// Stable `max` that prefers the earlier window in `windows` when values are
    /// within `percentEpsilon`. Keeps `primary` as the tie-break winner when it
    /// is mathematically equivalent to a derived window.
    private static func primaryWindow(from windows: [UsageWindow]) -> UsageWindow? {
        guard let first = windows.first else { return nil }
        return windows.dropFirst().reduce(first) { best, candidate in
            if isEssentiallyEqual(best.usedPercent, candidate.usedPercent) {
                return best
            }
            return candidate.usedPercent > best.usedPercent ? candidate : best
        }
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
