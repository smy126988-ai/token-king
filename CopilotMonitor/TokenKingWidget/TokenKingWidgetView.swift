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
        case .placeholder:
            EmptyStateView(message: "Updating widget", detail: "Loading the latest data")
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
        case .ready:
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
                .font(.system(
                    size: WidgetDesignToken.bodySize,
                    weight: WidgetDesignToken.quotaTitleWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                .multilineTextAlignment(.center)
            if let detail = detail {
                Text(detail)
                    .font(.system(
                        size: WidgetDesignToken.captionSize,
                        weight: WidgetDesignToken.quotaLabelWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
                    .foregroundStyle(WidgetDesignToken.AuroraInk.faint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            WidgetRefreshButton()
        }
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

struct SmallProviderHeader: View {
    let providerId: String
    let title: String
    let subtitle: String?
    let statusColor: Color
    let lastUpdatedAt: Date?

    var body: some View {
        HStack(alignment: .top, spacing: WidgetDesignToken.zeroSpacing) {
            HStack(alignment: .top, spacing: WidgetDesignToken.smallProviderHeaderSpacing) {
                SmallProviderMark(providerId: providerId)
                VStack(alignment: .leading, spacing: WidgetDesignToken.smallProviderHeaderTextSpacing) {
                    HStack(spacing: WidgetDesignToken.smallProviderTitleStatusSpacing) {
                        Text(title)
                            .font(.system(
                                size: WidgetDesignToken.smallProviderTitleSize,
                                weight: WidgetDesignToken.smallProviderTitleWeight,
                                design: WidgetDesignToken.quotaFontDesign
                            ))
                            .tracking(WidgetDesignToken.smallProviderTitleTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                            .lineLimit(WidgetDesignToken.singleLine)
                            .minimumScaleFactor(WidgetDesignToken.smallProviderTitleMinimumScale)
                            .allowsTightening(true)
                            .layoutPriority(1)
                        StatusDot(
                            color: statusColor,
                            size: WidgetDesignToken.smallProviderStatusDotSize,
                            glowRadius: WidgetDesignToken.smallProviderStatusGlowRadius
                        )
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(
                                size: WidgetDesignToken.smallProviderSubtitleSize,
                                weight: WidgetDesignToken.quotaLabelWeight,
                                design: WidgetDesignToken.quotaFontDesign
                            ))
                            .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                            .lineLimit(WidgetDesignToken.singleLine)
                    }
                }
            }
            .layoutPriority(1)
            Spacer(minLength: WidgetDesignToken.zeroLength)
            WidgetHeaderActions(lastUpdatedAt: lastUpdatedAt)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SmallProviderMark: View {
    let providerId: String

    private var iconSize: CGFloat {
        providerId == WidgetDesignToken.ProviderID.codex
            ? WidgetDesignToken.smallCodexMarkIconSize
            : WidgetDesignToken.smallProviderMarkIconSize
    }

    var body: some View {
        ProviderIconView(
            providerId: providerId,
            size: iconSize,
            fallbackTint: WidgetDesignToken.AuroraInk.primary
        )
        .widgetAccentable()
        .frame(
            width: WidgetDesignToken.smallProviderMarkWidth,
            height: WidgetDesignToken.smallProviderMarkHeight
        )
    }
}

struct SmallQuotaBody: View {
    let windowLabel: String
    let usedPercent: Double
    let resetsAt: Date?

    private var remaining: Double {
        max(
            WidgetDesignToken.zeroDouble,
            min(WidgetDesignToken.percentMax, WidgetDesignToken.percentMax - usedPercent)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.zeroSpacing) {
            RemainingQuotaMetric(
                remaining: remaining,
                numberSize: WidgetDesignToken.smallHeroNumberSize,
                suffixSize: WidgetDesignToken.smallHeroSuffixSize,
                tracking: WidgetDesignToken.smallHeroTracking,
                suffixLift: WidgetDesignToken.smallHeroSuffixLift
            )
            .frame(
                height: WidgetDesignToken.smallHeroNumberSize * WidgetDesignToken.quotaHeroBoxFactor,
                alignment: .bottom
            )

            CapsuleProgressBar(
                value: remaining,
                colorValue: usedPercent,
                height: WidgetDesignToken.smallProgressHeight,
                glow: true
            )
            .padding(.top, WidgetDesignToken.smallHeroToBarSpacing)

            SmallQuotaMetadata(windowLabel: windowLabel, resetsAt: resetsAt)
                .padding(.top, WidgetDesignToken.smallBarToResetSpacing)
        }
        .padding(.top, WidgetDesignToken.smallHeaderToHeroSpacing)
    }
}

struct SmallQuotaMetadata: View {
    let windowLabel: String
    let resetsAt: Date?

    var body: some View {
        HStack(spacing: WidgetDesignToken.smallMetadataSpacing) {
            Text(windowLabel)
                .fontWeight(WidgetDesignToken.quotaLabelWeight)
            Text("·")
                .accessibilityHidden(true)
            Text(resetsAt == nil ? "Reset unknown" : RelativeResetFormatter.string(from: resetsAt))
        }
        .font(.system(
            size: WidgetDesignToken.smallResetSize,
            weight: WidgetDesignToken.smallMetadataWeight,
            design: WidgetDesignToken.quotaFontDesign
        ))
        .foregroundStyle(
            WidgetDesignToken.AuroraInk.secondary.opacity(WidgetDesignToken.smallResetOpacity)
        )
        .lineLimit(WidgetDesignToken.singleLine)
        .minimumScaleFactor(WidgetDesignToken.smallMetadataMinimumScale)
        .allowsTightening(true)
        .accessibilityElement(children: .combine)
    }
}

struct SmallWidgetView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot
    let selectedProviderId: String?

    private var provider: ProviderSnapshot? {
        resolvedProvider(snapshot: snapshot, selectedProviderId: selectedProviderId)
    }

    var body: some View {
        if let provider = provider {
            if provider.widgetDataStatus == .unavailable {
                ProviderUnavailableStateView(providerName: provider.displayName)
            } else if provider.kind == .usage, let spend = provider.spendUSD {
                VStack(alignment: .leading, spacing: WidgetDesignToken.zeroSpacing) {
                    SmallProviderHeader(
                        providerId: provider.id,
                        title: provider.compactDisplayName ?? provider.displayName,
                        subtitle: "Usage",
                        statusColor: statusColor(for: provider),
                        lastUpdatedAt: provider.fetchedAt
                    )
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbCopySuffixSpacing) {
                        Text(USDFormatter.string(from: spend))
                            .font(.system(size: WidgetDesignToken.orbCopyNumberSize, weight: WidgetDesignToken.orbWeight, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        Text("spent")
                            .font(.system(
                                size: WidgetDesignToken.miniDescriptorSize,
                                weight: WidgetDesignToken.quotaLabelWeight,
                                design: WidgetDesignToken.quotaFontDesign
                            ))
                            .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                    }
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let window = primaryWindow(of: provider) {
                VStack(alignment: .leading, spacing: WidgetDesignToken.zeroSpacing) {
                    SmallProviderHeader(
                        providerId: provider.id,
                        title: provider.compactDisplayName ?? provider.displayName,
                        subtitle: nil,
                        statusColor: statusColor(for: provider),
                        lastUpdatedAt: provider.fetchedAt
                    )
                    SmallQuotaBody(
                        windowLabel: window.label,
                        usedPercent: window.usedPercent,
                        resetsAt: window.resetsAt
                    )
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: WidgetDesignToken.zeroSpacing) {
                    SmallProviderHeader(
                        providerId: provider.id,
                        title: provider.compactDisplayName ?? provider.displayName,
                        subtitle: nil,
                        statusColor: statusColor(for: provider),
                        lastUpdatedAt: provider.fetchedAt
                    )
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    HStack(spacing: WidgetDesignToken.zeroSpacing) {
                        Spacer(minLength: WidgetDesignToken.zeroLength)
                        ProviderIconView(providerId: provider.id, size: WidgetDesignToken.ringIconSize)
                            .widgetAccentable()
                        Spacer(minLength: WidgetDesignToken.zeroLength)
                    }
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            missingProviderView(selectedProviderId: selectedProviderId)
        }
    }

    private func statusColor(for provider: ProviderSnapshot) -> Color {
        if provider.widgetDataStatus == .stale {
            return WidgetDesignToken.DataStatus.stale
        }
        if let window = primaryWindow(of: provider) {
            return window.usedPercent.severityColor(scheme)
        }
        return WidgetDesignToken.healthyColor
    }
}

func selectedProvider(snapshot: WidgetSnapshot, selectedProviderId: String?) -> ProviderSnapshot? {
    guard let id = selectedProviderId else { return nil }
    return snapshot.providers.first { $0.id == id }
}

/// A configured provider never falls back to a different provider. `nil` is
/// the intentional zero-configuration mode and selects the current priority
/// provider instead.
func resolvedProvider(snapshot: WidgetSnapshot, selectedProviderId: String?) -> ProviderSnapshot? {
    if selectedProviderId != nil {
        return selectedProvider(snapshot: snapshot, selectedProviderId: selectedProviderId)
    }
    return topProvider(snapshot: snapshot)
}

extension ProviderSnapshot {
    var widgetDataStatus: WidgetDataStatus {
        status ?? .available
    }
}

struct ProviderUnavailableStateView: View {
    let providerName: String

    var body: some View {
        EmptyStateView(message: "Provider unavailable", detail: providerName)
    }
}

@ViewBuilder
func missingProviderView(selectedProviderId: String?) -> some View {
    if let selectedProviderId {
        ProviderUnavailableStateView(providerName: fallbackProviderName(for: selectedProviderId))
    } else {
        EmptyStateView(message: "No providers")
    }
}

func fallbackProviderName(for providerId: String) -> String {
    if providerId == WidgetDesignToken.ProviderID.codex {
        return "ChatGPT"
    }
    return providerId
        .replacingOccurrences(of: "_", with: " ")
        .capitalized
}

// MARK: - Medium overview widget

struct MediumOverviewView: View {
    @Environment(\.colorScheme) private var scheme
    let snapshot: WidgetSnapshot

    var body: some View {
        let visible = topN(snapshot: snapshot, n: WidgetDesignToken.mediumVisibleCount)

        VStack(alignment: .leading, spacing: WidgetDesignToken.rowGap) {
            ForEach(visible, id: \.id) { provider in
                MediumProviderCard(provider: provider)
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
        let provider = resolvedProvider(snapshot: snapshot, selectedProviderId: selectedProviderId)

        if let provider = provider {
            Group {
                if provider.widgetDataStatus == .unavailable {
                    ProviderUnavailableStateView(providerName: provider.displayName)
                } else {
                    MediumProviderCard(provider: provider)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            missingProviderView(selectedProviderId: selectedProviderId)
        }
    }
}

struct MediumProviderCard: View {
    @Environment(\.colorScheme) private var scheme
    let provider: ProviderSnapshot

    private var statusColor: Color {
        if provider.widgetDataStatus == .stale {
            return WidgetDesignToken.DataStatus.stale
        }
        if let window = primaryWindow(of: provider) {
            return window.usedPercent.severityColor(scheme)
        }
        return WidgetDesignToken.healthyColor
    }

    private var secondaryMetric: UsageWindow? {
        secondaryWindow(of: provider)
    }

    var body: some View {
        if provider.widgetDataStatus == .unavailable {
            ProviderUnavailableStateView(providerName: provider.displayName)
        } else {
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
                    Text(provider.compactDisplayName ?? provider.displayName)
                        .font(.system(
                            size: WidgetDesignToken.providerTitleMediumSize,
                            weight: WidgetDesignToken.quotaTitleWeight,
                            design: WidgetDesignToken.quotaFontDesign
                        ))
                        .tracking(WidgetDesignToken.providerTitleTracking)
                        .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        .lineLimit(WidgetDesignToken.singleLine)
                        .minimumScaleFactor(WidgetDesignToken.eyebrowMinimumScale)
                    if let window = primaryWindow(of: provider) {
                        Text(window.label)
                            .font(.system(
                                size: WidgetDesignToken.miniDescriptorSize,
                                weight: WidgetDesignToken.quotaLabelWeight,
                                design: WidgetDesignToken.quotaFontDesign
                            ))
                            .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                    }
                }
                Spacer(minLength: WidgetDesignToken.zeroLength)
                WidgetHeaderActions(statusColor: statusColor, lastUpdatedAt: provider.fetchedAt)
            }

            // Body — flows straight down from the header like the reference
            // card; the only flexible gap sits before the footer.
            if provider.kind == .usage, let spend = provider.spendUSD {
                HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.smallGap) {
                    Text(USDFormatter.string(from: spend))
                        .font(.system(size: WidgetDesignToken.percentHeroMediumSize, weight: WidgetDesignToken.percentHeroWeight, design: .monospaced))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                    Text("spent")
                        .font(.system(
                            size: WidgetDesignToken.captionSize,
                            weight: WidgetDesignToken.quotaLabelWeight,
                            design: WidgetDesignToken.quotaFontDesign
                        ))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                }
            } else if let window = primaryWindow(of: provider) {
                let remaining = max(WidgetDesignToken.zeroDouble,
                                    min(WidgetDesignToken.percentMax,
                                        WidgetDesignToken.percentMax - window.usedPercent))
                HStack(alignment: .bottom, spacing: WidgetDesignToken.quotaMediumColumnSpacing) {
                    VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
                        RemainingQuotaMetric(
                            remaining: remaining,
                            numberSize: WidgetDesignToken.percentHeroMediumSize,
                            suffixSize: WidgetDesignToken.percentSuffixSize,
                            tracking: WidgetDesignToken.mediumHeroTracking
                        )
                        .frame(height: WidgetDesignToken.percentHeroMediumSize * WidgetDesignToken.quotaHeroBoxFactor)
                        CapsuleProgressBar(value: remaining, colorValue: window.usedPercent, height: WidgetDesignToken.barHeight, glow: true)
                        Text(window.resetsAt == nil ? "Reset unknown" : RelativeResetFormatter.string(from: window.resetsAt))
                            .font(.system(
                                size: WidgetDesignToken.resetTimeSize,
                                weight: WidgetDesignToken.quotaLabelWeight,
                                design: WidgetDesignToken.quotaFontDesign
                            ))
                            .tracking(WidgetDesignToken.resetTimeTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.secondary.opacity(WidgetDesignToken.resetTimeOpacity))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    if let secondary = secondaryMetric {
                        Rectangle()
                            .fill(WidgetDesignToken.AuroraInk.faint.opacity(WidgetDesignToken.quotaDividerOpacity))
                            .frame(width: WidgetDesignToken.hairline, height: WidgetDesignToken.quotaMediumDividerHeight)
                        SecondaryQuotaMetric(window: secondary, numberSize: WidgetDesignToken.quotaMediumSecondaryNumberSize)
                            .frame(width: WidgetDesignToken.quotaMediumSecondaryWidth, alignment: .leading)
                    } else {
                        QuotaUpdatedMetadata(fetchedAt: provider.fetchedAt, status: provider.widgetDataStatus)
                            .frame(width: WidgetDesignToken.quotaMediumSecondaryWidth, alignment: .trailing)
                    }
                }
                .padding(.top, WidgetDesignToken.quotaMediumBodyTopSpacing)
            } else {
                HStack(spacing: WidgetDesignToken.zeroSpacing) {
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    ProviderIconView(providerId: provider.id, size: WidgetDesignToken.ringIconSize)
                        .widgetAccentable()
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                }
            }

        }
        }
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
                    .font(.system(
                        size: WidgetDesignToken.sectionTitleSize,
                        weight: WidgetDesignToken.quotaTitleWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
                    .tracking(WidgetDesignToken.sectionTitleTracking)
                    .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                Spacer(minLength: WidgetDesignToken.zeroLength)
                WidgetHeaderActions(
                    lastUpdatedAt: snapshot.providers.compactMap(\.fetchedAt).max()
                )
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
        let provider = resolvedProvider(snapshot: snapshot, selectedProviderId: selectedProviderId)

        if let provider = provider {
            if provider.widgetDataStatus == .unavailable {
                ProviderUnavailableStateView(providerName: provider.displayName)
            } else {
            VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
                // card-header
                HStack(alignment: .top, spacing: WidgetDesignToken.smallGap) {
                    VStack(alignment: .leading, spacing: WidgetDesignToken.descriptorTopMargin) {
                        Text(provider.compactDisplayName ?? provider.displayName)
                            .font(.system(
                                size: WidgetDesignToken.providerTitleLargeSize,
                                weight: WidgetDesignToken.quotaTitleWeight,
                                design: WidgetDesignToken.quotaFontDesign
                            ))
                            .tracking(WidgetDesignToken.providerTitleTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                            .lineLimit(WidgetDesignToken.singleLine)
                            .minimumScaleFactor(WidgetDesignToken.eyebrowMinimumScale)
                        if let window = primaryWindow(of: provider) {
                            Text(window.label)
                                .font(.system(
                                    size: WidgetDesignToken.updatedSize,
                                    weight: WidgetDesignToken.updatedWeight,
                                    design: WidgetDesignToken.quotaFontDesign
                                ))
                                .tracking(WidgetDesignToken.updatedTracking)
                                .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                        }
                    }
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                    WidgetHeaderActions(
                        statusColor: statusColor(for: provider),
                        lastUpdatedAt: provider.fetchedAt
                    )
                }

                if provider.kind == .usage, let spend = provider.spendUSD {
                    HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbSuffixSpacing) {
                        Text(USDFormatter.string(from: spend))
                            .font(.system(size: WidgetDesignToken.percentHeroSize, weight: WidgetDesignToken.percentHeroWeight, design: .monospaced))
                            .tracking(WidgetDesignToken.percentHeroTracking)
                            .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                        Text("spent")
                            .font(.system(
                                size: WidgetDesignToken.captionSize,
                                weight: WidgetDesignToken.quotaLabelWeight,
                                design: WidgetDesignToken.quotaFontDesign
                            ))
                            .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                    }
                    .padding(.top, WidgetDesignToken.quotaLargeHeroTopSpacing)
                    Spacer(minLength: WidgetDesignToken.zeroLength)
                } else if let window = primaryWindow(of: provider) {
                    let remaining = max(WidgetDesignToken.zeroDouble,
                                        min(WidgetDesignToken.percentMax,
                                            WidgetDesignToken.percentMax - window.usedPercent))
                    RemainingQuotaMetric(
                        remaining: remaining,
                        numberSize: WidgetDesignToken.percentHeroSize,
                        suffixSize: WidgetDesignToken.percentSuffixSize,
                        tracking: WidgetDesignToken.percentHeroTracking
                    )
                    .frame(height: WidgetDesignToken.percentHeroSize * WidgetDesignToken.quotaHeroBoxFactor)
                    .padding(.top, WidgetDesignToken.quotaLargeHeroTopSpacing)
                    CapsuleProgressBar(value: remaining, colorValue: window.usedPercent,
                                       height: WidgetDesignToken.barHeight, glow: true)
                        .padding(.top, WidgetDesignToken.quotaLargeBarTopSpacing)
                    Text(window.resetsAt == nil ? "Reset unknown" : RelativeResetFormatter.string(from: window.resetsAt))
                        .font(.system(
                            size: WidgetDesignToken.resetTimeSize,
                            weight: WidgetDesignToken.quotaLabelWeight,
                            design: WidgetDesignToken.quotaFontDesign
                        ))
                        .tracking(WidgetDesignToken.resetTimeTracking)
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary.opacity(WidgetDesignToken.resetTimeOpacity))
                        .padding(.top, WidgetDesignToken.quotaResetTopMargin)

                    Spacer(minLength: WidgetDesignToken.zeroLength)

                    Rectangle()
                        .fill(WidgetDesignToken.AuroraInk.faint.opacity(WidgetDesignToken.quotaDividerOpacity))
                        .frame(height: WidgetDesignToken.hairline)
                        .padding(.top, WidgetDesignToken.quotaLargeFooterTopSpacing)
                    HStack(alignment: .bottom, spacing: WidgetDesignToken.smallGap) {
                        if let secondary = secondaryWindow(of: provider) {
                            SecondaryQuotaMetric(window: secondary, numberSize: WidgetDesignToken.weeklyHeroSize, label: secondaryLabel(for: secondary))
                        }
                        Spacer(minLength: WidgetDesignToken.zeroLength)
                        QuotaUpdatedMetadata(fetchedAt: provider.fetchedAt, status: provider.widgetDataStatus)
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
            }
        } else {
            missingProviderView(selectedProviderId: selectedProviderId)
        }
    }

    private func statusColor(for provider: ProviderSnapshot) -> Color {
        if provider.widgetDataStatus == .stale {
            return WidgetDesignToken.DataStatus.stale
        }
        if let window = primaryWindow(of: provider) {
            return window.usedPercent.severityColor(scheme)
        }
        return WidgetDesignToken.healthyColor
    }

    private func secondaryLabel(for window: UsageWindow) -> String {
        guard let resetsAt = window.resetsAt else { return window.label }
        let md = resetsAt.formatted(.dateTime.month(.defaultDigits).day(.defaultDigits))
        return "\(window.label) · until \(md)"
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
                    .font(.system(
                        size: WidgetDesignToken.sectionTitleSize,
                        weight: WidgetDesignToken.quotaTitleWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
                    .tracking(WidgetDesignToken.sectionTitleTracking)
                    .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                Spacer(minLength: WidgetDesignToken.zeroLength)
                WidgetHeaderActions(
                    lastUpdatedAt: searchProviders.compactMap(\.fetchedAt).max()
                )
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
        if provider.widgetDataStatus == .unavailable {
            ProviderUnavailableRow(providerName: provider.displayName)
        } else {
            VStack(alignment: .leading, spacing: WidgetDesignToken.largeBarTopMargin) {
            HStack(spacing: WidgetDesignToken.largeRowGap) {
                StatusDot(color: statusColor)
                ProviderIconView(providerId: provider.id, size: WidgetDesignToken.largeIconSize)
                    .widgetAccentable()
                Text(provider.displayName)
                    .font(.system(
                        size: WidgetDesignToken.bodySize,
                        weight: WidgetDesignToken.quotaTitleWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
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
    }

    private var statusColor: Color {
        if provider.widgetDataStatus == .stale {
            return WidgetDesignToken.DataStatus.stale
        }
        if let window = primaryWindow(of: provider) {
            return window.usedPercent.severityColor(scheme)
        }
        return WidgetDesignToken.healthyColor
    }

    private var progressValue: Double {
        guard provider.kind != .usage else { return WidgetDesignToken.zeroDouble }
        let used = primaryWindow(of: provider)?.usedPercent ?? WidgetDesignToken.percentMax
        return max(WidgetDesignToken.zeroDouble,
                   min(WidgetDesignToken.percentMax, WidgetDesignToken.percentMax - used))
    }

    private var colourValue: Double {
        primaryWindow(of: provider)?.usedPercent ?? WidgetDesignToken.zeroDouble
    }

    private var valueString: String {
        if provider.kind == .usage, let spend = provider.spendUSD {
            return "\(USDFormatter.string(from: spend)) spent"
        }
        guard let window = primaryWindow(of: provider) else {
            return ""
        }
        let remaining = max(WidgetDesignToken.zeroDouble,
                            min(WidgetDesignToken.percentMax,
                                WidgetDesignToken.percentMax - window.usedPercent))
        return "\(window.label) \(Int(remaining.rounded()))%"
    }
}

struct ProviderUnavailableRow: View {
    let providerName: String

    var body: some View {
        HStack(spacing: WidgetDesignToken.largeRowGap) {
            StatusDot(color: WidgetDesignToken.DataStatus.unavailable)
            Text(providerName)
                .font(.system(
                    size: WidgetDesignToken.bodySize,
                    weight: WidgetDesignToken.quotaTitleWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
                .lineLimit(WidgetDesignToken.singleLine)
            Spacer(minLength: WidgetDesignToken.zeroLength)
            Text("Unavailable")
                .font(.system(
                    size: WidgetDesignToken.captionSize,
                    weight: WidgetDesignToken.quotaLabelWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
        }
    }
}

struct MonthlyCostFooter: View {
    let cost: MonthlyCost

    var body: some View {
        HStack {
            Text("Monthly")
                .font(.system(
                    size: WidgetDesignToken.captionSize,
                    weight: WidgetDesignToken.quotaLabelWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
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

struct WidgetHeaderActions: View {
    let statusColor: Color?
    let lastUpdatedAt: Date?

    private var alignment: HorizontalAlignment {
        statusColor == nil ? .center : .trailing
    }

    init(statusColor: Color? = nil, lastUpdatedAt: Date? = nil) {
        self.statusColor = statusColor
        self.lastUpdatedAt = lastUpdatedAt
    }

    var body: some View {
        VStack(alignment: alignment, spacing: WidgetDesignToken.refreshTimestampSpacing) {
            HStack(spacing: WidgetDesignToken.refreshStatusSpacing) {
                if let statusColor {
                    StatusDot(
                        color: statusColor,
                        size: WidgetDesignToken.refreshStatusDotSize,
                        glowRadius: WidgetDesignToken.smallProviderStatusGlowRadius
                    )
                }
                WidgetRefreshButton()
            }
            if let lastUpdatedAt {
                Text(
                    lastUpdatedAt,
                    format: .dateTime
                        .hour(.twoDigits(amPM: .omitted))
                        .minute(.twoDigits)
                )
                .font(.system(
                    size: WidgetDesignToken.refreshTimestampSize,
                    weight: WidgetDesignToken.quotaLabelWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(
                    WidgetDesignToken.AuroraInk.faint.opacity(
                        WidgetDesignToken.refreshTimestampOpacity
                    )
                )
                .monospacedDigit()
                .lineLimit(WidgetDesignToken.singleLine)
                .contentTransition(.numericText())
            }
        }
    }
}

struct WidgetRefreshButton: View {

    private var destination: URL? {
        URL(string: "tokenking://refresh")
    }

    var body: some View {
        if let destination {
            Link(destination: destination) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(WidgetDesignToken.refreshBackgroundOpacity))
                        .overlay {
                            Circle()
                                .strokeBorder(
                                    Color.white.opacity(WidgetDesignToken.refreshBorderOpacity),
                                    lineWidth: WidgetDesignToken.orbCardBorderWidth
                                )
                        }
                    Image(systemName: "arrow.clockwise")
                        .font(.system(
                            size: WidgetDesignToken.refreshSymbolSize,
                            weight: .semibold
                        ))
                        .foregroundStyle(WidgetDesignToken.AuroraInk.secondary)
                }
                .frame(
                    width: WidgetDesignToken.refreshControlSize,
                    height: WidgetDesignToken.refreshControlSize
                )
                .shadow(
                    color: Color.black.opacity(WidgetDesignToken.refreshShadowOpacity),
                    radius: WidgetDesignToken.refreshShadowRadius
                )
            }
            .buttonStyle(WidgetRefreshButtonStyle())
            .accessibilityLabel("Refresh Token King")
            .accessibilityHint("Fetch the latest provider usage")
        }
    }
}

private struct WidgetRefreshButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? WidgetDesignToken.refreshPressedScale : 1)
            .rotationEffect(.degrees(
                configuration.isPressed ? WidgetDesignToken.refreshPressedRotation : 0
            ))
            .opacity(configuration.isPressed ? WidgetDesignToken.refreshPressedOpacity : 1)
            .animation(
                .easeOut(duration: WidgetDesignToken.refreshAnimationDuration),
                value: configuration.isPressed
            )
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = WidgetDesignToken.dotSize
    var glowRadius: CGFloat = WidgetDesignToken.barGlowRadius

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(WidgetDesignToken.barGlowOpacity),
                    radius: glowRadius, x: 0, y: 0)
    }
}

struct RemainingQuotaMetric: View {
    let remaining: Double
    let numberSize: CGFloat
    let suffixSize: CGFloat
    let tracking: CGFloat
    var suffixLift: CGFloat = 0

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.orbSuffixSpacing) {
            Text("\(Int(remaining.rounded()))")
                .font(.system(
                    size: numberSize,
                    weight: WidgetDesignToken.percentHeroWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .monospacedDigit()
                .tracking(tracking)
                .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
            Text("%")
                .font(.system(
                    size: suffixSize,
                    weight: WidgetDesignToken.percentSuffixWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .baselineOffset(suffixLift)
                .foregroundStyle(WidgetDesignToken.AuroraInk.primary)
        }
    }
}

struct SecondaryQuotaMetric: View {
    let window: UsageWindow
    let numberSize: CGFloat
    var label: String? = nil

    private var remaining: Double {
        max(WidgetDesignToken.zeroDouble,
            min(WidgetDesignToken.percentMax,
                WidgetDesignToken.percentMax - window.usedPercent))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.smallGap) {
            Text(label ?? "\(window.label) left")
                .font(.system(
                    size: WidgetDesignToken.footerSize,
                    weight: WidgetDesignToken.weeklyLabelWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(WidgetDesignToken.AuroraInk.faint)
                .lineLimit(WidgetDesignToken.singleLine)
            RemainingQuotaMetric(
                remaining: remaining,
                numberSize: numberSize,
                suffixSize: numberSize == WidgetDesignToken.weeklyHeroSize
                    ? WidgetDesignToken.weeklyHeroSuffixSize
                    : WidgetDesignToken.orbCopySuffixSize,
                tracking: WidgetDesignToken.percentSuffixTracking
            )
        }
    }
}

struct QuotaUpdatedMetadata: View {
    let fetchedAt: Date?
    let status: WidgetDataStatus

    var body: some View {
        VStack(alignment: .trailing, spacing: WidgetDesignToken.smallGap) {
            Text(status == .stale ? "Stale data" : "Updated")
                .font(.system(
                    size: WidgetDesignToken.footerSize,
                    weight: WidgetDesignToken.updatedWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
            Text(fetchedAt?.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)) ?? "Time unknown")
                .font(.system(size: WidgetDesignToken.quotaMetadataSize, design: .monospaced))
        }
        .foregroundStyle(WidgetDesignToken.AuroraInk.faint)
    }
}

struct CapsuleProgressBar: View {
    @Environment(\.colorScheme) private var scheme
    let value: Double
    var colorValue: Double? = nil
    var tierOverride: WidgetDesignToken.Aurora.Tier? = nil
    var height: CGFloat = WidgetDesignToken.barHeight
    var glow: Bool = false
    var trackColor: Color? = nil

    private var fraction: CGFloat {
        CGFloat(min(max(value, WidgetDesignToken.zeroDouble), WidgetDesignToken.percentMax) / WidgetDesignToken.percentMax)
    }

    private var gradientColors: (start: Color, end: Color) {
        if let tierOverride {
            return (start: tierOverride.progressStart, end: tierOverride.progressEnd)
        }
        return WidgetDesignToken.Aurora.progressGradient(forUsedPercent: colorValue ?? value)
    }

    var body: some View {
        GeometryReader { geometry in
            let progressWidth = geometry.size.width * fraction
            let (startColor, endColor) = gradientColors
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: WidgetDesignToken.barRadius, style: .continuous)
                    .fill(trackColor ?? WidgetDesignToken.AuroraInk.faint.opacity(WidgetDesignToken.trackOpacity))
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
    var fallbackTint: Color = .secondary

    var body: some View {
        if let assetName = providerAssetName(providerId) {
            Image(assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(providerBrandTint(providerId) ?? fallbackTint)
        } else {
            Image(systemName: providerIconSystemName(providerId))
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(providerBrandTint(providerId) ?? fallbackTint)
        }
    }
}

// MARK: - Helpers

func topProvider(snapshot: WidgetSnapshot) -> ProviderSnapshot? {
    snapshot.providers
        .compactMap { provider -> (ProviderSnapshot, Double)? in
            guard provider.widgetDataStatus != .unavailable,
                  let window = primaryWindow(of: provider) else { return nil }
            return (provider, window.usedPercent)
        }
        .max(by: { $0.1 < $1.1 })?.0
}

func topN(snapshot: WidgetSnapshot, n: Int) -> [ProviderSnapshot] {
    let sorted = snapshot.providers.sorted { leftProvider, rightProvider in
        let leftUnavailable = leftProvider.widgetDataStatus == .unavailable
        let rightUnavailable = rightProvider.widgetDataStatus == .unavailable
        if leftUnavailable != rightUnavailable { return !leftUnavailable }
        let leftPercent = primaryWindow(of: leftProvider)?.usedPercent ?? WidgetDesignToken.zeroDouble
        let rightPercent = primaryWindow(of: rightProvider)?.usedPercent ?? WidgetDesignToken.zeroDouble
        if leftPercent == rightPercent {
            return leftProvider.id.localizedCaseInsensitiveCompare(rightProvider.id) == .orderedAscending
        }
        return leftPercent > rightPercent
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

private enum WidgetUsageWindowID {
    static let aggregate = "primary"
}

/// Returns the next data-layer-ranked metric after the displayed primary.
/// A synthetic aggregate must not displace a real secondary quota window.
func secondaryWindow(of provider: ProviderSnapshot) -> UsageWindow? {
    guard let primary = primaryWindow(of: provider) else { return nil }
    return provider.windows
        .filter { window in
            window.id != primary.id &&
                (primary.id == WidgetUsageWindowID.aggregate ||
                    window.id != WidgetUsageWindowID.aggregate)
        }
        .enumerated()
        .min { lhs, rhs in
            let leftPriority = lhs.element.priority ?? Int.max
            let rightPriority = rhs.element.priority ?? Int.max
            return leftPriority == rightPriority ? lhs.offset < rhs.offset : leftPriority < rightPriority
        }?
        .element
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
    case "kimi_cn", "kimi_global":       return "KimiIcon"
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
    TokenKingEntry(date: .now, kind: .small, selectedProviderId: nil, snapshot: .previewFixture, readStatus: .ready, snapshotAgeSeconds: 30)
}

#Preview("MediumOverview/Light/Focused", as: .systemMedium) {
    TokenKingWidgetMediumOverview()
} timeline: {
    TokenKingEntry(date: .now, kind: .mediumOverview, selectedProviderId: nil, snapshot: .previewFixture, readStatus: .ready, snapshotAgeSeconds: 30)
}

#Preview("MediumDetail/Light/Focused", as: .systemMedium) {
    TokenKingWidgetMediumDetail()
} timeline: {
    TokenKingEntry(date: .now, kind: .mediumDetail, selectedProviderId: "codex", snapshot: .previewFixture, readStatus: .ready, snapshotAgeSeconds: 30)
}

#Preview("LargeOverview/Light/Focused", as: .systemLarge) {
    TokenKingWidgetLargeOverview()
} timeline: {
    TokenKingEntry(date: .now, kind: .largeOverview, selectedProviderId: nil, snapshot: .previewFixture, readStatus: .ready, snapshotAgeSeconds: 30)
}

#Preview("LargeDetail/Light/Focused", as: .systemLarge) {
    TokenKingWidgetLargeDetail()
} timeline: {
    TokenKingEntry(date: .now, kind: .largeDetail, selectedProviderId: "codex", snapshot: .previewFixture, readStatus: .ready, snapshotAgeSeconds: 30)
}

#Preview("SearchEngines/Light/Focused", as: .systemLarge) {
    TokenKingWidgetSearchEngines()
} timeline: {
    TokenKingEntry(date: .now, kind: .searchEngines, selectedProviderId: nil, snapshot: .previewFixture, readStatus: .ready, snapshotAgeSeconds: 30)
}

#Preview("Small/UsageProvider", as: .systemSmall) {
    TokenKingWidgetSmall()
} timeline: {
    TokenKingEntry(date: .now, kind: .small, selectedProviderId: "openrouter", snapshot: .previewFixture, readStatus: .ready, snapshotAgeSeconds: 30)
}

#Preview("Small/Light/NoFile", as: .systemSmall) {
    TokenKingWidgetSmall()
} timeline: {
    TokenKingEntry(date: .now, kind: .small, selectedProviderId: nil, snapshot: nil, readStatus: .noFile, snapshotAgeSeconds: nil)
}

#Preview("Medium/Light/Empty", as: .systemMedium) {
    TokenKingWidgetMediumOverview()
} timeline: {
    TokenKingEntry(date: .now, kind: .mediumOverview, selectedProviderId: nil, snapshot: WidgetSnapshot(version: 1, snapshotAt: .now, providers: [], monthlyCost: nil), readStatus: .ready, snapshotAgeSeconds: 30)
}

#Preview("Large/Light/Stale", as: .systemLarge) {
    TokenKingWidgetLargeOverview()
} timeline: {
    TokenKingEntry(date: .now, kind: .largeOverview, selectedProviderId: nil, snapshot: .previewFixture, readStatus: .stale, snapshotAgeSeconds: 600)
}
