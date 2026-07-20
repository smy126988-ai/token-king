import Foundation
import SwiftUI
import WidgetKit

struct CodexQuotaCardView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TokenKingEntry

    var body: some View {
        ZStack {
            switch CodexCardResolver.resolve(entry: entry) {
            case .content(let content):
                CodexResolvedQuotaCard(content: content, family: family)
            case .state(let state):
                CodexWidgetStateView(state: state, family: family)
            }
        }
        .padding(WidgetDesignToken.cardContentPadding)
    }
}

private enum CodexCardResolver {
    static func resolve(entry: TokenKingEntry) -> CodexCardResolution {
        switch entry.readStatus {
        case .placeholder:
            return .state(.updating)
        case .noFile:
            return .state(.openTokenKing)
        case .corrupt:
            return .state(.snapshotCorrupt)
        case .ready, .stale:
            break
        }

        guard let codex = entry.snapshot?.providers.first(where: {
            $0.id == WidgetDesignToken.ProviderID.codex
        }) else {
            return entry.selectedProviderId == nil
                ? .state(.connectCodex)
                : .state(.accountUnavailable)
        }

        let accounts = codex.accounts ?? []
        let account: ProviderAccountSnapshot
        if let selectedAccountId = entry.selectedProviderId {
            guard let selected = accounts.first(where: { $0.id == selectedAccountId }) else {
                return .state(.accountUnavailable)
            }
            account = selected
        } else {
            guard accounts.count == WidgetDesignToken.singleWindowCount,
                  let onlyAccount = accounts.first else {
                return accounts.isEmpty ? .state(.connectCodex) : .state(.selectAccount)
            }
            account = onlyAccount
        }

        guard account.status != .unavailable else {
            return .state(.accountUnavailable)
        }
        guard let firstMetric = account.metrics.first,
              let hero = CodexMetricPresentation(metric: firstMetric) else {
            return .state(.quotaUnavailable)
        }

        let secondary = account.metrics.dropFirst().first.flatMap(CodexMetricPresentation.init(metric:))
        let freshness = freshness(entry: entry, account: account)
        return .content(
            CodexCardContent(
                accountName: account.displayName,
                plan: account.plan,
                hero: hero,
                secondary: secondary,
                freshness: freshness,
                lastUpdatedAt: account.fetchedAt
            )
        )
    }

    private static func freshness(
        entry: TokenKingEntry,
        account: ProviderAccountSnapshot
    ) -> CodexFreshness {
        guard account.status == .available,
              entry.readStatus == .ready,
              let fetchedAt = account.fetchedAt,
              entry.date.timeIntervalSince(fetchedAt) <= WidgetDesignToken.codexFreshnessThreshold else {
            return .stale
        }
        return .fresh
    }
}

private enum CodexCardResolution {
    case content(CodexCardContent)
    case state(CodexWidgetState)
}

private struct CodexCardContent {
    let accountName: String
    let plan: String?
    let hero: CodexMetricPresentation
    let secondary: CodexMetricPresentation?
    let freshness: CodexFreshness
    let lastUpdatedAt: Date?
}

private struct CodexMetricPresentation: Equatable {
    let label: String
    let usedPercent: Double
    let remainingPercent: Double
    let resetsAt: Date?

    init?(metric: UsageWindow) {
        guard metric.usedPercent.isFinite,
              metric.usedPercent >= WidgetDesignToken.zeroDouble,
              metric.usedPercent <= WidgetDesignToken.percentMax else {
            return nil
        }
        label = metric.label
        usedPercent = metric.usedPercent
        remainingPercent = WidgetDesignToken.percentMax - metric.usedPercent
        resetsAt = metric.resetsAt
    }

}

private enum CodexFreshness {
    case fresh
    case stale

    var statusColor: Color {
        switch self {
        case .fresh: WidgetDesignToken.DataStatus.fresh
        case .stale: WidgetDesignToken.DataStatus.stale
        }
    }
}

