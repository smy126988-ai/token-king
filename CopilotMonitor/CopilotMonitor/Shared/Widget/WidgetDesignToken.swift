import SwiftUI
import Foundation

// ============================================================================
// Widget design tokens — SwiftUI mirror of DESIGN.md (repo root).
// ============================================================================
// Every literal below traces to a key in DESIGN.md's YAML front matter.
// Change the visual there first, then update these values. No stray hex.
//   Layer 1: Color(hex:) / Color(light:dark:)   — value primitives
//   Layer 2: WidgetDesignToken enum              — named tokens
//   (Layer 3 composite views removed: the system owns the widget background)
// ============================================================================

// MARK: - Layer 1: Color primitives

extension Color {
    /// Hex string → Color. Accepts "#rrggbb" or "rrggbb".
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v & 0xFF0000) >> 16) / 255
        let g = Double((v & 0x00FF00) >> 8) / 255
        let b = Double(v & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// Resolve a light/dark pair against the current appearance.
    static func themed(light: Color, dark: Color, scheme: ColorScheme) -> Color {
        scheme == .dark ? dark : light
    }
}

// MARK: - Layer 2: Named tokens

enum WidgetDesignToken {
    // MARK: Typography
    // SF Rounded gives provider names and quota figures one coherent voice.
    // Monospaced is reserved for timestamps and financial values.
    static let quotaFontDesign: Font.Design = .rounded
    static let quotaTitleWeight: Font.Weight = .semibold
    static let quotaNumberWeight: Font.Weight = .medium
    static let quotaSuffixWeight: Font.Weight = .semibold
    static let quotaLabelWeight: Font.Weight = .medium
    static let bodySize: CGFloat = 13
    static let percentRingSize: CGFloat = 13
    static let percentBigSize: CGFloat = 24
    static let captionSize: CGFloat = 11
    static let mLabelSize: CGFloat = 9.5
    static let portSize: CGFloat = 10
    static let slashLimitSize: CGFloat = 14
    static let footerSize: CGFloat = 11

    // MARK: Percent hero typography
    static let percentHeroSize: CGFloat = 68
    static let percentHeroMediumSize: CGFloat = 52
    static let percentHeroWeight = quotaNumberWeight
    static let percentHeroTracking: CGFloat = -3.2
    static let percentSuffixSize: CGFloat = 22
    static let percentSuffixWeight = quotaSuffixWeight
    static let percentSuffixTracking: CGFloat = -0.5
    static let providerTitleMediumSize: CGFloat = 15
    static let providerTitleLargeSize: CGFloat = 16
    static let providerTitleTracking: CGFloat = 0
    static let sectionTitleSize: CGFloat = 13
    static let sectionTitleTracking: CGFloat = 1.2
    static let updatedSize: CGFloat = 12
    static let updatedWeight = quotaLabelWeight
    static let updatedTracking: CGFloat = 0
    static let resetTimeSize: CGFloat = 11
    static let resetTimeOpacity: Double = 0.52
    static let orbWeight: Font.Weight = .semibold
    static let orbSuffixSpacing: CGFloat = 1

    // MARK: QuotaCard adaptation (medium)
    // The 52pt hero keeps a clear lead over the 24–26pt secondary metric
    // without overpowering the 166pt-high medium family.
    static let mediumHeroTracking: CGFloat = -2.2
    static let resetTimeTracking: CGFloat = 0

    static let orbCardBackground = Color(hex: "#edf3f8")
    static let orbCardBorderWidth: CGFloat = 1

    // MARK: QuotaOrb exact copy (small) — 2026-07-16 round 6
    // Everything below is quota-float source-exact, scaled ×1.675 from the 80px
    // orb to the ~134pt card area inside systemSmall (80px × 1.675 = 134pt).
    static let orbCopyNumberSize: CGFloat = 45       // 27px × 1.675
    static let orbCopySuffixSize: CGFloat = 17       // 10px × 1.675
    static let orbCopyTracking: CGFloat = -2.7       // -.06em at 45px (orb-metric)
    static let orbCopySuffixSpacing: CGFloat = 1.7   // % margin-left 1px × 1.675
    static let orbCopySuffixLift: CGFloat = 5        // % margin-bottom 3px × 1.675

