import Foundation

/// Shared diagnostic logger wrapper.
///
/// All Token King components call `recordDiagnostic(_:)` (or `debugLog(_:)`
/// from `StatusBarController`) to record diagnostic information. This wrapper
/// routes the call through `DiagnosticsLogger`, which is disabled by default —
/// when disabled, calls are a no-op (no file I/O, no PII leak risk).
///
/// All provider and app diagnostics delegate here so the entire app respects
/// one user-controlled toggle and one sanitization boundary.
func recordDiagnostic(_ message: String) {
    // No-op when diagnostics are disabled (default).
    DiagnosticsLogger.shared.log(message, category: "App")
}