private struct CodexResolvedQuotaCard: View {
    let content: CodexCardContent
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .systemSmall:
            CodexSmallQuotaCard(
                accountName: content.accountName,
                plan: content.plan,
                hero: content.hero,
                freshness: content.freshness,
                lastUpdatedAt: content.lastUpdatedAt
            )
        case .systemLarge:
            CodexLargeQuotaCard(
                accountName: content.accountName,
                plan: content.plan,
                hero: content.hero,
                secondary: content.secondary,
                freshness: content.freshness,
                lastUpdatedAt: content.lastUpdatedAt
            )
        default:
            CodexMediumQuotaCard(
                accountName: content.accountName,
                plan: content.plan,
                hero: content.hero,
                secondary: content.secondary,
                freshness: content.freshness,
                lastUpdatedAt: content.lastUpdatedAt
            )
        }
    }
}

private struct CodexSmallQuotaCard: View {
    let accountName: String
    let plan: String?
    let hero: CodexMetricPresentation
    let freshness: CodexFreshness
    let lastUpdatedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.zeroSpacing) {
            CodexCardHeader(
                accountName: accountName,
                plan: plan,
                statusColor: freshness.statusColor,
                markSize: WidgetDesignToken.codexHeaderMarkSmallSize,
                titleSize: WidgetDesignToken.codexHeaderSmallSize,
                accountSize: WidgetDesignToken.codexAccountSmallSize,
                showsAccount: false,
                lastUpdatedAt: lastUpdatedAt
            )
            Spacer(minLength: WidgetDesignToken.codexSmallHeaderToHeroSpacing)
            CodexPercentValue(
                percent: hero.remainingPercent,
                numberSize: WidgetDesignToken.codexHeroSmallSize,
                suffixSize: WidgetDesignToken.codexSuffixSmallSize,
                tracking: WidgetDesignToken.codexHeroTrackingSmall,
                suffixLift: WidgetDesignToken.codexSuffixLiftSmall
            )
            Spacer(minLength: WidgetDesignToken.codexSmallHeroToBarSpacing)
            CapsuleProgressBar(
                value: hero.remainingPercent,
                colorValue: hero.usedPercent,
                tierOverride: WidgetDesignToken.CodexQuota.tier(forUsedPercent: hero.usedPercent),
                height: WidgetDesignToken.barHeight,
                glow: true,
                trackColor: WidgetDesignToken.CodexInk.track
            )
            SmallQuotaMetadata(windowLabel: hero.label, resetsAt: hero.resetsAt)
                .padding(.top, WidgetDesignToken.smallBarToResetSpacing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CodexMediumQuotaCard: View {
    let accountName: String
    let plan: String?
    let hero: CodexMetricPresentation
    let secondary: CodexMetricPresentation?
    let freshness: CodexFreshness
    let lastUpdatedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.codexMediumSpacing) {
            CodexCompactHeader(
                accountName: accountName,
                plan: plan,
                statusColor: freshness.statusColor,
                markSize: WidgetDesignToken.codexHeaderMarkMediumSize,
                titleSize: WidgetDesignToken.codexHeaderMediumSize,
                accountSize: WidgetDesignToken.codexAccountMediumSize,
                lastUpdatedAt: lastUpdatedAt
            )
            HStack(alignment: .bottom, spacing: WidgetDesignToken.codexSectionSpacing) {
                VStack(alignment: .leading, spacing: WidgetDesignToken.codexMediumSpacing) {
                    CodexQuotaHero(
                        label: hero.label,
                        remainingPercent: hero.remainingPercent,
                        resetsAt: hero.resetsAt,
                        numberSize: WidgetDesignToken.codexHeroMediumSize,
                        suffixSize: WidgetDesignToken.codexSuffixMediumSize,
                        descriptorSize: WidgetDesignToken.codexDescriptorMediumSize,
                        resetSize: WidgetDesignToken.codexResetMediumSize,
                        tracking: WidgetDesignToken.codexHeroTrackingMedium,
                        suffixLift: WidgetDesignToken.codexSuffixLiftMedium
                    )
                    CapsuleProgressBar(
                        value: hero.remainingPercent,
                        colorValue: hero.usedPercent,
                        tierOverride: WidgetDesignToken.CodexQuota.tier(forUsedPercent: hero.usedPercent),
                        height: WidgetDesignToken.codexBarMediumHeight,
                        glow: true,
                        trackColor: WidgetDesignToken.CodexInk.track
                    )
                }
                .frame(minWidth: WidgetDesignToken.codexMediumPrimaryMinWidth,
                       maxWidth: .infinity,
                       alignment: .leading)
                Rectangle()
                    .fill(Color.white.opacity(WidgetDesignToken.codexDividerOpacity))
                    .frame(width: WidgetDesignToken.hairline)
                CodexSecondarySummary(
                    metric: secondary,
                    freshness: freshness,
                    numberSize: WidgetDesignToken.codexSecondaryMediumSize,
                    suffixSize: WidgetDesignToken.codexSecondarySuffixMediumSize,
                    labelSize: WidgetDesignToken.codexMetadataMediumSize
                )
                .frame(width: WidgetDesignToken.codexMediumSecondaryWidth, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CodexLargeQuotaCard: View {
    let accountName: String
    let plan: String?
    let hero: CodexMetricPresentation
    let secondary: CodexMetricPresentation?
    let freshness: CodexFreshness
    let lastUpdatedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.codexLargeSpacing) {
            CodexCardHeader(
                accountName: accountName,
                plan: plan,
                statusColor: freshness.statusColor,
                markSize: WidgetDesignToken.codexHeaderMarkLargeSize,
                titleSize: WidgetDesignToken.codexHeaderLargeSize,
                accountSize: WidgetDesignToken.codexAccountLargeSize,
                showsAccount: true,
                lastUpdatedAt: lastUpdatedAt
            )
            Color.clear
                .frame(height: WidgetDesignToken.codexLargeHeroTopSpacing)
            CodexQuotaHero(
                label: hero.label,
                remainingPercent: hero.remainingPercent,
                resetsAt: hero.resetsAt,
                numberSize: WidgetDesignToken.codexHeroLargeSize,
                suffixSize: WidgetDesignToken.codexSuffixLargeSize,
                descriptorSize: WidgetDesignToken.codexDescriptorLargeSize,
                resetSize: WidgetDesignToken.codexResetLargeSize,
                tracking: WidgetDesignToken.codexHeroTrackingLarge,
                suffixLift: WidgetDesignToken.codexSuffixLiftLarge
            )
            CapsuleProgressBar(
                value: hero.remainingPercent,
                colorValue: hero.usedPercent,
                tierOverride: WidgetDesignToken.CodexQuota.tier(forUsedPercent: hero.usedPercent),
                height: WidgetDesignToken.codexBarLargeHeight,
                glow: true,
                trackColor: WidgetDesignToken.CodexInk.track
            )
            Spacer(minLength: WidgetDesignToken.zeroLength)
            Rectangle()
                .fill(Color.white.opacity(WidgetDesignToken.codexDividerOpacity))
                .frame(height: WidgetDesignToken.hairline)
            HStack(alignment: .bottom, spacing: WidgetDesignToken.codexLargeMetadataSpacing) {
                CodexSecondarySummary(
                    metric: secondary,
                    freshness: freshness,
                    numberSize: WidgetDesignToken.codexSecondaryLargeSize,
                    suffixSize: WidgetDesignToken.codexSecondarySuffixLargeSize,
                    labelSize: WidgetDesignToken.codexMetadataLargeSize
                )
                Spacer(minLength: WidgetDesignToken.zeroLength)
                CodexFreshnessPill(freshness: freshness, size: WidgetDesignToken.codexMetadataLargeSize)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct CodexCardHeader: View {
    let accountName: String
    let plan: String?
    let statusColor: Color
    let markSize: CGFloat
    let titleSize: CGFloat
    let accountSize: CGFloat
    let showsAccount: Bool
    let lastUpdatedAt: Date?

    var body: some View {
        HStack(spacing: WidgetDesignToken.codexMediumSpacing) {
            CodexProviderMark(size: markSize)
            VStack(alignment: .leading, spacing: WidgetDesignToken.codexSmallSpacing) {
                HStack(spacing: WidgetDesignToken.codexMediumSpacing) {
                    Text("Codex")
                        .font(.system(
                            size: titleSize,
                            weight: WidgetDesignToken.quotaTitleWeight,
                            design: WidgetDesignToken.quotaFontDesign
                        ))
                    if let plan, !plan.isEmpty {
                        Text(plan)
                            .font(.system(
                                size: titleSize,
                                weight: WidgetDesignToken.quotaLabelWeight,
                                design: WidgetDesignToken.quotaFontDesign
                            ))
                            .foregroundStyle(WidgetDesignToken.CodexInk.secondary)
                            .lineLimit(WidgetDesignToken.singleLine)
                    }
                }
                if showsAccount {
                    Text(accountName)
                        .font(.system(
                            size: accountSize,
                            weight: WidgetDesignToken.quotaLabelWeight,
                            design: WidgetDesignToken.quotaFontDesign
                        ))
                        .foregroundStyle(WidgetDesignToken.CodexInk.faint)
                        .lineLimit(WidgetDesignToken.singleLine)
                }
            }
            .foregroundStyle(WidgetDesignToken.CodexInk.primary)
            .minimumScaleFactor(WidgetDesignToken.eyebrowMinimumScale)
            Spacer(minLength: WidgetDesignToken.zeroLength)
            WidgetHeaderActions(statusColor: statusColor, lastUpdatedAt: lastUpdatedAt)
        }
    }
}

private struct CodexCompactHeader: View {
    let accountName: String
    let plan: String?
    let statusColor: Color
    let markSize: CGFloat
    let titleSize: CGFloat
    let accountSize: CGFloat
    let lastUpdatedAt: Date?

    var body: some View {
        HStack(spacing: WidgetDesignToken.codexMediumSpacing) {
            CodexProviderMark(size: markSize)
            Text("Codex")
                .font(.system(
                    size: titleSize,
                    weight: WidgetDesignToken.quotaTitleWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(WidgetDesignToken.CodexInk.primary)
            if let plan, !plan.isEmpty {
                Text(plan)
                    .font(.system(
                        size: accountSize,
                        weight: WidgetDesignToken.quotaLabelWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
                    .foregroundStyle(WidgetDesignToken.CodexInk.secondary)
                    .lineLimit(WidgetDesignToken.singleLine)
            }
            Spacer(minLength: WidgetDesignToken.zeroLength)
            Text(accountName)
                .font(.system(
                    size: accountSize,
                    weight: WidgetDesignToken.quotaLabelWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(WidgetDesignToken.CodexInk.faint)
                .lineLimit(WidgetDesignToken.singleLine)
                .minimumScaleFactor(WidgetDesignToken.eyebrowMinimumScale)
            WidgetHeaderActions(statusColor: statusColor, lastUpdatedAt: lastUpdatedAt)
        }
    }
}

private struct CodexPercentValue: View {
    let percent: Double
    let numberSize: CGFloat
    let suffixSize: CGFloat
    let tracking: CGFloat
    let suffixLift: CGFloat

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.zeroSpacing) {
            Text(IntegerFormatter.string(from: Int(percent.rounded())))
                .font(.system(
                    size: numberSize,
                    weight: WidgetDesignToken.quotaNumberWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .tracking(tracking)
            Text("%")
                .font(.system(
                    size: suffixSize,
                    weight: WidgetDesignToken.quotaSuffixWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .padding(.bottom, suffixLift)
        }
        .foregroundStyle(WidgetDesignToken.CodexInk.primary)
        .monospacedDigit()
    }
}

private struct CodexSecondarySummary: View {
    let metric: CodexMetricPresentation?
    let freshness: CodexFreshness
    let numberSize: CGFloat
    let suffixSize: CGFloat
    let labelSize: CGFloat

    var body: some View {
        if let metric {
            VStack(alignment: .leading, spacing: WidgetDesignToken.codexSmallSpacing) {
                Text(metric.label)
                    .font(.system(
                        size: labelSize,
                        weight: WidgetDesignToken.quotaLabelWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
                    .foregroundStyle(WidgetDesignToken.CodexInk.faint)
                    .lineLimit(WidgetDesignToken.singleLine)
                    .minimumScaleFactor(WidgetDesignToken.eyebrowMinimumScale)
                CodexPercentValue(
                    percent: metric.remainingPercent,
                    numberSize: numberSize,
                    suffixSize: suffixSize,
                    tracking: WidgetDesignToken.codexHeroTrackingSmall,
                    suffixLift: WidgetDesignToken.zeroLength
                )
                if let resetsAt = metric.resetsAt {
                    Text(RelativeResetFormatter.string(from: resetsAt))
                        .font(.system(
                            size: labelSize,
                            weight: WidgetDesignToken.quotaLabelWeight,
                            design: WidgetDesignToken.quotaFontDesign
                        ))
                        .foregroundStyle(WidgetDesignToken.CodexInk.faint)
                        .lineLimit(WidgetDesignToken.singleLine)
                        .minimumScaleFactor(WidgetDesignToken.eyebrowMinimumScale)
                }
            }
        } else {
            CodexFreshnessLabel(freshness: freshness, size: labelSize)
        }
    }
}

private struct CodexFreshnessPill: View {
    let freshness: CodexFreshness
    let size: CGFloat

    var body: some View {
        HStack(spacing: WidgetDesignToken.codexSmallSpacing) {
            StatusDot(color: freshness.statusColor)
            CodexFreshnessLabel(freshness: freshness, size: size)
        }
        .padding(.horizontal, WidgetDesignToken.codexMetadataPillHPadding)
        .padding(.vertical, WidgetDesignToken.codexMetadataPillVPadding)
        .background(Color.white.opacity(WidgetDesignToken.codexStatusRingOpacity))
        .clipShape(RoundedRectangle(cornerRadius: WidgetDesignToken.codexMetadataPillRadius))
    }
}

private struct CodexQuotaHero: View {
    let label: String
    let remainingPercent: Double
    let resetsAt: Date?
    let numberSize: CGFloat
    let suffixSize: CGFloat
    let descriptorSize: CGFloat
    let resetSize: CGFloat
    let tracking: CGFloat
    let suffixLift: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.codexSmallSpacing) {
            HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.zeroSpacing) {
                Text(IntegerFormatter.string(from: Int(remainingPercent.rounded())))
                    .font(.system(
                        size: numberSize,
                        weight: WidgetDesignToken.quotaNumberWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
                    .tracking(tracking)
                Text("%")
                    .font(.system(
                        size: suffixSize,
                        weight: WidgetDesignToken.quotaSuffixWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
                    .padding(.bottom, suffixLift)
            }
            .foregroundStyle(WidgetDesignToken.CodexInk.primary)
            .monospacedDigit()
            .accessibilityLabel("\(Int(remainingPercent.rounded())) percent remaining")
            Text(label)
                .font(.system(
                    size: descriptorSize,
                    weight: WidgetDesignToken.quotaLabelWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(WidgetDesignToken.CodexInk.secondary)
                .lineLimit(WidgetDesignToken.singleLine)
            if let resetsAt {
                Text(RelativeResetFormatter.string(from: resetsAt))
                    .font(.system(
                        size: resetSize,
                        weight: WidgetDesignToken.quotaLabelWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
                    .foregroundStyle(WidgetDesignToken.CodexInk.faint)
                    .lineLimit(WidgetDesignToken.singleLine)
            }
        }
    }
}

private struct CodexCardFooter: View {
    let metric: CodexMetricPresentation?
    let freshness: CodexFreshness
    let numberSize: CGFloat
    let suffixSize: CGFloat
    let labelSize: CGFloat
    let showsProviderMark: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: WidgetDesignToken.codexSectionSpacing) {
            if let metric {
                CodexSecondaryMetric(
                    label: metric.label,
                    remainingPercent: metric.remainingPercent,
                    resetsAt: metric.resetsAt,
                    numberSize: numberSize,
                    suffixSize: suffixSize,
                    labelSize: labelSize
                )
            } else {
                CodexFreshnessLabel(freshness: freshness, size: labelSize)
            }
            Spacer(minLength: WidgetDesignToken.zeroLength)
            if metric != nil {
                CodexFreshnessLabel(freshness: freshness, size: labelSize)
            }
            if showsProviderMark {
                CodexProviderMark(size: WidgetDesignToken.providerMarkSize)
            }
        }
    }
}

private struct CodexSecondaryMetric: View {
    let label: String
    let remainingPercent: Double
    let resetsAt: Date?
    let numberSize: CGFloat
    let suffixSize: CGFloat
    let labelSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.codexSmallSpacing) {
            Text(label)
                .font(.system(
                    size: labelSize,
                    weight: WidgetDesignToken.quotaLabelWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(WidgetDesignToken.CodexInk.faint)
                .lineLimit(WidgetDesignToken.singleLine)
            HStack(alignment: .lastTextBaseline, spacing: WidgetDesignToken.zeroSpacing) {
                Text(IntegerFormatter.string(from: Int(remainingPercent.rounded())))
                    .font(.system(
                        size: numberSize,
                        weight: WidgetDesignToken.quotaNumberWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
                Text("%")
                    .font(.system(
                        size: suffixSize,
                        weight: WidgetDesignToken.quotaSuffixWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
            }
            .foregroundStyle(WidgetDesignToken.CodexInk.primary)
            .monospacedDigit()
            if let resetsAt {
                Text(RelativeResetFormatter.string(from: resetsAt))
                    .font(.system(
                        size: labelSize,
                        weight: WidgetDesignToken.quotaLabelWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
                    .foregroundStyle(WidgetDesignToken.CodexInk.faint)
                    .lineLimit(WidgetDesignToken.singleLine)
            }
        }
    }
}

private struct CodexFreshnessLabel: View {
    let freshness: CodexFreshness
    let size: CGFloat

    var body: some View {
        switch freshness {
        case .fresh:
            Text("Fresh data")
                .font(.system(
                    size: size,
                    weight: WidgetDesignToken.quotaLabelWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(WidgetDesignToken.CodexInk.faint)
        case .stale:
            Text("Stale data")
                .font(.system(
                    size: size,
                    weight: WidgetDesignToken.quotaLabelWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(WidgetDesignToken.DataStatus.stale)
        }
    }
}

private struct CodexStatusLight: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(Color.white.opacity(WidgetDesignToken.codexStatusRingOpacity))
            .frame(width: WidgetDesignToken.codexStatusRingSize,
                   height: WidgetDesignToken.codexStatusRingSize)
            .overlay(StatusDot(color: color))
    }
}

private struct CodexProviderMark: View {
    let size: CGFloat

    var body: some View {
        ProviderIconView(
            providerId: WidgetDesignToken.ProviderID.codex,
            size: size,
            fallbackTint: WidgetDesignToken.CodexInk.primary
        )
        .frame(width: size, height: size)
    }
}

private enum CodexWidgetState {
    case updating
    case openTokenKing
    case selectAccount
    case accountUnavailable
    case connectCodex
    case quotaUnavailable
    case snapshotCorrupt

    var statusColor: Color {
        switch self {
        case .updating, .openTokenKing, .selectAccount, .connectCodex:
            WidgetDesignToken.DataStatus.stale
        case .accountUnavailable, .quotaUnavailable, .snapshotCorrupt:
            WidgetDesignToken.DataStatus.unavailable
        }
    }

    var iconName: String {
        switch self {
        case .updating: "arrow.triangle.2.circlepath"
        case .openTokenKing: "arrow.up.forward.app"
        case .selectAccount: "person.crop.circle.badge.checkmark"
        case .accountUnavailable: "person.crop.circle.badge.exclamationmark"
        case .connectCodex: "link.badge.plus"
        case .quotaUnavailable: "gauge.with.dots.needle.0percent"
        case .snapshotCorrupt: "exclamationmark.triangle"
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .updating: "Updating widget"
        case .openTokenKing: "Open Token King"
        case .selectAccount: "Select account"
        case .accountUnavailable: "Account unavailable"
        case .connectCodex: "Connect Codex in Token King"
        case .quotaUnavailable: "Quota unavailable"
        case .snapshotCorrupt: "Snapshot corrupt"
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .updating: "Loading the latest quota"
        case .openTokenKing: "Populate Codex quota"
        case .selectAccount: "Edit this widget"
        case .accountUnavailable: "Choose an available account"
        case .connectCodex: "Open Token King to connect"
        case .quotaUnavailable: "Refresh Codex in Token King"
        case .snapshotCorrupt: "Open Token King to refresh"
        }
    }
}

private struct CodexWidgetStateView: View {
    let state: CodexWidgetState
    let family: WidgetFamily

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetDesignToken.codexMediumSpacing) {
            HStack {
                CodexProviderMark(size: WidgetDesignToken.codexHeaderMarkLargeSize)
                Spacer(minLength: WidgetDesignToken.zeroLength)
                WidgetHeaderActions(statusColor: state.statusColor)
            }
            Spacer(minLength: WidgetDesignToken.zeroLength)
            Image(systemName: stateIconName)
                .font(.system(size: WidgetDesignToken.codexStateIconSize, weight: .semibold))
                .foregroundStyle(state.statusColor)
            Text(state.title)
                .font(.system(
                    size: WidgetDesignToken.codexStateTitleSize,
                    weight: WidgetDesignToken.quotaTitleWeight,
                    design: WidgetDesignToken.quotaFontDesign
                ))
                .foregroundStyle(WidgetDesignToken.CodexInk.primary)
                .lineLimit(
                    family == .systemSmall
                        ? WidgetDesignToken.codexStateSmallLineCount
                        : WidgetDesignToken.singleLine
                )
                .minimumScaleFactor(WidgetDesignToken.eyebrowMinimumScale)
            if family != .systemSmall {
                Text(state.detail)
                    .font(.system(
                        size: WidgetDesignToken.codexStateDetailSize,
                        weight: WidgetDesignToken.quotaLabelWeight,
                        design: WidgetDesignToken.quotaFontDesign
                    ))
                    .foregroundStyle(WidgetDesignToken.CodexInk.faint)
                    .lineLimit(WidgetDesignToken.singleLine)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var stateIconName: String { state.iconName }
}

#Preview("Codex Small", as: .systemSmall) {
    TokenKingCodexWidget()
} timeline: {
    TokenKingEntry(
        date: .now,
        kind: .small,
        selectedProviderId: nil,
        snapshot: .codexQuotaPreviewFixture,
        readStatus: .ready,
        snapshotAgeSeconds: WidgetDesignToken.zeroDouble
    )
}

#Preview("Codex Medium", as: .systemMedium) {
    TokenKingCodexWidget()
} timeline: {
    TokenKingEntry(
        date: .now,
        kind: .small,
        selectedProviderId: nil,
        snapshot: .codexQuotaPreviewFixture,
        readStatus: .ready,
        snapshotAgeSeconds: WidgetDesignToken.zeroDouble
    )
}

#Preview("Codex Large", as: .systemLarge) {
    TokenKingCodexWidget()
} timeline: {
    TokenKingEntry(
        date: .now,
        kind: .small,
        selectedProviderId: nil,
        snapshot: .codexQuotaPreviewFixture,
        readStatus: .stale,
        snapshotAgeSeconds: BasePreviewValue.staleAge
    )
}

private enum BasePreviewValue {
    static let shortResetHours = 2
    static let longResetHours = 72
    static let staleAge: Double = 7200
}

private extension WidgetSnapshot {
    static var codexQuotaPreviewFixture: WidgetSnapshot {
        let now = Date()
        let metrics = [
            UsageWindow(
                id: "session",
                label: "Session",
                usedPercent: WidgetDesignToken.fixtureCodex5hPercent,
                resetsAt: now.addingTimeInterval(
                    Double(BasePreviewValue.shortResetHours) * WidgetDesignToken.secondsPerHour
                ),
                used: nil,
                limit: nil,
                windowSeconds: nil,
                priority: WidgetDesignToken.zeroInt
            ),
            UsageWindow(
                id: "week",
                label: "Weekly",
                usedPercent: WidgetDesignToken.fixtureCodexWeeklyPercent,
                resetsAt: now.addingTimeInterval(
                    Double(BasePreviewValue.longResetHours) * WidgetDesignToken.secondsPerHour
                ),
                used: nil,
                limit: nil,
                windowSeconds: nil,
                priority: WidgetDesignToken.singleWindowCount
            )
        ]
        let account = ProviderAccountSnapshot(
            id: "preview-account",
            displayName: "p•••@example.com",
            plan: "Plus",
            status: .available,
            metrics: metrics,
            fetchedAt: now
        )
        let provider = ProviderSnapshot(
            id: WidgetDesignToken.ProviderID.codex,
            displayName: "Codex",
            kind: .quota,
            primaryWindowId: nil,
            windows: metrics,
            spendUSD: nil,
            fetchedAt: now,
            accounts: [account]
        )
        return WidgetSnapshot(
            version: WidgetDesignToken.snapshotVersion,
            snapshotAt: now,
            providers: [provider],
            monthlyCost: nil
        )
    }
}
