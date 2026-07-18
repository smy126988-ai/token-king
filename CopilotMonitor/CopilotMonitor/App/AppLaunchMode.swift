import Foundation

enum AppLaunchMode: Equatable {
    case production
    case unitTest
    case liveTest

    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppLaunchMode {
        switch environment["TOKEN_KING_TEST_MODE"] {
        case "1":
            return .unitTest
        case "live":
            return .liveTest
        default:
            return .production
        }
    }

    var shouldInitializeRuntimeServices: Bool {
        self == .production
    }

    var shouldActivateOfflineSandbox: Bool {
        self == .unitTest
    }
}

struct OfflineTestSandbox: Equatable {
    private static let rootPrefix = "TokenKingOffline-"

    let rootURL: URL
    let homeURL: URL
    let xdgConfigURL: URL
    let xdgDataURL: URL
    private let expectedRootName: String
    private let temporaryDirectoryURL: URL

    static func activate(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        uuid: UUID = UUID(),
        setEnvironment: (String, String) -> Void = { name, value in
            setenv(name, value, 1)
        }
    ) throws -> OfflineTestSandbox {
        try cleanupStaleDirectories(
            fileManager: fileManager,
            temporaryDirectory: temporaryDirectory
        )

        let rootName = "\(rootPrefix)\(processIdentifier)-\(uuid.uuidString)"
        let rootURL = temporaryDirectory.appendingPathComponent(
            rootName,
            isDirectory: true
        )
        let sandbox = OfflineTestSandbox(
            rootURL: rootURL,
            homeURL: rootURL.appendingPathComponent("home", isDirectory: true),
            xdgConfigURL: rootURL.appendingPathComponent("xdg-config", isDirectory: true),
            xdgDataURL: rootURL.appendingPathComponent("xdg-data", isDirectory: true),
            expectedRootName: rootName,
            temporaryDirectoryURL: temporaryDirectory
        )

        for directory in [
            sandbox.rootURL,
            sandbox.homeURL,
            sandbox.xdgConfigURL,
            sandbox.xdgDataURL
        ] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        }

        setEnvironment("HOME", sandbox.homeURL.path)
        setEnvironment("CFFIXED_USER_HOME", sandbox.homeURL.path)
        setEnvironment("XDG_CONFIG_HOME", sandbox.xdgConfigURL.path)
        setEnvironment("XDG_DATA_HOME", sandbox.xdgDataURL.path)
        return sandbox
    }

    static func cleanupStaleDirectories(
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        now: Date = Date(),
        maximumAge: TimeInterval = 24 * 60 * 60
    ) throws {
        let names = try fileManager.contentsOfDirectory(atPath: temporaryDirectory.path)
        for name in names where isOwnedRootName(name) {
            let candidate = temporaryDirectory.appendingPathComponent(name, isDirectory: true)
            let attributes = try fileManager.attributesOfItem(atPath: candidate.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  let modificationDate = attributes[.modificationDate] as? Date,
                  now.timeIntervalSince(modificationDate) > maximumAge
            else {
                continue
            }
            try fileManager.removeItem(at: candidate)
        }
    }

    func cleanup(fileManager: FileManager = .default) throws {
        let rootParent = rootURL.deletingLastPathComponent().standardizedFileURL
        let expectedParent = temporaryDirectoryURL.standardizedFileURL
        guard expectedRootName.hasPrefix(Self.rootPrefix),
              rootURL.lastPathComponent == expectedRootName,
              rootParent == expectedParent
        else {
            throw CleanupError.unsafeRoot(rootURL)
        }

        if fileManager.fileExists(atPath: rootURL.path) {
            try fileManager.removeItem(at: rootURL)
        }
    }

    enum CleanupError: Error {
        case unsafeRoot(URL)
    }

    private static func isOwnedRootName(_ name: String) -> Bool {
        guard name.hasPrefix(rootPrefix) else { return false }
        let suffix = name.dropFirst(rootPrefix.count)
        guard let separator = suffix.firstIndex(of: "-") else { return false }
        let processIdentifier = suffix[..<separator]
        let uuidStart = suffix.index(after: separator)
        let uuid = String(suffix[uuidStart...])
        return !processIdentifier.isEmpty
            && processIdentifier.allSatisfy { $0.isNumber }
            && UUID(uuidString: uuid) != nil
    }
}
