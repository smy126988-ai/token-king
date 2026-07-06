# Token King Menu Bar Icon Blurry — Handoff (2026-07-05)

**Date**: 2026-07-05
**Branch**: main (HEAD `1cf46ad` — docs-only commit "B09 fixed, B39+B40 added to bug backlog")
**Status**: 🟡 **UNRESOLVED — investigation stalled, true root cause not identified**. Earlier "fix" did not stick across sessions.
**Working tree**: `/Users/simengyu/projects/usage-deck/`
**Running binary**: `/Applications/Token King.app` (Debug, built from `/tmp/tk-derived/`)

> ⚠️ **Discrepancy note for next session**: The existing B40 entry in `docs/backlog/bugs/README.md` (row 47) describes a **different** bug — "macOS 26.x 多显示器下 replicant 的菜单栏图标仍是 SwiftUI 默认 gauge" (multi-monitor secondary display showing SwiftUI's default `gauge.medium` because `button == nil` on the secondary `NSSceneStatusItem`). That entry is the **multi-monitor replicant** bug. This handoff covers the **single-monitor icon-blurry** symptom, which has been called "B40" informally across sessions but is technically a separate item. Decide at session start whether to:
> - file this as a new bug ID (B41?) and update README.md row 47 to clarify scope, **or**
> - merge both under B40 (they share the SwiftUI MenuBarExtra + button.image codepath).

---

## 0. TL;DR

User has reported on multiple occasions across multiple sessions that the Token King menu bar icon looks **visually soft/blurry** compared to neighboring icons (Terminal, 1Password, etc.) which render crisp. An earlier session rewrote `renderStatusItemImage()` (commits `39c41a0` and `f5a2676`) to use `NSBitmapImageRep` at `pixelsWide = logicalWidth * NSScreen.main.backingScaleFactor` instead of `NSImage(size:).lockFocus()`. User confirmed after restart the icon "不模糊了". Later in the **same session** the user said the icon was blurry again. Subsequent investigation suggested it was perceptual (SF Symbol `gauge.medium` at 16pt inherently softer than geometric icons like Terminal/1Password), but this hypothesis was never confirmed and the "fix" did not persist across sessions.

**The current `renderStatusItemImage()` does produce a 44×46 pixel `NSBitmapImageRep` on the active button (lldb confirmed)**, i.e. the outer bitmap IS at 2x for Retina. Yet the icon still looks soft. True root cause remains unidentified.

---

## 1. The Bug

### Symptom
- Menu bar icon renders but appears fuzzy/soft-edged to the user.
- Comparison: Terminal, 1Password icons in same menu bar look crisp.
- Reproduces on the active machine. Not known to be intermittent vs. always-fuzzy.

### Earlier "Fix" That Did Not Stick
- Commits `39c41a0` and `f5a2676` rewrote `renderStatusItemImage()` in `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:442-490` to:
  - allocate `NSBitmapImageRep` with `pixelsWide = Int(logicalWidth * backingScaleFactor)`
  - render via `NSGraphicsContext(bitmapImageRep: bitmap)`
  - set `ctx.imageInterpolation = .high`
  - assign `bitmap` to `button.image` (template)
- User feedback after restart: "不模糊了" → fix appears to work.
- Same user, later in same session: "又模糊了" → fix did not actually resolve.
- Across sessions: no consistent improvement.

### Current State of `renderStatusItemImage()`
File: `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift:442-490`

```swift
private func renderStatusItemImage() {
    guard let iconView = statusBarIconView, let button = statusItem?.button else {
        return
    }
    let logicalSize = NSSize(
        width: max(iconView.intrinsicContentSize.width, 22),
        height: iconView.intrinsicContentSize.height
    )
    let scale = NSScreen.main?.backingScaleFactor ?? 1.0
    let pixelSize = NSSize(
        width: logicalSize.width * scale,
        height: logicalSize.height * scale
    )
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: max(1, Int(pixelSize.width)),
        pixelsHigh: max(1, Int(pixelSize.height)),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    ) else { return }
    bitmap.size = logicalSize
    let image = NSImage(size: logicalSize)
    image.addRepresentation(bitmap)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    if let ctx = NSGraphicsContext(bitmapImageRep: bitmap) {
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        iconView.draw(NSRect(origin: .zero, size: logicalSize))
    }
    image.isTemplate = true
    button.image = image
    button.title = ""
}
```

**lldb-verified**: This DOES produce a 44×46 pixel `NSBitmapImageRep` on the active button. So the **outer bitmap IS at 2x for Retina**. Yet the icon still looks soft.

---

## 2. Earlier Conclusions That Turned Out Wrong

These were hypothesized as the root cause but ruled out (or only partially true):

1. **"Inner `drawTintedIcon()` rasterizes at 1x via `lockFocus()`"** — tested via standalone Swift script.
   - Result: `NSImage(size: X).lockFocus()` on a Retina machine DOES scale-aware create a 2x rep (e.g., `NSImage(size:64).lockFocus` rep has `width=128` pixels).
   - Verdict: **NOT the bug**.

2. **"SF Symbol `gauge.medium` at 16pt is inherently softer than Terminal/1Password icons"** — partially true.
   - Gradient/curved symbols are perceptually softer than flat geometric icons.
   - But does NOT explain why our own 44×46 render should look fuzzy.
   - Verdict: **Partial — explains some perceptual softness but not all**.

---

## 3. Open Angles To Re-Investigate

The render path looks correct on paper. The actual visual softness source remains unidentified. Try these in order:

### 3.1 Dump the bitmap to PNG and inspect
After `iconView.draw(...)` inside `renderStatusItemImage()`, add a one-shot debug path:

```swift
if let pngData = bitmap.representation(using: .png, properties: [:]) {
    try? pngData.write(to: URL(fileURLWithPath: "/tmp/rendered.png"))
}
```

Then compare `/tmp/rendered.png` against a screenshot of the actual menu bar. Determine:
- Is the PNG content sharp at 2x or blurry/upscaled?
- Are there blank/transparent regions at 1x where content should be at 2x?
- Does the SF Symbol rasterization look pixel-aligned to the 2x grid?

### 3.2 Try `imageInterpolation = .none` instead of `.high`
`.high` interpolation may be over-smoothing hard-edged icons. Try `.none` — icons are typically vector SF Symbols with built-in aliasing; further interpolation may double-smooth.

### 3.3 Inspect CTM inside `iconView.draw(...)`
The outer context is at 2x backing, but inside `iconView.draw(...)` it draws in logical points. **Some draw commands bypass the CTM and produce 1x output.** Try wrapping with:

```swift
if let cgCtx = ctx.cgContext {
    cgCtx.saveGState()
    cgCtx.translateBy(x: 0, y: logicalSize.height * scale)
    cgCtx.scaleBy(x: scale, y: -scale)
    // ... draw
    cgCtx.restoreGState()
}
```

This forces pixel-space draws and may reveal whether content is being painted at 1x or 2x.

### 3.4 Compare against SwiftUI `Image` baseline
Render `Image(systemName: "gauge.medium")` standalone to PNG at the same logical size and bit depth as ours. Compare pixel-by-pixel with `/tmp/rendered.png`. If the SwiftUI standalone is crisp but ours is soft, the bug is in our pipeline. If both are soft, the SF Symbol itself is the issue.

### 3.5 SF Symbol swap test (localize the symptom)
In `CopilotMonitor/CopilotMonitor/App/ModernApp.swift:36`, change:
```swift
Image(systemName: "gauge.medium")
```
to:
```swift
Image(systemName: "dock.rectangle")
```
(or another flat/geometric symbol). Rebuild and check:
- If `dock.rectangle` is crisp → `gauge.medium` SF Symbol is the issue.
- If `dock.rectangle` is also soft → our rendering pipeline is the issue.

### 3.6 `.scaled` icon variant test
Maybe `Image(systemName:)` at 16pt produces subpixel-rasterized output that `.high` interpolation then over-smooths. Try wrapping with `.imageScale(.large)` or `.imageScale(.small)` and compare.

---

## 4. Constraints (carry over from earlier session)

These are hard rules; do NOT violate:

- **Do NOT touch the SwiftUI `MenuBarExtra` bridge chain** — do not revert to pure AppKit. That was the `0f4fe55` mistake. See `docs/handoffs/2026-07-04-statusbar-architecture-problem.md` for why.
- **Do NOT commit `Info.plist`** — `GitCommitHash` is auto-bumped by the build phase; will be obsolete immediately.
- **Do NOT commit `.gitignore` wholesale** — currently has `.swarm/`, `*.pbxproj.bak` rules that user wants kept narrow per P3 feedback. `docs/handoffs/` is fine to keep separate (untracked handoff docs).
- **Do NOT commit `docs/handoffs/*`** — these are session debugging debris, untracked by design.
- **Do NOT commit `*.bak.*` artifacts** (e.g., `project.pbxproj.bak.20260704-014838`).
- **Always run `xcodebuild test` before claiming a fix is good.**
- **Always `git status --short` before `git add`** and stage explicit paths only.

---

## 5. Current Uncommitted State in Working Tree

```
M .gitignore                                                              (added .swarm/, *.pbxproj.bak, *.pbxproj.bak.*)
M CopilotMonitor/CopilotMonitor/App/AppDelegate.swift                     (B39 + B40 observability + retry logic)
M CopilotMonitor/CopilotMonitor/Info.plist                                (GitCommitHash = 1cf46ad, auto-injected; should `git restore`)
M CopilotMonitor/CopilotMonitorTests/StatusBarControllerTests.swift       (migrated to .testing InitOptions)
?? docs/handoffs/2026-07-04-token-king-debug-review.md                   (debug session notes, do NOT commit)
?? docs/handoffs/2026-07-05-token-king-icon-blurry.md                     (this file, do NOT commit)
?? project.pbxproj.bak.20260704-014838                                    (Xcode backup, do NOT commit)
```

**Important**: B40 in `AppDelegate.swift` modifications refers to the **multi-monitor replicant** fix (the original B40 from the backlog), NOT the icon-blurry issue. Do not conflate the two.

---

## 6. Reference Files

| File | Purpose |
|------|---------|
| `CopilotMonitor/CopilotMonitor/App/StatusBarController.swift` | `renderStatusItemImage()` at line 442; the active site of investigation |
| `CopilotMonitor/CopilotMonitor/Views/StatusBarIconView.swift` | Custom NSView drawn into the bitmap; contains `drawTintedIcon` (uses `lockFocus` historically — scale-aware per recent test) |
| `CopilotMonitor/CopilotMonitor/App/ModernApp.swift` | `Image(systemName: "gauge.medium")` label; line 36 is the SF Symbol swap test site |
| `docs/handoffs/2026-07-04-statusbar-architecture-problem.md` | Earlier architecture notes (commit `39c41a0`/`f5a2676` rationale) |
| `docs/backlog/bugs/README.md` | B40 row 47 — multi-monitor replicant bug (DIFFERENT bug, see discrepancy note) |

---

## 7. Start Here (next session checklist)

1. **Run `git status --short`** and `git diff CopilotMonitor/CopilotMonitor/App/StatusBarController.swift` to see exactly what state the workspace is in.
2. **Confirm the binary builds**:
   ```bash
   cd /Users/simengyu/projects/usage-deck/CopilotMonitor && \
   xcodebuild -project CopilotMonitor.xcodeproj -scheme CopilotMonitor \
     -configuration Debug -derivedDataPath /tmp/tk-derived build
   ```
3. **Take a fresh screenshot of the menu bar** with Token King running; save to `/tmp/menubar.png` for side-by-side comparison.
4. **Add a one-shot debug path** in `renderStatusItemImage()` to dump the bitmap to `/tmp/rendered.png` after `iconView.draw()`. Compare to `/tmp/menubar.png`.
5. **Try the SF Symbol swap test** (`gauge.medium` → `dock.rectangle`) to localize the symptom.
6. **Resolve the B40 backlog discrepancy** — decide whether this is a new bug (B41) or a re-scoping of existing B40, and update `docs/backlog/bugs/README.md` accordingly.

---

## 8. Lessons Learned (so we don't repeat)

1. **lldb pixel verification is necessary but not sufficient** — confirming the outer bitmap is at 2x does not prove the drawn content is sharp. Always inspect the actual pixel content.
2. **"Fix confirmed by user in same session" is a weak signal** — multiple rounds of user feedback in one session have disagreed (fix worked → fix didn't work). Cross-session verification is needed.
3. **SF Symbol shape matters for perceptual crispness** — gauge (curved, gradient) vs. dock.rectangle (flat, geometric) is a different visual baseline. When comparing to Terminal/1Password, remember those use geometric icons.
4. **`NSImage(size:).lockFocus()` is scale-aware on Retina** — earlier instinct that it produced 1x output was wrong; tested and ruled out via standalone script.
5. **`imageInterpolation = .high` may over-smooth** — for hard-edged icons, `.none` may actually look sharper. Worth testing.

---

## 9. Out of Scope (do NOT touch in next session)

- B39 (multi-monitor menu sync) — already partially mitigated, see `docs/backlog/bugs/README.md` row 46
- B41-onwards bugs not yet filed
- The SwiftUI `MenuBarExtra` + `MenuBarExtraAccess` bridge architecture — confirmed working on macOS 26.x, do not regress
- Currency / region / i18n settings