    // MARK: Mini QuotaCard (small)
    // Every provider shares one optical box and one text rhythm. Brand artwork
    // has no extra plate; status remains a separate signal at the trailing edge.
    static let smallProviderTitleSize: CGFloat = 15
    static let smallProviderTitleWeight = quotaTitleWeight
    static let smallProviderTitleTracking: CGFloat = 0
    static let smallProviderTitleMinimumScale: CGFloat = 0.72
    static let smallProviderSubtitleSize: CGFloat = 11
    static let smallProviderHeaderSpacing: CGFloat = 7
    static let smallProviderHeaderTextSpacing: CGFloat = 2
    static let smallProviderMarkWidth: CGFloat = 22
    static let smallProviderMarkHeight: CGFloat = 20
    static let smallProviderMarkIconSize: CGFloat = 18
    static let smallCodexMarkIconSize: CGFloat = 24
    static let smallProviderStatusDotSize: CGFloat = 6
    static let smallProviderTitleStatusSpacing: CGFloat = 7
    static let smallProviderStatusGlowRadius: CGFloat = 3
    static let smallHeaderToHeroSpacing: CGFloat = 14
    static let smallHeroNumberSize: CGFloat = 48
    static let smallHeroSuffixSize: CGFloat = 17
    static let smallHeroTracking: CGFloat = -1.8
    static let smallHeroSuffixLift: CGFloat = 4
    static let smallHeroToBarSpacing: CGFloat = 12
    static let smallBarToResetSpacing: CGFloat = 6
    static let smallProgressHeight: CGFloat = 5
    static let smallResetSize: CGFloat = 11
    static let smallMetadataWeight: Font.Weight = .regular
    static let smallResetOpacity: Double = 0.52
    static let smallMetadataSpacing: CGFloat = 4
    static let smallMetadataMinimumScale: CGFloat = 0.82
    static let miniDescriptorSize: CGFloat = 11
    static let miniResetSize: CGFloat = 8           // reset-time line
    static let miniBarTopMargin: CGFloat = 9        // progress margin-top 18px × 0.52
    static let descriptorTopMargin: CGFloat = 2
    // quota-float primary-metric line-height:.82 — the hero's box hugs the
    // glyphs. SwiftUI's default ~1.2 line height adds invisible slack that
    // made every gap below the hero read too loose.
    static let quotaHeroBoxFactor: CGFloat = 0.82
    static let eyebrowMinimumScale: CGFloat = 0.75  // medium/large provider names
    // Uniform content inset for ALL sizes, calibrated on the approved small
    // widget: quota-float card padding 30px on the 320px card (9.375%) →
    // 30/320 × 166pt ≈ 15.6 → 16pt. Applied explicitly in TokenKingWidgetView
    // because the system's default content margins differ per widget family.
    static let cardContentPadding: CGFloat = 16

    // MARK: Full QuotaCard (medium/large) — 2026-07-16 round 8
    // quota-float expanded card (320px) — systemLarge ≈ card scale, so these
    // are source-exact values, not scaled. Source: QuotaCard.tsx + styles.css.
    static let quotaHeroTopMargin: CGFloat = 18     // primary-metric margin 6 + padding 12
    static let quotaBarTopMargin: CGFloat = 18      // progress margin-top
    static let quotaResetTopMargin: CGFloat = 7     // reset-time margin-top
    // Weekly footer metric: 30px/400 number + 15px % (quota-float weekly-metric).
    static let weeklyHeroSize: CGFloat = 30
    static let weeklyHeroSuffixSize: CGFloat = 15
    static let weeklyLabelWeight = quotaLabelWeight
    // Status indicator: 8px dot inside a 25px frosted circle (usage-indicator:
    // border white .32, bg white .12).
    static let indicatorRingSize: CGFloat = 25
    static let indicatorRingBorderOpacity: Double = 0.32
    static let indicatorRingBackgroundOpacity: Double = 0.12
    // Provider mark bottom-right (43px on the 320px card).
    static let providerMarkSize: CGFloat = 43

