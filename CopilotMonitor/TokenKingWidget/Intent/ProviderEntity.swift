import AppIntents
import Foundation
import WidgetKit

/// AppEntity representing a single AI provider that the user can select
/// when configuring a Token King widget.
///
/// The entity is backed by `ProviderSnapshot` from the latest widget snapshot.
/// `ProviderQuery` dynamically populates the picker from the on-disk snapshot
/// so the list stays in sync with the main app without a hardcoded registry.
struct ProviderEntity: AppEntity {
    /// Stable identifier matching `ProviderSnapshot.id`.
    let id: String

    /// Human-readable name shown in the configuration picker.
    let displayName: String

    /// Required type identifier for WidgetKit configuration intents.
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Provider"

    /// How the selected provider appears in the widget configuration UI.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: displayName))
    }

    /// Default query used by the intent parameter picker.
    static var defaultQuery = ProviderQuery()
}

// MARK: - Conversion

extension ProviderEntity {
    /// Create an entity from a decoded provider snapshot.
    init(snapshot: ProviderSnapshot) {
        self.id = snapshot.id
        self.displayName = snapshot.displayName
    }
}

// MARK: - Query

/// EntityQuery that reads the current widget snapshot and returns all
/// providers in display order. Falls back to an empty list when the snapshot
/// file is missing or cannot be decoded, matching `TokenKingProvider.readEntry()`.
struct ProviderQuery: EntityQuery {
    func entities(for identifiers: [ProviderEntity.ID]) async throws -> [ProviderEntity] {
        allProviders().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ProviderEntity] {
        allProviders()
    }

    /// Read the snapshot from disk and map every provider to an entity.
    /// Returns an empty array on missing file or decode failure so the picker
    /// never crashes while the main app is still generating its first snapshot.
    private func allProviders() -> [ProviderEntity] {
        let url = SharedPaths.snapshotURL
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            WidgetLogger.provider.warning("ProviderQuery snapshot file does not exist at \(url.path, privacy: .public)")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(WidgetSnapshot.self, from: data)
            return snapshot.providers.map { ProviderEntity(snapshot: $0) }
        } catch {
            WidgetLogger.provider.error("ProviderQuery decode failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
