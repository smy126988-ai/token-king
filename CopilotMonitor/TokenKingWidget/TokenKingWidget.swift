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
        TokenKingCodexWidget()
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

struct TokenKingCodexWidget: Widget {
    let kind = "com.tokenking.app.widget.codex"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: CodexAccountSelectionIntent.self,
            provider: CodexQuotaTimelineProvider()
        ) { entry in
            CodexQuotaCardView(entry: entry)
                .unredacted()
                .containerBackground(for: .widget) {
                    QuotaCardBackground(
                        tier: codexTier(
                            snapshot: entry.snapshot,
                            selectedAccountId: entry.selectedProviderId
                        )
                    )
                }
        }
        .contentMarginsDisabled()
        .configurationDisplayName("Token King Codex")
        .description("Codex quota remaining for one account.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct TokenKingWidgetSmall: Widget {
    let kind = "com.tokenking.app.widget.small"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ProviderSelectionIntent.self, provider: SmallProvider()) { entry in
            TokenKingWidgetView(entry: entry)
                .unredacted()
                .containerBackground(for: .widget) {
                    // quota-float QuotaCard container; tier follows the SAME
                    // short window the content displays.
                    QuotaCardBackground(tier: providerTier(snapshot: entry.snapshot,
                                                           selectedProviderId: entry.selectedProviderId))
                }
        }
        .contentMarginsDisabled()
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
                .unredacted()
                .containerBackground(for: .widget) {
                    QuotaCardBackground(tier: providerTier(snapshot: entry.snapshot,
                                                           selectedProviderId: entry.selectedProviderId))
                }
        }
        .contentMarginsDisabled()
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
                .unredacted()
                .containerBackground(for: .widget) {
                    QuotaCardBackground(tier: providerTier(snapshot: entry.snapshot,
                                                           selectedProviderId: entry.selectedProviderId))
                }
        }
        .contentMarginsDisabled()
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
                .unredacted()
                .containerBackground(for: .widget) {
                    QuotaCardBackground(tier: overviewTier(snapshot: entry.snapshot))
                }
        }
        .contentMarginsDisabled()
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
                .unredacted()
                .containerBackground(for: .widget) {
                    QuotaCardBackground(tier: providerTier(snapshot: entry.snapshot,
                                                           selectedProviderId: entry.selectedProviderId))
                }
        }
        .contentMarginsDisabled()
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
                .unredacted()
                .containerBackground(for: .widget) {
                    QuotaCardBackground(tier: overviewTier(snapshot: entry.snapshot))
                }
        }
        .contentMarginsDisabled()
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

    /// Direct-tier init: paints the field with the same tier the content shows
    /// (e.g. the small orb's short window), so field and card never clash.
    init(tier: WidgetDesignToken.Aurora.Tier) {
        self.tier = tier
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tier.cool, tier.linearMid, tier.linearWarm, tier.linearEnd],
                startPoint: angleStart, endPoint: angleEnd
            )
            RadialGradient(colors: [tier.cool.opacity(0.9), .clear],
                           center: UnitPoint(x: 0.52, y: 0.12), startRadius: 0,
                           endRadius: WidgetDesignToken.auroraCoolEndRadius)
            RadialGradient(colors: [tier.glow.opacity(0.78), .clear],
                           center: UnitPoint(x: 0.28, y: 0.68), startRadius: 0,
                           endRadius: WidgetDesignToken.auroraGlowEndRadius)
            RadialGradient(colors: [tier.warm.opacity(0.64), .clear],
                           center: UnitPoint(x: 0.82, y: 0.82), startRadius: 0,
                           endRadius: WidgetDesignToken.auroraWarmEndRadius)
        }
        .opacity(tier.opacity)
    }

    // Map CSS gradient-angle (deg, 0 = up) to SwiftUI start/end unit points.
    private var angleStart: UnitPoint {
        tier.angle < 180 ? .topLeading : .bottomLeading
    }
    private var angleEnd: UnitPoint {
        tier.angle < 180 ? .bottomTrailing : .topTrailing
    }
}

// MARK: - QuotaCard container background

