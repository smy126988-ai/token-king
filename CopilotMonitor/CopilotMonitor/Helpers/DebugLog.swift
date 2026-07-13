import Foundation

/// Shared diagnostic logger wrapper.
///
/// All Token King components call `recordDiagnostic(_:)` (or `debugLog(_:)`
/// from `StatusBarController`) to record diagnostic information. This wrapper
/// routes the call through `DiagnosticsLogger`, which is disabled by default —
/// when disabled, calls are a no-op (no file I/O, no PII leak risk).
///
/// Old call sites that previously wrote directly to `/tmp/provider_debug.log`
/// delegate here so the entire app respects a single user-controlled toggle.
///
/// NOTE: We do NOT touch the per-provider private `debugLog(_:)` methods in
/// this change — those continue to write to the (now archived) legacy log
/// path. Migrating them is out of scope for P0-4.
func recordDiagnostic(_ message: String) {
    // No-op when diagnostics are disabled (default).
    DiagnosticsLogger.shared.log(message, category: "App")
}