    // MARK: Generic quota card composition
    // Shared by non-Codex provider widgets. These keep the same reading rhythm
    // across families without coupling the layouts to a particular quota window.
    static let quotaMediumBodyTopSpacing: CGFloat = 10
    static let quotaMediumColumnSpacing: CGFloat = 14
    static let quotaMediumSecondaryWidth: CGFloat = 74
    static let quotaMediumSecondaryNumberSize: CGFloat = 26
    static let quotaMediumDividerHeight: CGFloat = 56
    static let quotaLargeHeroTopSpacing: CGFloat = 12
    static let quotaLargeBarTopSpacing: CGFloat = 13
    static let quotaLargeFooterTopSpacing: CGFloat = 12
    static let quotaDividerOpacity: Double = 0.14
    static let quotaMetadataSize: CGFloat = 10

    // MARK: Codex QuotaCard
    static let codexCardCornerRadius: CGFloat = 22
    static let codexHeaderMarkSmallSize: CGFloat = 20
    static let codexHeaderMarkMediumSize: CGFloat = 22
    static let codexHeaderMarkLargeSize: CGFloat = 28
    static let codexHeaderSmallSize: CGFloat = 15
    static let codexHeaderMediumSize: CGFloat = 15
    static let codexHeaderLargeSize: CGFloat = 16
    static let codexAccountSmallSize: CGFloat = 9
    static let codexAccountMediumSize: CGFloat = 11
    static let codexAccountLargeSize: CGFloat = 12
    static let codexMetadataSmallSize: CGFloat = 9
    static let codexMetadataMediumSize: CGFloat = 10
    static let codexMetadataLargeSize: CGFloat = 11
    static let codexHeroSmallSize: CGFloat = 48
    static let codexHeroMediumSize: CGFloat = 52
    static let codexHeroLargeSize: CGFloat = 68
    static let codexSuffixSmallSize: CGFloat = 17
    static let codexSuffixMediumSize: CGFloat = 19
    static let codexSuffixLargeSize: CGFloat = 22
    static let codexDescriptorSmallSize: CGFloat = 10
    static let codexDescriptorMediumSize: CGFloat = 11
    static let codexDescriptorLargeSize: CGFloat = 12
    static let codexResetSmallSize: CGFloat = 9
    static let codexResetMediumSize: CGFloat = 10
    static let codexResetLargeSize: CGFloat = 11
    static let codexSecondaryMediumSize: CGFloat = 24
    static let codexSecondaryLargeSize: CGFloat = 30
    static let codexSecondarySuffixMediumSize: CGFloat = 11
    static let codexSecondarySuffixLargeSize: CGFloat = 14
    static let codexStatusRingSize: CGFloat = 20
    static let codexMediumSecondaryWidth: CGFloat = 68
    static let codexMetadataPillRadius: CGFloat = 8
    static let codexMetadataPillHPadding: CGFloat = 7
    static let codexMetadataPillVPadding: CGFloat = 3
    static let codexStateIconSize: CGFloat = 18
    static let codexStateTitleSize: CGFloat = 14
    static let codexStateDetailSize: CGFloat = 11
    static let codexSmallSpacing: CGFloat = 3
    static let codexMediumSpacing: CGFloat = 5
    static let codexLargeSpacing: CGFloat = 8
    static let codexSectionSpacing: CGFloat = 12
    static let codexLargeSectionSpacing: CGFloat = 18
    static let codexSmallHeaderToHeroSpacing: CGFloat = 8
    static let codexSmallHeroToBarSpacing: CGFloat = 8
    static let codexLargeMetadataSpacing: CGFloat = 10
    static let codexMediumPrimaryMinWidth: CGFloat = 164
    static let codexLargeHeroTopSpacing: CGFloat = 12
    static let codexHeroTrackingSmall: CGFloat = -1.8
    static let codexHeroTrackingMedium: CGFloat = -2.2
    static let codexHeroTrackingLarge: CGFloat = -3.2
    static let codexSuffixLiftSmall: CGFloat = 4
    static let codexSuffixLiftMedium: CGFloat = 5
    static let codexSuffixLiftLarge: CGFloat = 7
    static let codexBarMediumHeight: CGFloat = 7
    static let codexBarLargeHeight: CGFloat = 8
    static let codexDividerOpacity: Double = 0.14
    static let codexMutedOpacity: Double = 0.68
    static let codexFaintOpacity: Double = 0.46
    static let codexTrackOpacity: Double = 0.16
    static let codexStatusRingOpacity: Double = 0.10
    static let codexBorderTopOpacity: Double = 0.42
    static let codexBorderBottomOpacity: Double = 0.34
    static let auroraCoolEndRadius: CGFloat = 220
    static let auroraGlowEndRadius: CGFloat = 170
    static let auroraWarmEndRadius: CGFloat = 150

