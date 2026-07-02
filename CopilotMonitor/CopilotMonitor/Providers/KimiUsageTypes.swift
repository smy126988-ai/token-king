import Foundation

/// Maps Kimi `user.membership.level` strings to the product tier names used in subscription presets.
///
/// Verified mappings:
/// - `LEVEL_INTERMEDIATE` → "Moderato" (real CN account, usage.limit = "100", region = "REGION_CN").
/// - `LEVEL_VIVACE`       → "Vivace"   (unit-test fixtures; matches the top-tier preset name).
///
/// 待补映射：其它 level（如 LEVEL_BEGINNER / LEVEL_ADVANCED / LEVEL_EXPERT 等）
/// 需要真实账号响应确认，当前不猜测。未映射的 level 保持旧行为：去掉 `LEVEL_` 前缀并小写。
enum KimiPlanMapper {
    static func presetName(for level: String?, limit: String? = nil, region: String? = nil) -> String? {
        guard let level else { return nil }

        switch level.uppercased() {
        case "LEVEL_INTERMEDIATE":
            // Verified against real account: region=CN, usage.limit="100".
            return "Moderato"
        case "LEVEL_VIVACE":
            // Top-tier product name; present in test fixtures and expected to map directly.
            return "Vivace"
        default:
            // 待补：其它 level 等待真实响应验证。
            return legacyPlanType(for: level)
        }
    }

    private static func legacyPlanType(for level: String) -> String {
        level.replacingOccurrences(of: "LEVEL_", with: "", options: .caseInsensitive).lowercased()
    }
}

struct KimiUsageResponse: Codable {
    struct User: Codable {
        let userId: String?
        let region: String?
        let membership: Membership?
        let businessId: String?
    }

    struct Membership: Codable {
        let level: String?
    }

    struct Usage: Codable {
        let limit: String?
        let used: String?
        let remaining: String?
        let resetTime: String?
    }

    struct Limit: Codable {
        let window: Window?
        let detail: Detail?
    }

    struct Window: Codable {
        let duration: Int?
        let timeUnit: String?
    }

    struct Detail: Codable {
        let limit: String?
        let used: String?
        let remaining: String?
        let resetTime: String?
    }

    let user: User?
    let usage: Usage?
    let limits: [Limit]?
}
