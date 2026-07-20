import AppIntents
import WidgetKit

/// User-configurable intent that selects a single AI provider for detail widgets.
///
/// The picker reads display names from the current snapshot while persisting
/// the provider's stable id directly, keeping the timeline independent from
/// AppEntity registration caches.
struct ProviderSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Provider"
    static var description = IntentDescription("Choose a provider to display in the widget.")

    @Parameter(title: "Provider", optionsProvider: ProviderOptionsProvider())
    var provider: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$provider)")
    }

    init() {}
}
