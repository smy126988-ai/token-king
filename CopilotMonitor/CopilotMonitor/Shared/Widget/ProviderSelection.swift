import Foundation

/// The result of resolving a provider selection for a widget configuration.
///
/// An explicit selection is intentionally strict: if its id is not present in
/// the snapshot, the result stays empty instead of silently falling back to a
/// different provider. Automatic mode uses the highest-usage available
/// provider, matching the widget's existing zero-configuration behaviour.
struct ProviderSelectionResult: Equatable {
    let provider: ProviderSnapshot?
    let selectedProviderId: String?
    let source: Source

    enum Source: Equatable {
        case explicit
        case automatic
    }

    var isAutomatic: Bool {
        source == .automatic
    }
}

enum ProviderSelectionResolver {
    /// Resolves a configured provider id or, when no id is configured, the
    /// highest-usage provider that is not unavailable.
    static func selectProvider(
        _ snapshot: WidgetSnapshot,
        selectedProviderId: String?
    ) -> ProviderSelectionResult {
        if let selectedProviderId {
            return ProviderSelectionResult(
                provider: snapshot.providers.first { $0.id == selectedProviderId },
                selectedProviderId: selectedProviderId,
                source: .explicit
            )
        }

        let provider = snapshot.providers
            .compactMap { provider -> (ProviderSnapshot, Double)? in
                guard provider.status != .unavailable,
                      let window = primaryWindow(of: provider) else {
                    return nil
                }
                return (provider, window.usedPercent)
            }
            .max { left, right in
                if left.1 == right.1 {
                    return left.0.id.localizedCaseInsensitiveCompare(right.0.id) == .orderedDescending
                }
                return left.1 < right.1
            }?.0

        return ProviderSelectionResult(
            provider: provider,
            selectedProviderId: nil,
            source: .automatic
        )
    }

    private static func primaryWindow(of provider: ProviderSnapshot) -> UsageWindow? {
        if let id = provider.primaryWindowId,
           let window = provider.windows.first(where: { $0.id == id }) {
            return window
        }
        return provider.windows.first
    }
}
