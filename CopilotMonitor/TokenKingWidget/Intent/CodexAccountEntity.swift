import AppIntents
import Foundation

/// Dynamic Codex account choices that persist only the account's opaque id.
struct CodexAccountOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> IntentItemCollection<String> {
        let accounts = await allAccounts()
        let items = accounts.map { account in
            IntentItem(
                account.id,
                title: LocalizedStringResource(stringLiteral: account.displayName),
                subtitle: account.plan.map { LocalizedStringResource(stringLiteral: $0) }
            )
        }
        WidgetLogger.provider.notice("CodexAccountOptionsProvider returned \(items.count) choices")
        return IntentItemCollection(sections: [IntentItemSection(items: items)])
    }

    private func allAccounts() async -> [ProviderAccountSnapshot] {
        guard let snapshot = await WidgetSnapshotReader.currentSnapshotHTTPFirst() else {
            WidgetLogger.provider.warning("CodexAccountOptionsProvider could not read the current snapshot")
            return []
        }
        let codex = snapshot.providers.first { $0.id == WidgetDesignToken.ProviderID.codex }
        return codex?.accounts ?? []
    }
}
