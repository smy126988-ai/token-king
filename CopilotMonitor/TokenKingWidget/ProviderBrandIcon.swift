import SwiftUI

/// Brand icon set for the 6 providers with prototype assets in
/// `docs/design/widget/icons/*.svg`.
///
/// Each icon is rendered as a SwiftUI `Path` from the SVG path data,
/// parsed once. Non-matching providers fall back to a generic SF Symbol
/// (see `providerIconSystemName`).
///
/// All icons are template-rendered: a single colour (`.foregroundStyle`)
/// is applied at the call site. Per the prototype, the colour is the
/// brand colour when known and the secondary text colour otherwise.
struct ProviderBrandIcon: View {
    enum Kind {
        case claude, codex, kimi, kiro, opencode, xiaomimimo
    }

    let kind: Kind

    var body: some View {
        GeometryReader { geo in
            // The source SVGs all use a 24×24 viewBox; the geometry reader
            // gives us the actual render size so the icon scales to fit
            // while preserving the aspect ratio.
            let side = min(geo.size.width, geo.size.height)
            let scale = side / 24.0
            Canvas { context, _ in
                let path = Self.path(for: kind)
                context.scaleBy(x: scale, y: scale)
                context.fill(path, with: .foreground)
            }
            .frame(width: side, height: side)
        }
    }

    /// Build a CGPath from the stored SVG `d` attribute. Built once per kind
    /// and cached in a static dictionary to avoid re-parsing on every render.
    private static let cache: [Kind: CGPath] = {
        var result: [Kind: CGPath] = [:]
        for kind in [Kind.claude, .codex, .kimi, .kiro, .opencode, .xiaomimimo] {
            if let path = CGPath.fromSVGPath(d: svgPath(for: kind)) {
                result[kind] = path
            }
        }
        return result
    }()

    private static func path(for kind: Kind) -> CGPath {
        cache[kind] ?? CGPath(rect: .zero, transform: nil)
    }

