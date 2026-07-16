import SwiftUI
import WidgetKit

// MARK: - Top-level dispatcher

struct TokenKingWidgetView: View {
    let entry: TokenKingEntry

    var body: some View {
        // The aurora background is a light gradient in both appearances, so pin
        // content to the light colour scheme — Ink.primary/secondary then resolve
        // to the dark ink that reads on the gradient (matches quota-float's
        // light-card / dark-text pairing). The system still handles vibrant.
        innerContent
            .environment(\.colorScheme, .light)
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
                    content(for: snapshot, kind: entry.kind)
                }
            } else {
                EmptyStateView(message: "Stale data unavailable")
            }
        case .ok:
            if let snapshot = entry.snapshot {
                content(for: snapshot, kind: entry.kind)
            } else {
                EmptyStateView(message: "No data")
            }
        }
    }

    @ViewBuilder
    private func content(for snapshot: WidgetSnapshot, kind: TokenKingWidgetKind) -> some View {
        switch kind {
        case .small:
            SmallWidgetView(snapshot: snapshot, selectedProviderId: entry.selectedProviderId)
        case .mediumOverview:
            MediumOverviewView(snapshot: snapshot)
        case .mediumDetail:
            MediumDetailView(snapshot: snapshot, selectedProviderId: entry.selectedProviderId)
        case .largeOverview:
            LargeOverviewView(snapshot: snapshot)
        case .largeDetail:
            LargeDetailView(snapshot: snapshot, selectedProviderId: entry.selectedProviderId)
        case .searchEngines:
            SearchEnginesView(snapshot: snapshot)
        }
    }
}

// MARK: - Empty state + stale badge

struct EmptyStateView: View {
    @Environment(\.colorScheme) private var scheme
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
    @Environment(\.colorScheme) private var scheme
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

// MARK: - Small widget

struct SmallWidgetView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot
    let selectedProviderId: String?

