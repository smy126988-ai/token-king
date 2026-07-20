import XCTest
import AppKit
@testable import OpenCode_Bar

/// B39 + B40 regression coverage for multi-display menu sync and secondary
/// status-item icon attachment.
@MainActor
final class AppDelegateB39Tests: XCTestCase {
    func testWidgetRefreshURLMatchesRegisteredRoute() throws {
        let url = try XCTUnwrap(URL(string: "tokenking://refresh"))
        XCTAssertTrue(AppDelegate.isWidgetRefreshURL(url))
    }

    func testWidgetRefreshURLRejectsOtherRoutes() throws {
        let wrongHost = try XCTUnwrap(URL(string: "tokenking://settings"))
        let wrongScheme = try XCTUnwrap(URL(string: "https://refresh"))
        XCTAssertFalse(AppDelegate.isWidgetRefreshURL(wrongHost))
        XCTAssertFalse(AppDelegate.isWidgetRefreshURL(wrongScheme))
    }

    private var primaryItem: NSStatusItem?
    private var fakeWindow: NSWindow?

    override func tearDown() {
        if let window = fakeWindow {
            window.orderOut(nil)
            fakeWindow = nil
        }
        if let item = primaryItem {
            item.isVisible = false
            NSStatusBar.system.removeStatusItem(item)
            primaryItem = nil
        }
        super.tearDown()
    }

    func testScheduleResyncAfterLaunchIsCallableAndCounted() {
        let delegate = AppDelegate()
        XCTAssertEqual(delegate.resyncAfterLaunchCallCount, 0)

        delegate.scheduleResyncAfterLaunch()

        XCTAssertEqual(delegate.resyncAfterLaunchCallCount, 1)
    }

    func testSyncMenuToAllStatusWindowsDoesNotCrashOnSingleScreen() {
        let delegate = AppDelegate()
        let controller = StatusBarController(options: .testing())
        delegate.statusBarController = controller

        let summary = delegate.syncMenuToAllStatusWindows()

        XCTAssertEqual(summary.barWindows, 0)
        XCTAssertEqual(summary.attached, 0)
        XCTAssertEqual(summary.skipped, 0)
    }

    /// Reflection-based check: a window whose class name contains
    /// "NSStatusBarWindow" and exposes a `statusItem` should be inspected by
    /// `syncMenuToAllStatusWindows`. The primary item is found and skipped,
    /// proving the Mirror/KVC path works without crashing.
    func testSyncMenuToAllStatusWindowsFindsPrimaryStatusItemViaReflection() {
        let delegate = AppDelegate()
        let controller = StatusBarController(options: .testing())
        delegate.statusBarController = controller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        primaryItem = item
        controller.attachTo(item)

        let window = B39FakeNSStatusBarWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [],
            backing: .buffered,
            defer: false
        )
        window.statusItem = item
        window.orderFront(nil)
        fakeWindow = window

        XCTAssertTrue(delegate._safeStatusItem(from: window) === item)

        let summary = delegate.syncMenuToAllStatusWindows()

        XCTAssertGreaterThanOrEqual(summary.barWindows, 1)
        // The primary item's own window is found and skipped, so at least one
        // window should not contribute to `attached`.
        XCTAssertLessThan(summary.attached, summary.barWindows)
    }
}

private final class B39FakeNSStatusBarWindow: NSWindow {
    var statusItem: NSStatusItem?
}
