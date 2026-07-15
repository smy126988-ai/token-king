import WidgetKit
import SwiftUI

// MARK: - WidgetBundle

@main
struct TokenKingWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenKingWidgetSmall()
        TokenKingWidgetMediumOverview()
        TokenKingWidgetMediumDetail()
        TokenKingWidgetLargeOverview()
        TokenKingWidgetLargeDetail()
        TokenKingWidgetSearchEngines()
    }
}

// MARK: - WidgetKind

/// Identifies which independent widget instance an entry belongs to.
///
/// The value is set by each provider so the shared `TokenKingWidgetView` can
/// dispatch rendering based on kind rather than widget family.
enum TokenKingWidgetKind: String, Equatable {
    case small
    case mediumOverview
    case mediumDetail
    case largeOverview
    case largeDetail
    case searchEngines
}

// MARK: - Widgets

struct TokenKingWidgetSmall: Widget {
    let kind = "com.tokenking.app.widget.small"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ProviderSelectionIntent.self, provider: SmallProvider()) { entry in
            TokenKingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Let the system own the background: on the macOS desktop it
                    // provides the wallpaper-aware frosted material (native look)
                    // and removes/replaces this in vibrant/accented modes. Drawing
                    // our own gradient here fought the system and looked muddy in
                    // fullColor. See DESIGN.md §1 + the plan's Context section.
                    Color.clear
                }
        }
        .configurationDisplayName("Token King Small")
        .description("Single provider usage at a glance.")
        .supportedFamilies([.systemSmall])
    }
}

struct TokenKingWidgetMediumOverview: Widget {
    let kind = "com.tokenking.app.widget.mediumOverview"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MediumOverviewProvider()) { entry in
            TokenKingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Let the system own the background: on the macOS desktop it
                    // provides the wallpaper-aware frosted material (native look)
                    // and removes/replaces this in vibrant/accented modes. Drawing
                    // our own gradient here fought the system and looked muddy in
                    // fullColor. See DESIGN.md §1 + the plan's Context section.
                    Color.clear
                }
        }
        .configurationDisplayName("Token King Medium Overview")
        .description("Multi-provider usage overview.")
        .supportedFamilies([.systemMedium])
    }
}

struct TokenKingWidgetMediumDetail: Widget {
    let kind = "com.tokenking.app.widget.mediumDetail"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ProviderSelectionIntent.self, provider: MediumDetailProvider()) { entry in
            TokenKingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Let the system own the background: on the macOS desktop it
                    // provides the wallpaper-aware frosted material (native look)
                    // and removes/replaces this in vibrant/accented modes. Drawing
                    // our own gradient here fought the system and looked muddy in
                    // fullColor. See DESIGN.md §1 + the plan's Context section.
                    Color.clear
                }
        }
        .configurationDisplayName("Token King Medium Detail")
        .description("Detailed view for a single provider.")
        .supportedFamilies([.systemMedium])
    }
}

struct TokenKingWidgetLargeOverview: Widget {
    let kind = "com.tokenking.app.widget.largeOverview"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LargeOverviewProvider()) { entry in
            TokenKingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Let the system own the background: on the macOS desktop it
                    // provides the wallpaper-aware frosted material (native look)
                    // and removes/replaces this in vibrant/accented modes. Drawing
                    // our own gradient here fought the system and looked muddy in
                    // fullColor. See DESIGN.md §1 + the plan's Context section.
                    Color.clear
                }
        }
        .configurationDisplayName("Token King Large Overview")
        .description("Multi-provider overview with monthly cost.")
        .supportedFamilies([.systemLarge])
    }
}

struct TokenKingWidgetLargeDetail: Widget {
    let kind = "com.tokenking.app.widget.largeDetail"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ProviderSelectionIntent.self, provider: LargeDetailProvider()) { entry in
            TokenKingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Let the system own the background: on the macOS desktop it
                    // provides the wallpaper-aware frosted material (native look)
                    // and removes/replaces this in vibrant/accented modes. Drawing
                    // our own gradient here fought the system and looked muddy in
                    // fullColor. See DESIGN.md §1 + the plan's Context section.
                    Color.clear
                }
        }
        .configurationDisplayName("Token King Large Detail")
        .description("Detailed view for a single provider.")
        .supportedFamilies([.systemLarge])
    }
}

