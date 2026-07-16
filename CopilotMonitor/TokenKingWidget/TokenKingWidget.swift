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
                    // Single-layer tier gradient (quota-float palette). Pure
                    // SwiftUI gradient, no material/scrim — renders full-colour
                    // on the desktop; the system replaces it in vibrant/accented.
                    AuroraBackgroundView(snapshot: entry.snapshot)
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
                    // Single-layer tier gradient (quota-float palette). Pure
                    // SwiftUI gradient, no material/scrim — renders full-colour
                    // on the desktop; the system replaces it in vibrant/accented.
                    AuroraBackgroundView(snapshot: entry.snapshot)
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
                    // Single-layer tier gradient (quota-float palette). Pure
                    // SwiftUI gradient, no material/scrim — renders full-colour
                    // on the desktop; the system replaces it in vibrant/accented.
                    AuroraBackgroundView(snapshot: entry.snapshot)
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
                    // Single-layer tier gradient (quota-float palette). Pure
                    // SwiftUI gradient, no material/scrim — renders full-colour
                    // on the desktop; the system replaces it in vibrant/accented.
                    AuroraBackgroundView(snapshot: entry.snapshot)
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
                    // Single-layer tier gradient (quota-float palette). Pure
                    // SwiftUI gradient, no material/scrim — renders full-colour
                    // on the desktop; the system replaces it in vibrant/accented.
                    AuroraBackgroundView(snapshot: entry.snapshot)
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
                    // Single-layer tier gradient (quota-float palette). Pure
                    // SwiftUI gradient, no material/scrim — renders full-colour
                    // on the desktop; the system replaces it in vibrant/accented.
                    AuroraBackgroundView(snapshot: entry.snapshot)
                }
        }
        .configurationDisplayName("Token King Search Engines")
        .description("Brave + Tavily search usage.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Aurora background

/// Single-layer tier gradient drawn into `containerBackground`. Colours come
/// from the quota-float palette (WidgetDesignToken.Aurora). This is a pure
/// SwiftUI gradient — NO `.ultraThinMaterial` / scrim on top, which is what
/// turned the previous aurora muddy in fullColor. Self-contained pixels render
/// as full colour on the desktop; in vibrant/accented the system replaces it.
struct AuroraBackgroundView: View {
    let tier: WidgetDesignToken.Aurora.Tier

    init(snapshot: WidgetSnapshot?) {
        let peak = snapshot?.providers
            .flatMap { $0.windows }
            .map { $0.usedPercent }
            .max() ?? WidgetDesignToken.zeroDouble
        self.tier = WidgetDesignToken.Aurora.tier(forUsedPercent: peak)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tier.cool, tier.linearMid, tier.linearWarm, tier.linearEnd],
                startPoint: angleStart, endPoint: angleEnd
            )
            RadialGradient(colors: [tier.cool.opacity(0.9), .clear],
                           center: UnitPoint(x: 0.52, y: 0.12), startRadius: 0, endRadius: 220)
            RadialGradient(colors: [tier.glow.opacity(0.78), .clear],
                           center: UnitPoint(x: 0.28, y: 0.68), startRadius: 0, endRadius: 170)
            RadialGradient(colors: [tier.warm.opacity(0.64), .clear],
                           center: UnitPoint(x: 0.82, y: 0.82), startRadius: 0, endRadius: 150)
        }
    }

    // Map CSS gradient-angle (deg, 0 = up) to SwiftUI start/end unit points.
    private var angleStart: UnitPoint {
        tier.angle < 180 ? .topLeading : .bottomLeading
    }
    private var angleEnd: UnitPoint {
        tier.angle < 180 ? .bottomTrailing : .topTrailing
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

    // MARK: - HTTP-first reads (P1)

    /// Try to read the snapshot over the app's loopback HTTP bridge.
    ///
    /// Returns nil on any failure (app not running, timeout, non-200, decode
    /// error) so the caller falls back to the file channel. This is the
    /// preferred path: it sidesteps sandbox file-coordination stalls and
    /// always sees the writer's latest flush.
    func readEntryViaHTTP(selectedProviderId: String? = nil) async -> TokenKingEntry? {
        var request = URLRequest(url: SharedPaths.localSnapshotURL)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                WidgetLogger.provider.debug("http snapshot: non-200 response, falling back to file")
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)
            let age = Date().timeIntervalSince(snapshot.snapshotAt)
            let status: TokenKingEntry.ReadStatus = age > Self.staleThreshold ? .stale : .ok
            WidgetLogger.provider.notice("read snapshot via http v\(snapshot.version, privacy: .public) providers=\(snapshot.providers.count, privacy: .public) ageSec=\(Int(age), privacy: .public) status=\(status.rawValueString, privacy: .public)")
            return TokenKingEntry(date: Date(), kind: Self.kind, selectedProviderId: selectedProviderId, snapshot: snapshot, readStatus: status, snapshotAgeSeconds: age)
        } catch {
            WidgetLogger.provider.debug("http snapshot failed (\(error.localizedDescription, privacy: .public)); falling back to file")
            return nil
        }
    }

    /// HTTP-first entry: loopback server, then file fallback.
    func readEntryHTTPFirst(selectedProviderId: String? = nil) async -> TokenKingEntry {
        await readEntryViaHTTP(selectedProviderId: selectedProviderId) ?? readEntry(selectedProviderId: selectedProviderId)
    }

    /// HTTP-first timeline with the same 15-minute refresh policy.
    func makeTimelineHTTPFirst(selectedProviderId: String? = nil) async -> Timeline<TokenKingEntry> {
        let entry = await readEntryHTTPFirst(selectedProviderId: selectedProviderId)
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
        await readEntryHTTPFirst(selectedProviderId: configuration.provider?.id)
    }

    func timeline(for configuration: ProviderSelectionIntent, in context: Context) async -> Timeline<TokenKingEntry> {
        await makeTimelineHTTPFirst(selectedProviderId: configuration.provider?.id)
    }
}

