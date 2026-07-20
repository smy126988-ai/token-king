import AppIntents
import WidgetKit

/// Pins a Codex account to one widget instance when the user has more than one.
struct CodexAccountSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Codex Account"
    static var description = IntentDescription("Choose the Codex account to display.")

    @Parameter(title: "Account", optionsProvider: CodexAccountOptionsProvider())
    var account: String?

    init() {}
}