struct TokenKingWidgetSearchEngines: Widget {
    let kind = "com.tokenking.app.widget.searchEngines"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SearchEnginesProvider()) { entry in
            TokenKingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    // Let the system own the background: on the macOS desktop it
                    // provides the wallpaper-aware frosted material (native look)
                    // and removes/replaces this in vibrant/accented modes. Drawing
                    // our own gradient here fought the system and looked muddy in
                    // fullColor. See DESIGN.md §1 + the plan's Context section.
                    Color.clear
                }
        }
        .configurationDisplayName("Token King Search Engines")
        .description("Brave + Tavily search usage.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - TimelineEntry

struct TokenKingEntry: TimelineEntry {
    let date: Date
    let kind: TokenKingWidgetKind
    let selectedProviderId: String?
    let snapshot: WidgetSnapshot?
    let readStatus: ReadStatus
    let snapshotAgeSeconds: Double?

    enum ReadStatus: Equatable {
        case ok
        case stale
        case noFile
        case corrupt
    }
}

// MARK: - Base provider

/// Shared behavior for all Token King timeline providers.
///
/// Each concrete provider declares its `kind` and inherits the snapshot read
/// logic plus placeholder/timeline helpers. Providers do not filter the
/// snapshot; they only stamp the entry with the correct `TokenKingWidgetKind`
/// so the view layer can dispatch rendering.
protocol BaseTokenKingProvider {
    static var kind: TokenKingWidgetKind { get }
}

extension BaseTokenKingProvider {
    /// 90 minutes — system throttles to 15-60min anyway.
    static var staleThreshold: TimeInterval { 90 * 60 }

    func placeholder(in context: TimelineProviderContext) -> TokenKingEntry {
        TokenKingEntry(date: Date(), kind: Self.kind, selectedProviderId: nil, snapshot: nil, readStatus: .noFile, snapshotAgeSeconds: nil)
    }

    /// Read the shared snapshot from disk and tag the entry with this provider's kind.
    func readEntry(selectedProviderId: String? = nil) -> TokenKingEntry {
        let url = SharedPaths.snapshotURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            WidgetLogger.provider.warning("snapshot file does not exist at \(url.path, privacy: .public)")
            return TokenKingEntry(date: Date(), kind: Self.kind, selectedProviderId: selectedProviderId, snapshot: nil, readStatus: .noFile, snapshotAgeSeconds: nil)
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)

            let age = Date().timeIntervalSince(snapshot.snapshotAt)
            let status: TokenKingEntry.ReadStatus = age > Self.staleThreshold ? .stale : .ok
            WidgetLogger.provider.notice("read snapshot v\(snapshot.version) providers=\(snapshot.providers.count) ageSec=\(Int(age), privacy: .public) status=\(status.rawValueString, privacy: .public)")

            return TokenKingEntry(date: Date(), kind: Self.kind, selectedProviderId: selectedProviderId, snapshot: snapshot, readStatus: status, snapshotAgeSeconds: age)
        } catch {
            WidgetLogger.provider.error("decode failed: \(error.localizedDescription, privacy: .public)")
            return TokenKingEntry(date: Date(), kind: Self.kind, selectedProviderId: selectedProviderId, snapshot: nil, readStatus: .corrupt, snapshotAgeSeconds: nil)
        }
    }

    /// Build a timeline with a single entry and a 15-minute refresh policy.
    func makeTimeline(selectedProviderId: String? = nil) -> Timeline<TokenKingEntry> {
        let entry = readEntry(selectedProviderId: selectedProviderId)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        WidgetLogger.provider.debug("timeline next=\(nextRefresh, privacy: .public) status=\(entry.readStatus.rawValueString, privacy: .public)")
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

// MARK: - AppIntent providers

/// Provider for the configurable small widget.
struct SmallProvider: BaseTokenKingProvider, AppIntentTimelineProvider {
    static let kind: TokenKingWidgetKind = .small
    typealias Intent = ProviderSelectionIntent
    typealias Entry = TokenKingEntry

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> TokenKingEntry {
        readEntry(selectedProviderId: configuration.provider?.id)
    }

    func timeline(for configuration: ProviderSelectionIntent, in context: Context) async -> Timeline<TokenKingEntry> {
        makeTimeline(selectedProviderId: configuration.provider?.id)
    }
}

/// Provider for the configurable medium detail widget.
struct MediumDetailProvider: BaseTokenKingProvider, AppIntentTimelineProvider {
    static let kind: TokenKingWidgetKind = .mediumDetail
    typealias Intent = ProviderSelectionIntent
    typealias Entry = TokenKingEntry

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> TokenKingEntry {
        readEntry(selectedProviderId: configuration.provider?.id)
    }

    func timeline(for configuration: ProviderSelectionIntent, in context: Context) async -> Timeline<TokenKingEntry> {
        makeTimeline(selectedProviderId: configuration.provider?.id)
    }
}

/// Provider for the configurable large detail widget.
struct LargeDetailProvider: BaseTokenKingProvider, AppIntentTimelineProvider {
    static let kind: TokenKingWidgetKind = .largeDetail
    typealias Intent = ProviderSelectionIntent
    typealias Entry = TokenKingEntry

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> TokenKingEntry {
        readEntry(selectedProviderId: configuration.provider?.id)
    }

    func timeline(for configuration: ProviderSelectionIntent, in context: Context) async -> Timeline<TokenKingEntry> {
        makeTimeline(selectedProviderId: configuration.provider?.id)
    }
}

// MARK: - Static providers

/// Provider for the medium multi-provider overview widget.
struct MediumOverviewProvider: BaseTokenKingProvider, TimelineProvider {
    static let kind: TokenKingWidgetKind = .mediumOverview
    typealias Entry = TokenKingEntry

    func getSnapshot(in context: Context, completion: @escaping (TokenKingEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenKingEntry>) -> Void) {
        completion(makeTimeline())
    }
}

/// Provider for the large multi-provider overview widget.
struct LargeOverviewProvider: BaseTokenKingProvider, TimelineProvider {
    static let kind: TokenKingWidgetKind = .largeOverview
    typealias Entry = TokenKingEntry

    func getSnapshot(in context: Context, completion: @escaping (TokenKingEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenKingEntry>) -> Void) {
        completion(makeTimeline())
    }
}

/// Provider for the search-engine-only large widget.
struct SearchEnginesProvider: BaseTokenKingProvider, TimelineProvider {
    static let kind: TokenKingWidgetKind = .searchEngines
    typealias Entry = TokenKingEntry

    func getSnapshot(in context: Context, completion: @escaping (TokenKingEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenKingEntry>) -> Void) {
        completion(makeTimeline())
    }
}

// MARK: - ReadStatus helpers

extension TokenKingEntry.ReadStatus {
    var rawValueString: String {
        switch self {
        case .ok: return "ok"
        case .stale: return "stale"
        case .noFile: return "noFile"
        case .corrupt: return "corrupt"
        }
    }
}
