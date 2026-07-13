import Foundation

/// Computes usage percentages, status snapshots, and quota alert candidates for the status bar.
/// Controller-owned state is supplied explicitly so this helper does not depend on private members.
@MainActor
enum StatusBarUsageDisplay {
    enum StatusBarMetricKind: Equatable {
        case cost
        case usage
    }

    struct StatusBarProviderSnapshot: Equatable {
        let value: Double
        let kind: StatusBarMetricKind
    }

    struct RecentChangeCandidate: Equatable {
        let identifier: ProviderIdentifier
        let kind: StatusBarMetricKind
        let delta: Double
        let observedAt: Date
    }

    struct RecentChangeState: Equatable {
        var previousProviderSnapshots: [ProviderIdentifier: StatusBarProviderSnapshot]
        var recentChangeCandidate: RecentChangeCandidate?
    }

    struct AlertProviderCandidate {
        let identifier: ProviderIdentifier
        let usedPercent: Double
    }

    static func selectedPinnedProvider(
        _ controller: StatusBarController,
        menuBarDisplayProvider: ProviderIdentifier?,
        providerResults: [ProviderIdentifier: ProviderResult],
        isProviderEnabled: (ProviderIdentifier) -> Bool
    ) -> ProviderIdentifier? {
        let visibleQuotaProviderIds = Set(
            quotaAlertCandidates(
                controller,
                providerResults: providerResults,
                isProviderEnabled: isProviderEnabled,
                logContext: menuBarDisplayProvider == nil ? "pinned-provider-auto" : "pinned-provider"
            ).map(\.identifier)
        )
        if let selected = menuBarDisplayProvider {
            // If a pinned provider is disabled, fall back to total cost instead of switching providers.
            guard isProviderEnabled(selected) else { return nil }
            if let result = providerResults[selected],
               case .quotaBased = result.usage,
               !visibleQuotaProviderIds.contains(selected) {
                controller.debugLog(
                    "selectedPinnedProvider: hiding pinned \(selected.displayName) because exhausted while other quota remains"
                )
                return nil
            }
            return selected
        }
        if let quotaProvider = ProviderIdentifier.allCases.first(where: {
            visibleQuotaProviderIds.contains($0) && isProviderEnabled($0)
        }) {
            return quotaProvider
        }
        return ProviderIdentifier.allCases.first(where: isProviderEnabled)
    }

    static func normalizedUsagePercent(_ percent: Double?) -> Double? {
        guard let percent, percent.isFinite else { return nil }
        return min(max(percent, 0), 999)
    }

    static func dailyPercentFromDetails(_ details: DetailedUsage?) -> Double? {
        guard let details else { return nil }
        if let limit = details.limit, limit > 0, let used = details.dailyUsage {
            return (used / limit) * 100.0
        }
        return details.dailyUsage
    }

    static func priorityForWindowHours(
        _ hours: Int?,
        fallback: UsageDisplayWindowPriority
    ) -> UsageDisplayWindowPriority {
        guard let hours, hours > 0 else { return fallback }
        if hours >= 24 * 28 { return .monthly }
        if hours >= 24 * 7 { return .weekly }
        if hours >= 24 { return .daily }
        return .hourly
    }

    static func chutesMonthlyPercentFromDetails(_ details: DetailedUsage?) -> Double? {
        guard let details else { return nil }

        let configuredPlan = SubscriptionSettingsManager.shared.getPlan(for: .chutes)
        let configuredCapUSD = configuredPlan.isSet
            ? configuredPlan.cost * ChutesProvider.monthlyValueMultiplier
            : nil
        let capUSD = configuredCapUSD ?? details.chutesMonthlyValueCapUSD

        if let usedUSD = details.chutesMonthlyValueUsedUSD,
           let capUSD,
           capUSD > 0 {
            return min(max((usedUSD / capUSD) * 100.0, 0), 999)
        }

        return details.chutesMonthlyValueUsedPercent
    }

