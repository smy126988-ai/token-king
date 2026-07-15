import Foundation
import os.log
import WidgetKit

/// Bridges StatusBarController data → WidgetSnapshotMapper → WidgetSnapshotWriter.
///
/// Owned by AppDelegate; runs alongside the existing 5s refresh loop so the
/// widget always sees a snapshot within one refresh cycle of the latest
/// fetch. Pure orchestration: the actual data extraction lives in
/// `WidgetSnapshotMapper`, and disk I/O lives in `WidgetSnapshotWriter`.
@MainActor
final class WidgetSnapshotCoordinator {
    weak var statusBarController: StatusBarController?

    /// Structured logger for orchestration diagnostics. Kept on its own
    /// category so writes that fail here don't get drowned by the writer's
    /// per-write noise in Console.app.
    private let logger = Logger(subsystem: "com.tokenking", category: "widget.coordinator")

    init(statusBarController: StatusBarController?) {
        self.statusBarController = statusBarController
    }

    /// Build a snapshot from current state and feed it to the writer.
    /// Safe to call every 5s; the writer handles throttling.
    func tickAndWrite() {
        guard let controller = statusBarController else { return }
        let snapshot = buildSnapshot(controller: controller)
        let didChange = WidgetSnapshotWriter.shared.write(snapshot)
        if didChange {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Force-write a snapshot, bypassing throttle. Used at app launch.
    func primeAndWrite() {
        guard let controller = statusBarController else {
            logger.debug("primeAndWrite skipped (no controller)")
            return
        }
        let snapshot = buildSnapshot(controller: controller)
        let didChange = WidgetSnapshotWriter.shared.writeNow(snapshot)
        if didChange {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: - Snapshot construction

    /// Compose a snapshot from the controller's cached state.
    private func buildSnapshot(controller: StatusBarController) -> WidgetSnapshot {
        let monthlyCost = computeMonthlyCost(controller: controller)
        return WidgetSnapshotMapper.makeSnapshot(
            providerResults: controller.providerResults,
            monthlyCost: monthlyCost
        )
    }

    /// Aggregate monthly cost from `cachedMonthlyTotals`.
    ///
    /// `MonthlyTotal` only carries RMB (per-provider, derived from
    /// `MonthCostCalculator` against the pricing table). We sum the RMB
    /// column and derive USD via `CurrencyFormatter.currentRate`
    /// (USD→CNY exchange rate), so the widget's USD figure tracks what the
    /// menu's "monthly API equivalent" section displays after the same conversion.
    ///
    /// Returns `nil` when there is nothing to report (no provider data yet),
    /// so the widget can show "no data" rather than "$0.00".
    private func computeMonthlyCost(controller: StatusBarController) -> MonthlyCost? {
        let totals = controller.cachedMonthlyTotals
        guard !totals.isEmpty else { return nil }

        let rmb = totals.reduce(0.0) { $0 + $1.totalCostRMB }
        guard rmb > 0 else { return nil }

        // rate is USD→CNY: usd * rate == rmb. Guard against zero / negative
        // rate (shouldn't happen — CurrencyFormatter falls back to 7.2 — but
        // a misconfigured formatter or pre-init write must not produce inf/NaN
        // in the JSON that the widget would then display as garbage).
        let rate = controller.currencyFormatter.currentRate
        guard rate > 0 else {
            // RMB is meaningful but USD is not — still emit a partial snapshot
            // so the widget can show RMB; drop the bad USD field.
            return MonthlyCost(usd: 0, rmb: rmb)
        }

        let usd = rmb / rate
        return MonthlyCost(usd: usd, rmb: rmb)
    }
}
