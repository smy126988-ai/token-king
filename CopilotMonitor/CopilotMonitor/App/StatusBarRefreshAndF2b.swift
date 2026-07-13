import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "StatusBarController")

/// Refresh timer / fetch / F2b monthly aggregates, extracted from
/// `StatusBarController` so the refresh path and the F2b actor bridge
/// live in a focused file.
///
/// The same pattern as `StatusBarMenuBuilder`: an `@MainActor` instance
/// class that holds a weak reference to the controller and forwards
/// through `controller?` for every property read/write. Properties that
/// this builder mutates are listed in the "Access Adjustments" section
/// below — they need to be loosened from `private` to `internal`
/// (file-level read/write) so this file compiles once it is added to
/// the target. Today the file is a draft kept under `CopilotMonitor/App/`
/// mirroring `StatusBarMenuBuilder.swift`; it is not yet referenced
/// from `project.pbxproj`.
///
/// ## Access Adjustments Required on `StatusBarController`
///
/// The following members need to move from `private` to `internal`
/// (or `fileprivate`-equivalent open scope) when this file is wired into
/// the build, otherwise the `controller?.<member>` calls below will not
/// compile. All of these are read **and** written by this builder:
///
/// - `var refreshTimer: Timer?` (line 173)
/// - `var initialRefreshTask: Task<Void, Never>?` (line 174)
/// - `var isFetching: Bool` (line 181)
/// - `var isMainMenuTracking: Bool` (line 175)
/// - `var hasDeferredStatusBarRefresh: Bool` (line 177)
/// - `var statusBarIconView: StatusBarIconView?` (line 158)
/// - `var providerResults: [ProviderIdentifier: ProviderResult]` (line 192)
/// - `var loadingProviders: Set<ProviderIdentifier>` (line 193)
/// - `var lastProviderErrors: [ProviderIdentifier: String]` (line 196)
/// - `var viewErrorDetailsItem: NSMenuItem!` (line 197)
/// - `var currentUsage: CopilotUsage?` (line 179)
/// - `var cachedMonthlyTotals: [MonthlyTotal]` (line 217)
/// - `var lastMonthlyTotalsFetchAt: Date?` (line 218)
/// - `var refreshActorInitError: SQLiteError?` (line 221)
/// - `var cachedTokenStats: TokenStatsAggregator.Snapshot?` (line 226)
/// - `var lastTokenStatsFetchAt: Date?` (line 227)
///
/// And the following **methods** also need access loosening (read-only,
///
/// driven from inside this file):
///
/// - `func debugLog(_:)` (line 417)
/// - `func isProviderEnabled(_:)` (line 856)
/// - `func updateMultiProviderMenu()` (line 1993)
/// - `func updateStatusBarText()` (line 1763)
/// - computed `var refreshInterval: RefreshInterval` (line 252)
///
/// `refreshActor` (line 208) and `tokenUsageStore` (line 212) are
/// already `internal var`, and `currencyFormatter` (line 155) is
/// already an internal getter — no adjustment needed.
///
/// ## Usage from the controller (future wiring, NOT in this task)
///
/// ```swift
/// private lazy var refreshAndF2b = StatusBarRefreshAndF2b(controller: self)
///
/// func startBackgroundTasks() {
///     refreshAndF2b.startRefreshTimer()
/// }
///
/// func triggerRefresh() {
///     refreshAndF2b.triggerRefresh()
/// }
/// ```
@MainActor
final class StatusBarRefreshAndF2b {
    /// Weak reference to the owning controller. Cleared on controller
    /// dealloc so we do not retain the NSStatusItem-bearing object.
    weak var controller: StatusBarController?

    init(controller: StatusBarController) {
        self.controller = controller
    }

    // MARK: - Refresh Timer

    /// Restart the periodic refresh timer (delegate is the F2b
    /// `RefreshActor` for the 30s tick). Equivalent to calling
    /// `startRefreshTimer()`; kept as a separate entry point so call
    /// sites can read intent at the call site (e.g. after a settings
    /// change that mutates `refreshInterval`).
    func restartRefreshTimer() {
        startRefreshTimer()
    }

    /// Placeholder for future provider-specific notification
    /// observers (e.g. Copilot quota reset). Intentionally empty for
    /// now; preserved so the call site at app launch remains stable.
    func setupNotificationObservers() {
        // Keep this for future provider-specific observers.
    }

