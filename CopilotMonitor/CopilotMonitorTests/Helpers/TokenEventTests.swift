import XCTest
@testable import OpenCode_Bar

final class TokenEventTests: XCTestCase {

    // MARK: - TokenBreakdown

    func testTokenBreakdownTotal() {
        let breakdown = TokenBreakdown(
            input: 100, output: 50, cacheRead: 30, cacheWrite: 0, reasoning: 5
        )
        XCTAssertEqual(breakdown.total, 185)
    }

    func testTokenBreakdownZero() {
        XCTAssertEqual(TokenBreakdown.zero.total, 0)
    }

    func testTokenBreakdownCodable() throws {
        let original = TokenBreakdown(
            input: 10, output: 20, cacheRead: 30, cacheWrite: 40, reasoning: 50
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TokenBreakdown.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testTokenBreakdownEquatable() {
        let a = TokenBreakdown(
            input: 100, output: 50, cacheRead: 30, cacheWrite: 0, reasoning: 5
        )
        let b = TokenBreakdown(
            input: 100, output: 50, cacheRead: 30, cacheWrite: 0, reasoning: 5
        )
        let c = TokenBreakdown(
            input: 1, output: 2, cacheRead: 3, cacheWrite: 4, reasoning: 5
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - Provider

    func testProviderCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for provider in Provider.allCases {
            let data = try encoder.encode(provider)
            let decoded = try decoder.decode(Provider.self, from: data)
            XCTAssertEqual(decoded, provider)
        }
    }

    func testProviderDisplayName() {
        XCTAssertEqual(Provider.kimi.displayName, "Kimi Global")
        XCTAssertEqual(Provider.kimiCN.displayName, "Kimi CN")
        XCTAssertEqual(Provider.claude.displayName, "Claude")
        XCTAssertEqual(Provider.codex.displayName, "Codex")
        XCTAssertEqual(Provider.zai.displayName, "Z.AI")
        XCTAssertEqual(Provider.nanoGpt.displayName, "NanoGpt")
    }

    // MARK: - TokenSource

    func testTokenSourceCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for source in TokenSource.allCases {
            let data = try encoder.encode(source)
            let decoded = try decoder.decode(TokenSource.self, from: data)
            XCTAssertEqual(decoded, source)
        }
    }

    // MARK: - TokenEvent

    func testTokenEventCodable() throws {
        let original = TokenEvent(
            provider: .claude,
            model: "claude-sonnet-4-5",
            source: .claudeCode,
            sessionId: "sess-1",
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            tokens: TokenBreakdown(input: 10, output: 20, cacheRead: 5, cacheWrite: 1, reasoning: 2),
            sourceId: "src-1"
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TokenEvent.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testTokenEventHashable() {
        let a = TokenEvent(
            provider: .kimi,
            model: "kimi-k2",
            source: .kimiCli,
            sessionId: "s1",
            timestamp: Date(timeIntervalSince1970: 1),
            tokens: TokenBreakdown(input: 1, output: 2, cacheRead: 3, cacheWrite: 4, reasoning: 5),
            sourceId: "src-1"
        )
        let b = TokenEvent(
            provider: .kimi,
            model: "kimi-k2",
            source: .kimiCli,
            sessionId: "s1",
            timestamp: Date(timeIntervalSince1970: 1),
            tokens: TokenBreakdown(input: 1, output: 2, cacheRead: 3, cacheWrite: 4, reasoning: 5),
            sourceId: "src-1"
        )
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    func testTokenEventSet() {
        let a = TokenEvent(
            provider: .codex,
            model: "gpt-4o",
            source: .codexCli,
            sessionId: "s",
            timestamp: Date(timeIntervalSince1970: 0),
            tokens: TokenBreakdown.zero,
            sourceId: "src"
        )
        let b = TokenEvent(
            provider: .codex,
            model: "gpt-4o",
            source: .codexCli,
            sessionId: "s",
            timestamp: Date(timeIntervalSince1970: 0),
            tokens: TokenBreakdown.zero,
            sourceId: "src"
        )
        var set: Set<TokenEvent> = []
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
    }

    // MARK: - sourceId

    func testSourceIdUniqueness() {
        // Same sourceId for different providers is allowed by design: dedup
        // is keyed on (provider, sourceId), not sourceId alone.
        let e1 = TokenEvent(
            provider: .claude,
            model: "m",
            source: .claudeCode,
            sessionId: "s",
            timestamp: Date(timeIntervalSince1970: 0),
            tokens: TokenBreakdown.zero,
            sourceId: "shared-id"
        )
        let e2 = TokenEvent(
            provider: .zai,
            model: "m",
            source: .zaiApi,
            sessionId: "s",
            timestamp: Date(timeIntervalSince1970: 0),
            tokens: TokenBreakdown.zero,
            sourceId: "shared-id"
        )
        XCTAssertNotEqual(e1, e2)
        XCTAssertEqual(e1.sourceId, e2.sourceId)
        var set: Set<TokenEvent> = [e1, e2]
        XCTAssertEqual(set.count, 2)
        set.remove(e1)
        XCTAssertEqual(set.count, 1)
        XCTAssertTrue(set.contains(e2))
    }
}