    static func usagePercentCandidates(
        identifier: ProviderIdentifier,
        usage: ProviderUsage,
        details: DetailedUsage?
    ) -> [UsagePercentCandidate] {
        var candidates: [UsagePercentCandidate] = []
        func add(_ percent: Double?, priority: UsageDisplayWindowPriority) {
            guard let normalized = normalizedUsagePercent(percent) else { return }
            candidates.append(UsagePercentCandidate(percent: normalized, priority: priority))
        }

        switch identifier {
        case .claude:
            add(details?.sevenDayUsage, priority: .weekly)
            add(details?.sonnetUsage, priority: .weekly)
            add(details?.opusUsage, priority: .weekly)
            add(details?.extraUsageUtilizationPercent, priority: .monthly)
            add(details?.fiveHourUsage, priority: .hourly)
        case .kimi:
            add(details?.sevenDayUsage, priority: .weekly)
            add(details?.fiveHourUsage, priority: .hourly)
        case .kimiCN:
            add(details?.sevenDayUsage, priority: .weekly)
            add(details?.fiveHourUsage, priority: .hourly)
        case .minimaxCodingPlan:
            add(details?.sevenDayUsage, priority: .weekly)
            add(details?.fiveHourUsage, priority: .hourly)
        case .minimaxCodingPlanCN:
            add(details?.sevenDayUsage, priority: .weekly)
            add(details?.fiveHourUsage, priority: .hourly)
        case .volcanoArk, .mimo, .hunyuan, .zhipuGLM:
            add(details?.sevenDayUsage, priority: .weekly)
            add(details?.fiveHourUsage, priority: .hourly)
        case .openCodeGo, .minimaxCN, .minimax, .xiaomi, .xiaomiTokenPlanCN:
            // Raw API rate-tracking providers do not expose live quota windows.
            break
        case .kiro:
            add(usage.usagePercentage, priority: .monthly)
        case .grok:
            add(details?.monthlyUsage, priority: .monthly)
        case .codex:
            add(
                details?.secondaryUsage,
                priority: priorityForWindowHours(details?.codexSecondaryWindowHours, fallback: .weekly)
            )
            add(
                details?.sparkSecondaryUsage,
                priority: priorityForWindowHours(details?.sparkSecondaryWindowHours, fallback: .weekly)
            )
            add(
                dailyPercentFromDetails(details),
                priority: priorityForWindowHours(details?.codexPrimaryWindowHours, fallback: .daily)
            )
            add(
                details?.sparkUsage,
                priority: priorityForWindowHours(details?.sparkPrimaryWindowHours, fallback: .hourly)
            )
        case .commandCode:
            add(usage.usagePercentage, priority: .monthly)
        case .cursor:
            add(details?.cursorAutoUsage, priority: .monthly)
            add(details?.cursorApiUsage, priority: .monthly)
        case .copilot:
            if let used = details?.copilotUsedRequests,
               let limit = details?.copilotLimitRequests,
               limit > 0 {
                add((Double(used) / Double(limit)) * 100.0, priority: .monthly)
            }
            add(usage.usagePercentage, priority: .monthly)
        case .zaiCodingPlan:
            add(details?.mcpUsagePercent, priority: .monthly)
            add(details?.tokenUsagePercent, priority: .hourly)
        case .nanoGpt:
            add(details?.sevenDayUsage, priority: .weekly)
        case .chutes:
            add(chutesMonthlyPercentFromDetails(details), priority: .monthly)
            add(dailyPercentFromDetails(details), priority: .daily)
        case .synthetic:
            add(details?.fiveHourUsage, priority: .hourly)
        case .tavilySearch, .braveSearch:
            add(details?.mcpUsagePercent, priority: .monthly)
        case .antigravity, .geminiCLI, .openRouter, .openCode, .openCodeZen:
            break
        }

        add(usage.usagePercentage, priority: .fallback)
        return candidates
    }

    static func preferredUsedPercent(
        identifier: ProviderIdentifier,
        usage: ProviderUsage,
        details: DetailedUsage?
    ) -> Double? {
        let candidates = usagePercentCandidates(identifier: identifier, usage: usage, details: details)
        guard let selectedPriority = candidates.map(\.priority.rawValue).min() else {
            return nil
        }

        return candidates
            .filter { $0.priority.rawValue == selectedPriority }
            .map(\.percent)
            .max()
    }

    /// Applies the global window priority across a provider's main result and sub-accounts.
    static func preferredUsedPercentForStatusBar(
        identifier: ProviderIdentifier,
        result: ProviderResult
    ) -> Double? {
        var allCandidates: [UsagePercentCandidate] = []

        if case .quotaBased = result.usage {
            allCandidates.append(
                contentsOf: usagePercentCandidates(
                    identifier: identifier,
                    usage: result.usage,
                    details: result.details
                )
            )
        }

        if let accounts = result.accounts {
            for account in accounts {
                guard case .quotaBased = account.usage else { continue }
                allCandidates.append(
                    contentsOf: usagePercentCandidates(
                        identifier: identifier,
                        usage: account.usage,
                        details: account.details
                    )
                )
            }
        }

        // Gemini CLI accounts do not expose window metadata, so use fallback priority.
        if identifier == .geminiCLI, let geminiAccounts = result.details?.geminiAccounts {
            for account in geminiAccounts {
                if let normalized = normalizedUsagePercent(100.0 - account.remainingPercentage) {
                    allCandidates.append(UsagePercentCandidate(percent: normalized, priority: .fallback))
                }
            }
        }

        guard let selectedPriority = allCandidates.map(\.priority.rawValue).min() else {
            return nil
        }

        return allCandidates
            .filter { $0.priority.rawValue == selectedPriority }
            .map(\.percent)
            .max()
    }

