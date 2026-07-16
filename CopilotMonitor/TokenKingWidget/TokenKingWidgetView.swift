import SwiftUI
import WidgetKit

// MARK: - Top-level dispatcher

struct TokenKingWidgetView: View {
    let entry: TokenKingEntry

    var body: some View {
        // The aurora background is a light gradient in both appearances, so pin
        // content to the light colour scheme — AuroraInk.primary/secondary/faint
        // are the dark inks that read on the gradient (matches quota-float's
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
    let message: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: WidgetDesignToken.smallGap) {
            Image(systemName: "questionmark.circle")
                .font(.title2)
                .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
            Text(message)
                .font(.system(size: WidgetDesignToken.bodySize))
                .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                .multilineTextAlignment(.center)
            if let detail = detail {
                Text(detail)
                    .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                    .foregroundStyle(WidgetDesignToken.AuroraInk.faint)
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
        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
    }
}

// MARK: - Small widget

struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot
    let selectedProviderId: String?

    private var provider: ProviderSnapshot? {
        selectedProvider(snapshot: snapshot, selectedProviderId: selectedProviderId)
            ?? topProvider(snapshot: snapshot)
    }

    var body: some View {
        if let provider = provider {
            VStack(spacing: WidgetDesignToken.zeroSpacing) {
                Spacer(minLength: WidgetDesignToken.zeroLength)

                // quota-float QuotaOrb 1:1, canvas-scaled: 27px in an 80px orb →
                // 56px (orbHeroSize) on the ~166pt systemSmall canvas. Only the
                // remaining % of the primary window. No ring, no name.
                if provider.kind == .usage, let spend = provider.spendUSD {
                    Text(USDFormatter.string(from: spend))
                        .font(.system(size: WidgetDesignToken.orbHeroSize, weight: WidgetDesignToken.orbWeight, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                } else if let window = primaryWindow(of: provider) {
                    let remaining = max(WidgetDesignToken.zeroDouble,
                                        min(WidgetDesignToken.percentMax,
                                            WidgetDesignToken.percentMax - window.usedPercent))
                    HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbHeroSuffixSpacing) {
                        Text("\(Int(remaining.rounded()))")
                            .font(.system(size: WidgetDesignToken.orbHeroSize, weight: WidgetDesignToken.orbWeight))
                            .monospacedDigit()
                            .tracking(WidgetDesignToken.orbHeroTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        Text("%")
                            .font(.system(size: WidgetDesignToken.percentSuffixSize, weight: WidgetDesignToken.percentSuffixWeight))
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    }
                } else {
                    ProviderIconView(providerId: provider.id, size: WidgetDesignToken.ringIconSize)
                        .widgetAccentable()
                }

                Spacer(minLength: WidgetDesignToken.zeroLength)
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
                .stroke(WidgetDesignToken.AuroraInk.faint.opacity(WidgetDesignToken.trackOpacity), lineWidth: WidgetDesignToken.orbRingStroke)
            Circle()
                .trim(from: WidgetDesignToken.ringStart, to: min(percent, WidgetDesignToken.percentMax) / WidgetDesignToken.percentMax)
                .stroke(percent.severityColor(scheme), style: StrokeStyle(lineWidth: WidgetDesignToken.orbRingStroke, lineCap: .round))
                .rotationEffect(.degrees(WidgetDesignToken.ringRotation))
            content()
        }
        .frame(width: WidgetDesignToken.orbRingDiameter, height: WidgetDesignToken.orbRingDiameter)
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

    /// First window other than the primary — the QuotaCard footer secondary metric.
    private var secondaryWindow: UsageWindow? {
        guard let primary = primaryWindow(of: provider) else { return nil }
        return provider.windows.first { $0.id != primary.id }
    }

    var body: some View {
        // quota-float QuotaCard, compact: header → hero remaining % → tier bar →
        // reset-time → footer pinned bottom. Sized to fit the systemMedium canvas.
        VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
            // Header: dot + icon + eyebrow name + primary window descriptor
            HStack(spacing: WidgetDesignToken.smallGap) {
                StatusDot(color: statusColor)
                ProviderIconView(providerId: provider.id, size: WidgetDesignToken.mediumIconSize)
                    .widgetAccentable()
                Text(provider.displayName.uppercased())
                    .font(.system(size: WidgetDesignToken.eyebrowSize, weight: WidgetDesignToken.eyebrowWeight))
                    .tracking(WidgetDesignToken.eyebrowTracking)
                    .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    .lineLimit(WidgetDesignToken.singleLine)
                Spacer(minLength: WidgetDesignToken.zeroLength)
                if let window = primaryWindow(of: provider) {
                    Text(window.label.uppercased())
                        .font(.system(size: WidgetDesignToken.portSize, design: .monospaced))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                }
            }

            Spacer(minLength: WidgetDesignToken.zeroLength)

            // Body
            if provider.kind == .usage, let spend = provider.spendUSD {
                HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.smallGap) {
                    Text(USDFormatter.string(from: spend))
                        .font(.system(size: WidgetDesignToken.percentHeroMediumSize, weight: WidgetDesignToken.percentHeroWeight, design: .monospaced))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    Text("spent")
                        .font(.system(size: WidgetDesignToken.captionSize))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                }
            } else if let window = primaryWindow(of: provider) {
                let remaining = max(WidgetDesignToken.zeroDouble,
                                    min(WidgetDesignToken.percentMax,
                                        WidgetDesignToken.percentMax - window.usedPercent))
                VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
                    HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbSuffixSpacing) {
                        Text("\(Int(remaining.rounded()))")
                            .font(.system(size: WidgetDesignToken.percentHeroMediumSize, weight: WidgetDesignToken.percentHeroWeight))
                            .monospacedDigit()
                            .tracking(WidgetDesignToken.mediumHeroTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        Text("%")
                            .font(.system(size: WidgetDesignToken.percentSuffixSize, weight: WidgetDesignToken.percentSuffixWeight))
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    }
                    // Width encodes REMAINING; tier gradient colours encode USED —
                    // critical stays orange-red even on a short bar (quota-float semantics).
                    CapsuleProgressBar(value: remaining, colorValue: window.usedPercent, height: WidgetDesignToken.largeBarHeight, glow: true)
                    // quota-float renders "reset time unknown" when resetsAt is
                    // null — the line always renders so the hero↔footer rhythm never collapses.
                    Text(window.resetsAt == nil ? "Reset unknown" : RelativeResetFormatter.string(from: window.resetsAt))
                        .font(.system(size: WidgetDesignToken.resetTimeSize))
                        .tracking(WidgetDesignToken.resetTimeTracking)
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary.opacity(WidgetDesignToken.resetTimeOpacity))
                }
            } else {
                HStack(spacing: WidgetDesignToken.zeroSpacing) {
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    ProviderIconView(providerId: provider.id, size: WidgetDesignToken.ringIconSize)
                        .widgetAccentable()
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                }
            }

            Spacer(minLength: WidgetDesignToken.zeroLength)

            // Footer: weekly secondary metric when the provider has two windows,
            // else the update-cadence line.
            if let secondary = secondaryWindow {
                let secondaryRemaining = max(WidgetDesignToken.zeroDouble,
                                             min(WidgetDesignToken.percentMax,
                                                 WidgetDesignToken.percentMax - secondary.usedPercent))
                HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.smallGap) {
                    Text("\(secondary.label) LEFT".uppercased())
                        .font(.system(size: WidgetDesignToken.footerSize, design: .monospaced))
                        .tracking(WidgetDesignToken.weeklyLabelTracking)
                        .foregroundStyle(WidgetDesignToken.AuroraInk.faint)
                    Text("\(Int(secondaryRemaining.rounded()))")
                        .font(.system(size: WidgetDesignToken.weeklyNumberSize, design: .monospaced))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    Text("%")
                        .font(.system(size: WidgetDesignToken.orbSuffixSize, weight: WidgetDesignToken.orbSuffixWeight))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    ProviderIconView(providerId: provider.id, size: WidgetDesignToken.mediumFooterIconSize)
                }
            } else {
                // (medium widget height is tight, so use caption size instead of the
                // full 14px updated token that quota-float uses on its taller cards).
                HStack(spacing: WidgetDesignToken.smallGap) {
                    Text("Updated \(fetchedAtString)")
                        .font(.system(size: WidgetDesignToken.captionSize, weight: WidgetDesignToken.updatedWeight, design: .monospaced))
                        .tracking(WidgetDesignToken.updatedTracking)
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary.opacity(WidgetDesignToken.updatedOpacity))
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    Text("Every 15 min")
                        .font(.system(size: WidgetDesignToken.captionSize, weight: WidgetDesignToken.updatedWeight, design: .monospaced))
                        .tracking(WidgetDesignToken.updatedTracking)
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary.opacity(WidgetDesignToken.updatedOpacity))
                }
            }
        }
    }
}