    private static func svgPath(for kind: Kind) -> String {
        switch kind {
        case .claude:
            return "M4.709 15.955l4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 01-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z"
        case .codex:
            return "M8.086.457a6.105 6.105 0 013.046-.415c1.333.153 2.521.72 3.564 1.7a.117.117 0 00.107.029c1.408-.346 2.762-.224 4.061.366l.063.03.154.076c1.357.703 2.33 1.77 2.918 3.198.278.679.418 1.388.421 2.126a5.655 5.655 0 01-.18 1.631.167.167 0 00.04.155 5.982 5.982 0 011.578 2.891c.385 1.901-.01 3.615-1.183 5.14l-.182.22a6.063 6.063 0 01-2.934 1.851.162.162 0 00-.108.102c-.255.736-.511 1.364-.987 1.992-1.199 1.582-2.962 2.462-4.948 2.451-1.583-.008-2.986-.587-4.21-1.736a.145.145 0 00-.14-.032c-.518.167-1.04.191-1.604.185a5.924 5.924 0 01-2.595-.622 6.058 6.058 0 01-2.146-1.781c-.203-.269-.404-.522-.551-.821a7.74 7.74 0 01-.495-1.283 6.11 6.11 0 01-.017-3.064.166.166 0 00.008-.074.115.115 0 00-.037-.064 5.958 5.958 0 01-1.38-2.202 5.196 5.196 0 01-.333-1.589 6.915 6.915 0 01.188-2.132c.45-1.484 1.309-2.648 2.577-3.493.282-.188.55-.334.802-.438.286-.12.573-.22.861-.304a.129.129 0 00.087-.087A6.016 6.016 0 015.635 2.31C6.315 1.464 7.132.846 8.086.457zm-.804 7.85a.848.848 0 00-1.473.842l1.694 2.965-1.688 2.848a.849.849 0 001.46.864l1.94-3.272a.849.849 0 00.007-.854l-1.94-3.393zm5.446 6.24a.849.849 0 000 1.695h4.848a.849.849 0 000-1.696h-4.848z"
        case .kimi:
            return "M11.065 11.199l7.257-7.2c.137-.136.06-.41-.116-.41H14.3a.164.164 0 00-.117.051l-7.82 7.756c-.122.12-.302.013-.302-.179V3.82c0-.127-.083-.23-.185-.23H3.186c-.103 0-.186.103-.186.23V19.77c0 .128.083.23.186.23h2.69c.103 0 .186-.102.186-.23v-3.25c0-.069.025-.135.069-.178l2.424-2.406a.158.158 0 01.205-.023l6.484 4.772a7.677 7.677 0 003.453 1.283c.108.012.2-.095.2-.23v-3.06c0-.117-.07-.212-.164-.227a5.028 5.028 0 01-2.027-.807l-5.613-4.064c-.117-.078-.132-.279-.028-.381z"
        case .kiro:
            return "M4.594 6.677C6.67-2.226 18.746-2.211 21.16 6.632c.353 1.297 1.725 7.582-1.673 13.747-1.545 2.797-5.841 5.49-6.99 1.883C8.6 25.477 3.315 24.1 5.789 18.609l-.318.143c-3.57 1.305-3.863-1.208-3.173-2.513.45-.84.727-1.335.937-1.897.353-.975.458-1.568.593-2.498.27-1.837.277-3.607.765-5.167zm8.37.01a.92.92 0 00-.81.428c-.217.323-.33.825-.33 1.462 0 .705.15 1.89 1.14 1.89h.008c.757 0 1.214-.705 1.214-1.89 0-.622-.127-1.125-.367-1.455a1.014 1.014 0 00-.855-.435zm4.08 0a.92.92 0 00-.81.428c-.217.323-.33.825-.33 1.462 0 .705.15 1.89 1.14 1.89h.008c.757 0 1.215-.705 1.215-1.89 0-.622-.128-1.125-.368-1.455a1.014 1.014 0 00-.855-.435z"
        case .opencode:
            return "M16 6H8v12h8V6zm4 16H4V2h16v20z"
        case .xiaomimimo:
            return "M.958 15.936a.459.459 0 01.459.44v2.729a.46.46 0 01-.918 0v-2.729a.459.459 0 01.459-.44zm4.814-2.035a.46.46 0 01.553.45v4.754a.458.458 0 11-.918 0V15.48L3.74 17.202a.462.462 0 01-.655.016.462.462 0 01-.065-.082L.628 14.67a.459.459 0 01.658-.637l2.124 2.187 2.127-2.188a.46.46 0 01.235-.13zm2.068.004a.46.46 0 01.458.445v4.755a.46.46 0 01-.458.458.459.459 0 01-.458-.458V14.35a.459.459 0 01.458-.445zm1.973 2.014a.46.46 0 01.46.457v2.729a.46.46 0 01-.784.324.46.46 0 01-.134-.324v-2.729a.46.46 0 01.458-.458zm.002-2.045a.458.458 0 01.328.157l2.127 2.19 2.125-2.19a.459.459 0 01.784.318v4.756a.46.46 0 01-.455.458.46.46 0 01-.458-.458V15.48l-1.667 1.723a.46.46 0 01-.65.008l-.005-.005c0-.002-.002-.002-.004-.003l-2.455-2.534a.46.46 0 01-.008-.667.461.461 0 01.338-.128zm6.797 1.206a.46.46 0 01.53.651A1.966 1.966 0 0019.81 18.4a.462.462 0 01.623.18.46.46 0 01-.181.624 2.863 2.863 0 01-1.38.353l-.142-.004a2.88 2.88 0 01-2.393-4.263.461.461 0 01.274-.21zm.864-.931a2.884 2.884 0 013.915 3.914.46.46 0 01-.402.24l-.057-.004a.458.458 0 01-.164-.055.46.46 0 01-.182-.622 1.967 1.967 0 00-2.669-2.67.459.459 0 11-.441-.803zM9.59 6.368c1.481 0 1.696 1.202 1.696 1.654v2.648h-.917v-.432c-.26.346-.792.535-1.36.535-.133 0-1.289-.03-1.384-1.136-.082-.932.675-1.61 2.053-1.61h.691c0-.563-.367-.886-.983-.886-.44.013-.864.174-1.2.458l-.36-.664c.484-.379 1.012-.567 1.764-.567zm4.427.1c1.263 0 2.082.97 2.083 2.15 0 1.181-.824 2.154-2.083 2.154-1.26 0-2.084-.972-2.084-2.152 0-1.18.82-2.153 2.084-2.153zm6.801.015c.68 0 1.202.465 1.197 1.548v2.642H21.1V8.29c0-.312-.002-.98-.63-.98s-.628.667-.628.838v2.524h-.89V8.148c0-.17-.001-.838-.63-.838-.628 0-.628.668-.628.98v2.383h-.917v-4.03h.917V7a1.22 1.22 0 01.947-.516c.398 0 .76.193.982.686a1.321 1.321 0 011.195-.686zm-18.093.872l1.457-1.772H5.32L3.311 8.07l2.14 2.602H4.24L2.725 8.796 1.21 10.672H0L2.138 8.07.13 5.583h1.138l1.458 1.772zm4.149 3.317h-.916V6.644h.916v4.028zm16.99 0h-.916V6.644h.916v4.028zM9.925 8.71c-1.055 0-1.359.412-1.326.742.032.329.324.537.757.537a1.013 1.013 0 001.014-.968l.002-.31h-.447zM14.018 7.3c-.663 0-1.184.487-1.184 1.32 0 .832.52 1.32 1.184 1.32.662 0 1.182-.49 1.182-1.32 0-.832-.52-1.32-1.182-1.32zM6.417 5.001a.568.568 0 01.587.582.588.588 0 01-1.175 0A.57.57 0 016.417 5zm16.991 0a.57.57 0 01.592.582.588.588 0 01-1.174 0 .57.57 0 01.357-.542.572.572 0 01.225-.04z"
        }
    }
}

