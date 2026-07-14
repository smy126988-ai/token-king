import Foundation
import os.log

/// Writes `WidgetSnapshot` JSON to the shared directory for the widget extension.
/// Atomic writes via NSFileCoordinator; 30s throttle to avoid hammering disk.
final class WidgetSnapshotWriter {
    static let shared = WidgetSnapshotWriter()

    /// Subsystem matches the main app convention (`com.tokenking`); category
    /// separates widget writes from other components in Console.app.
    private let logger = Logger(subsystem: "com.tokenking", category: "widget.writer")

    /// Minimum interval between writes. The 5s main loop calls write() every
    /// cycle; without throttling we'd rewrite the same data 12 times per minute.
    private let throttleInterval: TimeInterval = 30

    private var lastWriteAt: Date?
    private let queue = DispatchQueue(label: "com.tokenking.widget.writer", qos: .utility)

    /// Override point for tests: inject a deterministic clock so the throttle
    /// interval can be advanced without sleeping. Production uses `Date.init`.
    var clock: () -> Date = { Date() }

    private init() {}

    /// Write the snapshot to disk, subject to throttle.
    /// - Parameter force: Bypass throttle (used at app launch to prime the cache).
    func write(_ snapshot: WidgetSnapshot, force: Bool = false) {
        // Throttle check (off the main queue to avoid blocking the 5s loop).
        let now = clock()
        let shouldWrite: Bool = queue.sync {
            if force { return true }
            guard let last = lastWriteAt else { return true }
            return now.timeIntervalSince(last) >= throttleInterval
        }
        guard shouldWrite else {
            logger.debug("write() skipped (throttled, last=\(self.lastWriteAt ?? .distantPast, privacy: .public))")
            return
        }

        do {
            try writeAtomically(snapshot)
            queue.sync { lastWriteAt = now }
            logger.notice("wrote snapshot v\(snapshot.version) providers=\(snapshot.providers.count) bytes=\(Self.byteCount(of: snapshot))")
        } catch {
            logger.error("write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Force-write bypassing throttle. Used at app launch.
    func writeNow(_ snapshot: WidgetSnapshot) {
        write(snapshot, force: true)
    }

    /// Atomic write via NSFileCoordinator (`.forReplacing` ensures readers see
    /// either the old or the new file, never a half-written one).
    private func writeAtomically(_ snapshot: WidgetSnapshot) throws {
        guard SharedPaths.ensureSharedDirectoryExists() else {
            throw WriterError.sharedDirectoryUnavailable
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)

        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var thrown: Error?

        coordinator.coordinate(
            writingItemAt: SharedPaths.snapshotURL,
            options: .forReplacing,
            error: &coordError
        ) { url in
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                thrown = error
            }
        }

        if let e = coordError { throw e }
        if let e = thrown { throw e }
    }

    private static func byteCount(of snapshot: WidgetSnapshot) -> Int {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(snapshot).count) ?? 0
    }

    enum WriterError: Error {
        case sharedDirectoryUnavailable
    }
}
