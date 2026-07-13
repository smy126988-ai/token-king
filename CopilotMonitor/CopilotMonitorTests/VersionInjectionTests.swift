import XCTest

/// End-to-end tests for scripts/inject-version.sh — verifies the version
/// injection mechanism actually edits an Info.plist on disk with values
/// derived from a stubbed `git describe` output.
///
/// These are integration tests (they shell out via Process), so they exercise
/// the script the same way `make version` does in development and CI.
final class VersionInjectionTests: XCTestCase {

    private var repoRoot: String!
    private var tempDir: URL!
    private var tempPlist: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Walk up from this test file's compiled location until we find a
        // Makefile sibling. This is robust against any DerivedData layout.
        repoRoot = try Self.locateRepoRoot()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("version-inject-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempPlist = tempDir.appendingPathComponent("Info.plist")
        try Self.writeTemplatePlist(to: tempPlist)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    // MARK: - Happy path: stubbed git describe is parsed into Info.plist

    func testInjectsTaggedVersionWithCommitDistance() throws {
        try runScript(
            gitDescribe: "v2.13.0-5-ga1b2c3d",
            gitShortSHA: "a1b2c3d"
        )

        let values = try Self.readPlistValues(tempPlist)
        XCTAssertEqual(values.short, "2.13.0", "CFBundleShortVersionString should be the tag portion")
        XCTAssertEqual(values.build, "5", "CFBundleVersion should be the commit distance")
        XCTAssertEqual(values.hash, "a1b2c3d", "GitCommitHash should be the short SHA")
    }

    func testInjectsPureTagVersion() throws {
        try runScript(gitDescribe: "v3.0.0", gitShortSHA: "d4e5f60")

        let values = try Self.readPlistValues(tempPlist)
        XCTAssertEqual(values.short, "3.0.0")
        XCTAssertEqual(values.build, "0", "No commits past the tag → build 0")
        XCTAssertEqual(values.hash, "d4e5f60")
    }

    func testInjectsDirtyTagWithoutChangingVersion() throws {
        try runScript(gitDescribe: "v2.13.0-5-ga1b2c3d-dirty", gitShortSHA: "a1b2c3d")

        let values = try Self.readPlistValues(tempPlist)
        XCTAssertEqual(values.short, "2.13.0", "Dirty marker must not affect marketing version")
        XCTAssertEqual(values.build, "5")
        XCTAssertEqual(values.hash, "a1b2c3d")
    }

    func testInjectsPreTagShortSHA() throws {
        // No tag exists yet — git describe falls back to plain SHA.
        try runScript(gitDescribe: "f1e2d3c", gitShortSHA: "f1e2d3c")

        let values = try Self.readPlistValues(tempPlist)
        XCTAssertEqual(values.short, "0.0.0", "Pre-tag falls back to 0.0.0 marketing version")
        XCTAssertEqual(values.build, "0")
        XCTAssertEqual(values.hash, "f1e2d3c")
    }

    // MARK: - Check mode (CI gate that fails when Info.plist drifts)

    func testCheckPassesWhenValuesMatch() throws {
        try runScript(gitDescribe: "v2.13.0-5-ga1b2c3d", gitShortSHA: "a1b2c3d")
        let (exit, _) = try runScriptCapturingExit(
            args: ["--check", "--info-plist", tempPlist.path],
            env: [
                "GIT_DESCRIBE": "v2.13.0-5-ga1b2c3d",
                "GIT_SHORT_SHA": "a1b2c3d"
            ]
        )
        XCTAssertEqual(exit, 0, "Check mode must succeed when Info.plist already matches git")
    }

    func testCheckFailsWhenDrift() throws {
        try runScript(gitDescribe: "v2.13.0-5-ga1b2c3d", gitShortSHA: "a1b2c3d")
        // Now pretend git moved on
        let (exit, stderr) = try runScriptCapturingExit(
            args: ["--check", "--info-plist", tempPlist.path],
            env: [
                "GIT_DESCRIBE": "v2.13.1-10-gfedcba9",
                "GIT_SHORT_SHA": "fedcba9"
            ]
        )
        XCTAssertEqual(exit, 1, "Check mode must exit 1 when Info.plist lags git")
        XCTAssertTrue(stderr.contains("MISMATCH"), "Stderr should explain why: \(stderr)")
    }

    func testCheckFailsWhenInfoPlistMissing() throws {
        let missing = tempDir.appendingPathComponent("does-not-exist.plist")
        let (exit, _) = try runScriptCapturingExit(
            args: ["--check", "--info-plist", missing.path],
            env: [
                "GIT_DESCRIBE": "v2.13.0",
                "GIT_SHORT_SHA": "a1b2c3d"
            ]
        )
        XCTAssertEqual(exit, 1, "Missing Info.plist must produce a non-zero exit")
    }

    // MARK: - Helpers

    /// Run the script with stubbed git output, writing to tempPlist.
    private func runScript(gitDescribe: String, gitShortSHA: String) throws {
        let (exit, stderr) = try runScriptCapturingExit(
            args: ["--info-plist", tempPlist.path],
            env: [
                "GIT_DESCRIBE": gitDescribe,
                "GIT_SHORT_SHA": gitShortSHA
            ]
        )
        if exit != 0 {
            XCTFail("inject-version.sh failed (exit=\(exit)). stderr:\n\(stderr)")
        }
    }

    /// Invoke scripts/inject-version.sh via Process and return (exit, stderr).
    private func runScriptCapturingExit(args: [String], env: [String: String]) throws -> (Int32, String) {
        let script = URL(fileURLWithPath: repoRoot).appendingPathComponent("scripts/inject-version.sh")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [script.path] + args
        var fullEnv = ProcessInfo.processInfo.environment
        for (k, v) in env { fullEnv[k] = v }
        // Run from anywhere — the script locates its own REPO_ROOT.
        fullEnv.removeValue(forKey: "GIT_DIR")
        process.environment = fullEnv

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe() // discard
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private struct PlistValues { let short: String; let build: String; let hash: String }

    private static func readPlistValues(_ plist: URL) throws -> PlistValues {
        let data = try Data(contentsOf: plist)
        guard let obj = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            XCTFail("Could not parse plist")
            throw NSError(domain: "plist", code: 1)
        }
        return PlistValues(
            short: obj["CFBundleShortVersionString"] as? String ?? "",
            build: obj["CFBundleVersion"] as? String ?? "",
            hash: obj["GitCommitHash"] as? String ?? ""
        )
    }

    private static func writeTemplatePlist(to url: URL) throws {
        // Minimal but realistic Info.plist shell with placeholder version keys.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>CFBundleDisplayName</key><string>Token King</string>
          <key>CFBundleIdentifier</key><string>com.tokenking.app</string>
          <key>CFBundleShortVersionString</key><string>0.0.0</string>
          <key>CFBundleVersion</key><string>0</string>
          <key>GitCommitHash</key><string>unknown</string>
          <key>SUFeedURL</key>
          <string>https://smy126988-ai.github.io/token-king/appcast.xml</string>
          <key>SUPublicEDKey</key>
          <string>IZgr4CR9D3RKrWp5gTX2eq/w2FtRXdAGenhDRCfaF4Y=</string>
        </dict>
        </plist>
        """
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Locate the repo root (parent of the `scripts/` directory) regardless of
    /// which DerivedData path Xcode used to compile this test.
    private static func locateRepoRoot() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<10 {
            let candidate = dir.appendingPathComponent("scripts/inject-version.sh")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return dir.path
            }
            dir = dir.deletingLastPathComponent()
        }
        throw NSError(
            domain: "VersionInjectionTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate scripts/inject-version.sh in any ancestor directory."]
        )
    }
}