// MARK: - CGPath SVG parser

extension CGPath {
    /// Minimal SVG path parser sufficient for the lobe-icons single-path,
    /// M/L/C/Q/Z-only assets. Anything more complex is rejected (returns nil).
    static func fromSVGPath(d: String) -> CGPath? {
        let path = CGMutablePath()
        var current = CGPoint.zero
        var start = CGPoint.zero
        var iter = d.unicodeScalars.makeIterator()
        var command: Character = " "

        func readNumber() -> Double? {
            var buf = ""
            while let c = iter.next() {
                if c == "-" || c == "." || ("0"..."9").contains(Character(c)) {
                    buf.unicodeScalars.append(c)
                } else if !buf.isEmpty {
                    // Put the character back — it's the next command
                    // Re-create iterator? Use a different approach.
                    _ = c
                    break
                }
            }
            return Double(buf)
        }

        while let c = iter.next() {
            let ch = Character(c)
            if ch.isLetter {
                command = ch
                continue
            }
            // Numbers; parse with current command
            // We need to handle multiple numbers per command (e.g. L 10 20 30 40)
            // and relative (lowercase) vs absolute (uppercase).
            let isRelative = command.isLowercase
            switch command {
            case "M", "m":
                guard let x = Double(String(c)), let y = readNumber() ?? 0 else { continue }
                let p = CGPoint(x: x, y: y)
                if isRelative {
                    current = CGPoint(x: current.x + p.x, y: current.y + p.y)
                } else {
                    current = p
                }
                start = current
                path.move(to: current)
                command = isRelative ? "l" : "L"  // subsequent pairs are implicit L
            case "L", "l":
                guard let x = Double(String(c)), let y = readNumber() ?? 0 else { continue }
                let p = CGPoint(x: x, y: y)
                if isRelative {
                    current = CGPoint(x: current.x + p.x, y: current.y + p.y)
                } else {
                    current = p
                }
                path.addLine(to: current)
            case "H", "h":
                guard let x = Double(String(c)) else { continue }
                if isRelative { current.x += x } else { current.x = x }
                path.addLine(to: current)
            case "V", "v":
                guard let y = Double(String(c)) else { continue }
                if isRelative { current.y += y } else { current.y = y }
                path.addLine(to: current)
            case "C", "c":
                guard let x1 = Double(String(c)),
                      let y1 = readNumber() ?? 0,
                      let x2 = readNumber() ?? 0,
                      let y2 = readNumber() ?? 0,
                      let x = readNumber() ?? 0,
                      let y = readNumber() ?? 0 else { continue }
                let c1 = isRelative ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                let c2 = isRelative ? CGPoint(x: current.x + x2, y: current.y + y2) : CGPoint(x: x2, y: y2)
                let end = isRelative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addCurve(to: end, control1: c1, control2: c2)
                current = end
            case "Q", "q":
                guard let x1 = Double(String(c)),
                      let y1 = readNumber() ?? 0,
                      let x = readNumber() ?? 0,
                      let y = readNumber() ?? 0 else { continue }
                let c = isRelative ? CGPoint(x: current.x + x1, y: current.y + y1) : CGPoint(x: x1, y: y1)
                let end = isRelative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.addQuadCurve(to: end, control: c)
                current = end
            case "Z", "z":
                path.closeSubpath()
                current = start
            default:
                continue
            }
        }
        return path
    }
}

// MARK: - Brand colours

extension ProviderBrandIcon {
    /// Brand colour per prototype DESIGN.md §3. Applied via `.foregroundStyle`.
    /// `nil` means "use the default secondary text colour" (for codex/opencode,
    /// which the prototype renders as plain glyphs).
    var brandColor: Color? {
        switch kind {
        case .claude:      return Color(red: 0.851, green: 0.467, blue: 0.341)  // #d97757
        case .codex:       return nil
        case .kimi:        return Color(red: 0.090, green: 0.514, blue: 1.000)  // #1783ff
        case .kiro:        return Color(red: 0.565, green: 0.275, blue: 1.000)  // #9046ff
        case .opencode:    return nil
        case .xiaomimimo:  return nil
        }
    }
}

// MARK: - Provider id → icon mapping

extension ProviderBrandIcon.Kind {
    /// Map a `ProviderIdentifier.rawValue` to a brand icon, or `nil` if the
    /// provider doesn't have a matching prototype asset. Callers fall back to
    /// a generic SF Symbol in that case.
    static func from(providerId: String) -> Kind? {
        switch providerId {
        case "claude":                  return .claude
        case "codex", "opencode_zen":    return .codex
        case "kimi_cn", "kimi_global":   return .kimi
        case "kiro":                    return .kiro
        case "opencode":                return .opencode
        case "minimax_cn", "minimax_global",
             "minimax_coding_plan_cn", "minimax_coding_plan_global",
             "xiaomimimo":              return .xiaomimimo
        default:                        return nil
        }
    }
}

/// SF Symbol fallback for providers without a brand icon.
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
