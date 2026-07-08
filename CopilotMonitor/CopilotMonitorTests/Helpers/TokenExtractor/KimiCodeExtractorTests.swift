import XCTest
@testable import OpenCode_Bar

final class KimiCodeExtractorTests: XCTestCase {

    private var tmpDir: String!

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "kimic_test_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: tmpDir + "/ws1/session1/agents/main", withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            atPath: tmpDir + "/ws2/session2/agents/main", withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        super.tearDown()
        try? FileManager.default.removeItem(atPath: tmpDir)
    }

    private func writeSample(root: String) {
        let wire1 = """
        {"time":1700000000000,"model":"kimi-code/kimi-for-coding","usage":{"inputOther":2306,"output":420,"inputCacheRead":5120,"inputCacheCreation":0},"usageScope":"turn"}
        {"time":1700000001000,"model":"kimi-code/kimi-for-coding","usage":{"inputOther":1100,"output":300,"inputCacheRead":2048,"inputCacheCreation":100},"usageScope":"turn"}
        """
        try? wire1.write(
            toFile: root + "/ws1/session1/agents/main/wire.jsonl",
            atomically: true, encoding: .utf8
        )

        let wire2 = """
        {"time":1700000100000,"model":"kimi-code/kimi-k2","usage":{"inputOther":500,"output":100,"inputCacheRead":256,"inputCacheCreation":0},"usageScope":"turn"}
        """
        try? wire2.write(
            toFile: root + "/ws2/session2/agents/main/wire.jsonl",
            atomically: true, encoding: .utf8
        )
    }

    func testExtractFromSampleData() async {
        writeSample(root: tmpDir)
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertNotNil(events)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.first?.source, .kimiCode)
    }

    func testEmptyDataSourceReturnsEmpty() async {
        let emptyDir = NSTemporaryDirectory() + "kimic_empty_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: emptyDir) }
        let extractor = KimiCodeExtractor(rootPath: emptyDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 0)
    }

    func testBrokenLineSkipped() async {
        let brokenDir = NSTemporaryDirectory() + "kimic_broken_\(UUID().uuidString)"
        try? FileManager.default.createDirectory(
            atPath: brokenDir + "/ws/sess/agents/main", withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: brokenDir) }

        let jsonl = """
        not json at all
        {"time":1700000000000,"model":"kimi-code/kimi-for-coding","usage":{"inputOther":1,"output":2,"inputCacheRead":3,"inputCacheCreation":0}}
        {also broken
        """
        try? jsonl.write(
            toFile: brokenDir + "/ws/sess/agents/main/wire.jsonl",
            atomically: true, encoding: .utf8
        )

        let extractor = KimiCodeExtractor(rootPath: brokenDir)
        let events = (try? await extractor.extractAll()) ?? []
        XCTAssertEqual(events.count, 1)
    }

    func testMultiSessionAggregation() async {
        writeSample(root: tmpDir)
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let sessionIds = Set(events.map { $0.sessionId })
        XCTAssertEqual(sessionIds.count, 2)
    }

    func testProviderNormalizationApplied() async {
        writeSample(root: tmpDir)
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        for event in events {
            XCTAssertEqual(event.provider, .kimi)
        }
    }

    func testCamelCaseUsageFieldExtraction() async {
        writeSample(root: tmpDir)
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        let events = (try? await extractor.extractAll()) ?? []
        let session1 = events.first { $0.sessionId == "session1" }
        XCTAssertNotNil(session1)
        XCTAssertEqual(session1?.tokens.input, 2306)
        XCTAssertEqual(session1?.tokens.output, 420)
        XCTAssertEqual(session1?.tokens.cacheRead, 5120)
        XCTAssertEqual(session1?.tokens.cacheWrite, 0)
    }

    func testLookupKimiModelPrefersEnv() {
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        XCTAssertEqual(
            extractor.lookupKimiModel(env: ["KIMI_MODEL_NAME": "kimi-env"], configPath: nil),
            "kimi-env"
        )
    }

    func testLookupKimiModelFallsBackToConfig() throws {
        let configDir = NSTemporaryDirectory() + "kimi_config_\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: configDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: configDir) }
        let configPath = configDir + "/config.toml"
        try "default_model = \"kimi-config-model\"".write(
            toFile: configPath, atomically: true, encoding: .utf8
        )

        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        XCTAssertEqual(
            extractor.lookupKimiModel(env: [:], configPath: configPath),
            "kimi-config-model"
        )
    }

    func testLookupKimiModelEnvOverridesConfig() throws {
        let configDir = NSTemporaryDirectory() + "kimi_config_\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: configDir, withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(atPath: configDir) }
        let configPath = configDir + "/config.toml"
        try "default_model = \"kimi-config-model\"".write(
            toFile: configPath, atomically: true, encoding: .utf8
        )

        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        XCTAssertEqual(
            extractor.lookupKimiModel(env: ["KIMI_MODEL_NAME": "kimi-env-model"], configPath: configPath),
            "kimi-env-model"
        )
    }

    func testLookupKimiModelUsesHardcodedFallback() {
        let extractor = KimiCodeExtractor(rootPath: tmpDir)
        let missingPath = "/nonexistent/kimi/config.toml"
        XCTAssertEqual(
            extractor.lookupKimiModel(env: [:], configPath: missingPath),
            "kimi-auto"
        )
    }
}