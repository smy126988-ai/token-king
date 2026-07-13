import Foundation

/// Common protocol for the 7 TokenExtractor adapters (F2b).
/// Each adapter is responsible for reading its data source and returning
/// normalized TokenEvent values. Empty result means "no data" (not error).
protocol TokenExtractorProtocol {
    func extractAll() async throws -> [TokenEvent]
}
