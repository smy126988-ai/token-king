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
        // Padding is explicit + uniform across families: system default content
        // margins differ per widget family, which made medium/large insets
        // inconsistent with the calibrated small widget. Configurations opt
        // out via .contentMarginsDisabled().
        innerContent
            .padding(WidgetDesignToken.cardContentPadding)
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
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot
    let selectedProviderId: String?

    private var provider: ProviderSnapshot? {
        selectedProvider(snapshot: snapshot, selectedProviderId: selectedProviderId)
            ?? topProvider(snapshot: snapshot)
    }

    var body: some View {
        if let provider = provider {
            // quota-float QuotaCard, mini (reference: quota-states.png):
            // eyebrow + status dot → "5-hour remaining" descriptor → big
            // remaining-% number → glowing tier progress bar → reset-time.
            // The milky card + aurora + border live in containerBackground, so
            // vibrant/accented stays system-rendered with no gating needed here.
            VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
                // Eyebrow row: NAME (wide-tracked) + glowing status dot, top-right
                HStack(spacing: WidgetDesignToken.smallGap) {
                    Text(provider.displayName.uppercased())
                        .font(.system(size: WidgetDesignToken.miniEyebrowSize, weight: WidgetDesignToken.eyebrowWeight))
                        .tracking(WidgetDesignToken.miniEyebrowTracking)
                        .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        .lineLimit(WidgetDesignToken.singleLine)
                        .minimumScaleFactor(WidgetDesignToken.eyebrowMinimumScale)
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    StatusDot(color: statusColor(for: provider))
                }

                if provider.kind == .usage, let spend = provider.spendUSD {
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbCopySuffixSpacing) {
                        Text(USDFormatter.string(from: spend))
                            .font(.system(size: WidgetDesignToken.orbCopyNumberSize, weight: WidgetDesignToken.orbWeight, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        Text("spent")
                            .font(.system(size: WidgetDesignToken.miniDescriptorSize))
                            .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                    }
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                } else if let window = shortWindow(of: provider) {
                    // quota-float's updated line describes the short window
                    Text(window.id == "5h" ? "5-hour remaining" : "\(window.label) remaining")
                        .font(.system(size: WidgetDesignToken.miniDescriptorSize))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)

                    Spacer(minLength: WidgetDesignToken.zeroLength)

                    let remaining = max(WidgetDesignToken.zeroDouble,
                                        min(WidgetDesignToken.percentMax,
                                            WidgetDesignToken.percentMax - window.usedPercent))
                    // 64px/500 hero on the 320px card → 45px on systemSmall
                    HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbCopySuffixSpacing) {
                        Text("\(Int(remaining.rounded()))")
                            .font(.system(size: WidgetDesignToken.orbCopyNumberSize, weight: WidgetDesignToken.percentHeroWeight))
                            .monospacedDigit()
                            .tracking(WidgetDesignToken.orbCopyTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        Text("%")
                            .font(.system(size: WidgetDesignToken.orbCopySuffixSize, weight: WidgetDesignToken.orbSuffixWeight))
                            .baselineOffset(WidgetDesignToken.orbCopySuffixLift)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    }
                    .padding(.bottom, WidgetDesignToken.miniBarTopMargin)
                    // Width = remaining, tier gradient colours = used (critical
                    // stays orange-red even on a short bar) + outer glow.
                    CapsuleProgressBar(value: remaining, colorValue: window.usedPercent,
                                       height: WidgetDesignToken.barHeight, glow: true)
                    Text(window.resetsAt == nil ? "Reset unknown" : RelativeResetFormatter.string(from: window.resetsAt))
                        .font(.system(size: WidgetDesignToken.miniResetSize))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary.opacity(WidgetDesignToken.resetTimeOpacity))
                } else {
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    HStack(spacing: WidgetDesignToken.zeroSpacing) {
                        Spacer(minLength: WidgetDesignToken.zeroLength)
                        ProviderIconView(providerId: provider.id, size: WidgetDesignToken.ringIconSize)
                            .widgetAccentable()
                        Spacer(minLength: WidgetDesignToken.zeroLength)
                    }
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(message: "No providers")
        }
    }

    private func statusColor(for provider: ProviderSnapshot) -> Color {
        if let window = shortWindow(of: provider) {
            return window.usedPercent.severityColor(scheme)
        }
        return WidgetDesignToken.healthyColor
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
        if let window = shortWindow(of: provider) {
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

    /// quota-float's weeklyWindow — the QuotaCard footer secondary metric.
    private var secondaryWindow: UsageWindow? {
        weeklyWindow(of: provider)
    }

    var body: some View {
        // quota-float QuotaCard (quota-states.png), compact for systemMedium:
        // eyebrow + "5-hour remaining" stacked left, glowing dot top-right →
        // hero remaining % → glowing tier bar → reset-time → weekly footer.
        // Hero/bar/reset track the SHORT window (5h); the footer tracks the
        // WEEKLY window (7d) — same data mapping as QuotaCard.
        VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
            // Header: eyebrow + descriptor stacked (quota-float card-header),
            // status dot pinned top-right.
            HStack(alignment: .top, spacing: WidgetDesignToken.smallGap) {
                VStack(alignment: .leading, spacing: WidgetDesignToken.descriptorTopMargin) {
                    Text(provider.displayName.uppercased())
                        .font(.system(size: WidgetDesignToken.eyebrowSize, weight: WidgetDesignToken.eyebrowWeight))
                        .tracking(WidgetDesignToken.eyebrowTracking)
                        .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        .lineLimit(WidgetDesignToken.singleLine)
                        .minimumScaleFactor(WidgetDesignToken.eyebrowMinimumScale)
                    if let window = shortWindow(of: provider) {
                        Text(window.id == "5h" ? "5-hour remaining" : "\(window.label) remaining")
                            .font(.system(size: WidgetDesignToken.miniDescriptorSize))
                            .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                    }
                }
                Spacer(minLength: WidgetDesignToken.zeroLength)
                StatusDot(color: statusColor)
            }

            // Body — flows straight down from the header like the reference
            // card; the only flexible gap sits before the footer.
            if provider.kind == .usage, let spend = provider.spendUSD {
                HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.smallGap) {
                    Text(USDFormatter.string(from: spend))
                        .font(.system(size: WidgetDesignToken.percentHeroMediumSize, weight: WidgetDesignToken.percentHeroWeight, design: .monospaced))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    Text("spent")
                        .font(.system(size: WidgetDesignToken.captionSize))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                }
            } else if let window = shortWindow(of: provider) {
                let remaining = max(WidgetDesignToken.zeroDouble,
                                    min(WidgetDesignToken.percentMax,
                                        WidgetDesignToken.percentMax - window.usedPercent))
                VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
                    HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbSuffixSpacing) {
                        Text("\(Int(remaining.rounded()))")
                            .font(.system(size: WidgetDesignToken.orbCopyNumberSize, weight: WidgetDesignToken.percentHeroWeight))
                            .monospacedDigit()
                            .tracking(WidgetDesignToken.mediumHeroTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        Text("%")
                            .font(.system(size: WidgetDesignToken.percentSuffixSize, weight: WidgetDesignToken.percentSuffixWeight))
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    }
                    .frame(height: WidgetDesignToken.orbCopyNumberSize * WidgetDesignToken.quotaHeroBoxFactor)
                    // Width encodes REMAINING; tier gradient colours encode USED —
                    // critical stays orange-red even on a short bar (quota-float semantics).
                    CapsuleProgressBar(value: remaining, colorValue: window.usedPercent, height: WidgetDesignToken.barHeight, glow: true)
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

            // Footer: weekly-window metric when the provider reports a 7d
            // window, else the update-cadence line.
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
                Text("TOKEN KING")
                    .font(.system(size: WidgetDesignToken.eyebrowSize, weight: WidgetDesignToken.eyebrowWeight))
                    .tracking(WidgetDesignToken.eyebrowTracking)
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
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot
    let selectedProviderId: String?

    var body: some View {
        let provider = selectedProvider(snapshot: snapshot, selectedProviderId: selectedProviderId)
            ?? topProvider(snapshot: snapshot)

        if let provider = provider {
            // quota-float QuotaCard at near 1:1 scale (systemLarge ≈ the 320px
            // card): eyebrow + "5-hour remaining" + frosted status indicator →
            // 64px remaining-% hero → glowing tier bar → reset-time → weekly
            // footer (30px metric + provider mark).
            VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
                // card-header
                HStack(alignment: .top, spacing: WidgetDesignToken.smallGap) {
                    VStack(alignment: .leading, spacing: WidgetDesignToken.descriptorTopMargin) {
                        Text(provider.displayName.uppercased())
                            .font(.system(size: WidgetDesignToken.eyebrowSize, weight: WidgetDesignToken.eyebrowWeight))
                            .tracking(WidgetDesignToken.eyebrowTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                            .lineLimit(WidgetDesignToken.singleLine)
                            .minimumScaleFactor(WidgetDesignToken.eyebrowMinimumScale)
                        if let window = shortWindow(of: provider) {
                            Text(window.id == "5h" ? "5-hour remaining" : "\(window.label) remaining")
                                .font(.system(size: WidgetDesignToken.updatedSize, weight: WidgetDesignToken.updatedWeight))
                                .tracking(WidgetDesignToken.updatedTracking)
                                .foregroundStyle(WidgetDesignToken.AuroraInk.primary.opacity(WidgetDesignToken.updatedOpacity))
                        }
                    }
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    // usage-indicator: 8px dot inside a 25px frosted ring
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(WidgetDesignToken.indicatorRingBackgroundOpacity))
                        Circle()
                            .strokeBorder(Color.white.opacity(WidgetDesignToken.indicatorRingBorderOpacity),
                                          lineWidth: WidgetDesignToken.orbCardBorderWidth)
                        StatusDot(color: statusColor(for: provider))
                    }
                    .frame(width: WidgetDesignToken.indicatorRingSize, height: WidgetDesignToken.indicatorRingSize)
                }

                if provider.kind == .usage, let spend = provider.spendUSD {
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbSuffixSpacing) {
                        Text(USDFormatter.string(from: spend))
                            .font(.system(size: WidgetDesignToken.percentHeroSize, weight: WidgetDesignToken.percentHeroWeight, design: .monospaced))
                            .tracking(WidgetDesignToken.percentHeroTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        Text("spent")
                            .font(.system(size: WidgetDesignToken.captionSize))
                            .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                    }
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                } else if let window = shortWindow(of: provider) {
                    let remaining = max(WidgetDesignToken.zeroDouble,
                                        min(WidgetDesignToken.percentMax,
                                            WidgetDesignToken.percentMax - window.usedPercent))
                    // primary-metric: 64px/500, -.07em, % 21px/700 baseline,
                    // box at line-height .82 so the glyph frame stays tight
                    HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbSuffixSpacing) {
                        Text("\(Int(remaining.rounded()))")
                            .font(.system(size: WidgetDesignToken.percentHeroSize, weight: WidgetDesignToken.percentHeroWeight))
                            .monospacedDigit()
                            .tracking(WidgetDesignToken.percentHeroTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        Text("%")
                            .font(.system(size: WidgetDesignToken.percentSuffixSize, weight: WidgetDesignToken.percentSuffixWeight))
                            .tracking(WidgetDesignToken.percentSuffixTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    }
                    .frame(height: WidgetDesignToken.percentHeroSize * WidgetDesignToken.quotaHeroBoxFactor)
                    .padding(.top, WidgetDesignToken.quotaHeroTopMargin)
                    // Width = remaining; tier gradient colours = used (critical
                    // stays orange-red even on a short bar) + outer glow.
                    CapsuleProgressBar(value: remaining, colorValue: window.usedPercent,
                                       height: WidgetDesignToken.barHeight, glow: true)
                        .padding(.top, WidgetDesignToken.quotaBarTopMargin)
                    Text(window.resetsAt == nil ? "Reset unknown" : RelativeResetFormatter.string(from: window.resetsAt))
                        .font(.system(size: WidgetDesignToken.resetTimeSize))
                        .tracking(WidgetDesignToken.resetTimeTracking)
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary.opacity(WidgetDesignToken.resetTimeOpacity))
                        .padding(.top, WidgetDesignToken.quotaResetTopMargin)

                    Spacer(minLength: WidgetDesignToken.zeroLength)

                    // card-footer: weekly metric + provider mark
                    if let weekly = weeklyWindow(of: provider) {
                        let weeklyRemaining = max(WidgetDesignToken.zeroDouble,
                                                  min(WidgetDesignToken.percentMax,
                                                      WidgetDesignToken.percentMax - weekly.usedPercent))
                        HStack(alignment: .bottom, spacing: WidgetDesignToken.zeroLength) {
                            VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
                                Text(weeklyLabel(for: weekly))
                                    .font(.system(size: WidgetDesignToken.resetTimeSize, weight: WidgetDesignToken.weeklyLabelWeight))
                                    .tracking(WidgetDesignToken.weeklyLabelTracking)
                                    .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                                HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbSuffixSpacing) {
                                    Text("\(Int(weeklyRemaining.rounded()))")
                                        .font(.system(size: WidgetDesignToken.weeklyHeroSize))
                                        .tracking(WidgetDesignToken.percentSuffixTracking)
                                        .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                                    Text("%")
                                        .font(.system(size: WidgetDesignToken.weeklyHeroSuffixSize))
                                        .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                                }
                            }
                            Spacer(minLength: WidgetDesignToken.zeroLength)
                            ProviderIconView(providerId: provider.id, size: WidgetDesignToken.providerMarkSize)
                        }
                    }
                } else {
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    HStack(spacing: WidgetDesignToken.zeroSpacing) {
                        Spacer(minLength: WidgetDesignToken.zeroLength)
                        ProviderIconView(providerId: provider.id, size: WidgetDesignToken.ringIconSize)
                            .widgetAccentable()
                        Spacer(minLength: WidgetDesignToken.zeroLength)
                    }
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(message: "No providers")
        }
    }

    private func statusColor(for provider: ProviderSnapshot) -> Color {
        if let window = shortWindow(of: provider) {
            return window.usedPercent.severityColor(scheme)
        }
        return WidgetDesignToken.healthyColor
    }

    /// quota-float weeklyUntil: "Weekly remaining · until 7/12".
    private func weeklyLabel(for window: UsageWindow) -> String {
        guard let resetsAt = window.resetsAt else { return "Weekly remaining" }
        let md = resetsAt.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
        return "Weekly remaining · until \(md)"
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
                Text("SEARCH ENGINES")
                    .font(.system(size: WidgetDesignToken.eyebrowSize, weight: WidgetDesignToken.eyebrowWeight))
                    .tracking(WidgetDesignToken.eyebrowTracking)
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
            // quota-float semantics: bar width = short window REMAINING, tier
            // gradient colours = USED (critical stays orange-red on a short bar).
            CapsuleProgressBar(value: progressValue, colorValue: colourValue,
                               height: WidgetDesignToken.largeBarHeight, glow: true)
                .widgetAccentable()
        }
    }

    private var statusColor: Color {
        if let window = shortWindow(of: provider) {
            return window.usedPercent.severityColor(scheme)
        }
        return WidgetDesignToken.healthyColor
    }

    private var progressValue: Double {
        guard provider.kind != .usage else { return WidgetDesignToken.zeroDouble }
        let used = shortWindow(of: provider)?.usedPercent ?? WidgetDesignToken.percentMax
        return max(WidgetDesignToken.zeroDouble,
                   min(WidgetDesignToken.percentMax, WidgetDesignToken.percentMax - used))
    }

    private var colourValue: Double {
        shortWindow(of: provider)?.usedPercent ?? WidgetDesignToken.zeroDouble
    }

    private var valueString: String {
        if provider.kind == .usage, let spend = provider.spendUSD {
            return "\(USDFormatter.string(from: spend)) spent"
        }
        guard let window = shortWindow(of: provider) else {
            return ""
        }
        let remaining = max(WidgetDesignToken.zeroDouble,
                            min(WidgetDesignToken.percentMax,
                                WidgetDesignToken.percentMax - window.usedPercent))
        return "\(window.label) \(Int(remaining.rounded()))%"
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

/// quota-float's "short window" — the 5-hour session quota window that drives
/// the QuotaOrb number and the QuotaCard hero. Falls back to the primary
/// window for providers that don't report a 5h window.
func shortWindow(of provider: ProviderSnapshot) -> UsageWindow? {
    if let w = provider.windows.first(where: { $0.id == "5h" }) {
        return w
    }
    return primaryWindow(of: provider)
}

/// quota-float's "weekly window" — the 7-day quota window shown as the
/// QuotaCard footer secondary metric. Nil when the provider has none.
func weeklyWindow(of provider: ProviderSnapshot) -> UsageWindow? {
    provider.windows.first { $0.id == "7d" || $0.id == "weekly" }
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
