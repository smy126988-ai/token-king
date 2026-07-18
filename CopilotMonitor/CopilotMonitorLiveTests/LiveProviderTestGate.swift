import XCTest

enum LiveProviderTestGate {
    static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["RUN_LIVE_PROVIDER_TESTS"] == "1"
    }

    static func requireEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        guard isEnabled(environment: environment) else {
            throw XCTSkip("Live provider tests require RUN_LIVE_PROVIDER_TESTS=1")
        }
    }
}