    var body: some View {
        let provider = selectedProvider(snapshot: snapshot, selectedProviderId: selectedProviderId)
            ?? topProvider(snapshot: snapshot)

        if let provider = provider {
            VStack(spacing: WidgetDesignToken.rowGap) {
                if provider.kind == .usage, let spend = provider.spendUSD {
                    // Usage-based provider: brand icon + big spend + name
                    ProviderIconView(providerId: provider.id, size: WidgetDesignToken.ringIconSize)
                        .widgetAccentable()
                    Text(USDFormatter.string(from: spend))
                        .font(.system(size: WidgetDesignToken.percentBigSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(WidgetDesignToken.Ink.primary(scheme))
                    Text("spent")
                        .font(.system(size: WidgetDesignToken.captionSize))
                        .foregroundStyle(WidgetDesignToken.Ink.secondary(scheme))
                } else if let window = primaryWindow(of: provider) {
                    RingGauge(
                        percent: window.usedPercent,
                        content: {
                            ProviderIconView(providerId: provider.id, size: WidgetDesignToken.ringIconSize)
                        }
                    )
                    .widgetAccentable()

                    VStack(spacing: WidgetDesignToken.zeroSpacing) {
                        Text("\(Int(window.usedPercent.rounded()))%")
                            .font(.system(size: WidgetDesignToken.percentRingSize, weight: .semibold, design: .monospaced))
                            .foregroundStyle(WidgetDesignToken.Ink.primary(scheme))
                    }
                } else {
                    ProviderIconView(providerId: provider.id, size: WidgetDesignToken.ringIconSize)
                        .widgetAccentable()
                    Text(provider.displayName)
                        .font(.system(size: WidgetDesignToken.captionSize))
                        .foregroundStyle(WidgetDesignToken.Ink.faint(scheme))
                        .lineLimit(WidgetDesignToken.singleLine)
                }

                Text(provider.displayName)
                    .font(.system(size: WidgetDesignToken.captionSize))
                    .foregroundStyle(WidgetDesignToken.Ink.faint(scheme))
                    .lineLimit(WidgetDesignToken.singleLine)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(message: "No providers")
        }
    }
}

func selectedProvider(snapshot: WidgetSnapshot, selectedProviderId: String?) -> ProviderSnapshot? {
    guard let id = selectedProviderId else { return nil }
    return snapshot.providers.first { $0.id == id }
}

// MARK: - Ring gauge

struct RingGauge<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let percent: Double
    let content: () -> Content

    var body: some View {
        ZStack {
            Circle()
                .stroke(WidgetDesignToken.Ink.faint(scheme).opacity(WidgetDesignToken.trackOpacity), lineWidth: WidgetDesignToken.ringStroke)
            Circle()
                .trim(from: WidgetDesignToken.ringStart, to: min(percent, WidgetDesignToken.percentMax) / WidgetDesignToken.percentMax)
                .stroke(percent.severityColor(scheme), style: StrokeStyle(lineWidth: WidgetDesignToken.ringStroke, lineCap: .round))
                .rotationEffect(.degrees(WidgetDesignToken.ringRotation))
            content()
        }
        .frame(width: WidgetDesignToken.ringDiameter, height: WidgetDesignToken.ringDiameter)
    }
}

// MARK: - Medium overview widget

struct MediumOverviewView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot

    var body: some View {
        let visible = topN(snapshot: snapshot, n: WidgetDesignToken.mediumVisibleCount)

        VStack(alignment: .leading, spacing: WidgetDesignToken.rowGap) {
            ForEach(visible, id: \.id) { provider in
                MediumProviderCard(provider: provider, fetchedAt: provider.fetchedAt ?? Date())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium detail widget

struct MediumDetailView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot
    let selectedProviderId: String?

    var body: some View {
        let provider = selectedProvider(snapshot: snapshot, selectedProviderId: selectedProviderId)
            ?? topProvider(snapshot: snapshot)

        if let provider = provider {
            MediumProviderCard(provider: provider, fetchedAt: provider.fetchedAt ?? Date())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            EmptyStateView(message: "No providers")
        }
    }
}

struct MediumProviderCard: View {
    @Environment(\.colorScheme) private var scheme
    let provider: ProviderSnapshot
    let fetchedAt: Date

    private var statusColor: Color {
        if let window = primaryWindow(of: provider) {
            return window.usedPercent.severityColor(scheme)
        }
        return WidgetDesignToken.healthyColor
    }

    private var fetchedAtString: String {
        fetchedAt.formatted(
            .dateTime
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
            .second(.twoDigits)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.rowGap) {
            // Header: icon + name + badge
            HStack(spacing: WidgetDesignToken.smallGap) {
                StatusDot(color: statusColor)
                ProviderIconView(providerId: provider.id, size: WidgetDesignToken.mediumIconSize)
                    .widgetAccentable()
                Text(provider.displayName)
                    .font(.system(size: WidgetDesignToken.wNameSize, weight: .semibold))
                    .foregroundStyle(WidgetDesignToken.Ink.primary(scheme))
                    .lineLimit(WidgetDesignToken.singleLine)
                Spacer(minLength: WidgetDesignToken.zeroLength)
                ProviderBadge(text: provider.kind == .usage ? "Usage" : "Quota")
            }

            // Body
            if provider.kind == .usage, let spend = provider.spendUSD {
                HStack(spacing: WidgetDesignToken.smallGap) {
                    Text(USDFormatter.string(from: spend))
                        .font(.system(size: WidgetDesignToken.percentBigSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(WidgetDesignToken.Ink.primary(scheme))
                    Text("spent")
                        .font(.system(size: WidgetDesignToken.captionSize))
                        .foregroundStyle(WidgetDesignToken.Ink.secondary(scheme))
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                }
            } else if let window = primaryWindow(of: provider) {
                if provider.windows.count == WidgetDesignToken.singleWindowCount,
                   let used = window.used, let limit = window.limit {
                    // Single-window quota: metric label + big number + progress bar
                    VStack(alignment: .leading, spacing: WidgetDesignToken.tinyGap) {
                        HStack(spacing: WidgetDesignToken.smallGap) {
                            Text(window.label)
                                .font(.system(size: WidgetDesignToken.mLabelSize, design: .monospaced))
                                .foregroundStyle(WidgetDesignToken.Ink.faint(scheme))
                                .textCase(.uppercase)
                            Spacer(minLength: WidgetDesignToken.zeroLength)
                        }
                        HStack(spacing: WidgetDesignToken.smallGap) {
                            Text(IntegerFormatter.string(from: used))
                                .font(.system(size: WidgetDesignToken.percentBigSize, weight: .bold, design: .monospaced))
                                .foregroundStyle(WidgetDesignToken.Ink.primary(scheme))
                            Text("/")
                                .font(.system(size: WidgetDesignToken.slashLimitSize, design: .monospaced))
                                .foregroundStyle(WidgetDesignToken.Ink.faint(scheme))
                            Text(IntegerFormatter.string(from: limit))
                                .font(.system(size: WidgetDesignToken.slashLimitSize, design: .monospaced))
                                .foregroundStyle(WidgetDesignToken.Ink.secondary(scheme))
                            Spacer(minLength: WidgetDesignToken.zeroLength)
                            Text("\(Int(window.usedPercent.rounded()))%")
                                .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                                .foregroundStyle(WidgetDesignToken.Ink.secondary(scheme))
                        }
                        CapsuleProgressBar(value: window.usedPercent)
                    }
                } else {
                    // Multi-window: rows per window. Zero-usage windows are
                    // collapsed — rows of "0%" bars carry no information.
                    // When every window is idle, show all so the card never
                    // renders empty.
                    let activeWindows = provider.windows.filter { $0.usedPercent > WidgetDesignToken.zeroDouble }
                    let visibleWindows = activeWindows.isEmpty ? provider.windows : activeWindows
                    VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
                        ForEach(visibleWindows, id: \.id) { window in
                            VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
                                HStack(spacing: WidgetDesignToken.smallGap) {
                                    windowLabelText(for: window)
                                        .font(.system(size: WidgetDesignToken.captionSize))
                                        .foregroundStyle(WidgetDesignToken.Ink.secondary(scheme))
                                    Spacer(minLength: WidgetDesignToken.zeroLength)
                                    if let resets = window.resetsAt {
                                        Text(RelativeResetFormatter.string(from: resets))
                                            .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                                            .foregroundStyle(WidgetDesignToken.Ink.faint(scheme))
                                    }
                                }
                                CapsuleProgressBar(value: window.usedPercent)
                            }
                        }
                    }
                }
            }

            // Footer
            HStack(spacing: WidgetDesignToken.smallGap) {
                Text("Updated \(fetchedAtString)")
                    .font(.system(size: WidgetDesignToken.footerSize, design: .monospaced))
                    .foregroundStyle(WidgetDesignToken.Ink.faint(scheme))
                Spacer(minLength: WidgetDesignToken.zeroLength)
                Text("Every 15 min")
                    .font(.system(size: WidgetDesignToken.footerSize, design: .monospaced))
                    .foregroundStyle(WidgetDesignToken.Ink.faint(scheme))
            }
        }
    }
}

struct ProviderBadge: View {
    @Environment(\.colorScheme) private var scheme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: WidgetDesignToken.portSize))
            .foregroundStyle(WidgetDesignToken.Ink.secondary(scheme))
            .padding(.horizontal, WidgetDesignToken.badgeHPadding)
            .padding(.vertical, WidgetDesignToken.badgeVPadding)
            .background(WidgetDesignToken.Ink.faint(scheme).opacity(WidgetDesignToken.badgeBackgroundOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: WidgetDesignToken.badgeRadius)
                    .stroke(WidgetDesignToken.Ink.faint(scheme).opacity(WidgetDesignToken.badgeStrokeOpacity), lineWidth: WidgetDesignToken.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: WidgetDesignToken.badgeRadius, style: .continuous))
    }
}

// MARK: - Large overview widget

struct LargeOverviewView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot

