import XCTest
@testable import OpenCode_Bar

final class AppLaunchModeTests: XCTestCase {
    func testStaleCleanupOnlyRemovesOwnedRootsOlderThanOneDay() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("TokenKingOfflineStaleTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let staleRoot = temporaryDirectory.appendingPathComponent(
            "TokenKingOffline-123-00000000-0000-0000-0000-000000000001",
            isDirectory: true
        )
        let freshRoot = temporaryDirectory.appendingPathComponent(
            "TokenKingOffline-456-00000000-0000-0000-0000-000000000002",
            isDirectory: true
        )
        let unrelatedRoot = temporaryDirectory.appendingPathComponent(
            "TokenKingOffline-not-an-owned-root",
            isDirectory: true
        )
        for directory in [staleRoot, freshRoot, unrelatedRoot] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-25 * 60 * 60)],
            ofItemAtPath: staleRoot.path
        )
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-23 * 60 * 60)],
            ofItemAtPath: freshRoot.path
        )
        try fileManager.setAttributes(
            [.modificationDate: now.addingTimeInterval(-25 * 60 * 60)],
            ofItemAtPath: unrelatedRoot.path
        )

        try OfflineTestSandbox.cleanupStaleDirectories(
            fileManager: fileManager,
            temporaryDirectory: temporaryDirectory,
            now: now
        )

        XCTAssertFalse(fileManager.fileExists(atPath: staleRoot.path))
        XCTAssertTrue(fileManager.fileExists(atPath: freshRoot.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedRoot.path))
    }

    func testOfflineSandboxCreatesUniquePrivateRootsAndEnvironmentValues() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("TokenKingOfflineSandboxTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let firstUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        var environment: [String: String] = [:]

        let first = try OfflineTestSandbox.activate(
            fileManager: fileManager,
            temporaryDirectory: temporaryDirectory,
            processIdentifier: 4242,
            uuid: firstUUID,
            setEnvironment: { environment[$0] = $1 }
        )
        let firstEnvironment = environment

        let second = try OfflineTestSandbox.activate(
            fileManager: fileManager,
            temporaryDirectory: temporaryDirectory,
            processIdentifier: 4242,
            uuid: secondUUID,
            setEnvironment: { environment[$0] = $1 }
        )

        XCTAssertNotEqual(first.rootURL, second.rootURL)
        XCTAssertEqual(
            first.rootURL.lastPathComponent,
            "TokenKingOffline-4242-\(firstUUID.uuidString)"
        )
        XCTAssertEqual(
            second.rootURL.lastPathComponent,
            "TokenKingOffline-4242-\(secondUUID.uuidString)"
        )

        assertPrivateDirectory(first.rootURL, fileManager: fileManager)
        assertPrivateDirectory(first.homeURL, fileManager: fileManager)
        assertPrivateDirectory(first.xdgConfigURL, fileManager: fileManager)
        assertPrivateDirectory(first.xdgDataURL, fileManager: fileManager)
        assertPrivateDirectory(second.rootURL, fileManager: fileManager)
        assertPrivateDirectory(second.homeURL, fileManager: fileManager)
        assertPrivateDirectory(second.xdgConfigURL, fileManager: fileManager)
        assertPrivateDirectory(second.xdgDataURL, fileManager: fileManager)

        XCTAssertEqual(firstEnvironment["HOME"], first.homeURL.path)
        XCTAssertEqual(firstEnvironment["CFFIXED_USER_HOME"], first.homeURL.path)
        XCTAssertEqual(firstEnvironment["XDG_CONFIG_HOME"], first.xdgConfigURL.path)
        XCTAssertEqual(firstEnvironment["XDG_DATA_HOME"], first.xdgDataURL.path)
        XCTAssertEqual(environment["HOME"], second.homeURL.path)
        XCTAssertEqual(environment["CFFIXED_USER_HOME"], second.homeURL.path)
        XCTAssertEqual(environment["XDG_CONFIG_HOME"], second.xdgConfigURL.path)
        XCTAssertEqual(environment["XDG_DATA_HOME"], second.xdgDataURL.path)
    }

    func testExactOneEnablesUnitTestMode() {
        XCTAssertEqual(
            AppLaunchMode.resolve(environment: ["TOKEN_KING_TEST_MODE": "1"]),
            .unitTest
        )
    }

    func testExactLiveEnablesLiveTestMode() {
        XCTAssertEqual(
            AppLaunchMode.resolve(environment: ["TOKEN_KING_TEST_MODE": "live"]),
            .liveTest
        )
    }

    func testOtherValuesKeepProductionMode() {
        for value in [nil, "", "0", "true", "TRUE", "yes", "2", "LIVE"] {
            let environment = value.map { ["TOKEN_KING_TEST_MODE": $0] } ?? [:]
            XCTAssertEqual(AppLaunchMode.resolve(environment: environment), .production)
        }
    }

    func testUnitTestModeDisablesRuntimeServiceInitialization() {
        XCTAssertFalse(AppLaunchMode.unitTest.shouldInitializeRuntimeServices)
        XCTAssertFalse(AppLaunchMode.liveTest.shouldInitializeRuntimeServices)
        XCTAssertTrue(AppLaunchMode.production.shouldInitializeRuntimeServices)
    }

    func testOnlyUnitTestModeRequiresOfflineSandbox() {
        XCTAssertTrue(AppLaunchMode.unitTest.shouldActivateOfflineSandbox)
        XCTAssertFalse(AppLaunchMode.liveTest.shouldActivateOfflineSandbox)
        XCTAssertFalse(AppLaunchMode.production.shouldActivateOfflineSandbox)
    }

    @MainActor
    func testLiveTestLaunchDisablesRuntimeWithoutActivatingSandbox() {
        var activatorCallCount = 0
        let delegate = AppDelegate(
            launchMode: .liveTest,
            offlineTestSandboxActivator: {
                activatorCallCount += 1
                throw TestError.unexpectedSandboxActivation
            }
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: Notification.Name("test.didFinishLaunching"))
        )

        XCTAssertEqual(activatorCallCount, 0)
        XCTAssertEqual(delegate.runtimeInitializationCount, 0)
        XCTAssertNil(delegate.offlineTestSandbox)
        XCTAssertNil(delegate.statusBarController)
        XCTAssertNil(delegate.updaterController)
    }

    @MainActor
    func testUnitTestLaunchCleansSandboxWithoutConstructingRuntimeServices() throws {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("TokenKingOfflineLifecycleTests-\(UUID().uuidString)", isDirectory: true)
        let unrelatedURL = temporaryDirectory.appendingPathComponent("unrelated", isDirectory: true)
        try fileManager.createDirectory(at: unrelatedURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: temporaryDirectory) }

        let delegate = AppDelegate(
            launchMode: .unitTest,
            offlineTestSandboxActivator: {
                try OfflineTestSandbox.activate(
                    fileManager: fileManager,
                    temporaryDirectory: temporaryDirectory,
                    processIdentifier: 5150,
                    uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                    setEnvironment: { _, _ in }
                )
            }
        )

        delegate.applicationDidFinishLaunching(
            Notification(name: Notification.Name("test.didFinishLaunching"))
        )

        let sandboxRoot = try XCTUnwrap(delegate.offlineTestSandbox?.rootURL)
        XCTAssertTrue(fileManager.fileExists(atPath: sandboxRoot.path))
        XCTAssertEqual(delegate.runtimeInitializationCount, 0)
        XCTAssertNil(delegate.statusBarController)
        XCTAssertNil(delegate.updaterController)

        delegate.applicationWillTerminate(
            Notification(name: Notification.Name("test.willTerminate"))
        )

        XCTAssertFalse(fileManager.fileExists(atPath: sandboxRoot.path))
        XCTAssertTrue(fileManager.fileExists(atPath: unrelatedURL.path))
        XCTAssertNil(delegate.offlineTestSandbox)
    }

    private func assertPrivateDirectory(
        _ url: URL,
        fileManager: FileManager,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var isDirectory: ObjCBool = false
        XCTAssertTrue(
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
            file: file,
            line: line
        )
        XCTAssertTrue(isDirectory.boolValue, file: file, line: line)

        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions.map { $0 & 0o777 }, 0o700, file: file, line: line)
    }

    private enum TestError: Error {
        case unexpectedSandboxActivation
    }
}
