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
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Token King")
        .description("AI provider usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
