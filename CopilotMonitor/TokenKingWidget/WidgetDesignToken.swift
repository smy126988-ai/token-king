import SwiftUI
import Foundation

/// Design tokens for widget views. Values aligned with `MenuDesignToken` in
/// `CopilotMonitor/Helpers/MenuDesignToken.swift` but using SwiftUI types.
enum WidgetDesignToken {
    // MARK: - Typography
    static let bodySize: CGFloat = 13
    static let captionSize: CGFloat = 11
    static let percentSize: CGFloat = 22
    static let percentLargeSize: CGFloat = 34

    // MARK: - Spacing
    static let rowGap: CGFloat = 6
    static let sectionGap: CGFloat = 10
    static let smallGap: CGFloat = 4

    // MARK: - Icons
    static let iconSize: CGFloat = 14
    static let statusDotSize: CGFloat = 6

    // MARK: - Colors (system colors only, no RGB)
    static let criticalColor: Color = .red
    static let warningColor: Color = .orange
    static let healthyColor: Color = .green
    static let neutralColor: Color = .secondary

    // MARK: - Card
    static let cardCornerRadius: CGFloat = 22

    // MARK: - Aurora background (decorative, P2 V1)
    //
    // Per AGENTS.md "no hard-coded RGB" is for semantic/UI roles
    // (progress / status). The aurora wall is a decorative gradient
    // background — it needs explicit hex values to reproduce the
    // approved prototype. Values copied from
    // `docs/design/widget/service-monitor-prototype-v6.html` (CSS --wall).
    // Do NOT adjust without a new prototype pass.
    enum Aurora {
        /// Light mode: warm peach → pink → lavender.
        /// Stops chosen to match the radial positions in the prototype
        /// (top-left / bottom-right / centre), approximated in SwiftUI
        /// without explicit pixel anchors.
        static let light: [Color] = [
            Color(red: 1.000, green: 0.729, blue: 0.561),  // #ffba8f (top-left)
            Color(red: 0.914, green: 0.663, blue: 0.878),  // #e9a9e0 (bottom-right)
            Color(red: 0.725, green: 0.659, blue: 0.941),  // #b9a8f0 (centre)
            Color(red: 0.780, green: 0.733, blue: 0.949)   // #c7d0f2 (linear end)
        ]

        /// Dark mode: deep teal → indigo → near-black.
        static let dark: [Color] = [
            Color(red: 0.102, green: 0.227, blue: 0.267),  // #1a3a44 (top-left)
            Color(red: 0.157, green: 0.110, blue: 0.267),  // #281c44 (bottom-right)
            Color(red: 0.075, green: 0.122, blue: 0.149)   // #13101f (linear end)
        ]

        /// Top-left radial start (used for the warm/cool focal point).
        static let lightFocal: Color = Color(red: 1.000, green: 0.792, blue: 0.627)  // #ffcaa0
        static let darkFocal: Color = Color(red: 0.051, green: 0.075, blue: 0.086)   // #0d1316

        /// Glass overlay (per prototype --glass, --glass-foc).
        /// WidgetKit ignores custom .opacity layering; use `.ultraThinMaterial`
        /// instead and tint slightly per color scheme.
        static let glassOpacity: Double = 0.24
    }
}

extension View {
    /// Apply monospaced digits to a Text (matches MenuDesignToken.monospacedFont).
    func monospacedDigits() -> some View {
        self.font(.system(.body, design: .monospaced))
    }
}

extension Double {
    /// Map a usage percent (0-100+) to a system color.
    var severityColor: Color {
        if self >= 85 { return WidgetDesignToken.criticalColor }
        if self >= 60 { return WidgetDesignToken.warningColor }
        return WidgetDesignToken.healthyColor
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
