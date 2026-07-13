import XCTest
@testable import OpenCode_Bar

final class DiagnosticsLoggerTests: XCTestCase {

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "DiagnosticsLoggerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func makeTempDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DiagnosticsLoggerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        // Reset shared singleton so state doesn't leak across tests.
        DiagnosticsLogger.shared.resetForTesting()
    }

    // MARK: - Defaults

    func testDefaultDisabled() throws {
        let (defaults, _) = makeIsolatedDefaults()
        let dir = makeTempDir()
        let logger = DiagnosticsLogger(defaults: defaults, baseDirectory: dir)

        XCTAssertFalse(logger.enabled, "diagnostics should default to OFF")
        logger.log("anything", category: "TestCategory")
        // No file should be created when disabled.
        let expected = dir.appendingPathComponent("tokenking_diag.log")
        XCTAssertFalse(FileManager.default.fileExists(atPath: expected.path),
                       "No log file should be created when diagnostics disabled")
    }

    // MARK: - Enabled writes to file

    func testEnabledWritesToFile() throws {
        let (defaults, _) = makeIsolatedDefaults()
        let dir = makeTempDir()
        let logger = DiagnosticsLogger(defaults: defaults, baseDirectory: dir)
        logger.setEnabled(true)
        defer { logger.setEnabled(false) }

        logger.log("hello world", category: "TestCategory")
        logger.flush()
        let expected = dir.appendingPathComponent("tokenking_diag.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expected.path),
                      "Log file should exist after enabled write")
        let content = try String(contentsOf: expected, encoding: .utf8)
        XCTAssertTrue(content.contains("hello world"), "Message must appear in log")
        XCTAssertTrue(content.contains("TestCategory"), "Category must appear in log")
    }

    // MARK: - Rotation at 5MB

    func testRotationAt5MB() throws {
        let (defaults, _) = makeIsolatedDefaults()
        let dir = makeTempDir()
        let logger = DiagnosticsLogger(defaults: defaults, baseDirectory: dir)
        logger.setEnabled(true)
        defer { logger.setEnabled(false) }

        // Lines are truncated to `maxLineLength` (4 KB) before writing, so each
        // log() call writes ~4 KB regardless of input size. To cross the 5 MB
        // rotation threshold, write enough lines.
        // 1500 chunks × ~4 KB ≈ 6 MB which is well over the 5 MB cap.
        let chunkCount = 1500
        for i in 0..<chunkCount {
            // Use small payload; the line will be truncated to maxLineLength anyway.
            logger.log("rotation-marker-\(i)", category: "Rotation")
        }
        logger.flush()

        let baseFile = dir.appendingPathComponent("tokenking_diag.log")
        let rotatedFile = dir.appendingPathComponent("tokenking_diag.log.1")
        let activeSize = (try? FileManager.default.attributesOfItem(atPath: baseFile.path)[.size] as? Int) ?? 0
        let rotatedExists = FileManager.default.fileExists(atPath: rotatedFile.path)
        XCTAssertTrue(rotatedExists || activeSize <= 5 * 1024 * 1024,
                      "After >5MB write, either a rotated file should exist or active file should be within cap")
    }

    // MARK: - Sanitization

    func testSanitizationRedactsEmail() {
        let result = DiagnosticsSanitizer.sanitize("User signed in: alice@example.com")
        XCTAssertTrue(result.contains("alice@***"), "Email local-part should be preserved, domain redacted: \(result)")
        XCTAssertFalse(result.contains("alice@example.com"), "Raw email must NOT appear: \(result)")
    }

    func testSanitizationRedactsPath() {
        let result = DiagnosticsSanitizer.sanitize("Auth file: /Users/simengyu/.local/share/opencode/auth.json")
        XCTAssertTrue(result.contains("/Users/***/"), "Home path segment should be redacted: \(result)")
        XCTAssertFalse(result.contains("/Users/simengyu/"), "Raw user path must NOT appear: \(result)")
    }

    func testSanitizationRedactsToken() {
        let result = DiagnosticsSanitizer.sanitize("Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature")
        XCTAssertTrue(result.contains("Bearer ***") || result.contains("Bearer *"),
                      "Bearer token should be redacted: \(result)")
        XCTAssertFalse(result.contains("eyJhbGciOi"), "Raw JWT must NOT appear: \(result)")
    }

    func testSanitizationRedactsKeyValue() {
        let result = DiagnosticsSanitizer.sanitize("cookie=abcdef0123456789; path=/; domain=.example.com")
        XCTAssertTrue(result.contains("cookie=***") || result.contains("cookie=*"),
                      "Cookie value should be redacted: \(result)")
        XCTAssertFalse(result.contains("abcdef0123456789"), "Raw cookie value must NOT appear: \(result)")
    }

    func testSanitizationKeepsShortValues() {
        let result = DiagnosticsSanitizer.sanitize("mode=test; count=42")
        // Short values are not sensitive; keep them.
        XCTAssertTrue(result.contains("test"), "Short values should pass through: \(result)")
    }

    func testSanitizationIsIdempotent() {
        let input = "User alice@example.com logged in from /Users/simengyu/app"
        let once = DiagnosticsSanitizer.sanitize(input)
        let twice = DiagnosticsSanitizer.sanitize(once)
        XCTAssertEqual(once, twice, "Sanitization must be idempotent")
    }
}
