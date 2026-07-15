import Foundation

/// Pure file-reading logic shared between the widget extension and the host app.
///
/// Kept free of WidgetKit/SwiftUI imports so it can be unit-tested without a
/// widget extension target and reused by any consumer of `WidgetSnapshot`.
enum WidgetSnapshotReader {

    /// Result of attempting to read a snapshot from disk.
    enum ReadResult: Equatable {
        /// No snapshot file exists at the requested URL.
        case noFile

        /// The file exists but could not be read or decoded as `WidgetSnapshot`.
        case corrupt

        /// Snapshot decoded successfully but is older than the caller's threshold.
        case stale(WidgetSnapshot, age: TimeInterval)

        /// Snapshot decoded successfully and is within the caller's threshold.
        case ok(WidgetSnapshot, age: TimeInterval)
    }

    /// Read and decode the snapshot at `url`, classifying it against `now` and
    /// `staleThreshold`.
    ///
    /// Uses `NSFileCoordinator` with `.withoutChanges` so the widget does not
    /// trigger a file-write conflict if the main app is currently rewriting the
    /// snapshot.
    static func read(at url: URL, now: Date, staleThreshold: TimeInterval) -> ReadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return .noFile
        }

        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var result: ReadResult = .corrupt

        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
            do {
                let data = try Data(contentsOf: coordinatedURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)
                let age = now.timeIntervalSince(snapshot.snapshotAt)
                result = age > staleThreshold
                    ? .stale(snapshot, age: age)
                    : .ok(snapshot, age: age)
            } catch {
                result = .corrupt
            }
        }

        if coordinationError != nil {
            return .corrupt
        }
        return result
    }
}
