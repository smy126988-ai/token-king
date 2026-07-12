//
//  TimeZone+UTC.swift
//  CopilotMonitor
//
//  Shared UTC timezone accessor with a hard fallback to GMT+0.
//

import Foundation

extension TimeZone {
    /// Single-point UTC timezone construction.
    ///
    /// `TimeZone(identifier: "UTC")` is expected to always succeed, but if the
    /// identifier lookup ever fails we fall back to `secondsFromGMT: 0`, which
    /// is guaranteed to return a non-nil `TimeZone` on Apple platforms.
    static let utc: TimeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
}

extension Optional where Wrapped == TimeZone {
    /// Convenience so `.utc` also works when the contextual type is `TimeZone?`.
    static var utc: TimeZone { TimeZone.utc }
}
