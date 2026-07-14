import WidgetKit
import SwiftUI

@main
struct TokenKingWidgetBundle: WidgetBundle {
    var body: some Widget {
        TokenKingWidget()
    }
}

struct TokenKingWidget: Widget {
    let kind = "TokenKingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TokenKingProvider()) { entry in
            TokenKingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    AuroraBackgroundView()
                }
        }
        .configurationDisplayName("Token King")
        .description("AI provider usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
            focalRadial
            if colorScheme == .light {
                centerRadial
            }
            // Glass veil — `ultraThinMaterial` adapts to the colour scheme
            // and gives the same "frosted" feel as the prototype's
            // `rgba(255,255,255,0.24)` / `rgba(28,30,36,0.30)` overlays.
            Rectangle()
                .fill(.ultraThinMaterial)
        }
    }

    private var palette: [Color] {
        colorScheme == .dark
            ? WidgetDesignToken.Aurora.dark
            : WidgetDesignToken.Aurora.light
    }

    private var focalColor: Color {
        colorScheme == .dark
            ? WidgetDesignToken.Aurora.darkFocal
            : WidgetDesignToken.Aurora.lightFocal
    }

    private var baseLinear: some View {
        LinearGradient(
            colors: palette,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var focalRadial: some View {
        RadialGradient(
            colors: [focalColor.opacity(0.65), focalColor.opacity(0)],
            center: .topLeading,
            startRadius: 8,
            endRadius: 200
        )
        .blendMode(.plusLighter)
    }

    private var centerRadial: some View {
        RadialGradient(
            colors: [palette[2].opacity(0.55), palette[2].opacity(0)],
            center: .center,
            startRadius: 20,
            endRadius: 180
        )
        .blendMode(.plusLighter)
    }
}

// MARK: - TimelineEntry

struct TokenKingEntry: TimelineEntry {
    let date: Date
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

// MARK: - Provider

struct TokenKingProvider: TimelineProvider {
    /// 90 minutes — system throttles to 15-60min anyway.
    static let staleThreshold: TimeInterval = 90 * 60

    func placeholder(in context: Context) -> TokenKingEntry {
        TokenKingEntry(date: Date(), snapshot: nil, readStatus: .noFile, snapshotAgeSeconds: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (TokenKingEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TokenKingEntry>) -> Void) {
        let entry = readEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        WidgetLogger.provider.debug("timeline next=\(nextRefresh, privacy: .public) status=\(entry.readStatus.rawValueString, privacy: .public)")
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func readEntry() -> TokenKingEntry {
        let url = SharedPaths.snapshotURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            WidgetLogger.provider.warning("snapshot file does not exist at \(url.path, privacy: .public)")
            return TokenKingEntry(date: Date(), snapshot: nil, readStatus: .noFile, snapshotAgeSeconds: nil)
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)

            let age = Date().timeIntervalSince(snapshot.snapshotAt)
            let status: TokenKingEntry.ReadStatus = age > Self.staleThreshold ? .stale : .ok
            WidgetLogger.provider.notice("read snapshot v\(snapshot.version) providers=\(snapshot.providers.count) ageSec=\(Int(age), privacy: .public) status=\(status.rawValueString, privacy: .public)")

            return TokenKingEntry(date: Date(), snapshot: snapshot, readStatus: status, snapshotAgeSeconds: age)
        } catch {
            WidgetLogger.provider.error("decode failed: \(error.localizedDescription, privacy: .public)")
            return TokenKingEntry(date: Date(), snapshot: nil, readStatus: .corrupt, snapshotAgeSeconds: nil)
        }
    }
}

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
