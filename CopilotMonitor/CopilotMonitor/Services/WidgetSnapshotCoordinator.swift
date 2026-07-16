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
        // Real monthly spend (actual pay-as-you-go charges + subscription fees),
        // not the token-volume API-equivalent estimate that overstated cost by
        // orders of magnitude for subscription users.
        let monthlyCost = controller.widgetMonthlySpend()
        return WidgetSnapshotMapper.makeSnapshot(
            providerResults: controller.providerResults,
            monthlyCost: monthlyCost
        )
    }
}
