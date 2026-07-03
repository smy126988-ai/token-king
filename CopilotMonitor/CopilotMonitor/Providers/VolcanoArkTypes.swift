import Foundation

struct VolcanoArkUsageResponse: Decodable {
    struct Window: Decodable {
        let quota: Double?
        let used: Double?
        let resetTime: Int64?

        enum CodingKeys: String, CodingKey {
            case quota = "Quota"
            case used = "Used"
            case resetTime = "ResetTime"
        }
    }

    struct Result: Decodable {
        let afpFiveHour: Window?
        let afpWeekly: Window?

        enum CodingKeys: String, CodingKey {
            case afpFiveHour = "AFPFiveHour"
            case afpWeekly = "AFPWeekly"
        }
    }

    let result: Result?

    enum CodingKeys: String, CodingKey {
        case result = "Result"
    }
}

func usagePercent(from window: VolcanoArkUsageResponse.Window?) -> Double? {
    guard let window else { return nil }
    if let quota = window.quota, quota > 0, let used = window.used {
        return (used / quota) * 100.0
    }
    return nil
}

func resetDate(from milliseconds: Int64?) -> Date? {
    guard let ms = milliseconds, ms > 0 else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
}