    // MARK: Progress bar effects
    static let barGlowRadius: CGFloat = 8
    static let barGlowOpacity: Double = 0.38

    // Back-compat aliases (existing views reference these).
    static let percentSize: CGFloat = 24
    static let percentLargeSize: CGFloat = 34

    // MARK: Spacing
    static let rowGap: CGFloat = 6
    static let sectionGap: CGFloat = 13
    static let smallGap: CGFloat = 4
    static let largeRowGap: CGFloat = 8
    static let largeBarTopMargin: CGFloat = 7

    // MARK: Metrics (DESIGN.md metrics)
    static let cardCornerRadius: CGFloat = 28
    static let barHeight: CGFloat = 6
    static let largeBarHeight: CGFloat = 9
    static let barRadius: CGFloat = 6
    static let ringStroke: CGFloat = 7
    static let ringDiameter: CGFloat = 66
    static let orbRingStroke: CGFloat = 9
    static let orbRingDiameter: CGFloat = 78
    static let dotSize: CGFloat = 8
    static let hairline: CGFloat = 0.5
    static let iconSize: CGFloat = 14
    static let ringIconSize: CGFloat = 24
    static let mediumIconSize: CGFloat = 16
    static let largeIconSize: CGFloat = 15
    static let refreshControlSize: CGFloat = 20
    static let refreshSymbolSize: CGFloat = 9
    static let refreshStatusDotSize: CGFloat = 6
    static let refreshStatusSpacing: CGFloat = 7
    static let refreshTimestampSpacing: CGFloat = 2
    static let refreshTimestampSize: CGFloat = 10
    static let refreshTimestampOpacity: Double = 0.64
    static let refreshBackgroundOpacity: Double = 0.12
    static let refreshBorderOpacity: Double = 0.24
    static let refreshShadowOpacity: Double = 0.06
    static let refreshShadowRadius: CGFloat = 2
    static let refreshPressedScale: CGFloat = 0.84
    static let refreshPressedOpacity: Double = 0.64
    static let refreshPressedRotation: Double = -16
    static let refreshAnimationDuration: Double = 0.12
    static let statusDotSize: CGFloat = 8

    // MARK: Layout constants (no stray literals in views)
    static let zeroInt: Int = 0
    static let singleLine: Int = 1
    static let codexStateSmallLineCount: Int = 2
    static let singleWindowCount: Int = 1
    static let mediumVisibleCount: Int = 1
    static let largeVisibleCount: Int = 5
    static let snapshotVersion: Int = 1

    static let zeroDouble: Double = 0
    static let percentMax: Double = 100
    static let secondsPerHour: Double = 3600
    static let codexFreshnessThreshold: TimeInterval = 90 * 60
    static let ringStart: CGFloat = 0
    static let ringRotation: Double = -90
    static let trackOpacity: Double = 0.13
    static let badgeBackgroundOpacity: Double = 0.05
    static let badgeStrokeOpacity: Double = 0.10
    static let hairlineOpacity: Double = 0.5
    static let zeroSpacing: CGFloat = 0
    static let zeroLength: CGFloat = 0
    static let badgeHPadding: CGFloat = 7
    static let badgeVPadding: CGFloat = 2
    static let badgeRadius: CGFloat = 6
    static let mediumLabelWidth: CGFloat = 50
    static let percentMinWidth: CGFloat = 36

