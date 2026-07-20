import AppIntents
import Foundation

/// Dynamic provider choices backed by the current snapshot.
///
/// The intent stores the stable provider id as a plain string. This avoids an
/// AppEntity restoration failure turning a valid saved choice into `nil` and
/// silently falling back to the highest-usage provider.
struct ProviderOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        let choices = await allChoices()
        let items = choices.map { choice in
            IntentItem(
                choice.id,
                title: LocalizedStringResource(stringLiteral: choice.displayName)
            )
        }
        WidgetLogger.provider.notice("ProviderOptionsProvider returned \(items.count) choices")
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }

    private func allChoices() async -> [ProviderChoice] {
        guard let snapshot = await WidgetSnapshotReader.currentSnapshotHTTPFirst() else {
            WidgetLogger.provider.warning("ProviderOptionsProvider could not read the current snapshot")
            return [.chatGPT]
        }

        var choices = snapshot.providers.map {
            ProviderChoice(id: $0.id, displayName: $0.displayName)
        }
        if !choices.contains(where: { $0.id == WidgetDesignToken.ProviderID.codex }) {
            choices.insert(.chatGPT, at: choices.startIndex)
        }
        return choices
    }
}

private struct ProviderChoice {
    let id: String
    let displayName: String

    static let chatGPT = ProviderChoice(
        id: WidgetDesignToken.ProviderID.codex,
        displayName: "ChatGPT"
    )
}
