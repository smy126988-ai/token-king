// main.swift — Token King (Personal Customized Fork of OpenCode Bar)
//
// Pure AppKit application entry point.
//
// We deliberately do NOT use Swift's `@NSApplicationMain` because in Xcode 26.x
// debug-dylib builds the macro fails to inject the delegate class into the
// `NSApplicationMain()` call, leaving `NSApp.delegate == nil` and
// `applicationDidFinishLaunching` uncalled. The macro generates a stub `_main`
// that invokes `NSApplicationMain` with whatever registers happen to hold at
// startup — so the status bar item is never created.
//
// We register the `AppDelegate` here manually, ensuring the standard NSMenu
// status bar item path is used (no SwiftUI Scene involvement, no
// `NSSceneStatusItem` subclass routing).

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
