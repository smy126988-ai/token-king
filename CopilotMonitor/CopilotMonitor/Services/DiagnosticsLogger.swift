import Foundation
import os.log

/// Centralized diagnostic logger for Token King.
///
/// Behavior:
/// - **Default disabled.** When disabled, `log(...)` is a no-op (no file I/O,
///   no leak). Old `/tmp/provider_debug.log` is NOT touched when disabled.
/// - When enabled, writes sanitized lines to `<baseDirectory>/tokenking_diag.log`.
/// - File rotation: when the active file exceeds `maxFileSizeBytes`,
///   it is rotated to `tokenking_diag.log.1`, `.2`, ... up to `maxRotatedFiles`.
/// - Thread-safe: all I/O happens on a private serial queue.
///
/// Persistence: the enabled flag is stored in `UserDefaults` under
/// `tokenKing.diagnostics.enabled`.
final class DiagnosticsLogger: @unchecked Sendable {

    // MARK: - Configuration

    static let enabledDefaultsKey = "tokenKing.diagnostics.enabled"
    static let defaultLogFileName = "tokenking_diag.log"
    static let maxFileSizeBytes: Int = 5 * 1024 * 1024  // 5 MB
    static let maxRotatedFiles: Int = 3
    static let maxLineLength: Int = 4_096  // truncate lines longer than this

    // MARK: - Singleton

    /// Process-wide singleton. Reads `UserDefaults.standard` unless reset
    /// for tests via `resetForTesting()`.
    static let shared = DiagnosticsLogger()

    // MARK: - State

    private let defaults: UserDefaults
    private let baseDirectory: URL
    private let activeFileURL: URL
    private let queue: DispatchQueue
    private var _enabled: Bool
    private var fileHandle: FileHandle?

    // MARK: - Init

    /// Production initializer.
    private convenience init() {
        // Default base directory is `/tmp`, distinct from the old
        // `/tmp/provider_debug.log` to avoid clobbering user logs.
        self.init(
            defaults: UserDefaults.standard,
            baseDirectory: URL(fileURLWithPath: "/tmp")
        )
    }

    /// Designated initializer. Used by `shared` and by tests.
    init(defaults: UserDefaults, baseDirectory: URL) {
        self.defaults = defaults
        self.baseDirectory = baseDirectory
        self.activeFileURL = baseDirectory.appendingPathComponent(Self.defaultLogFileName)
        self.queue = DispatchQueue(label: "com.tokenking.DiagnosticsLogger", qos: .utility)
        // Default OFF. Only honor persisted enabled flag if explicitly true.
        let stored = defaults.object(forKey: Self.enabledDefaultsKey) as? Bool
        self._enabled = stored ?? false
    }

    deinit {
        try? fileHandle?.close()
    }

    // MARK: - Public API

    var enabled: Bool {
        queue.sync { _enabled }
    }

    func setEnabled(_ newValue: Bool) {
        queue.sync {
            _enabled = newValue
            defaults.set(newValue, forKey: Self.enabledDefaultsKey)
            if !newValue {
                try? fileHandle?.close()
                fileHandle = nil
            }
        }
    }

    /// Log a sanitized message under the given category.
    /// No-op when `enabled == false`.
    func log(_ message: String, category: String) {
        queue.async { [weak self] in
            self?.appendLine(message: message, category: category)
        }
    }

    /// Synchronous flush (test hook). Drains the queue.
    func flush() {
        queue.sync { }
    }

    /// Tear down state for testing. Closes the active file handle so subsequent
    /// tests start clean.
    func resetForTesting() {
        queue.sync {
            try? fileHandle?.close()
            fileHandle = nil
        }
    }

    /// Test hook: clear all rotated + active files.
#if false
    func clearLogsForTesting() throws {
        try queue.sync {
            try? fileHandle?.close()
            fileHandle = nil
            try? FileManager.default.removeItem(at: activeFileURL)
            for i in 1...Self.maxRotatedFiles {
                let rotated = baseDirectory.appendingPathComponent("\(Self.defaultLogFileName).\(i)")
                try? FileManager.default.removeItem(at: rotated)
            }
        }
    }
#endif

    /// Test hook: current active file size in bytes.
#if false
    func activeFileSizeForTesting() -> Int {
        queue.sync {
            (try? FileManager.default.attributesOfItem(atPath: activeFileURL.path)[.size] as? Int) ?? 0
        }
    }
#endif

    /// Test hook: list of existing rotated files (e.g. ["tokenking_diag.log.1"]).
#if false
    func existingRotatedFilesForTesting() -> [String] {
        queue.sync {
            (1...Self.maxRotatedFiles).compactMap { i -> String? in
                let path = baseDirectory.appendingPathComponent("\(Self.defaultLogFileName).\(i)").path
                return FileManager.default.fileExists(atPath: path)
                    ? "\(Self.defaultLogFileName).\(i)"
                    : nil
            }
        }
    }
#endif

    // MARK: - Private

    private func appendLine(message: String, category: String) {
        guard _enabled else { return }

        let sanitized = DiagnosticsSanitizer.sanitize(message)
        let truncated = sanitized.count > Self.maxLineLength
            ? String(sanitized.prefix(Self.maxLineLength)) + "...[truncated]"
            : sanitized
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(truncated)\n"

        guard let data = line.data(using: .utf8) else { return }

        do {
            try ensureDirectoryExists()
            try rotateIfNeeded(forAppendSize: data.count)
            try openHandleIfNeeded()
            guard let handle = fileHandle else { return }
            try handle.write(contentsOf: data)
        } catch {
            // Swallow: diagnostics must never crash the app.
            os_log("DiagnosticsLogger write failed: %{public}@", String(describing: error))
        }
    }

    private func ensureDirectoryExists() throws {
        if !FileManager.default.fileExists(atPath: baseDirectory.path) {
            try FileManager.default.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
        }
    }

    private func openHandleIfNeeded() throws {
        if fileHandle != nil { return }
        if !FileManager.default.fileExists(atPath: activeFileURL.path) {
            FileManager.default.createFile(atPath: activeFileURL.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: activeFileURL)
        try handle.seekToEnd()
        self.fileHandle = handle
    }

    private func rotateIfNeeded(forAppendSize size: Int) throws {
        let attrs = try? FileManager.default.attributesOfItem(atPath: activeFileURL.path)
        let current = (attrs?[.size] as? Int) ?? 0
        guard current + size > Self.maxFileSizeBytes else { return }

        try? fileHandle?.close()
        fileHandle = nil

        // Shift existing rotated files: .N → deleted, .N-1 → .N, ..., .1 → .2
        for i in stride(from: Self.maxRotatedFiles, to: 1, by: -1) {
            let oldPath = baseDirectory.appendingPathComponent("\(Self.defaultLogFileName).\(i - 1)")
            let newPath = baseDirectory.appendingPathComponent("\(Self.defaultLogFileName).\(i)")
            if FileManager.default.fileExists(atPath: oldPath.path) {
                if FileManager.default.fileExists(atPath: newPath.path) {
                    try? FileManager.default.removeItem(at: newPath)
                }
                try FileManager.default.moveItem(at: oldPath, to: newPath)
            }
        }

        // Active → .1
        if FileManager.default.fileExists(atPath: activeFileURL.path) {
            let rotatedOne = baseDirectory.appendingPathComponent("\(Self.defaultLogFileName).1")
            if FileManager.default.fileExists(atPath: rotatedOne.path) {
                try? FileManager.default.removeItem(at: rotatedOne)
            }
            try FileManager.default.moveItem(at: activeFileURL, to: rotatedOne)
        }
    }
}
