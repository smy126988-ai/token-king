// ModernApp.swift — Token King (Personal Customized Fork of OpenCode Bar)
//
// SwiftUI App entry point. The actual menu bar item is supplied by the
// `MenuBarExtraAccess` bridge: SwiftUI's `MenuBarExtra` creates a real
// `NSSceneStatusItem` (registered in `[NSStatusBar systemStatusBar] _statusItems`)
// and we hand that `NSStatusItem` to `StatusBarController` via
// `appDelegate.attachStatusItem(_:)`.
//
// We use `@main` on this `App` struct (NOT `@NSApplicationMain` on a class) so
// the SwiftUI lifecycle drives the app. In Xcode 26.x debug-dylib builds the
// `@NSApplicationMain` macro emits a stub `_main` that invokes
// `NSApplicationMain` without passing the delegate class, which leaves
// `NSApp.delegate == nil`. The `@main` attribute on a SwiftUI `App` struct does
// not use that broken macro path — it routes through SwiftUI's own `main()`,
// which wires up the delegate correctly.
//
// `StatusItemBridge.isInserted` normally stays true so SwiftUI owns the
// `MenuBarExtra`. It briefly reinserts the scene only when the bridge misses
// its cold-launch callback.

import SwiftUI
import MenuBarExtraAccess
import os.log

private let statusItemBridgeLogger = Logger(
    subsystem: "com.opencodeproviders",
    category: "StatusItemBridge"
)

/// Owns the supported SwiftUI `MenuBarExtra` insertion lifecycle.
/// Re-inserting the scene is the recovery path when the first package
/// introspection runs before AppKit has created its status item.
@MainActor
final class StatusItemBridge: ObservableObject {
    static let shared = StatusItemBridge()

    @Published var isInserted = true

    private(set) var hasAttached = false
    private var recoveryTask: Task<Void, Never>?
    private let recoveryDelays: [Duration]
    private let attachmentGracePeriod: Duration

    init(
        recoveryDelays: [Duration] = [.milliseconds(400), .seconds(1), .seconds(2), .seconds(4), .seconds(6)],
        attachmentGracePeriod: Duration = .milliseconds(500)
    ) {
        self.recoveryDelays = recoveryDelays
        self.attachmentGracePeriod = attachmentGracePeriod
    }

    func markAttached() {
        hasAttached = true
        recoveryTask?.cancel()
        recoveryTask = nil
        statusItemBridgeLogger.notice("MenuBarExtra status item attached")
    }

    func beginRecovery() {
        guard !hasAttached, recoveryTask == nil else { return }
        statusItemBridgeLogger.info("Starting MenuBarExtra cold-launch recovery")

        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for (attempt, delay) in self.recoveryDelays.enumerated() {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                guard !self.hasAttached else { return }

                statusItemBridgeLogger.info("Reinserting MenuBarExtra scene, attempt \(attempt + 1)")
                self.isInserted = false
                do {
                    try await Task.sleep(for: .milliseconds(80))
                } catch {
                    return
                }
                guard !self.hasAttached else { return }
                self.isInserted = true
            }

            do {
                try await Task.sleep(for: self.attachmentGracePeriod)
            } catch {
                return
            }
            guard !self.hasAttached else { return }
            statusItemBridgeLogger.error("MenuBarExtra recovery exhausted without an attachment callback")
            self.recoveryTask = nil
        }
    }

    func cancelRecovery() {
        recoveryTask?.cancel()
        recoveryTask = nil
    }
}

@main
struct ModernApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isMenuPresented = false
    @StateObject private var statusItemBridge = StatusItemBridge.shared

    var body: some Scene {
        MenuBarExtra(isInserted: $statusItemBridge.isInserted) {
            // Placeholder content — MenuBarExtraAccess bridge replaces the menu
            // with the StatusBarController's NSMenu at runtime.
            Text("Loading...")
        } label: {
            // The visible menu bar icon is drawn by `StatusBarIconView` (a subview
            // of `statusItem.button`, attached in `StatusBarController.attachStatusIconViewToButton`).
            // Keeping a visible SwiftUI `Image(systemName:)` label here caused
            // `button.image` to flicker between our `nil` (after commit 5fe507c)
            // and SwiftUI's own `NSSymbolImageRep` of gauge.medium — every time
            // SwiftUI re-evaluated the label the MenuBar briefly showed two icons:
            // the SwiftUI label on top of the subview. See
            // `docs/handoffs/2026-07-05-token-king-icon-blurry.md`. We render a
            // zero-size transparent placeholder here so MenuBarExtraAccess still
            // provisions an NSSceneStatusItem (the bridge needs that), but
            // SwiftUI never paints a competing icon in the menu bar.
            Color.clear.frame(width: 1, height: 1)
        }
        .menuBarExtraStyle(.menu)
        .menuBarExtraAccess(
            isPresented: $isMenuPresented,
            isEnabled: $statusItemBridge.isInserted,
            statusItem: { statusItem in
                // Hand the SwiftUI-owned NSSceneStatusItem to AppDelegate
                // which forwards to StatusBarController.attachTo(_:).
                appDelegate.attachStatusItem(statusItem)
            }
        )

        Settings {
            EmptyView()
        }
    }
}