struct ProviderBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: WidgetDesignToken.portSize))
            .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
            .padding(.horizontal, WidgetDesignToken.badgeHPadding)
            .padding(.vertical, WidgetDesignToken.badgeVPadding)
            .background(WidgetDesignToken.AuroraInk.faint.opacity(WidgetDesignToken.badgeBackgroundOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: WidgetDesignToken.badgeRadius)
                    .stroke(WidgetDesignToken.AuroraInk.faint.opacity(WidgetDesignToken.badgeStrokeOpacity), lineWidth: WidgetDesignToken.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: WidgetDesignToken.badgeRadius, style: .continuous))
    }
}

// MARK: - Large overview widget

struct LargeOverviewView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let visible = topN(snapshot: snapshot, n: WidgetDesignToken.largeVisibleCount)
        let hidden = max(WidgetDesignToken.zeroInt, snapshot.providers.count - visible.count)

        VStack(alignment: .leading, spacing: WidgetDesignToken.zeroLength) {
            // Header
            HStack(spacing: WidgetDesignToken.smallGap) {
                Text("Token King")
                    .font(.system(size: WidgetDesignToken.wNameSize, weight: .semibold))
                    .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                Spacer(minLength: WidgetDesignToken.zeroLength)
            }

            Spacer(minLength: WidgetDesignToken.zeroLength)

            // Rows distributed evenly across the middle
            VStack(alignment: .leading, spacing: WidgetDesignToken.sectionGap) {
                ForEach(visible, id: \.id) { provider in
                    LargeProviderRow(provider: provider)
                }
            }

            Spacer(minLength: WidgetDesignToken.zeroLength)

            // Footer pinned to bottom
            VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
                if hidden > WidgetDesignToken.zeroInt {
                    Text("+\(hidden) more")
                        .font(.system(size: WidgetDesignToken.captionSize))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.faint)
                }

                if let cost = snapshot.monthlyCost {
                    MonthlyCostFooter(cost: cost)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Large detail widget

struct LargeDetailView: View {
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
                                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                                    Spacer(minLength: WidgetDesignToken.zeroLength)
                                    Text("\(Int(window.usedPercent.rounded()))%")
                                        .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
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
    let snapshot: WidgetSnapshot

    private var searchProviders: [ProviderSnapshot] {
        snapshot.providers.filter {
            $0.id == WidgetDesignToken.ProviderID.braveSearch ||
            $0.id == WidgetDesignToken.ProviderID.tavilySearch
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.zeroLength) {
            // Header
            HStack(spacing: WidgetDesignToken.smallGap) {
                Text("Search Engines")
                    .font(.system(size: WidgetDesignToken.wNameSize, weight: .semibold))
                    .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                Spacer(minLength: WidgetDesignToken.zeroLength)
            }

            Spacer(minLength: WidgetDesignToken.zeroLength)

            // Rows distributed evenly across the middle
            VStack(alignment: .leading, spacing: WidgetDesignToken.sectionGap) {
                ForEach(searchProviders, id: \.id) { provider in
                    LargeProviderRow(provider: provider)
                }
            }

            Spacer(minLength: WidgetDesignToken.zeroLength)

            if searchProviders.isEmpty {
                EmptyStateView(message: "No search engine data")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    .lineLimit(WidgetDesignToken.singleLine)
                Spacer(minLength: WidgetDesignToken.zeroLength)
                Text(valueString)
                    .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                    .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
            }
            CapsuleProgressBar(value: progressValue, height: WidgetDesignToken.largeBarHeight, glow: true)
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
    let cost: MonthlyCost

    var body: some View {
        HStack {
            Text("Monthly")
                .font(.system(size: WidgetDesignToken.captionSize))
                .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
            Spacer(minLength: WidgetDesignToken.zeroLength)
            Text(USDFormatter.string(from: cost.usd))
                .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
            if let rmb = cost.rmb {
                Text("/ ¥\(String(format: "%.2f", rmb))")
                    .font(.system(size: WidgetDesignToken.captionSize, design: .monospaced))
                    .foregroundStyle(WidgetDesignToken.AuroraInk.faint)
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
            .shadow(color: color.opacity(WidgetDesignToken.barGlowOpacity),
                    radius: WidgetDesignToken.barGlowRadius, x: 0, y: 0)
    }
}

struct CapsuleProgressBar: View {
    @Environment(\.colorScheme) private var scheme
    let value: Double
    var colorValue: Double? = nil
    var height: CGFloat = WidgetDesignToken.barHeight
    var glow: Bool = false

    private var fraction: CGFloat {
        CGFloat(min(max(value, WidgetDesignToken.zeroDouble), WidgetDesignToken.percentMax) / WidgetDesignToken.percentMax)
    }

    private var gradientColors: (start: Color, end: Color) {
        WidgetDesignToken.Aurora.progressGradient(forUsedPercent: colorValue ?? value)
    }

    var body: some View {
        GeometryReader { geometry in
            let progressWidth = geometry.size.width * fraction
            let (startColor, endColor) = gradientColors
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: WidgetDesignToken.barRadius, style: .continuous)
                    .fill(WidgetDesignToken.AuroraInk.faint.opacity(WidgetDesignToken.trackOpacity))
                if glow {
                    RoundedRectangle(cornerRadius: WidgetDesignToken.barRadius, style: .continuous)
                        .fill(LinearGradient(colors: [startColor, endColor],
                                             startPoint: .leading, endPoint: .trailing))
                        .shadow(color: startColor.opacity(WidgetDesignToken.barGlowOpacity),
                                radius: WidgetDesignToken.barGlowRadius, x: 0, y: 0)
                        .frame(width: progressWidth, height: height)
                } else {
                    RoundedRectangle(cornerRadius: WidgetDesignToken.barRadius, style: .continuous)
                        .fill(value.severityColor(scheme))
                        .frame(width: progressWidth, height: height)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
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