    // MARK: Provider identifiers for widgets that filter by kind.
    enum ProviderID {
        static let codex = "codex"
        static let braveSearch = "brave_search"
        static let tavilySearch = "tavily_search"
    }

    // MARK: Preview fixture values
    static let fixtureResetHours: Int = 240
    static let fixtureKimiPercent: Double = 87
    static let fixtureCodex5hPercent: Double = 25
    static let fixtureCodexWeeklyPercent: Double = 59
    static let fixtureClaudePercent: Double = 40
    static let fixtureKiroPercent: Double = 28.5

    // MARK: Severity colours (DESIGN.md severity)
    enum Severity {
        static let amberAt: Double = 60
        static let redAt: Double = 85
        static func green(_ s: ColorScheme) -> Color { .themed(light: Color(hex: "#28c63f"), dark: Color(hex: "#34d94a"), scheme: s) }
        static func amber(_ s: ColorScheme) -> Color { .themed(light: Color(hex: "#e0972a"), dark: Color(hex: "#f5b134"), scheme: s) }
        static func red(_ s: ColorScheme) -> Color { .themed(light: Color(hex: "#e8453f"), dark: Color(hex: "#ff5b52"), scheme: s) }
    }

    // Back-compat: system semantic colours (used where scheme isn't threaded).
    static let criticalColor: Color = .red
    static let warningColor: Color = .orange
    static let healthyColor: Color = .green
    static let neutralColor: Color = .secondary

    // MARK: Ink (DESIGN.md ink)
    enum Ink {
        static func primary(_ s: ColorScheme) -> Color { .themed(light: Color(hex: "#2a2433"), dark: Color(hex: "#eef2f0"), scheme: s) }
        static func secondary(_ s: ColorScheme) -> Color { .themed(light: Color(hex: "#615a6d"), dark: Color(hex: "#9aa4a6"), scheme: s) }
        static func faint(_ s: ColorScheme) -> Color { .themed(light: Color(hex: "#9a92a4"), dark: Color(hex: "#646d71"), scheme: s) }
    }

    // MARK: Brand tint (DESIGN.md brand) — identity only, kept restrained.
    enum Brand {
        static let kiro = Color(hex: "#9046ff")
        static let claude = Color(hex: "#d97757")
        static let kimi = Color(hex: "#1783ff")
    }

    // MARK: Aurora tiers — quota-float palette (colours only, drawn as a single
    // gradient layer in containerBackground; NO material/scrim on top, which is
    // what turned the old aurora muddy in fullColor). See the design-tokens doc.
    enum Aurora {
        struct Tier {
            let cool: Color
            let glow: Color
            let warm: Color
            let linearMid: Color
            let linearWarm: Color
            let linearEnd: Color
            let progressStart: Color
            let progressEnd: Color
            let opacity: Double
            let angle: Double // gradient-angle in degrees
            let warmX: Double // warm cloud centre, unit-x (quota-float --warm-position)
            let warmY: Double // warm cloud centre, unit-y
        }

        static let healthy = Tier(
            cool: Color(hex: "#b9d5ee"), glow: Color(hex: "#dff4e5"), warm: Color(hex: "#c7ddf2"),
            linearMid: Color(hex: "#c7c9d1"), linearWarm: Color(hex: "#c7ddf2"), linearEnd: Color(hex: "#eef4fb"),
            progressStart: Color(hex: "#397ae0"), progressEnd: Color(hex: "#91baf0"),
            opacity: 0.42, angle: 145, warmX: 0.82, warmY: 0.82)
        static let caution = Tier(
            cool: Color(hex: "#b7d0ec"), glow: Color(hex: "#fff0ba"), warm: Color(hex: "#f4c979"),
            linearMid: Color(hex: "#c7c9d1"), linearWarm: Color(hex: "#e4e7ed"), linearEnd: Color(hex: "#f1f5f8"),
            progressStart: Color(hex: "#4d88d8"), progressEnd: Color(hex: "#9fc2ee"),
            opacity: 0.50, angle: 213, warmX: 0.12, warmY: 0.96)
        static let critical = Tier(
            cool: Color(hex: "#c4cee0"), glow: Color(hex: "#ffd8a8"), warm: Color(hex: "#f07260"),
            linearMid: Color(hex: "#c7c9d1"), linearWarm: Color(hex: "#e3e4e9"), linearEnd: Color(hex: "#f3f5f8"),
            progressStart: Color(hex: "#ff7848"), progressEnd: Color(hex: "#ffd064"),
            opacity: 0.56, angle: 213, warmX: 0.11, warmY: 0.98)

