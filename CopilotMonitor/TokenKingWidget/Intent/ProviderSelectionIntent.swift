import AppIntents
import WidgetKit

/// User-configurable intent that selects a single AI provider for detail widgets.
///
/// This placeholder is registered with `AppIntentConfiguration` in
/// `TokenKingWidget.swift`. The picker is backed by `ProviderEntity` and
/// `ProviderQuery`, which read the current widget snapshot so the list stays in
/// sync with the main app. A follow-up agent may refine the parameter set and
/// default selection behavior.
struct ProviderSelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Provider"
    static var description = IntentDescription("Choose a provider to display in the widget.")

    @Parameter(title: "Provider")
    var provider: ProviderEntity?

    init() {}
}
