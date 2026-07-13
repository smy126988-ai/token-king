import AppKit

/// Builder for the static (non-dynamic) portion of the status bar menu.
///
/// Extracted from `StatusBarController` so the menu construction logic lives in
/// a focused file. The dynamic provider rows are still rebuilt by
/// `updateMultiProviderMenu()` on the controller — this builder only owns the
/// setup work and the per-frame state sync helpers that run on every menu
/// open (refresh interval check, status bar display state, currency state,
/// provider enabled-state).
///
/// Usage from the controller:
/// ```swift
/// private lazy var menuBuilder = StatusBarMenuBuilder(controller: self)
///
/// func setupMenu() {
///     menuBuilder.setupMenu()
/// }
/// ```
@MainActor
final class StatusBarMenuBuilder {
    weak var controller: StatusBarController?

    init(controller: StatusBarController) {
        self.controller = controller
    }

    // MARK: - Setup

    /// Build the static menu structure: refresh action, settings submenu tree,
    /// status-bar options, launch-at-login, CLI install, diagnostics, version
    /// row, quit. Leaves a tag-0 separator anchor for `updateMultiProviderMenu`
    /// to append dynamic provider rows after.
    func setupMenu() {
        guard let controller else { return }
        controller.menu = NSMenu()
        controller.menu.delegate = controller
        controller.debugLog("[anchor-fp] setupMenu: fresh NSMenu created, anchor=nil")

        // Load cached history immediately on startup (before API fetch completes)
        controller.loadCachedHistoryOnStartup()

        let refreshItem = NSMenuItem(title: "刷新", action: #selector(controller.refreshClicked), keyEquivalent: "r")
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        refreshItem.target = controller
        controller.menu.addItem(refreshItem)

        // 设置 ▶
        controller.settingsMenuItem = NSMenuItem(title: "设置", action: nil, keyEquivalent: "")
        controller.settingsMenuItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        controller.settingsSubmenu = NSMenu()

        let refreshIntervalItem = NSMenuItem(title: "自动刷新", action: nil, keyEquivalent: "")
        refreshIntervalItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Auto Refresh")
        controller.refreshIntervalMenu = NSMenu()
        for interval in RefreshInterval.allCases {
            let item = NSMenuItem(title: interval.title, action: #selector(controller.refreshIntervalSelected(_:)), keyEquivalent: "")
            item.target = controller
            item.tag = interval.rawValue
            controller.refreshIntervalMenu.addItem(item)
        }
        refreshIntervalItem.submenu = controller.refreshIntervalMenu
        controller.settingsSubmenu.addItem(refreshIntervalItem)
        updateRefreshIntervalMenu()

        let statusBarOptionsItem = NSMenuItem(title: "状态栏选项", action: nil, keyEquivalent: "")
        statusBarOptionsItem.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Status Bar Options")
        let statusBarOptionsMenu = NSMenu()

        let displayModeItem = NSMenuItem(title: "菜单栏显示", action: nil, keyEquivalent: "")
        displayModeItem.image = NSImage(systemSymbolName: "textformat.size", accessibilityDescription: "Menu Bar Display")
        controller.menuBarDisplayModeMenu = NSMenu()
        for mode in MenuBarDisplayMode.allCases {
            if mode == .onlyShow {
                let onlyShowItem = NSMenuItem(title: mode.title, action: nil, keyEquivalent: "")
                onlyShowItem.tag = mode.rawValue
                controller.onlyShowModeMenu = NSMenu()
                for onlyShowMode in OnlyShowMode.allCases {
                    if onlyShowMode == .pinnedProvider {
                        let pinnedProviderItem = NSMenuItem(title: onlyShowMode.title, action: nil, keyEquivalent: "")
                        controller.onlyShowProviderMenu = NSMenu()
                        for identifier in ProviderIdentifier.allCases.filter(\.isEnabled) {
                            let providerItem = NSMenuItem(
                                title: identifier.displayName,
                                action: #selector(controller.menuBarOnlyShowProviderSelected(_:)),
                                keyEquivalent: ""
                            )
                            providerItem.target = controller
                            providerItem.representedObject = identifier.rawValue
                            controller.onlyShowProviderMenu.addItem(providerItem)
                        }
                        pinnedProviderItem.submenu = controller.onlyShowProviderMenu
                        controller.onlyShowModeMenu.addItem(pinnedProviderItem)
                    } else {
                        let onlyShowModeItem = NSMenuItem(
                            title: onlyShowMode.title,
                            action: #selector(controller.onlyShowModeSelected(_:)),
                            keyEquivalent: ""
                        )
                        onlyShowModeItem.target = controller
                        onlyShowModeItem.tag = onlyShowMode.rawValue
                        controller.onlyShowModeMenu.addItem(onlyShowModeItem)
                    }
                }
                onlyShowItem.submenu = controller.onlyShowModeMenu
                controller.menuBarDisplayModeMenu.addItem(onlyShowItem)
            } else {
                let modeItem = NSMenuItem(title: mode.title, action: #selector(controller.menuBarDisplayModeSelected(_:)), keyEquivalent: "")
                modeItem.target = controller
                modeItem.tag = mode.rawValue
                controller.menuBarDisplayModeMenu.addItem(modeItem)
            }
        }
        displayModeItem.submenu = controller.menuBarDisplayModeMenu
        statusBarOptionsMenu.addItem(displayModeItem)
        statusBarOptionsMenu.addItem(NSMenuItem.separator())

        controller.criticalBadgeMenuItem = NSMenuItem(title: "严重告警标记", action: #selector(controller.toggleCriticalBadge(_:)), keyEquivalent: "")
        controller.criticalBadgeMenuItem.target = controller
        statusBarOptionsMenu.addItem(controller.criticalBadgeMenuItem)

        controller.showProviderNameMenuItem = NSMenuItem(title: "显示服务商图标", action: #selector(controller.toggleShowProviderName(_:)), keyEquivalent: "")
        controller.showProviderNameMenuItem.target = controller
        statusBarOptionsMenu.addItem(controller.showProviderNameMenuItem)
        statusBarOptionsMenu.addItem(buildCurrencyMenu())

        statusBarOptionsItem.submenu = statusBarOptionsMenu
        controller.settingsSubmenu.addItem(statusBarOptionsItem)
        updateStatusBarDisplayMenuState()

        controller.launchAtLoginItem = NSMenuItem(title: "开机启动", action: #selector(controller.launchAtLoginClicked), keyEquivalent: "")
        controller.launchAtLoginItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Launch at Login")
        controller.launchAtLoginItem.target = controller
        controller.updateLaunchAtLoginState()
        controller.settingsSubmenu.addItem(controller.launchAtLoginItem)

        controller.installCLIItem = NSMenuItem(title: "安装命令行工具 (opencodebar)", action: #selector(controller.installCLIClicked), keyEquivalent: "")
        controller.installCLIItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Install CLI")
        controller.installCLIItem.target = controller
        controller.settingsSubmenu.addItem(controller.installCLIItem)
        controller.updateCLIInstallState()

        controller.diagnosticsModeMenuItem = NSMenuItem(title: "诊断模式", action: #selector(controller.toggleDiagnosticsMode(_:)), keyEquivalent: "")
        controller.diagnosticsModeMenuItem.image = NSImage(systemSymbolName: "stethoscope", accessibilityDescription: "Diagnostic Mode")
        controller.diagnosticsModeMenuItem.target = controller
        controller.settingsSubmenu.addItem(controller.diagnosticsModeMenuItem)
        controller.updateDiagnosticsModeMenuState()

        let shareSnapshotItem = NSMenuItem(title: "分享用量快照…", action: #selector(controller.shareUsageSnapshotClicked), keyEquivalent: "")
        shareSnapshotItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share Usage Snapshot")
        shareSnapshotItem.target = controller
        controller.settingsSubmenu.addItem(shareSnapshotItem)
        controller.debugLog("setupMenu: Share Usage Snapshot menu item added")

        let checkForUpdatesItem = NSMenuItem(title: "检查更新…", action: #selector(AppDelegate.checkForUpdates), keyEquivalent: "u")
        checkForUpdatesItem.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "Check for Updates")
        checkForUpdatesItem.target = NSApp.delegate
        controller.settingsSubmenu.addItem(checkForUpdatesItem)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let gitHash = Bundle.main.infoDictionary?["GitCommitHash"] as? String ?? "unknown"
        let shortHash = String(gitHash.prefix(7))
        let versionItem = NSMenuItem(title: "Token King v\(version) (\(shortHash))", action: #selector(controller.openGitHub), keyEquivalent: "")
        versionItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Version")
        versionItem.target = controller
        controller.settingsSubmenu.addItem(versionItem)

        let quitItem = NSMenuItem(title: "退出", action: #selector(controller.quitClicked), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Quit")
        quitItem.target = controller
        controller.settingsSubmenu.addItem(quitItem)

        controller.viewErrorDetailsItem = NSMenuItem(title: "查看错误详情…", action: #selector(controller.viewErrorDetailsClicked), keyEquivalent: "e")
        controller.viewErrorDetailsItem.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "View Error Details")
        controller.viewErrorDetailsItem.target = controller
        controller.viewErrorDetailsItem.isHidden = true
        controller.settingsSubmenu.addItem(controller.viewErrorDetailsItem)

        controller.settingsMenuItem.submenu = controller.settingsSubmenu
        controller.menu.addItem(controller.settingsMenuItem)

        // This separator is the anchor that updateMultiProviderMenu() uses as
        // the start point for dynamic provider rows. Must be preserved.
        controller.menu.addItem(NSMenuItem.separator())

        // SwiftUI MenuBarExtra + MenuBarExtraAccess bridge: NSStatusItem is
        // supplied to us via `attachTo(_:)` from AppDelegate (the bridge
        // callback fires once SwiftUI provisions the NSSceneStatusItem).
        controller.logMenuStructure()
    }

    // MARK: - State sync helpers

    /// Toggle the checkmark on the auto-refresh submenu to match the
    /// currently-selected `RefreshInterval`.
    func updateRefreshIntervalMenu() {
        guard let controller else { return }
        for item in controller.refreshIntervalMenu.items {
            item.state = (item.tag == controller.refreshInterval.rawValue) ? .on : .off
        }
    }

    /// Seed the Brave search refresh-mode preference to `.eventOnly` the first
    /// time the app runs. Idempotent for existing users.
    func ensureBraveRefreshModeDefault() {
        guard let controller else { return }
        if controller.userDefaults.object(forKey: SearchEnginePreferences.braveRefreshModeKey) == nil {
            controller.userDefaults.set(
                BraveSearchRefreshMode.eventOnly.rawValue,
                forKey: SearchEnginePreferences.braveRefreshModeKey
            )
            controller.debugLog("braveRefreshMode default initialized: \(BraveSearchRefreshMode.eventOnly.title)")
        }
    }

    /// Sync the menu-bar display submenu checkmarks with the current
    /// `MenuBarDisplayMode`, `OnlyShowMode`, and pinned-provider selection.
    /// Also toggles the critical-badge and provider-icon checkmarks.
    func updateStatusBarDisplayMenuState() {
        guard let controller else { return }
        if let menuBarDisplayModeMenu = controller.menuBarDisplayModeMenu {
            let currentMode = controller.menuBarDisplayMode
            let currentOnlyShowMode = controller.onlyShowMode
            let currentProvider = controller.menuBarDisplayProvider
            for item in menuBarDisplayModeMenu.items {
                if let submenu = item.submenu, submenu === controller.onlyShowModeMenu {
                    item.state = (currentMode == .onlyShow) ? .on : .off

                    for onlyShowItem in submenu.items {
                        if let providerSubmenu = onlyShowItem.submenu {
                            onlyShowItem.state = (currentMode == .onlyShow && currentOnlyShowMode == .pinnedProvider) ? .on : .off
                            for providerItem in providerSubmenu.items {
                                guard let rawValue = providerItem.representedObject as? String,
                                      let identifier = ProviderIdentifier(rawValue: rawValue) else {
                                    continue
                                }
                                providerItem.state = (
                                    currentMode == .onlyShow &&
                                    currentOnlyShowMode == .pinnedProvider &&
                                    currentProvider == identifier
                                ) ? .on : .off
                                providerItem.isEnabled = isProviderEnabled(identifier)
                            }
                        } else if let mode = OnlyShowMode(rawValue: onlyShowItem.tag) {
                            onlyShowItem.state = (currentMode == .onlyShow && currentOnlyShowMode == mode) ? .on : .off
                        }
                    }
                    continue
                }

                if let mode = MenuBarDisplayMode(rawValue: item.tag) {
                    item.state = (mode == currentMode) ? .on : .off
                    continue
                }
            }
        }

        controller.criticalBadgeMenuItem?.state = controller.criticalBadgeEnabled ? .on : .off
        controller.showProviderNameMenuItem?.state = controller.showProviderName ? .on : .off
    }

    /// Whether the given provider is enabled. Reads
    /// `provider.<id>.enabled` from `UserDefaults`, defaulting to `true` when
    /// unset. Hard-disabled providers (`isEnabled == false`) are always off.
    func isProviderEnabled(_ identifier: ProviderIdentifier) -> Bool {
        guard let controller else { return false }
        guard identifier.isEnabled else { return false }
        let key = "provider.\(identifier.rawValue).enabled"
        if controller.userDefaults.object(forKey: key) == nil {
            return true
        }
        return controller.userDefaults.bool(forKey: key)
    }

    /// Sync the checkmarks in the enabled-providers submenu with the current
    /// per-provider toggle state.
    func updateEnabledProvidersMenu() {
        guard let controller else { return }
        for item in controller.enabledProvidersMenu.items {
            guard let idString = item.representedObject as? String,
                  let identifier = ProviderIdentifier(rawValue: idString) else { continue }
            item.state = isProviderEnabled(identifier) ? .on : .off
        }
    }

    /// Build the currency picker submenu and cache the inner `NSMenu` on the
    /// controller so `updateCurrencyMenuState()` can re-check the active row.
    func buildCurrencyMenu() -> NSMenuItem {
        guard let controller else { return NSMenuItem() }
        let parent = NSMenuItem(title: "货币", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for currency in Currency.allCases {
            let item = NSMenuItem(title: currency.menuTitle,
                                  action: #selector(controller.selectCurrency(_:)),
                                  keyEquivalent: "")
            item.target = controller
            item.representedObject = currency.rawValue
            item.state = (controller.currencyFormatter.currency == currency) ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        controller.currencyMenu = submenu
        return parent
    }

    /// Sync the currency submenu checkmark with `currencyFormatter.currency`.
    func updateCurrencyMenuState() {
        guard let controller, let currencyMenu = controller.currencyMenu else { return }
        let selected = controller.currencyFormatter.currency.rawValue
        for item in currencyMenu.items {
            guard let raw = item.representedObject as? String else { continue }
            item.state = (raw == selected) ? .on : .off
        }
    }
}