        /// Pick a tier using the legacy widget thresholds.
        static func tier(forUsedPercent p: Double) -> Tier {
            if p >= WidgetDesignToken.Severity.redAt { return critical }
            if p >= WidgetDesignToken.Severity.amberAt { return caution }
            return healthy
        }

        /// Gradient fill colours for the glowing progress bar.
        static func progressGradient(forUsedPercent p: Double) -> (start: Color, end: Color) {
            let tier = tier(forUsedPercent: p)
            return (start: tier.progressStart, end: tier.progressEnd)
        }
    }

    // Ink for content sitting on the light aurora gradient — quota-float uses
    // near-black #17191f on its light card. Kept separate from the dark-card Ink.
    enum AuroraInk {
        static let primary = Color(hex: "#17191f")
        static let secondary = Color(red: 0.09, green: 0.10, blue: 0.12).opacity(0.62)
        static let faint = Color(red: 0.09, green: 0.10, blue: 0.12).opacity(0.42)
    }

    enum CodexInk {
        static let primary = AuroraInk.primary
        static let secondary = AuroraInk.secondary
        static let faint = AuroraInk.faint
        static let track = AuroraInk.faint.opacity(WidgetDesignToken.codexTrackOpacity)
    }

    enum CodexQuota {
        static let cautionUsedAbove: Double = 50
        static let criticalUsedAbove: Double = 90

        static func tier(forUsedPercent percent: Double) -> Aurora.Tier {
            if percent > criticalUsedAbove { return Aurora.critical }
            if percent > cautionUsedAbove { return Aurora.caution }
            return Aurora.healthy
        }
    }

    enum DataStatus {
        static let fresh = Color(hex: "#63f58c")
        static let stale = Color(hex: "#8f9094")
        static let unavailable = Color(hex: "#ff7653")
    }
}

// Layer 3 removed: the system owns the widget background on the macOS
// desktop (wallpaper-aware frosted material via containerBackground).
// Branding comes from content tokens (Severity/Ink/Brand), not a background.

// MARK: - Helpers (unchanged behaviour)

extension View {
    func monospacedDigits() -> some View {
        self.font(.system(.body, design: .monospaced))
    }
}

extension Double {
    /// Usage percent → system semantic colour (used where ColorScheme not threaded).
    var severityColor: Color {
        if self >= WidgetDesignToken.Severity.redAt { return WidgetDesignToken.criticalColor }
        if self >= WidgetDesignToken.Severity.amberAt { return WidgetDesignToken.warningColor }
        return WidgetDesignToken.healthyColor
    }

    /// Usage percent → prototype-exact severity colour for the given scheme.
    func severityColor(_ scheme: ColorScheme) -> Color {
        if self >= WidgetDesignToken.Severity.redAt { return WidgetDesignToken.Severity.red(scheme) }
        if self >= WidgetDesignToken.Severity.amberAt { return WidgetDesignToken.Severity.amber(scheme) }
        return WidgetDesignToken.Severity.green(scheme)
    }
}

enum RelativeResetFormatter {
    static func string(from resetsAt: Date?, relativeTo now: Date = Date()) -> String {
        guard let resetsAt = resetsAt else { return "" }
        let interval = resetsAt.timeIntervalSince(now)
        if interval <= 0 { return "resetting" }
        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours >= 24 {
            let days = hours / 24
            return "\(days)d left"
        }
        if hours >= 1 {
            return "\(hours)h \(minutes)m left"
        }
        return "\(minutes)m left"
    }
}

enum USDFormatter {
    static func string(from usd: Double?) -> String {
        guard let usd = usd else { return "$0.00" }
        return String(format: "$%.2f", usd)
    }
}
