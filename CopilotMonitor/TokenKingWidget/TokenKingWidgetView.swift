import SwiftUI
import WidgetKit

// MARK: - Top-level dispatcher

struct TokenKingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TokenKingEntry

    var body: some View {
        // P2 V3: card corner radius + inner padding aligned with prototype.
        // The `containerBackground` AuroraBackgroundView provides the
        // gradient underneath, the rounded `background(.clear)` here lets
        // the aurora show through while keeping content inside the corners.
        ZStack {
            RoundedRectangle(cornerRadius: WidgetDesignToken.cardCornerRadius, style: .continuous)
                .strokeBorder(.tertiary.opacity(0.5), lineWidth: 0.5)
            innerContent
                .padding(12)
        }
        .background(
            RoundedRectangle(cornerRadius: WidgetDesignToken.cardCornerRadius, style: .continuous)
                .fill(Color.clear)
        )
    }

    @ViewBuilder
    private var innerContent: some View {
        switch entry.readStatus {
        case .noFile:
            EmptyStateView(message: "Open Token King to populate")
        case .corrupt:
            EmptyStateView(message: "Snapshot corrupt", detail: entry.date.formatted(.dateTime))
        case .stale:
            if let snapshot = entry.snapshot, let age = entry.snapshotAgeSeconds {
                VStack(spacing: WidgetDesignToken.smallGap) {
                    StaleBadge(ageSeconds: age)
                    content(for: snapshot, family: family)
                }
            } else {
                EmptyStateView(message: "Stale data unavailable")
            }
        case .ok:
            if let snapshot = entry.snapshot {
                content(for: snapshot, family: family)
            } else {
                EmptyStateView(message: "No data")
            }
        }
    }

    @ViewBuilder
    private func content(for snapshot: WidgetSnapshot, family: WidgetFamily) -> some View {
        switch family {
        case .systemSmall:
            SmallFamilyView(snapshot: snapshot)
        case .systemMedium:
            MediumFamilyView(snapshot: snapshot)
        case .systemLarge:
            LargeFamilyView(snapshot: snapshot)
        default:
            MediumFamilyView(snapshot: snapshot)
        }
    }
}

// MARK: - Empty state + stale badge

struct EmptyStateView: View {
    let message: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: WidgetDesignToken.smallGap) {
            Image(systemName: "questionmark.circle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: WidgetDesignToken.bodySize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let detail = detail {
                Text(detail)
                    .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StaleBadge: View {
    let ageSeconds: Double

    var body: some View {
        HStack(spacing: WidgetDesignToken.smallGap) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: WidgetDesignToken.captionSize))
            Text("Stale \(Int(ageSeconds / 60))m")
                .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
        }
        .foregroundStyle(WidgetDesignToken.warningColor)
    }
}

// MARK: - Small family