    static func usedPercentsForChangeDetection(
        identifier: ProviderIdentifier,
        result: ProviderResult
    ) -> [Double] {
        var usedPercents: [Double] = []

        func appendMetrics(usage: ProviderUsage, details: DetailedUsage?) {
            guard case .quotaBased = usage else { return }
            if let percent = normalizedUsagePercent(usage.usagePercentage) {
                usedPercents.append(percent)
            }

            if let details {
                let extraPercents: [Double?] = [
                    details.fiveHourUsage,
                    details.sevenDayUsage,
                    details.sonnetUsage,
                    details.opusUsage,
                    details.secondaryUsage,
                    details.sparkUsage,
                    details.sparkSecondaryUsage,
                    details.cursorAutoUsage,
                    details.cursorApiUsage,
                    details.tokenUsagePercent,
                    details.mcpUsagePercent,
                    details.openCodeGoMonthlyUsage
                ]
                for percent in extraPercents {
                    if let normalized = normalizedUsagePercent(percent) {
                        usedPercents.append(normalized)
                    }
                }
            }
        }

        appendMetrics(usage: result.usage, details: result.details)

        if let accounts = result.accounts {
            for account in accounts {
                appendMetrics(usage: account.usage, details: account.details)
            }
        }

        if identifier == .geminiCLI, let geminiAccounts = result.details?.geminiAccounts {
            for account in geminiAccounts {
                if let percent = normalizedUsagePercent(100.0 - account.remainingPercentage) {
                    usedPercents.append(percent)
                }
            }
        }

        return usedPercents
    }

    static func statusSnapshot(
        for identifier: ProviderIdentifier,
        result: ProviderResult
    ) -> StatusBarProviderSnapshot? {
        switch result.usage {
        case .payAsYouGo(_, let cost, _):
            return StatusBarProviderSnapshot(
                value: max(0.0, cost ?? 0.0),
                kind: .cost
            )
        case .quotaBased:
            let cappedPercents = usedPercentsForChangeDetection(
                identifier: identifier,
                result: result
            ).map { min($0, 100.0) }
            // Aggregate quota usage so non-max windows and accounts can trigger updates.
            let aggregatePercent = cappedPercents.isEmpty
                ? min(max(result.usage.usagePercentage, 0.0), 100.0)
                : cappedPercents.reduce(0.0, +)
            return StatusBarProviderSnapshot(value: max(0.0, aggregatePercent), kind: .usage)
        }
    }