/// Static light QuotaCard container with a tier aurora and subtle edge light.
/// Pure gradients keep the extension deterministic and let the system replace
/// the field in vibrant or accented rendering modes.
struct QuotaCardBackground: View {
    let tier: WidgetDesignToken.Aurora.Tier

    var body: some View {
        ZStack {
            WidgetDesignToken.orbCardBackground
            AuroraBackgroundView(tier: tier)
            RoundedRectangle(cornerRadius: WidgetDesignToken.codexCardCornerRadius, style: .continuous)
                .stroke(LinearGradient(colors: [Color.white.opacity(WidgetDesignToken.codexBorderTopOpacity),
                                                Color.white.opacity(WidgetDesignToken.codexBorderBottomOpacity)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: WidgetDesignToken.orbCardBorderWidth)
        }
    }
}

/// Quota tier for the account this widget instance actually resolves.
func codexTier(snapshot: WidgetSnapshot?, selectedAccountId: String?) -> WidgetDesignToken.Aurora.Tier {
    guard let codex = snapshot?.providers.first(where: { $0.id == WidgetDesignToken.ProviderID.codex }) else {
        return WidgetDesignToken.Aurora.healthy
    }
    let accounts = codex.accounts ?? []
    let account: ProviderAccountSnapshot?
    if let selectedAccountId {
        account = accounts.first { $0.id == selectedAccountId }
    } else {
        account = accounts.count == WidgetDesignToken.singleWindowCount ? accounts.first : nil
    }
    guard account?.status == .available, let usedPercent = account?.metrics.first?.usedPercent else {
        return WidgetDesignToken.Aurora.healthy
    }
    return WidgetDesignToken.CodexQuota.tier(forUsedPercent: usedPercent)
}

/// Tier for a single-provider widget: the displayed provider's short window.
func providerTier(snapshot: WidgetSnapshot?, selectedProviderId: String?) -> WidgetDesignToken.Aurora.Tier {
    let provider = snapshot.flatMap {
        resolvedProvider(snapshot: $0, selectedProviderId: selectedProviderId)
    }
    let used = provider.flatMap { primaryWindow(of: $0) }?.usedPercent ?? WidgetDesignToken.zeroDouble
    return WidgetDesignToken.Aurora.tier(forUsedPercent: used)
}

/// Tier for a multi-provider widget: worst short-window usage across providers.
func overviewTier(snapshot: WidgetSnapshot?) -> WidgetDesignToken.Aurora.Tier {
    let peak = snapshot?.providers
        .compactMap { primaryWindow(of: $0) }
        .map { $0.usedPercent }
        .max() ?? WidgetDesignToken.zeroDouble
    return WidgetDesignToken.Aurora.tier(forUsedPercent: peak)
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
        case ready
        case stale
        case noFile
        case corrupt
        case placeholder
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

    func logConfiguration(selectedProviderId: String?, phase: String) {
        WidgetLogger.provider.notice(
            "\(phase, privacy: .public) kind=\(Self.kind.rawValue, privacy: .public) selectedProvider=\(selectedProviderId ?? "automatic", privacy: .public)"
        )
    }

    func placeholderEntry() -> TokenKingEntry {
        // The widget gallery renders this synchronously and may retain the
        // result while the user is editing widgets. It must therefore be a
        // complete card, rather than a transient "updating" state. Timeline
        // and snapshot requests still replace this fixture with live data.
        TokenKingEntry(
            date: .now,
            kind: Self.kind,
            selectedProviderId: nil,
            snapshot: .previewFixture,
            readStatus: .ready,
            snapshotAgeSeconds: 0
        )
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
            let status: TokenKingEntry.ReadStatus = .ready
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
            let status: TokenKingEntry.ReadStatus = age > Self.staleThreshold ? .stale : .ready
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

    func placeholder(in context: Context) -> TokenKingEntry {
        placeholderEntry()
    }

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> TokenKingEntry {
        let selectedProviderId = configuration.provider
        logConfiguration(selectedProviderId: selectedProviderId, phase: "snapshot")
        return await readEntryHTTPFirst(selectedProviderId: selectedProviderId)
    }

    func timeline(for configuration: ProviderSelectionIntent, in context: Context) async -> Timeline<TokenKingEntry> {
        let selectedProviderId = configuration.provider
        logConfiguration(selectedProviderId: selectedProviderId, phase: "timeline")
        return await makeTimelineHTTPFirst(selectedProviderId: selectedProviderId)
    }
}

/// Provider for the configurable medium detail widget.
struct MediumDetailProvider: BaseTokenKingProvider, AppIntentTimelineProvider {
    static let kind: TokenKingWidgetKind = .mediumDetail
    typealias Intent = ProviderSelectionIntent
    typealias Entry = TokenKingEntry

    func placeholder(in context: Context) -> TokenKingEntry {
        placeholderEntry()
    }

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> TokenKingEntry {
        let selectedProviderId = configuration.provider
        logConfiguration(selectedProviderId: selectedProviderId, phase: "snapshot")
        return await readEntryHTTPFirst(selectedProviderId: selectedProviderId)
    }

    func timeline(for configuration: ProviderSelectionIntent, in context: Context) async -> Timeline<TokenKingEntry> {
        let selectedProviderId = configuration.provider
        logConfiguration(selectedProviderId: selectedProviderId, phase: "timeline")
        return await makeTimelineHTTPFirst(selectedProviderId: selectedProviderId)
    }
}

/// Provider for the configurable large detail widget.
struct LargeDetailProvider: BaseTokenKingProvider, AppIntentTimelineProvider {
    static let kind: TokenKingWidgetKind = .largeDetail
    typealias Intent = ProviderSelectionIntent
    typealias Entry = TokenKingEntry

    func placeholder(in context: Context) -> TokenKingEntry {
        placeholderEntry()
    }

    func snapshot(for configuration: ProviderSelectionIntent, in context: Context) async -> TokenKingEntry {
        let selectedProviderId = configuration.provider
        logConfiguration(selectedProviderId: selectedProviderId, phase: "snapshot")
        return await readEntryHTTPFirst(selectedProviderId: selectedProviderId)
    }

    func timeline(for configuration: ProviderSelectionIntent, in context: Context) async -> Timeline<TokenKingEntry> {
        let selectedProviderId = configuration.provider
        logConfiguration(selectedProviderId: selectedProviderId, phase: "timeline")
        return await makeTimelineHTTPFirst(selectedProviderId: selectedProviderId)
    }
}

/// Unified Codex provider shared by all supported WidgetKit families.
struct CodexQuotaTimelineProvider: BaseTokenKingProvider, AppIntentTimelineProvider {
    static let kind: TokenKingWidgetKind = .small
    typealias Intent = CodexAccountSelectionIntent
    typealias Entry = TokenKingEntry

    func placeholder(in context: Context) -> TokenKingEntry {
        placeholderEntry()
    }

    func snapshot(for configuration: CodexAccountSelectionIntent, in context: Context) async -> TokenKingEntry {
        await readEntryHTTPFirst(selectedProviderId: configuration.account)
    }

    func timeline(for configuration: CodexAccountSelectionIntent, in context: Context) async -> Timeline<TokenKingEntry> {
        await makeTimelineHTTPFirst(selectedProviderId: configuration.account)
    }
}

// MARK: - Static providers

/// Provider for the medium multi-provider overview widget.
struct MediumOverviewProvider: BaseTokenKingProvider, TimelineProvider {
    static let kind: TokenKingWidgetKind = .mediumOverview
    typealias Entry = TokenKingEntry

    func placeholder(in context: Context) -> TokenKingEntry {
        placeholderEntry()
    }

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

    func placeholder(in context: Context) -> TokenKingEntry {
        placeholderEntry()
    }

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

    func placeholder(in context: Context) -> TokenKingEntry {
        placeholderEntry()
    }

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
        case .ready: return "ok"
        case .stale: return "stale"
        case .noFile: return "noFile"
        case .corrupt: return "corrupt"
        case .placeholder: return "placeholder"
        }
    }
}