    var body: some View {
        let visible = topN(snapshot: snapshot, n: WidgetDesignToken.largeVisibleCount)
        let hidden = max(WidgetDesignToken.zeroInt, snapshot.providers.count - visible.count)

        VStack(alignment: .leading, spacing: WidgetDesignToken.sectionGap) {
            // Header
            HStack(spacing: WidgetDesignToken.smallGap) {
                Text("Token King")
                    .font(.system(size: WidgetDesignToken.wNameSize, weight: .semibold))
                    .foregroundStyle(WidgetDesignToken.Ink.primary(scheme))
                Spacer(minLength: WidgetDesignToken.zeroLength)
            }

            // Rows
            ForEach(visible, id: \.id) { provider in
                LargeProviderRow(provider: provider)
            }

            if hidden > WidgetDesignToken.zeroInt {
                Text("+\(hidden) more")
                    .font(.system(size: WidgetDesignToken.captionSize))
                    .foregroundStyle(WidgetDesignToken.Ink.faint(scheme))
            }

            if let cost = snapshot.monthlyCost {
                MonthlyCostFooter(cost: cost)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Large detail widget

struct LargeDetailView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot
    let selectedProviderId: String?

    var body: some View {
        let provider = selectedProvider(snapshot: snapshot, selectedProviderId: selectedProviderId)
            ?? topProvider(snapshot: snapshot)

        if let provider = provider {
            // Vertically centred: the large canvas left a dead empty band at
            // the bottom when content was pinned to the top.
            VStack(spacing: WidgetDesignToken.zeroLength) {
                Spacer(minLength: WidgetDesignToken.zeroLength)
                VStack(alignment: .leading, spacing: WidgetDesignToken.sectionGap) {
                    LargeProviderRow(provider: provider)
                    // Same zero-collapse rule as the medium card.
                    let activeWindows = provider.windows.filter { $0.usedPercent > WidgetDesignToken.zeroDouble }
                    let visibleWindows = activeWindows.isEmpty ? provider.windows : activeWindows
                    if visibleWindows.count > WidgetDesignToken.singleWindowCount {
                        VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
                            ForEach(visibleWindows, id: \.id) { window in
                                HStack(spacing: WidgetDesignToken.smallGap) {
                                    windowLabelText(for: window)
                                        .font(.system(size: WidgetDesignToken.captionSize))
                                        .foregroundStyle(WidgetDesignToken.Ink.secondary(scheme))
                                    Spacer(minLength: WidgetDesignToken.zeroLength)
                                    Text("\(Int(window.usedPercent.rounded()))%")
                                        .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                                        .foregroundStyle(WidgetDesignToken.Ink.secondary(scheme))
                                }
                                CapsuleProgressBar(value: window.usedPercent)
                            }
                        }
                    }
                }
                Spacer(minLength: WidgetDesignToken.zeroLength)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(message: "No providers")
        }
    }
}

// MARK: - Search engines widget

struct SearchEnginesView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot

    private var searchProviders: [ProviderSnapshot] {
        snapshot.providers.filter {
            $0.id == WidgetDesignToken.ProviderID.braveSearch ||
            $0.id == WidgetDesignToken.ProviderID.tavilySearch
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.sectionGap) {
            HStack(spacing: WidgetDesignToken.smallGap) {
                Text("Search Engines")
                    .font(.system(size: WidgetDesignToken.wNameSize, weight: .semibold))
                    .foregroundStyle(WidgetDesignToken.Ink.primary(scheme))
                Spacer(minLength: WidgetDesignToken.zeroLength)
            }

            ForEach(searchProviders, id: \.id) { provider in
                LargeProviderRow(provider: provider)
            }

            if searchProviders.isEmpty {
                EmptyStateView(message: "No search engine data")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct LargeProviderRow: View {
    @Environment(\.colorScheme) private var scheme
    let provider: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.largeBarTopMargin) {
            HStack(spacing: WidgetDesignToken.largeRowGap) {
                StatusDot(color: statusColor)
                ProviderIconView(providerId: provider.id, size: WidgetDesignToken.largeIconSize)
                    .widgetAccentable()
                Text(provider.displayName)
                    .font(.system(size: WidgetDesignToken.bodySize, weight: .semibold))
                    .foregroundStyle(WidgetDesignToken.Ink.primary(scheme))
                    .lineLimit(WidgetDesignToken.singleLine)
                Spacer(minLength: WidgetDesignToken.zeroLength)
                Text(valueString)
                    .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                    .foregroundStyle(WidgetDesignToken.Ink.secondary(scheme))
            }
            CapsuleProgressBar(value: progressValue)
                .widgetAccentable()
        }
    }

    private var statusColor: Color {
        if let window = primaryWindow(of: provider) {
            return window.usedPercent.severityColor(scheme)
        }
        return WidgetDesignToken.healthyColor
    }

    private var progressValue: Double {
        if provider.kind == .usage {
            return WidgetDesignToken.zeroDouble
        }
        if provider.windows.count > WidgetDesignToken.singleWindowCount {
            return provider.windows.map(\.usedPercent).max() ?? WidgetDesignToken.zeroDouble
        }
        return primaryWindow(of: provider)?.usedPercent ?? WidgetDesignToken.zeroDouble
    }

    private var valueString: String {
        if provider.kind == .usage, let spend = provider.spendUSD {
            return "\(USDFormatter.string(from: spend)) spent"
        }
        guard let window = primaryWindow(of: provider) else {
            return ""
        }
        // Multi-window providers show only the primary window here; the full
        // "5h 25% · 7d 59%" chain was the main cause of name truncation.
        if provider.windows.count > WidgetDesignToken.singleWindowCount {
            return "\(window.label) \(Int(window.usedPercent.rounded()))%"
        }
        if let used = window.used, let limit = window.limit {
            return "\(IntegerFormatter.string(from: used))/\(abbreviatedLimit(limit)) · \(Int(window.usedPercent.rounded()))%"
        }
        return "\(Int(window.usedPercent.rounded()))%"
    }

    private func abbreviatedLimit(_ limit: Int) -> String {
        if limit >= 1000 {
            return "\(limit / 1000)k"
        }
        return IntegerFormatter.string(from: limit)
    }
}

struct MonthlyCostFooter: View {
    @Environment(\.colorScheme) private var scheme
    let cost: MonthlyCost

    var body: some View {
        HStack {
            Text("Monthly")
                .font(.system(size: WidgetDesignToken.captionSize))
                .foregroundStyle(WidgetDesignToken.Ink.secondary(scheme))
            Spacer(minLength: WidgetDesignToken.zeroLength)
            Text(USDFormatter.string(from: cost.usd))
                .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                .foregroundStyle(WidgetDesignToken.Ink.secondary(scheme))
            if let rmb = cost.rmb {
                Text("/ ¥\(String(format: "%.2f", rmb))")
                    .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                    .foregroundStyle(WidgetDesignToken.Ink.faint(scheme))
            }
        }
    }
}

// MARK: - Shared components

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: WidgetDesignToken.dotSize, height: WidgetDesignToken.dotSize)
    }
}

struct CapsuleProgressBar: View {
    @Environment(\.colorScheme) private var scheme
    let value: Double

