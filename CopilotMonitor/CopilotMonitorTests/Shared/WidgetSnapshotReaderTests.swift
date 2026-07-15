import XCTest
@testable import OpenCode_Bar

final class WidgetSnapshotReaderTests: XCTestCase {

    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testMissingFileReturnsNoFile() {
        let result = WidgetSnapshotReader.read(
            at: tempURL,
            now: Date(),
            staleThreshold: 90 * 60
        )

        XCTAssertEqual(result, .noFile)
    }

    func testValidJSONReturnsOk() throws {
        let now = Date()
        let snapshot = WidgetSnapshot(
            version: 1,
            snapshotAt: now,
            providers: [],
            monthlyCost: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: tempURL)

        let result = WidgetSnapshotReader.read(
            at: tempURL,
            now: now,
            staleThreshold: 90 * 60
        )

        guard case .ok(let readSnapshot, let age) = result else {
            XCTFail("expected .ok, got \(result)")
            return
        }

        XCTAssertEqual(readSnapshot.version, snapshot.version)
        XCTAssertEqual(readSnapshot.providers, snapshot.providers)
        XCTAssertEqual(readSnapshot.monthlyCost, snapshot.monthlyCost)
        XCTAssertEqual(readSnapshot.snapshotAt.timeIntervalSince(snapshot.snapshotAt), 0, accuracy: 1.0)
        XCTAssertEqual(age, 0, accuracy: 1.0)
    }

    func testMalformedJSONReturnsCorrupt() throws {
        try "not json".write(to: tempURL, atomically: true, encoding: .utf8)

        let result = WidgetSnapshotReader.read(
            at: tempURL,
            now: Date(),
            staleThreshold: 90 * 60
        )

        XCTAssertEqual(result, .corrupt)
    }

    func testTruncatedJSONReturnsCorrupt() throws {
        let partial = "{\"version\": 1, \"snapshotAt\":"
        try partial.write(to: tempURL, atomically: true, encoding: .utf8)

        let result = WidgetSnapshotReader.read(
            at: tempURL,
            now: Date(),
            staleThreshold: 90 * 60
        )

        XCTAssertEqual(result, .corrupt)
    }

    func testStaleSnapshotReturnsStaleWithAge() throws {
        let threshold: TimeInterval = 90 * 60
        let snapshotAt = Date().addingTimeInterval(-threshold - 1)
        let snapshot = WidgetSnapshot(
            version: 1,
            snapshotAt: snapshotAt,
            providers: [],
            monthlyCost: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: tempURL)

        let now = Date()
        let result = WidgetSnapshotReader.read(
            at: tempURL,
            now: now,
            staleThreshold: threshold
        )

        guard case .stale(let readSnapshot, let age) = result else {
            XCTFail("expected .stale, got \(result)")
            return
        }

        XCTAssertEqual(readSnapshot.version, snapshot.version)
        XCTAssertEqual(readSnapshot.providers, snapshot.providers)
        XCTAssertEqual(readSnapshot.monthlyCost, snapshot.monthlyCost)
        XCTAssertEqual(readSnapshot.snapshotAt.timeIntervalSince(snapshot.snapshotAt), 0, accuracy: 1.0)
        XCTAssertEqual(age, now.timeIntervalSince(snapshotAt), accuracy: 1.0)
    }
}
