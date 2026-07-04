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
// `isMenuEnabled` MUST be true so SwiftUI actually inserts the `MenuBarExtra`
// into the menu bar; otherwise the bridge never receives a `NSStatusItem` to
// forward to us.

import SwiftUI
import MenuBarExtraAccess

@main
struct ModernApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var isMenuPresented = false
    @State private var isMenuEnabled = true

    var body: some Scene {
        MenuBarExtra(isInserted: $isMenuEnabled) {
            // Placeholder content — MenuBarExtraAccess bridge replaces the menu
            // with the StatusBarController's NSMenu at runtime.
            Text("Loading...")
        } label: {
            Image(systemName: "gauge.medium")
        }
        .menuBarExtraStyle(.menu)
        .menuBarExtraAccess(
            isPresented: $isMenuPresented,
            isEnabled: $isMenuEnabled,
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