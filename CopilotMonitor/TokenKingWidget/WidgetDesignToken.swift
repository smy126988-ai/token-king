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
    // MARK: Typography (DESIGN.md typography.sizes)
    static let wNameSize: CGFloat = 14
    static let bodySize: CGFloat = 13
    static let percentRingSize: CGFloat = 13
    static let percentBigSize: CGFloat = 24
    static let captionSize: CGFloat = 11
    static let mLabelSize: CGFloat = 9.5
    static let portSize: CGFloat = 10
    static let slashLimitSize: CGFloat = 14
    static let footerSize: CGFloat = 10

    // MARK: Percent-hero typography (quota-float exact)
    static let percentHeroSize: CGFloat = 64
    static let percentHeroMediumSize: CGFloat = 48
    static let percentHeroWeight: Font.Weight = .medium
    static let percentHeroTracking: CGFloat = -4
    static let percentHeroSmallTracking: CGFloat = -2
    static let percentSuffixSize: CGFloat = 21
    static let percentSuffixWeight: Font.Weight = .bold
    static let percentSuffixTracking: CGFloat = -1
    static let eyebrowSize: CGFloat = 14
    static let eyebrowWeight: Font.Weight = .semibold
    static let eyebrowTracking: CGFloat = 2.5
    static let updatedSize: CGFloat = 14
    static let updatedWeight: Font.Weight = .medium
    static let updatedTracking: CGFloat = 1.1
    static let updatedOpacity: Double = 0.9
    static let resetTimeSize: CGFloat = 12
    static let resetTimeOpacity: Double = 0.52
    static let orbSize: CGFloat = 27
    static let orbWeight: Font.Weight = .semibold
    static let orbSuffixSize: CGFloat = 10
    static let orbSuffixWeight: Font.Weight = .bold
    static let orbSuffixSpacing: CGFloat = 1
    static let orbTracking: CGFloat = -1.6

    // MARK: QuotaCard adaptation (medium) + canvas-scaled orb (small) — 2026-07-16
    // Small-widget orb scaled from quota-float QuotaOrb: 27px number in an 80px orb
    // → 56px on the ~166pt systemSmall canvas (27 × 166/80 ≈ 56).
    static let orbHeroSize: CGFloat = 56
    static let orbHeroTracking: CGFloat = -3.4   // -.06em at 56px (quota-float orb-metric letter-spacing)
    static let orbHeroSuffixSpacing: CGFloat = 2
    // Medium hero: quota-float primary-metric is 64px; 48px (percentHeroMediumSize) is the
    // established vertical scale for the 166pt card. -.07em at 48px ≈ -3.4.
    static let mediumHeroTracking: CGFloat = -3.4
    static let resetTimeTracking: CGFloat = 0.6  // .05em at 12px (quota-float .reset-time)
    // Footer secondary metric (quota-float weekly-metric 30px → 17px at the 0.57 vertical scale).
    static let weeklyNumberSize: CGFloat = 17
    static let weeklyLabelTracking: CGFloat = 1  // ≈.08em at 12px, kept readable at 10px
    static let mediumFooterIconSize: CGFloat = 20

    // MARK: QuotaOrb card (small) — 2026-07-16 round 3
    // quota-float QuotaOrb is an 80px light frosted card, NOT bare content on the
    // aurora: bg #edf3f8 @ .82, 1px white border .42, inset top highlight .48,
    // soft shadow 0 4px 14px rgba(72,88,112,.08), radius 28, aurora drawn inside.
    static let orbCardBackground = Color(hex: "#edf3f8")
    static let orbCardBackgroundOpacity: Double = 0.82
    static let orbCardRadius: CGFloat = 28
    static let orbCardBorderOpacity: Double = 0.42
    static let orbCardBorderWidth: CGFloat = 1
    static let orbCardHighlightOpacity: Double = 0.48
    static let orbCardShadowColor = Color(red: 0.282, green: 0.345, blue: 0.44).opacity(0.08)
    static let orbCardShadowRadius: CGFloat = 14
    static let orbCardShadowY: CGFloat = 4
    static let orbHeroCardTracking: CGFloat = -2.9  // -.06em at 48px (orb-metric letter-spacing)

    // MARK: QuotaOrb exact copy (small) — 2026-07-16 round 6
    // Everything below is quota-float source-exact, scaled ×1.675 from the 80px
    // orb to the ~134pt card area inside systemSmall (80px × 1.675 = 134pt).
    static let orbCopyScale: CGFloat = 1.675
    static let orbCopyNumberSize: CGFloat = 45       // 27px × 1.675
    static let orbCopySuffixSize: CGFloat = 17       // 10px × 1.675
    static let orbCopyTracking: CGFloat = -2.7       // -.06em at 45px (orb-metric)
    static let orbCopySuffixSpacing: CGFloat = 1.7   // % margin-left 1px × 1.675
    static let orbCopySuffixLift: CGFloat = 5        // % margin-bottom 3px × 1.675
    static let orbCopyRadius: CGFloat = 47           // card radius 28px × 1.675
    // Aurora layer: quota-float draws it at inset -55% (⇒ 2.1× card size), so
    // cloud centres sit mostly OFF the card and only their fades bleed in.
    static let orbAuroraScale: CGFloat = 2.1         // 1 + 2×0.55
    // Cloud radii: CSS fade stop (glow 43% / warm 34% / cool 52%) × the ray to
    // the layer's farthest corner (278/326/282pt), expressed in unscaled view
    // space (÷2.1). healthy-tier fades; per-tier fade deltas are <8%, invisible.
    static let orbAuroraGlowRadius: CGFloat = 57
    static let orbAuroraWarmRadius: CGFloat = 53
    static let orbAuroraCoolRadius: CGFloat = 70

    // MARK: Mini QuotaCard (small) — 2026-07-16 round 7
    // quota-float's expanded card (min 320px) compressed into systemSmall.
    // Reference screenshot (docs/images/quota-states.png in the quota-float
    // repo): eyebrow 14px + descriptor 14px on a 320px card ⇒ 7.3px at 0.52
    // scale — below the readability floor, so labels pin at 8-9px.
    static let miniEyebrowSize: CGFloat = 9
    static let miniEyebrowTracking: CGFloat = 1.7   // .18em at 9px (quota-float eyebrow)
    static let miniDescriptorSize: CGFloat = 8      // "5-hour remaining" line
    static let miniResetSize: CGFloat = 8           // reset-time line
    static let miniBarTopMargin: CGFloat = 9        // progress margin-top 18px × 0.52

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
    static let mediumRefreshSize: CGFloat = 23
    static let smallRefreshRadius: CGFloat = 7
    static let statusDotSize: CGFloat = 8

    // MARK: Layout constants (no stray literals in views)
    static let zeroInt: Int = 0
    static let singleLine: Int = 1
    static let singleWindowCount: Int = 1
    static let mediumVisibleCount: Int = 1
    static let largeVisibleCount: Int = 5
    static let snapshotVersion: Int = 1

    static let zeroDouble: Double = 0
    static let percentMax: Double = 100
    static let secondsPerHour: Double = 3600
    static let ringStart: CGFloat = 0
    static let ringRotation: Double = -90
    static let trackOpacity: Double = 0.13
    static let badgeBackgroundOpacity: Double = 0.05
    static let badgeStrokeOpacity: Double = 0.10
    static let hairlineOpacity: Double = 0.5
    static let zeroSpacing: CGFloat = 0
    static let tinyGap: CGFloat = 2
    static let zeroLength: CGFloat = 0
    static let badgeHPadding: CGFloat = 7
    static let badgeVPadding: CGFloat = 2
    static let badgeRadius: CGFloat = 6
    static let mediumLabelWidth: CGFloat = 50
    static let percentMinWidth: CGFloat = 36

    // MARK: Provider identifiers for widgets that filter by kind.
    enum ProviderID {
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

        /// Pick a tier from used-percent, matching Severity thresholds (amber 60, red 85).
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
            return "resets in \(days)d"
        }
        if hours >= 1 {
            return "resets in \(hours)h \(minutes)m"
        }
        return "resets in \(minutes)m"
    }
}

enum USDFormatter {
    static func string(from usd: Double?) -> String {
        guard let usd = usd else { return "$0.00" }
        return String(format: "$%.2f", usd)
    }
}
