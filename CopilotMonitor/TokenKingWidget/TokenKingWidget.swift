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
                    AuroraBackgroundView()
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
                    AuroraBackgroundView()
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
                    AuroraBackgroundView()
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
                    AuroraBackgroundView()
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
                    AuroraBackgroundView()
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
                    AuroraBackgroundView()
                }
        }
        .configurationDisplayName("Token King Search Engines")
        .description("Brave + Tavily search usage.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Aurora background (P2 V1)

/// Decorative aurora gradient + ultraThinMaterial glass overlay.
///
/// Colour values are defined in `WidgetDesignToken.Aurora` (copied from the
/// approved prototype). SwiftUI can't reproduce the CSS `radial-gradient(Npx
/// at X% Y%)` exactly, so we approximate with two offset `RadialGradient`s
/// plus a base `LinearGradient`. Goal: the same "warm peach → pink → lavender"
/// mood in light, "deep teal → indigo → near-black" in dark, with a glass
/// veil on top so the content stays readable.
struct AuroraBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            baseLinear
            ForEach(Array(radialStops.enumerated()), id: \.offset) { idx, color in
                RadialGradient(
                    colors: [color.opacity(0.6), color.opacity(0)],
                    center: radialCenters[idx % radialCenters.count],
                    startRadius: 8,
                    endRadius: 220
                )
                .blendMode(.plusLighter)
            }
        }
    }

    private var linearStops: [Color] {
        colorScheme == .dark
            ? WidgetDesignToken.Aurora.darkLinear
            : WidgetDesignToken.Aurora.lightLinear
    }

    private var radialStops: [Color] {
        colorScheme == .dark
            ? WidgetDesignToken.Aurora.darkRadial
            : WidgetDesignToken.Aurora.lightRadial
    }

    /// Radial focal anchors approximating the prototype's
    /// `radial-gradient(... at 6% 0% / 100% 100% / 55% 50%)` positions.
    private let radialCenters: [UnitPoint] = [
        UnitPoint(x: 0.06, y: 0.0),
        UnitPoint(x: 1.0, y: 1.0),
        .center
    ]

    /// Base linear wash (150deg peach→pink→lavender / teal→indigo→black).
    private var baseLinear: some View {
        LinearGradient(
            colors: linearStops,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
        let result = WidgetSnapshotReader.read(at: url, now: Date(), staleThreshold: Self.staleThreshold)

        switch result {
        case .noFile:
            WidgetLogger.provider.warning("snapshot file does not exist at \(url.path, privacy: .public)")
            return TokenKingEntry(date: Date(), kind: Self.kind, selectedProviderId: selectedProviderId, snapshot: nil, readStatus: .noFile, snapshotAgeSeconds: nil)

        case .corrupt:
            WidgetLogger.provider.error("decode failed")
            return TokenKingEntry(date: Date(), kind: Self.kind, selectedProviderId: selectedProviderId, snapshot: nil, readStatus: .corrupt, snapshotAgeSeconds: nil)

        case .stale(let snapshot, let age):
            let status: TokenKingEntry.ReadStatus = .stale
            WidgetLogger.provider.notice("read snapshot v\(snapshot.version) providers=\(snapshot.providers.count) ageSec=\(Int(age), privacy: .public) status=\(status.rawValueString, privacy: .public)")
            return TokenKingEntry(date: Date(), kind: Self.kind, selectedProviderId: selectedProviderId, snapshot: snapshot, readStatus: status, snapshotAgeSeconds: age)

        case .ok(let snapshot, let age):
            let status: TokenKingEntry.ReadStatus = .ok
            WidgetLogger.provider.notice("read snapshot v\(snapshot.version) providers=\(snapshot.providers.count) ageSec=\(Int(age), privacy: .public) status=\(status.rawValueString, privacy: .public)")
            return TokenKingEntry(date: Date(), kind: Self.kind, selectedProviderId: selectedProviderId, snapshot: snapshot, readStatus: status, snapshotAgeSeconds: age)
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
