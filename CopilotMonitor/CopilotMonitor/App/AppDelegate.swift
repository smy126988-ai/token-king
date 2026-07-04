import AppKit
import Sparkle
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "AppDelegate")

// SwiftUI App lifecycle entry point: `@main struct ModernApp` (in
// `ModernApp.swift`) constructs this delegate via
// `@NSApplicationDelegateAdaptor`. The `MenuBarExtraAccess` bridge inside
// `ModernApp` calls `attachStatusItem(_:)` once SwiftUI has provisioned the
// underlying `NSSceneStatusItem`. We forward it to `StatusBarController`,
// queuing it if the controller has not been initialized yet (the bridge
// callback can fire before `applicationDidFinishLaunching` in some launch
// orderings).
class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var statusBarController: StatusBarController!
    private(set) var updaterController: SPUStandardUpdaterController!

    // Bridge handoff: MenuBarExtraAccess calls this from ModernApp's body
    // evaluation. If `statusBarController` already exists (the normal case,
    // since `applicationDidFinishLaunching` runs first), we forward
    // directly. Otherwise we queue the item and drain the queue after the
    // controller is created in `applicationDidFinishLaunching`.
    private var pendingStatusItem: NSStatusItem?

    @objc func checkForUpdates() {
        logger.info("⌨️ [Keyboard] ⌘U Check for Updates triggered")
        NSApp.activate(ignoringOtherApps: true)
        updaterController.checkForUpdates(self)
    }

    @MainActor
    func attachStatusItem(_ statusItem: NSStatusItem) {
        if let controller = statusBarController {
            logger.info("🌉 [Bridge] attachStatusItem: forwarding to existing controller")
            controller.attachTo(statusItem)
        } else {
            logger.info("🌉 [Bridge] attachStatusItem: controller not ready, queuing item")
            pendingStatusItem = statusItem
        }
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMigrationHelper.shared.checkAndMigrateIfNeeded() {
            return
        }

        AppMigrationHelper.shared.cleanupLegacyBundlesIfNeeded()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        configureAutomaticUpdates()
        statusBarController = StatusBarController()
        closeAllWindows()

        // Drain the bridge queue if the bridge callback already fired
        // before the controller was constructed.
        if let pending = pendingStatusItem {
            logger.info("🌉 [Bridge] draining queued statusItem into controller")
            statusBarController?.attachTo(pending)
            pendingStatusItem = nil
        }
    }
    
    private func configureAutomaticUpdates() {
        let updater = updaterController.updater
        let desiredCheckInterval: TimeInterval = 21600

        // Sparkle persists user preferences for update behavior.
        // Do not override these values on launch.
        if updater.updateCheckInterval != desiredCheckInterval {
            updater.updateCheckInterval = desiredCheckInterval
            logger.info("🔄 [Sparkle] Update check interval updated to 6h (\(desiredCheckInterval)s)")
        }

        let checksEnabled = updater.automaticallyChecksForUpdates
        let downloadsEnabled = updater.automaticallyDownloadsUpdates
        let checkInterval = updater.updateCheckInterval
        
        logger.info("🔄 [Sparkle] Auto-update state loaded: checks=\(checksEnabled), downloads=\(downloadsEnabled), interval=\(checkInterval)s")
    }

    private func closeAllWindows() {
        for window in NSApp.windows where window.title.contains("Settings") {
            window.close()
        }
    }

    // MARK: - SPUUpdaterDelegate
    
    nonisolated func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        logger.info("🔄 [Sparkle] App will relaunch after update")
    }
    
    nonisolated func updaterDidRelaunchApplication(_ updater: SPUUpdater) {
        logger.info("✅ [Sparkle] App relaunched successfully")
    }
}
