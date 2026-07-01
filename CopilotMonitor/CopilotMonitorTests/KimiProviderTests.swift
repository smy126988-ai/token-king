import XCTest
@testable import OpenCode_Bar

final class KimiProviderTests: XCTestCase {
    func testWeeklyUsedComputedFromLimitMinusRemaining() throws {
        // Kimi 真实响应：usage 无 used 字段，只有 limit/remaining
        let json = """
        {
          "user": {"userId": "u1", "membership": {"level": "LEVEL_VIVACE"}},
          "usage": {"limit": "100", "remaining": "40", "resetTime": "2026-07-08T02:32:44Z"},
          "limits": [{"window": {"duration": 5, "timeUnit": "HOUR"},
                      "detail": {"limit": "50", "remaining": "45", "resetTime": "2026-07-01T08:00:00Z"}}]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(KimiUsageResponse.self, from: json)
        XCTAssertNil(decoded.usage?.used, "Kimi usage object should not contain a used field")

        let limit = Int(decoded.usage?.limit ?? "0") ?? 0
        let remaining = Int(decoded.usage?.remaining ?? "0") ?? 0
        let used = max(0, limit - remaining)

        XCTAssertEqual(used, 60)
        let percent = limit > 0 ? Double(used) / Double(limit) * 100 : 0
        XCTAssertEqual(percent, 60.0, accuracy: 0.01)
    }
}