struct SmallFamilyView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if let provider = topProvider(snapshot: snapshot),
           let window = primaryWindow(of: provider) {
            VStack(spacing: WidgetDesignToken.rowGap) {
                ZStack {
                    Circle()
                        .stroke(.tertiary, lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: min(window.usedPercent, 100) / 100)
                        .stroke(window.usedPercent.severityColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    // P2 V3: brand icon centred inside the ring, per prototype.
                    ProviderIconView(providerId: provider.id, size: 22)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 0) {
                    Text("\(Int(window.usedPercent.rounded()))% Used")
                        .font(.system(size: WidgetDesignToken.percentSize, weight: .semibold, design: .monospaced))
                    if let resets = window.resetsAt {
                        Text(RelativeResetFormatter.string(from: resets))
                            .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(provider.displayName)
                    .font(.system(size: WidgetDesignToken.bodySize, weight: .semibold))
                    .lineLimit(1)
            }
        } else {
            EmptyStateView(message: "No providers")
        }
    }
}

// MARK: - Medium family

struct MediumFamilyView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let visible = topN(snapshot: snapshot, n: 5)
        let hidden = max(0, snapshot.providers.count - visible.count)

        VStack(alignment: .leading, spacing: WidgetDesignToken.rowGap) {
            ForEach(visible, id: \.id) { provider in
                ProviderRow(provider: provider, compact: true)
            }
            if hidden > 0 {
                Text("+\(hidden) more")
                    .font(.system(size: WidgetDesignToken.captionSize))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large family

struct LargeFamilyView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let visible = topN(snapshot: snapshot, n: 8)
        let hidden = max(0, snapshot.providers.count - visible.count)

        VStack(alignment: .leading, spacing: WidgetDesignToken.sectionGap) {
            ForEach(visible, id: \.id) { provider in
                ProviderSection(provider: provider)
            }
            if hidden > 0 {
                Text("+\(hidden) more")
                    .font(.system(size: WidgetDesignToken.captionSize))
                    .foregroundStyle(.tertiary)
            }
            if let cost = snapshot.monthlyCost {
                MonthlyCostFooter(cost: cost)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Provider row / section

struct ProviderRow: View {
    let provider: ProviderSnapshot
    let compact: Bool

    var body: some View {
        if provider.kind == .usage, let spend = provider.spendUSD {
            HStack(spacing: WidgetDesignToken.smallGap) {
                ProviderIconView(providerId: provider.id, size: WidgetDesignToken.iconSize)
                    .font(.system(size: WidgetDesignToken.iconSize))
                    .foregroundStyle(.secondary)
                Text(provider.displayName)
                    .font(.system(size: WidgetDesignToken.bodySize))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(USDFormatter.string(from: spend)) spent")
                    .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        } else if let window = primaryWindow(of: provider) {
            HStack(spacing: WidgetDesignToken.smallGap) {
                ProviderIconView(providerId: provider.id, size: WidgetDesignToken.iconSize)
                    .font(.system(size: WidgetDesignToken.iconSize))
                    .foregroundStyle(.secondary)
                Text(provider.displayName)
                    .font(.system(size: WidgetDesignToken.bodySize))
                    .lineLimit(1)
                    .frame(width: 70, alignment: .leading)
                if !compact {
                    Text(window.label)
                        .font(.system(size: WidgetDesignToken.captionSize))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                }
                ProgressView(value: min(window.usedPercent, 100), total: 100)
                    .tint(window.usedPercent.severityColor)
                Text("\(Int(window.usedPercent.rounded()))% Used")
                    .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 50, alignment: .trailing)
            }
        }
    }
}

struct ProviderSection: View {
    let provider: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
            HStack(spacing: WidgetDesignToken.smallGap) {
                ProviderIconView(providerId: provider.id, size: WidgetDesignToken.iconSize)
                    .font(.system(size: WidgetDesignToken.iconSize))
                    .foregroundStyle(.secondary)
                Text(provider.displayName)
                    .font(.system(size: WidgetDesignToken.bodySize, weight: .semibold))
            }
            ForEach(provider.windows, id: \.id) { window in
                if provider.kind == .usage {
                    HStack {
                        Text(window.label)
                            .font(.system(size: WidgetDesignToken.captionSize))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(window.usedPercent.rounded()))% used")
                            .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                    }
                } else {
                    HStack(spacing: WidgetDesignToken.smallGap) {
                        Text(window.label)
                            .font(.system(size: WidgetDesignToken.captionSize))
                            .frame(width: 50, alignment: .leading)
                        ProgressView(value: min(window.usedPercent, 100), total: 100)
                            .tint(window.usedPercent.severityColor)
                        Text("\(Int(window.usedPercent.rounded()))%")
                            .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                }
            }
        }
    }
}

struct MonthlyCostFooter: View {
    let cost: MonthlyCost

    var body: some View {
        HStack {
            Text("Monthly")
                .font(.system(size: WidgetDesignToken.captionSize))
                .foregroundStyle(.secondary)
            Spacer()
            Text(USDFormatter.string(from: cost.usd))
                .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                .foregroundStyle(.secondary)
            if let rmb = cost.rmb {
                Text("/ ¥\(String(format: "%.2f", rmb))")
                    .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Helpers

func topProvider(snapshot: WidgetSnapshot) -> ProviderSnapshot? {
    snapshot.providers
        .compactMap { p -> (ProviderSnapshot, Double)? in
            guard let w = primaryWindow(of: p) else { return nil }
            return (p, w.usedPercent)
        }
        .max(by: { $0.1 < $1.1 })?.0
}

func topN(snapshot: WidgetSnapshot, n: Int) -> [ProviderSnapshot] {
    let sorted = snapshot.providers.sorted { p1, p2 in
        (primaryWindow(of: p1)?.usedPercent ?? 0) > (primaryWindow(of: p2)?.usedPercent ?? 0)
    }
    return Array(sorted.prefix(n))
}

func primaryWindow(of provider: ProviderSnapshot) -> UsageWindow? {
    if let id = provider.primaryWindowId,
       let w = provider.windows.first(where: { $0.id == id }) {
        return w
    }
    return provider.windows.first
}

func providerIcon(_ id: String) -> String {
    switch id {
    case "claude":      return "sparkles"
    case "codex":       return "chevron.left.forwardslash.chevron.right"
    case "copilot":     return "person.crop.circle.badge.checkmark"
    case "openrouter":  return "arrow.triangle.branch"
    case "gemini_cli":  return "sparkle"
    case "kiro":        return "terminal"
    case "antigravity": return "airplane"
    case "opencode_zen": return "cube"
    default:            return "gauge.medium"
    }
}

// MARK: - Provider icon view (brand + SF Symbol fallback)

/// Brand icon if the provider has a matching prototype asset; otherwise a
/// generic SF Symbol. Tinted with the brand colour when available, falling
/// back to the secondary text colour so non-selected / vibrant modes still
/// pick up the system de-saturation automatically.
struct ProviderIconView: View {
    let providerId: String
    let size: CGFloat

    var body: some View {
        if let kind = ProviderBrandIcon.Kind.from(providerId: providerId) {
            ProviderBrandIcon(kind: kind)
                .frame(width: size, height: size)
                .foregroundStyle(kind.brandColor ?? .secondary)
        } else {
            Image(systemName: providerIconSystemName(providerId))
                .font(.system(size: size))
                .foregroundStyle(.secondary)
        }
    }
}
