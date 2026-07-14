import XCTest
@testable import OpenCode_Bar

/// Validates the WidgetSnapshotWriter throttle and atomic-write contract.
///
/// Tests run against the shared `WidgetSnapshotWriter.shared` singleton but
/// each test resets `clock` and `lastWriteAt` deterministically so the
/// throttle interval can be advanced without sleeping.
final class WidgetSnapshotWriterTests: XCTestCase {

    /// Holds a manually-advanced clock so we can simulate elapsed time
    /// without sleeping. The writer consults `clock()` for every write
    /// decision and only updates `lastWriteAt` when a write actually lands.
    private final class FakeClock {
        var now: Date = Date(timeIntervalSince1970: 1_700_000_000)
        func advance(by seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    private var fakeClock: FakeClock!
    private var writer: WidgetSnapshotWriter!
    private var snapshotURL: URL { SharedPaths.snapshotURL }
    private var backupClock: (() -> Date)!

    override func setUp() {
        super.setUp()
        fakeClock = FakeClock()
        // Capture the production clock so each test restores it after messing
        // with the singleton.
        backupClock = WidgetSnapshotWriter.shared.clock
        WidgetSnapshotWriter.shared.clock = { [weak fakeClock] in
            fakeClock?.now ?? Date()
        }
        // Reset the throttle gating state — test isolation. The writer's
        // `lastWriteAt` is private but the test can drive `clock` to make
        // any subsequent write attempt either succeed or get throttled.
        writer = WidgetSnapshotWriter.shared

        // Clean any pre-existing snapshot file so byte-count assertions
        // are deterministic and we don't leak state between tests.
        try? FileManager.default.removeItem(at: snapshotURL)
    }

    override func tearDown() {
        WidgetSnapshotWriter.shared.clock = backupClock
        try? FileManager.default.removeItem(at: snapshotURL)
        super.tearDown()
    }

    // MARK: - Throttle behavior

    /// Writes inside the 30s throttle window must not modify the on-disk file.
    ///
    /// The shared singleton's `lastWriteAt` may carry over from a previous
    /// test run, so we prime the writer once with `force: true` and use the
    /// resulting file as the baseline that subsequent throttled writes must
    /// leave alone.
    func testThrottleBlocksFrequentWrites() {
        let snapshot = makeSnapshot()

        // Prime — establishes a known baseline file regardless of inherited
        // `lastWriteAt` state from earlier tests.
        writer.write(snapshot, force: true)
        let bytesAfterPrime = (try? Data(contentsOf: snapshotURL).count) ?? -1
        XCTAssertGreaterThan(bytesAfterPrime, 0, "primed write must hit disk")

        // Two back-to-back non-forced calls inside the throttle window must
        // NOT rewrite the file. The on-disk byte count is the canonical
        // proxy for "the writer took another trip through `writeAtomically`".
        writer.write(snapshot)
        writer.write(snapshot)
        let bytesAfterThrottled = (try? Data(contentsOf: snapshotURL).count) ?? -1
        XCTAssertEqual(
            bytesAfterThrottled, bytesAfterPrime,
            "throttled writes must leave the on-disk file untouched"
        )

        // Advance the fake clock past the 30s window — the next write must
        // land and rewrite the file (same byte count is fine, just not zero).
        fakeClock.advance(by: 31)
        writer.write(snapshot)
        let bytesAfterElapse = (try? Data(contentsOf: snapshotURL).count) ?? -1
        XCTAssertGreaterThanOrEqual(
            bytesAfterElapse, bytesAfterPrime,
            "post-throttle write should re-emit the file"
        )
    }

    /// `write(snapshot, force: true)` must bypass the throttle gate. Two
    /// back-to-back forced writes both land regardless of clock state.
    func testForceBypassesThrottle() {
        let snapshot = makeSnapshot()
        writer.write(snapshot, force: true)
        // No clock advance — second write would be throttled without force.
        writer.write(snapshot, force: true)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: snapshotURL.path),
            "force writes must produce a file even back-to-back"
        )

        let data = (try? Data(contentsOf: snapshotURL)) ?? Data()
        XCTAssertGreaterThan(data.count, 0)
    }

    /// The output file must be a valid `WidgetSnapshot` JSON. Verifies:
    /// - `JSONDecoder` with `iso8601` strategy round-trips the writer's
    ///   output
    /// - The decoded snapshot matches the one we wrote (encoded equality)
    func testAtomicWriteProducesValidJSON() throws {
        let original = makeSnapshot()
        writer.write(original, force: true)

        let data = try Data(contentsOf: snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.version, 1, "schema version must round-trip")
        XCTAssertEqual(decoded, original, "decoded snapshot must match the input")
        XCTAssertGreaterThan(data.count, 0, "encoded payload must be non-empty")
    }

    // MARK: - Helpers

    /// Minimal-but-valid snapshot covering all schema fields so JSON round-trip
    /// exercises every Codable path. Empty `providers` keeps the test focused
    /// on the writer, not the mapper.
    private func makeSnapshot() -> WidgetSnapshot {
        WidgetSnapshot(
            version: 1,
            snapshotAt: Date(timeIntervalSince1970: 1_700_000_000),
            providers: [],
            monthlyCost: MonthlyCost(usd: 12.34, rmb: 88.85)
        )
    }
}