    private var fraction: CGFloat {
        CGFloat(min(max(value, WidgetDesignToken.zeroDouble), WidgetDesignToken.percentMax) / WidgetDesignToken.percentMax)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: WidgetDesignToken.barRadius, style: .continuous)
                    .fill(WidgetDesignToken.Ink.faint(scheme).opacity(WidgetDesignToken.trackOpacity))
                RoundedRectangle(cornerRadius: WidgetDesignToken.barRadius, style: .continuous)
                    .fill(value.severityColor(scheme))
                    .frame(width: geometry.size.width * fraction, height: WidgetDesignToken.barHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: WidgetDesignToken.barHeight)
    }
}

struct ProviderIconView: View {
    let providerId: String
    let size: CGFloat

    var body: some View {
        if let assetName = providerAssetName(providerId) {
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(providerBrandTint(providerId) ?? .secondary)
        } else {
            Image(systemName: providerIconSystemName(providerId))
                .font(.system(size: size))
                .foregroundStyle(providerBrandTint(providerId) ?? .secondary)
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
        (primaryWindow(of: p1)?.usedPercent ?? WidgetDesignToken.zeroDouble) > (primaryWindow(of: p2)?.usedPercent ?? WidgetDesignToken.zeroDouble)
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

/// Label for a multi-window row. Shows "Label · used/limit" only when both
/// absolute values are available; otherwise just the label + percent.
func windowLabelText(for window: UsageWindow) -> Text {
    if let used = window.used, let limit = window.limit {
        return Text("\(window.label) · \(IntegerFormatter.string(from: used))/\(IntegerFormatter.string(from: limit))")
    }
    return Text("\(window.label) \(Int(window.usedPercent.rounded()))%")
}

func providerIconSystemName(_ providerId: String) -> String {
    switch providerId {
    case "copilot":            return "person.crop.circle.badge.checkmark"
    case "openrouter":         return "arrow.triangle.branch"
    case "gemini_cli":         return "sparkle"
    case "antigravity":        return "airplane"
    case "kiro":               return "terminal"
    case "brave_search":       return "magnifyingglass.circle"
    case "tavily_search":      return "magnifyingglass.circle"
    case "grok":               return "bolt"
    case "nano_gpt":           return "circle.grid.cross"
    case "synthetic":          return "atom"
    case "chutes":             return "arrow.down.circle"
    case "cursor":             return "arrow.up.forward.app"
    case "hunyuan":            return "globe.asia.australia.fill"
    case "zhipu_glm":          return "globe.asia.australia.fill"
    case "volcano_ark":        return "flame"
    case "opencode_go":        return "cube"
    case "command_code":       return "terminal"
    case "zhipuai":            return "globe.asia.australia.fill"
    case "minimax_cn", "minimax_global",
         "minimax_coding_plan_cn", "minimax_coding_plan_global",
         "xiaomimimo":          return "wand.and.stars"
    case "mimo":               return "wand.and.stars"
    case "claude":             return "sparkles"
    case "codex", "opencode_zen": return "chevron.left.forwardslash.chevron.right"
    case "kimi_cn", "kimi_global": return "globe.asia.australia.fill"
    case "zai_coding_plan":    return "chevron.left.forwardslash.chevron.right"
    default:                   return "gauge.medium"
    }
}

func providerAssetName(_ providerId: String) -> String? {
    switch providerId {
    case "copilot":                       return "CopilotIcon"
    case "claude":                        return "ClaudeIcon"
    case "codex":                         return "CodexIcon"
    case "cursor":                        return "CursorIcon"
    case "gemini_cli":                    return "GeminiIcon"
    case "open_code":                     return "OpencodeIcon"
    case "opencode_zen":                  return "OpencodeIcon"
    case "opencode_go":                   return "OpencodeIcon"
    case "kiro":                          return "KiroIcon"
    case "grok":                          return "GrokIcon"
    case "minimax_coding_plan",
         "minimax_coding_plan_cn",
         "minimax_cn",
         "minimax":                       return "MinimaxIcon"
    case "zai_coding_plan":               return "ZaiIcon"
    case "nano_gpt":                      return "NanoGptIcon"
    case "synthetic":                     return "SyntheticIcon"
    case "chutes":                        return "ChutesIcon"
    case "tavily_search":                 return "TavilyIcon"
    case "brave_search":                  return "BraveSearchIcon"
    case "antigravity":                   return "AntigravityIcon"
    default:                              return nil
    }
}

func providerBrandTint(_ providerId: String) -> Color? {
    switch providerId {
    case "claude":                  return WidgetDesignToken.Brand.claude
    case "kimi_cn", "kimi_global":  return WidgetDesignToken.Brand.kimi
    case "kiro":                    return WidgetDesignToken.Brand.kiro
    default:                        return nil
    }
}

// MARK: - Formatters

enum IntegerFormatter {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func string(from value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Preview fixture

extension WidgetSnapshot {
    static var previewFixture: WidgetSnapshot {
        let now = Date()
        func reset(_ h: Int) -> Date { now.addingTimeInterval(Double(h) * WidgetDesignToken.secondsPerHour) }
        return WidgetSnapshot(
            version: WidgetDesignToken.snapshotVersion,
            snapshotAt: now,
            providers: [
                ProviderSnapshot(id: "kimi_cn", displayName: "Kimi", kind: .quota,
                    primaryWindowId: "monthly",
                    windows: [UsageWindow(id: "monthly", label: "Monthly", usedPercent: WidgetDesignToken.fixtureKimiPercent,
                        resetsAt: reset(WidgetDesignToken.fixtureResetHours), used: 8700, limit: 10000)],
                    spendUSD: nil, fetchedAt: now),
                ProviderSnapshot(id: "codex", displayName: "Codex", kind: .quota,
                    primaryWindowId: "5h",
                    windows: [
                        UsageWindow(id: "5h", label: "5 hours", usedPercent: WidgetDesignToken.fixtureCodex5hPercent, resetsAt: reset(2), used: 38, limit: 150),
                        UsageWindow(id: "weekly", label: "Weekly", usedPercent: WidgetDesignToken.fixtureCodexWeeklyPercent, resetsAt: reset(72), used: 1180, limit: 2000)],
                    spendUSD: nil, fetchedAt: now),
                ProviderSnapshot(id: "claude", displayName: "Claude", kind: .quota,
                    primaryWindowId: "5h",
                    windows: [UsageWindow(id: "5h", label: "5 hours", usedPercent: WidgetDesignToken.fixtureClaudePercent, resetsAt: reset(3), used: 40, limit: 100)],
                    spendUSD: nil, fetchedAt: now),
                ProviderSnapshot(id: "kiro", displayName: "Kiro", kind: .quota,
                    primaryWindowId: "power",
                    windows: [UsageWindow(id: "power", label: "Credits", usedPercent: WidgetDesignToken.fixtureKiroPercent, resetsAt: reset(120), used: 2853, limit: 10000)],
                    spendUSD: nil, fetchedAt: now),
                ProviderSnapshot(id: "openrouter", displayName: "OpenRouter", kind: .usage,
                    primaryWindowId: nil, windows: [], spendUSD: 37.42, fetchedAt: now)
            ],
            monthlyCost: MonthlyCost(usd: 124.80, rmb: 892.30)
        )
    }
}

// MARK: - Previews

#Preview("Small/Light/Focused", as: .systemSmall) {
    TokenKingWidgetSmall()
} timeline: {
    TokenKingEntry(date: .now, kind: .small, selectedProviderId: nil, snapshot: .previewFixture, readStatus: .ok, snapshotAgeSeconds: 30)
}

#Preview("MediumOverview/Light/Focused", as: .systemMedium) {
    TokenKingWidgetMediumOverview()
} timeline: {
    TokenKingEntry(date: .now, kind: .mediumOverview, selectedProviderId: nil, snapshot: .previewFixture, readStatus: .ok, snapshotAgeSeconds: 30)
}

#Preview("MediumDetail/Light/Focused", as: .systemMedium) {
    TokenKingWidgetMediumDetail()
} timeline: {
    TokenKingEntry(date: .now, kind: .mediumDetail, selectedProviderId: "codex", snapshot: .previewFixture, readStatus: .ok, snapshotAgeSeconds: 30)
}

#Preview("LargeOverview/Light/Focused", as: .systemLarge) {
    TokenKingWidgetLargeOverview()
} timeline: {
    TokenKingEntry(date: .now, kind: .largeOverview, selectedProviderId: nil, snapshot: .previewFixture, readStatus: .ok, snapshotAgeSeconds: 30)
}

#Preview("LargeDetail/Light/Focused", as: .systemLarge) {
    TokenKingWidgetLargeDetail()
} timeline: {
    TokenKingEntry(date: .now, kind: .largeDetail, selectedProviderId: "codex", snapshot: .previewFixture, readStatus: .ok, snapshotAgeSeconds: 30)
}