    /// Stop any existing timer + initial-refresh task, then start a
    /// new timer keyed off the current `refreshInterval`. Also kicks
    /// off a one-shot 1s initial refresh so the UI updates quickly
    /// after the user changes the refresh interval.
    func startRefreshTimer() {
        guard let controller else { return }
        controller.refreshTimer?.invalidate()
        controller.initialRefreshTimer?.invalidate()

        let interval = TimeInterval(controller.refreshInterval.rawValue)
        let intervalTitle = controller.refreshInterval.title
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            logger.info("Timer triggered (\(intervalTitle))")
            Task { @MainActor [weak self] in
                self?.triggerRefresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        controller.refreshTimer = timer

        let initialTimer = Timer(timeInterval: 1.0, repeats: false) { [weak self] _ in
            self?.triggerRefresh()
        }
        RunLoop.main.add(initialTimer, forMode: .common)
        controller.initialRefreshTimer = initialTimer
    }

    /// Entry point for any caller that wants to force a fetch now
    /// (menu "Refresh" item, `AppDelegate` boot hook, timer tick).
    /// Simply forwards to `fetchUsage()`.
    func triggerRefresh() {
        logger.info("triggerRefresh started")
        fetchUsage()
    }

    // MARK: - Single Fetch

    /// Coalesce duplicate fetch requests, flip the loading flag, then
    /// dispatch the multi-provider fetch on the main actor. Called from
    /// `triggerRefresh()`.
    func fetchUsage() {
        guard let controller else { return }
        controller.debugLog("fetchUsage: called")
        logger.info("fetchUsage started, isFetching: \(controller.isFetching)")

        guard !controller.isFetching else {
            controller.debugLog("fetchUsage: already fetching, returning")
            return
        }
        controller.isFetching = true
        if controller.isMainMenuTracking {
            controller.hasDeferredStatusBarRefresh = true
            controller.debugLog("fetchUsage: menu is open, deferring loading indicator")
        } else {
            controller.debugLog("fetchUsage: showing loading")
            controller.statusBarIconView?.showLoading()
        }

        controller.debugLog("fetchUsage: creating Task")
        Task { @MainActor [weak self] in
            controller.debugLog("fetchUsage Task: calling fetchMultiProviderData")
            await self?.fetchMultiProviderData()
            controller.debugLog("fetchUsage Task: fetchMultiProviderData completed")
            controller.debugLog("fetchUsage Task: all done, setting isFetching=false")
            controller.isFetching = false
        }
        controller.debugLog("fetchUsage: Task created")
    }

    // MARK: - Multi-Provider Fetch

    /// Walk every enabled provider, collect results + errors from
    /// `ProviderManager.fetchAll()`, project the result into
    /// `controller.providerResults` / `currentUsage`, then rebuild
    /// the dynamic portion of the menu and the status bar text.
    ///
    /// Mirrors the implementation that lived at
    /// `StatusBarController.swift` lines 988-1083 verbatim except for
    /// the controller hop.
    func fetchMultiProviderData() async {
        guard let controller else { return }
        controller.debugLog("🔵 fetchMultiProviderData: started")
        logger.info("🔵 [StatusBarController] fetchMultiProviderData() started")

        let enabledProviders = await ProviderManager.shared.getAllProviders().filter { provider in
            controller.isProviderEnabled(provider.identifier)
        }
        controller.debugLog("🔵 fetchMultiProviderData: enabledProviders count=\(enabledProviders.count)")
        logger.debug("🔵 [StatusBarController] enabledProviders: \(enabledProviders.map { $0.identifier.displayName }.joined(separator: ", "))")

        guard !enabledProviders.isEmpty else {
            logger.info("🟡 [StatusBarController] fetchMultiProviderData: No enabled providers, skipping")
            controller.debugLog("🟡 fetchMultiProviderData: No enabled providers, returning")
            return
        }

        controller.loadingProviders = Set(enabledProviders.map { $0.identifier })
        let loadingCount = controller.loadingProviders.count
        let loadingNames = controller.loadingProviders.map { $0.displayName }.joined(separator: ", ")
        controller.debugLog("🟡 fetchMultiProviderData: marked \(loadingCount) providers as loading")
        logger.debug("🟡 [StatusBarController] loadingProviders set: \(loadingNames)")
        controller.updateMultiProviderMenu()

        logger.info("🟡 [StatusBarController] fetchMultiProviderData: Calling ProviderManager.fetchAll()")
        controller.debugLog("🟡 fetchMultiProviderData: calling ProviderManager.fetchAll()")
        let fetchResult = await ProviderManager.shared.fetchAll()
        controller.debugLog("🟢 fetchMultiProviderData: fetchAll returned \(fetchResult.results.count) results, \(fetchResult.errors.count) errors")
        logger.info("🟢 [StatusBarController] fetchMultiProviderData: fetchAll() returned \(fetchResult.results.count) results, \(fetchResult.errors.count) errors")

        let filteredResults = fetchResult.results.filter { identifier, _ in
            controller.isProviderEnabled(identifier)
        }
        let filteredNames = filteredResults.keys.map { $0.displayName }.joined(separator: ", ")
        controller.debugLog("🟢 fetchMultiProviderData: filteredResults count=\(filteredResults.count)")
        logger.debug("🟢 [StatusBarController] filteredResults: \(filteredNames)")

        controller.providerResults = filteredResults

        // Extract CopilotUsage from provider result if available
        if let copilotResult = filteredResults[.copilot],
           let details = copilotResult.details,
           let usedRequests = details.copilotUsedRequests,
           let limitRequests = details.copilotLimitRequests {
            controller.currentUsage = CopilotUsage(
                netBilledAmount: details.copilotOverageCost ?? 0.0,
                netQuantity: details.copilotOverageRequests ?? 0.0,
                discountQuantity: Double(usedRequests),
                userPremiumRequestEntitlement: limitRequests,
                filteredUserPremiumRequestEntitlement: 0,
                copilotPlan: details.planType,
                quotaResetDateUTC: details.copilotQuotaResetDateUTC
            )
            controller.debugLog("🟢 fetchMultiProviderData: currentUsage set from Copilot provider - used: \(usedRequests), limit: \(limitRequests)")
            logger.info("🟢 [StatusBarController] currentUsage set from Copilot provider")
        } else {
            controller.debugLog("🟡 fetchMultiProviderData: No Copilot data available, currentUsage not set")
        }

        let filteredErrors = fetchResult.errors.filter { identifier, _ in
            controller.isProviderEnabled(identifier)
        }
        controller.lastProviderErrors = filteredErrors

        for identifier in filteredResults.keys {
            controller.loadingProviders.remove(identifier)
        }
        for identifier in filteredErrors.keys {
            controller.loadingProviders.remove(identifier)
        }
        let remainingLoading = controller.loadingProviders.map { $0.displayName }.joined(separator: ", ")
        controller.debugLog("🟢 fetchMultiProviderData: cleared loading state for \(filteredResults.count) results, \(filteredErrors.count) errors")
        logger.debug("🟢 [StatusBarController] loadingProviders after clear: \(remainingLoading)")
        controller.viewErrorDetailsItem.isHidden = filteredErrors.isEmpty
        controller.debugLog("📍 fetchMultiProviderData: viewErrorDetailsItem.isHidden = \(filteredErrors.isEmpty)")

        if !filteredErrors.isEmpty {
            let errorNames = filteredErrors.keys.map { $0.displayName }.joined(separator: ", ")
            controller.debugLog("🔴 fetchMultiProviderData: errors from: \(errorNames)")
            logger.warning("🔴 [StatusBarController] Errors from providers: \(errorNames)")
        }
        controller.debugLog("🟢 fetchMultiProviderData: calling updateMultiProviderMenu")
        logger.debug("🟢 [StatusBarController] providerResults updated, calling updateMultiProviderMenu()")
        controller.updateMultiProviderMenu()
        controller.debugLog("🟢 fetchMultiProviderData: updateMultiProviderMenu completed")
        logger.info("🟢 [StatusBarController] fetchMultiProviderData: updateMultiProviderMenu() completed")

        // Refresh the status bar text/icon so the loading spinner is replaced
        // with the real cost/usage display. Without this call, the icon stays
        // in showLoading() state (rotating gauge) and the user sees a
        // permanent "Loading..." indicator (B09 follow-up).
        controller.debugLog("🟢 fetchMultiProviderData: calling updateStatusBarText")
        controller.updateStatusBarText()

        logger.info("🟢 [StatusBarController] fetchMultiProviderData: Completed with \(filteredResults.count) results")
        controller.debugLog("🟢 fetchMultiProviderData: completed")
    }

    // MARK: - Cost Aggregations

    /// Sum `payAsYouGo` costs across every provider plus
    /// `CopilotUsage.netBilledAmount`. Returns USD regardless of the
    /// active currency — convert at the call site if needed.
    func calculatePayAsYouGoTotal(providerResults: [ProviderIdentifier: ProviderResult], copilotUsage: CopilotUsage?) -> Double {
        var total = 0.0

        if let copilot = copilotUsage {
            total += copilot.netBilledAmount
        }

        for (_, result) in providerResults {
            if case .payAsYouGo(_, let cost, _) = result.usage, let cost = cost {
                total += cost
            }
        }

        return total
    }

    /// Convert the pay-as-you-go total to the active currency and
    /// add the subscription monthly cost from
    /// `SubscriptionSettingsManager`.
    func calculateTotalWithSubscriptions(providerResults: [ProviderIdentifier: ProviderResult], copilotUsage: CopilotUsage?) -> Double {
        guard let controller else { return 0.0 }
        let payAsYouGoUSD = calculatePayAsYouGoTotal(providerResults: providerResults, copilotUsage: copilotUsage)
        let currency = controller.currencyFormatter.currency
        let payAsYouGoInCurrency = payAsYouGoUSD * (currency == .rmb ? controller.currencyFormatter.currentRate : 1.0)
        let subscriptionsInCurrency = SubscriptionSettingsManager.shared.totalMonthlyCost(inCurrency: currency, formatter: controller.currencyFormatter)
        return payAsYouGoInCurrency + subscriptionsInCurrency
    }

    // MARK: - Status Bar Formatting

    /// Format a USD cost for the status bar (no currency symbol —
    /// status bar rows carry the currency separately).
    func formatCostForStatusBar(_ cost: Double) -> String {
        guard let controller else { return "" }
        return controller.currencyFormatter.format(usd: cost)
    }

    /// Format a pre-converted amount in the active currency for the
    /// status bar (skips USD→currency conversion that
    /// `format(usd:)` would apply).
    func formatCurrencyAmountForStatusBar(_ amount: Double) -> String {
        guard let controller else { return "" }
        return controller.currencyFormatter.format(amount: amount, as: controller.currencyFormatter.currency)
    }

    /// Format a cost for the status bar, falling back to the brand
    /// string "TK" when the cost is zero (so the menu bar icon stays
    /// meaningful even with no spend yet).
    func formatCostOrStatusBarBrand(_ cost: Double) -> String {
        if cost <= 0 {
            return "TK"
        }
        return formatCurrencyAmountForStatusBar(cost)
    }

    // MARK: - F2b Monthly Aggregates Access

    /// F2b: total RMB across every provider for the current month.
    /// Wraps `RefreshActor.fetchMonthlyTotals()` and sums
    /// `totalCostRMB`. Returns `nil` when no actor is wired up
    /// (legacy/test paths).
    func monthTotalPayAsYouGoRMB() async -> Double? {
        guard let controller, let actor = controller.refreshActor else { return nil }
        let totals = await actor.fetchMonthlyTotals()
        return totals.reduce(0) { $0 + $1.totalCostRMB }
    }

    /// F2b: synchronous read of the cached monthly total (RMB). Used
    /// by the share snapshot so it can append the F2b line without an
    /// `async` hop.
    var monthTotalPayAsYouGoRMBSync: Double? {
        guard let controller, !controller.cachedMonthlyTotals.isEmpty else { return nil }
        return controller.cachedMonthlyTotals.reduce(0) { $0 + $1.totalCostRMB }
    }

    /// F2b: pass-through to `RefreshActor.fetchMonthlyTotals()`.
    /// Returns `nil` when no actor is wired up so call sites can
    /// early-exit without actor isolation noise.
    func fetchMonthlyTotals() async -> [MonthlyTotal]? {
        guard let controller, let actor = controller.refreshActor else { return nil }
        return await actor.fetchMonthlyTotals()
    }

    /// F2b: fetch the latest monthly totals from the actor and update
    /// the synchronous cache, then rebuild the menu so the new row
    /// appears. Scheduled by AppDelegate as a periodic task after
    /// `startRefreshActor()`.
    func refreshMonthlyTotalsCache() async {
        guard let controller, let actor = controller.refreshActor else { return }
        if let initError = actor.initError {
            controller.refreshActorInitError = initError
            controller.cachedMonthlyTotals = []
            controller.updateMultiProviderMenu()
            return
        }
        controller.refreshActorInitError = nil
        let totals = await actor.fetchMonthlyTotals()
        controller.cachedMonthlyTotals = totals
        controller.lastMonthlyTotalsFetchAt = Date()
        controller.debugLog("refreshMonthlyTotalsCache: \(totals.count) provider(s)")
        controller.updateMultiProviderMenu()
    }

    /// F2b: lookup helper for `ProviderMenuBuilder`. Resolves the
    /// per-provider monthly cost-equivalent (RMB) from the
    /// synchronous cache. Returns `nil` when the cache has not been
    /// populated yet OR the provider has no row.
    func monthlyCostRMB(for providerRaw: String) -> Double? {
        guard let controller, !controller.cachedMonthlyTotals.isEmpty else { return nil }
        return controller.cachedMonthlyTotals.first(where: { $0.provider == providerRaw })?.totalCostRMB
    }

    /// F1 / F4: fetch the latest `day_aggregates` from the store and
    /// recompute today / week / month totals into the sync cache.
    /// Scheduled by `AppDelegate` on the same periodic loop as
    /// `refreshMonthlyTotalsCache`. Returns silently when no
    /// `tokenUsageStore` is wired up.
    func refreshTokenStatsCache() async {
        guard let controller else { return }
        guard let store = controller.tokenUsageStore else {
            controller.cachedTokenStats = nil
            return
        }
        // F2b B54: if the store failed to init, hide F1/F4 (mirrors
        // refreshMonthlyTotalsCache which switches the cost section
        // to "用量数据不可用").
        if await store.initError != nil {
            controller.cachedTokenStats = nil
            controller.updateMultiProviderMenu()
            return
        }
        let month = await store.currentYearMonth()
        let dayAggregates = await store.fetchDayAggregates(yearMonth: month)
        let todayString = TokenUsageFormatter.todayUTCString()
        let (weekStart, weekEnd) = TokenUsageFormatter.currentISOWeekRange()
        // P0-2 fix: source `monthTotal` from `month_aggregates`
        // (refreshed on every tick for the current month) instead of
        // `day_aggregates` (single-day incremental, can be missing
        // past days → underreports monthly total).
        let monthTotalFromAggregates = await store.fetchMonthAggregatesSum(yearMonth: month)
        controller.cachedTokenStats = TokenStatsAggregator.snapshot(
            dayAggregates: dayAggregates,
            todayString: todayString,
            weekStart: weekStart,
            weekEnd: weekEnd,
            monthPrefix: month,
            monthTotalOverride: monthTotalFromAggregates
        )
        controller.lastTokenStatsFetchAt = Date()
        controller.updateMultiProviderMenu()
    }

    /// F1 / F4: synchronous accessor for the latest token snapshot.
    /// Returns `nil` when the cache has not been populated yet
    /// (e.g. before the first periodic tick) or no store is wired up.
    func tokenStatsSnapshot() -> TokenStatsAggregator.Snapshot? {
        controller?.cachedTokenStats
    }

    /// F1: synchronous accessor for the current month's total token
    /// count. Returns 0 when the cache is empty (so the caller can
    /// decide whether to render the header — the F1 section is hidden
    /// at 0 by the menu builder).
    func currentMonthTotalTokens() -> TokenBreakdown {
        controller?.cachedTokenStats?.monthTotal ?? TokenBreakdown.zero
    }

    /// F2b: render a token count as a compact "1.2k" / "3.4M" string.
    func formatTokenCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    /// F2b: bridge from F2a `ProviderIdentifier` (which carries
    /// regional variants and snake_case raw values) to the F2b
    /// `Provider.rawValue` strings stored in
    /// `TokenUsageStore.month_aggregates`. Returns `nil` for
    /// providers without an F2b row (e.g. Copilot, OpenRouter —
    /// these are real pay-as-you-go providers, not the hypothetical
    /// conversion target F2b tracks).
    func f2bProviderRaw(for identifier: ProviderIdentifier) -> String? {
        switch identifier {
        case .kimi, .kimiCN: return "kimi"
        case .claude: return "claude"
        case .codex: return "codex"
        case .zaiCodingPlan: return "zai"
        case .nanoGpt: return "nanogpt"
        case .minimaxCN: return "minimaxCN"
        case .openCodeGo: return "opencodeGo"
        case .xiaomiTokenPlanCN: return "xiaomiTokenPlanCN"
        default: return nil
        }
    }

    /// F1 (token aggregation): splits .kimi / .kimiCN into distinct
    /// F2b `Provider.rawValue` strings so the SQL filter
    /// `provider = ?` matches Kimi CN events stored separately from
    /// Kimi Global events in `day_aggregates`. Differs from
    /// `f2bProviderRaw` which intentionally merges them for the cost
    /// path (PricingTable treats both at the same rate).
    func f2bTokenProviderRaw(for identifier: ProviderIdentifier) -> String? {
        switch identifier {
        case .kimi:           return "kimi"
        case .kimiCN:         return "kimiCN"
        case .claude:         return "claude"
        case .codex:          return "codex"
        case .zaiCodingPlan:  return "zai"
        case .nanoGpt:        return "nanogpt"
        case .minimaxCN:         return "minimaxCN"
        case .openCodeGo:        return "opencodeGo"
        case .xiaomiTokenPlanCN: return "xiaomiTokenPlanCN"
        default:              return nil
        }
    }
}