    static func refreshRecentChangeCandidate(
        _ controller: StatusBarController,
        providerResults: [ProviderIdentifier: ProviderResult],
        previousProviderSnapshots: [ProviderIdentifier: StatusBarProviderSnapshot],
        recentChangeCandidate: RecentChangeCandidate?,
        isProviderEnabled: (ProviderIdentifier) -> Bool,
        now: Date = Date()
    ) -> RecentChangeState {
        var state = RecentChangeState(
            previousProviderSnapshots: previousProviderSnapshots,
            recentChangeCandidate: recentChangeCandidate
        )
        var currentSnapshots: [ProviderIdentifier: StatusBarProviderSnapshot] = [:]
        for (identifier, result) in providerResults {
            guard isProviderEnabled(identifier) else { continue }
            guard case .quotaBased = result.usage else { continue }
            guard let snapshot = statusSnapshot(for: identifier, result: result) else { continue }
            currentSnapshots[identifier] = snapshot
        }
        let visibleQuotaIdentifiers = Set(
            quotaAlertCandidates(
                controller,
                providerResults: providerResults,
                isProviderEnabled: isProviderEnabled,
                logContext: "recent-change"
            ).map(\.identifier)
        )

        guard !currentSnapshots.isEmpty else {
            state.previousProviderSnapshots = [:]
            state.recentChangeCandidate = nil
            controller.debugLog("refreshRecentChangeCandidate: no snapshots")
            return state
        }

        if state.previousProviderSnapshots.isEmpty {
            state.previousProviderSnapshots = currentSnapshots
            controller.debugLog("refreshRecentChangeCandidate: baseline snapshots saved")
            return state
        }

        if currentSnapshots == state.previousProviderSnapshots {
            if let existing = state.recentChangeCandidate,
               currentSnapshots[existing.identifier] == nil || !visibleQuotaIdentifiers.contains(existing.identifier) {
                state.recentChangeCandidate = nil
                controller.debugLog("refreshRecentChangeCandidate: cleared hidden or missing candidate")
            } else {
                controller.debugLog("refreshRecentChangeCandidate: snapshots unchanged, keeping previous candidate")
            }
            return state
        }

        var bestCandidate: RecentChangeCandidate?
        for (identifier, newSnapshot) in currentSnapshots {
            guard visibleQuotaIdentifiers.contains(identifier) else {
                controller.debugLog(
                    "refreshRecentChangeCandidate: skipping \(identifier.displayName) because exhausted while other quota remains"
                )
                continue
            }
            guard let oldSnapshot = state.previousProviderSnapshots[identifier],
                  oldSnapshot.kind == newSnapshot.kind else {
                continue
            }

            let delta = newSnapshot.value - oldSnapshot.value
            let absDelta = abs(delta)
            let minThreshold = 0.01
            guard absDelta >= minThreshold else { continue }

            if bestCandidate == nil || absDelta > abs(bestCandidate!.delta) {
                bestCandidate = RecentChangeCandidate(
                    identifier: identifier,
                    kind: newSnapshot.kind,
                    delta: delta,
                    observedAt: now
                )
            }
        }

        state.previousProviderSnapshots = currentSnapshots
        var didClearExistingCandidate = false
        if let bestCandidate {
            state.recentChangeCandidate = bestCandidate
        } else if let existing = state.recentChangeCandidate,
                  currentSnapshots[existing.identifier] == nil || !visibleQuotaIdentifiers.contains(existing.identifier) {
            state.recentChangeCandidate = nil
            didClearExistingCandidate = true
            controller.debugLog("refreshRecentChangeCandidate: cleared hidden or missing candidate after refresh")
        }

        if let bestCandidate {
            controller.debugLog(
                "refreshRecentChangeCandidate: provider=\(bestCandidate.identifier.displayName), "
                    + "kind=\(bestCandidate.kind), delta=\(String(format: "%.2f", bestCandidate.delta))"
            )
        } else if didClearExistingCandidate {
            controller.debugLog("refreshRecentChangeCandidate: no significant change after clearing hidden candidate")
        } else {
            controller.debugLog("refreshRecentChangeCandidate: no significant change, keeping previous candidate")
        }

        return state
    }

    static func rawQuotaAlertCandidates(
        providerResults: [ProviderIdentifier: ProviderResult],
        isProviderEnabled: (ProviderIdentifier) -> Bool
    ) -> [AlertProviderCandidate] {
        var candidates: [AlertProviderCandidate] = []
        for (identifier, result) in providerResults {
            guard isProviderEnabled(identifier) else { continue }
            guard case .quotaBased = result.usage else { continue }
            guard let usedPercent = preferredUsedPercentForStatusBar(
                identifier: identifier,
                result: result
            ) else { continue }
            candidates.append(AlertProviderCandidate(identifier: identifier, usedPercent: usedPercent))
        }
        return candidates
    }

    static func quotaAlertCandidates(
        _ controller: StatusBarController,
        providerResults: [ProviderIdentifier: ProviderResult],
        isProviderEnabled: (ProviderIdentifier) -> Bool,
        logContext: String? = nil
    ) -> [AlertProviderCandidate] {
        let candidates = rawQuotaAlertCandidates(
            providerResults: providerResults,
            isProviderEnabled: isProviderEnabled
        )
        let visibleCandidates = StatusBarQuotaVisibilityPolicy.visibleCandidates(
            from: candidates,
            usedPercent: { $0.usedPercent }
        )
        let allCandidatesExhausted = !candidates.isEmpty
            && candidates.allSatisfy {
                $0.usedPercent >= StatusBarQuotaVisibilityPolicy.exhaustedUsageThreshold
            }

        if let logContext, !candidates.isEmpty {
            controller.debugLog(
                "statusBarQuotaVisibility[\(logContext)]: checked candidates=\(candidates.count), "
                    + "visible=\(visibleCandidates.count), allExhausted=\(allCandidatesExhausted)"
            )
        }

        if let logContext, visibleCandidates.count != candidates.count {
            let visibleIdentifiers = Set(visibleCandidates.map(\.identifier))
            let hiddenProviders = candidates
                .filter { !visibleIdentifiers.contains($0.identifier) }
                .map {
                    "\($0.identifier.displayName)=\(UsagePercentDisplayFormatter.string(from: $0.usedPercent))"
                }
                .joined(separator: ", ")
            controller.debugLog(
                "statusBarQuotaVisibility[\(logContext)]: hiding exhausted providers while other quota remains: "
                    + hiddenProviders
            )
        } else if let logContext, allCandidatesExhausted {
            controller.debugLog(
                "statusBarQuotaVisibility[\(logContext)]: all quota providers exhausted; allowing exhausted provider display"
            )
        }

        return visibleCandidates
    }
}