#Preview("SearchEngines/Light/Focused", as: .systemLarge) {
    TokenKingWidgetSearchEngines()
} timeline: {
    TokenKingEntry(date: .now, kind: .searchEngines, selectedProviderId: nil, snapshot: .previewFixture, readStatus: .ok, snapshotAgeSeconds: 30)
}

#Preview("Small/UsageProvider", as: .systemSmall) {
    TokenKingWidgetSmall()
} timeline: {
    TokenKingEntry(date: .now, kind: .small, selectedProviderId: "openrouter", snapshot: .previewFixture, readStatus: .ok, snapshotAgeSeconds: 30)
}

#Preview("Small/Light/NoFile", as: .systemSmall) {
    TokenKingWidgetSmall()
} timeline: {
    TokenKingEntry(date: .now, kind: .small, selectedProviderId: nil, snapshot: nil, readStatus: .noFile, snapshotAgeSeconds: nil)
}

#Preview("Medium/Light/Empty", as: .systemMedium) {
    TokenKingWidgetMediumOverview()
} timeline: {
    TokenKingEntry(date: .now, kind: .mediumOverview, selectedProviderId: nil, snapshot: WidgetSnapshot(version: 1, snapshotAt: .now, providers: [], monthlyCost: nil), readStatus: .ok, snapshotAgeSeconds: 30)
}

#Preview("Large/Light/Stale", as: .systemLarge) {
    TokenKingWidgetLargeOverview()
} timeline: {
    TokenKingEntry(date: .now, kind: .largeOverview, selectedProviderId: nil, snapshot: .previewFixture, readStatus: .stale, snapshotAgeSeconds: 600)
}