/// Provider for the configurable medium detail widget.
struct MediumDetailProvider: BaseTokenKingProvider, AppIntentTimelineProvider {
    static let kind: TokenKingWidgetKind = .mediumDetail
    typealias Intent = ProviderSelectionIntent
    typealias Entry = TokenKingEntry

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> TokenKingEntry {
        await readEntryHTTPFirst(selectedProviderId: configuration.provider?.id)
    }

    func timeline(for configuration: ProviderSelectionIntent, in context: Context) async -> Timeline<TokenKingEntry> {
        await makeTimelineHTTPFirst(selectedProviderId: configuration.provider?.id)
    }
}

/// Provider for the configurable large detail widget.
struct LargeDetailProvider: BaseTokenKingProvider, AppIntentTimelineProvider {
    static let kind: TokenKingWidgetKind = .largeDetail
    typealias Intent = ProviderSelectionIntent
    typealias Entry = TokenKingEntry

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> TokenKingEntry {
        await readEntryHTTPFirst(selectedProviderId: configuration.provider?.id)
    }

    func timeline(for configuration: ProviderSelectionIntent, in context: Context) async -> Timeline<TokenKingEntry> {
        await makeTimelineHTTPFirst(selectedProviderId: configuration.provider?.id)
    }
}

// MARK: - Static providers

/// Provider for the medium multi-provider overview widget.
struct MediumOverviewProvider: BaseTokenKingProvider, TimelineProvider {
    static let kind: TokenKingWidgetKind = .mediumOverview
    typealias Entry = TokenKingEntry

    func getSnapshot(in context: Context, completion: @escaping (TokenKingEntry) -> Void) {
        Task { completion(await readEntryHTTPFirst()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenKingEntry>) -> Void) {
        Task { completion(await makeTimelineHTTPFirst()) }
    }
}

/// Provider for the large multi-provider overview widget.
struct LargeOverviewProvider: BaseTokenKingProvider, TimelineProvider {
    static let kind: TokenKingWidgetKind = .largeOverview
    typealias Entry = TokenKingEntry

    func getSnapshot(in context: Context, completion: @escaping (TokenKingEntry) -> Void) {
        Task { completion(await readEntryHTTPFirst()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenKingEntry>) -> Void) {
        Task { completion(await makeTimelineHTTPFirst()) }
    }
}

/// Provider for the search-engine-only large widget.
struct SearchEnginesProvider: BaseTokenKingProvider, TimelineProvider {
    static let kind: TokenKingWidgetKind = .searchEngines
    typealias Entry = TokenKingEntry

    func getSnapshot(in context: Context, completion: @escaping (TokenKingEntry) -> Void) {
        Task { completion(await readEntryHTTPFirst()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenKingEntry>) -> Void) {
        Task { completion(await makeTimelineHTTPFirst()) }
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
