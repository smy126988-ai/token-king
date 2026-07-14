import Foundation
import os.log

/// Shared filesystem paths used by the main app and the widget extension.
///
/// Both targets compile this file so the writer (app) and the reader (widget)
/// agree on the exact same location. The path resolves against the **real
/// login user's home** (via `getpwuid`) so non-sandboxed and sandboxed builds
/// land in the same directory.
///
/// The shared directory is created lazily by the writer on first write; the
/// widget must treat a missing file as "no snapshot yet" and recover silently.
enum SharedPaths {
    // MARK: - Configuration

    /// Directory name under `~/Library/Application Support/`.
    /// Picked to mirror the bundle id namespace so concurrent apps don't clash.
    static let sharedDirName = "com.tokenking.app.shared"

    /// Snapshot file name — JSON encoded `WidgetSnapshot` v1.
    static let snapshotFileName = "widget-snapshot.json"

    // MARK: - Path resolution

    /// Resolve the current user's real home directory.
    ///
    /// We deliberately use `getpwuid(getuid())` instead of `NSHomeDirectory()`.
    /// `NSHomeDirectory()` returns the container home when running inside a
    /// sandbox, which would put the file in a place the widget extension
    /// can't see. Falls back to `NSHomeDirectory()` only when the passwd
    /// lookup fails (effectively unreachable on a healthy Unix host).
    static func realHome() -> String {
        guard let passwd = getpwuid(getuid()) else {
            return NSHomeDirectory()
        }
        return String(cString: passwd.pointee.pw_dir)
    }

    /// `~/Library/Application Support/com.tokenking.app.shared/`
    static var sharedDirectory: URL {
        URL(fileURLWithPath: realHome())
            .appendingPathComponent("Library/Application Support/\(sharedDirName)", isDirectory: true)
    }

    /// `~/Library/Application Support/com.tokenking.app.shared/widget-snapshot.json`
    static var snapshotURL: URL {
        sharedDirectory.appendingPathComponent(snapshotFileName)
    }

    // MARK: - Directory bootstrap

    /// Ensure the shared directory exists. Idempotent.
    ///
    /// Called by the writer before the first snapshot write. Returns `true`
    /// when the directory is present (pre-existing or freshly created), and
    /// `false` only when creation fails — the caller should treat `false` as
    /// a hard failure and skip the write for that tick.
    @discardableResult
    static func ensureSharedDirectoryExists() -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: sharedDirectory.path) {
            return true
        }
        do {
            try fileManager.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)
            logger.debug("Shared directory ready: \(sharedDirectory.path, privacy: .public)")
            return true
        } catch {
            logger.error("ensureSharedDirectoryExists failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

// MARK: - Logging

extension SharedPaths {
    /// Structured logger for shared-path operations.
    ///
    /// Subsystem matches the main app convention (`com.tokenking`). The
    /// `widget.paths` category is filtered independently from
    /// `widget.writer` / `widget.provider` so path-layer diagnostics stay
    /// distinct from snapshot I/O concerns. Log messages are English only.
    static let logger = Logger(subsystem: "com.tokenking", category: "widget.paths")
}
