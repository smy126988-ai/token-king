import Foundation
import os.log

/// Logger for the WidgetKit extension process.
///
/// Subsystem `com.tokenking` matches main app conventions; the `provider`
/// category filters in Console.app / `log stream --predicate`.
///
/// The widget target is the only consumer of `WidgetLogger` (3 call sites
/// in `TokenKingWidget.swift`). The other widget-related loggers
/// (`widget.writer` / `widget.mapper` / `widget.paths` / `widget.coordinator`)
/// live in their respective files and are referenced directly by the
/// main app — keeping them there avoids a double-maintenance trap where
/// a category name could drift between the centralized logger and the
/// concrete call site.
///
/// All log messages MUST be in English per AGENTS.md. Never log OAuth tokens,
/// API keys, or credential material.
enum WidgetLogger {
    static let subsystem = "com.tokenking"

    /// Widget timeline read/decode lifecycle: read source, success, decode
    /// failure, stale age, timeline next refresh date.
    static let provider = Logger(subsystem: subsystem, category: "widget.provider")
}
