// EntryDocumentation.swift — Token King (Personal Customized Fork of OpenCode Bar)
//
// This file is intentionally code-free. The application entry point is the
// `@main struct ModernApp` in `ModernApp.swift`, which conforms to SwiftUI's
// `App` protocol and uses the `MenuBarExtraAccess` bridge to obtain a real
// `NSSceneStatusItem` from the SwiftUI Scene path.
//
// History / why a stub:
//   - An earlier iteration used `@NSApplicationMain` on `AppDelegate` to
//     drive a pure-AppKit entry point. That worked on macOS 13–15, but on
//     macOS 26.x it broke: `NSStatusBar.system.statusItem(withLength:)`
//     returns an `NSSceneStatusItem` that does not respond to `setMenu:`
//     and renders at `button.frame = (0, 0)`, leaving the menu bar item
//     invisible and unclickable.
//   - The fix is to obtain the status item from SwiftUI's `MenuBarExtra`
//     (via the `MenuBarExtraAccess` bridge) and forward it to the
//     `StatusBarController` so we can attach our own `NSMenu` and
//     `StatusBarIconView` to it.
//   - SwiftUI's `@main` on an `App` struct does not invoke the broken
//     `@NSApplicationMain` macro, so we use it here. This means we cannot
//     also have top-level code in a `main.swift` (Swift forbids both
//     `@main` and `main.swift` top-level code in the same target), which
//     is why this file is named `EntryDocumentation.swift` and contains
//     comments only.
//
// If you need to debug the menu bar item lifecycle, look for `attachTo:`
// log lines in `/tmp/provider_debug.log` — that string is emitted by
// `StatusBarController.attachTo(_:)` when the bridge successfully hands
// over the `NSStatusItem`.

// Intentionally empty — see comments above.
