import Foundation

// MARK: - Refresh Interval
enum RefreshInterval: Int, CaseIterable {
    case oneMinute = 60
    case threeMinutes = 180
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1800
    case oneHour = 3600

    var title: String {
        switch self {
        case .oneMinute: return "1m"
        case .threeMinutes: return "3m"
        case .fiveMinutes: return "5m"
        case .tenMinutes: return "10m"
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        }
    }

    static var defaultInterval: RefreshInterval { .fiveMinutes }
}

// MARK: - Prediction Period
enum PredictionPeriod: Int, CaseIterable {
    case oneWeek = 7
    case twoWeeks = 14
    case threeWeeks = 21

    var title: String {
        switch self {
        case .oneWeek: return String(localized: "7 days", comment: "Prediction period menu title")
        case .twoWeeks: return String(localized: "14 days", comment: "Prediction period menu title")
        case .threeWeeks: return String(localized: "21 days", comment: "Prediction period menu title")
        }
    }

    var weights: [Double] {
        switch self {
        case .oneWeek:
            return [1.5, 1.5, 1.2, 1.2, 1.2, 1.0, 1.0]
        case .twoWeeks:
            return [1.5, 1.5, 1.4, 1.4, 1.3, 1.3, 1.2, 1.2, 1.1, 1.1, 1.0, 1.0, 1.0, 1.0]
        case .threeWeeks:
            return [1.5, 1.5, 1.4, 1.4, 1.3, 1.3, 1.2, 1.2, 1.2, 1.1, 1.1, 1.1, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
        }
    }

    static var defaultPeriod: PredictionPeriod { .oneWeek }
}

// MARK: - Brave Search Refresh Mode
enum BraveSearchRefreshMode: Int, CaseIterable {
    case eventOnly = 0
    case apiEverySixHours = 1
    case hybrid = 2

    var title: String {
        switch self {
        case .eventOnly: return String(localized: "Event only", comment: "Brave Search refresh mode menu title")
        case .apiEverySixHours: return String(localized: "API sync every 6 hours", comment: "Brave Search refresh mode menu title")
        case .hybrid: return String(localized: "Hybrid (events + 6-hour API)", comment: "Brave Search refresh mode menu title")
        }
    }

    var allowsAPISync: Bool {
        switch self {
        case .eventOnly:
            return false
        case .apiEverySixHours, .hybrid:
            return true
        }
    }

    var allowsEventCounting: Bool {
        switch self {
        case .eventOnly, .hybrid:
            return true
        case .apiEverySixHours:
            return false
        }
    }

    static var defaultMode: BraveSearchRefreshMode { .eventOnly }
}

// MARK: - Menu Bar Display
enum MenuBarDisplayMode: Int, CaseIterable {
    case totalCost = 0
    case iconOnly = 1
    case onlyShow = 2

    var title: String {
        switch self {
        case .totalCost: return String(localized: "Total Cost", comment: "Menu bar display mode menu title")
        case .iconOnly: return String(localized: "Icon Only", comment: "Menu bar display mode menu title")
        case .onlyShow: return String(localized: "Only Show", comment: "Menu bar display mode menu title")
        }
    }

    static var defaultMode: MenuBarDisplayMode { .totalCost }
}

enum OnlyShowMode: Int, CaseIterable {
    case pinnedProvider = 0
    case alertFirst = 1
    case recentChange = 2

    var title: String {
        switch self {
        case .pinnedProvider: return String(localized: "Pinned Provider", comment: "Only-show mode menu title")
        case .alertFirst: return String(localized: "Alert First", comment: "Only-show mode menu title")
        case .recentChange: return String(localized: "Recent Change Only", comment: "Only-show mode menu title")
        }
    }

    static var defaultMode: OnlyShowMode { .pinnedProvider }
}

enum StatusBarDisplayPreferences {
    static let modeKey = "statusBarDisplay.mode"
    static let onlyShowModeKey = "statusBarDisplay.onlyShowMode"
    static let providerKey = "statusBarDisplay.provider"
    // Legacy key kept for migration from old toggle-based UI.
    static let showAlertFirstKey = "statusBarDisplay.showAlertFirst"
    static let criticalBadgeKey = "statusBarDisplay.criticalBadge"
    static let showProviderNameKey = "statusBarDisplay.showProviderName"
}

enum SearchEnginePreferences {
    static let braveRefreshModeKey = "searchEngines.brave.refreshMode"
    static let braveLastAPISyncAtKey = "searchEngines.brave.lastApiSyncAt"
    static let braveLastUsedKey = "searchEngines.brave.lastUsed"
    static let braveLastRemainingKey = "searchEngines.brave.lastRemaining"
    static let braveLastLimitKey = "searchEngines.brave.lastLimit"
    static let braveLastResetSecondsKey = "searchEngines.brave.lastResetSeconds"
    static let braveEventEstimatedUsedKey = "searchEngines.brave.eventEstimatedUsed"
    static let braveEventCursorKey = "searchEngines.brave.eventCursor"
    static let braveEventMonthKey = "searchEngines.brave.eventMonth"
}

enum Currency: String, CaseIterable {
    case usd = "USD"
    case rmb = "RMB"

    var symbol: String {
        switch self {
        case .usd: return "$"
        case .rmb: return "¥"
        }
    }

    var menuTitle: String {
        switch self {
        case .usd: return String(localized: "US Dollar ($)", comment: "Currency menu title")
        case .rmb: return String(localized: "Chinese Yuan (¥)", comment: "Currency menu title")
        }
    }
}

enum CurrencyPreferences {
    static let selectedCurrencyKey = "currency.selected"
}
