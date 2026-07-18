import Foundation
@testable import OpenCode_Bar

final class FakeProviderCredentialStore: KimiCredentialProviding,
    MiniMaxCredentialProviding,
    NanoGptCredentialProviding,
    SyntheticCredentialProviding {
    var kimiAPIKey: String?
    var kimiCNAPIKey: String?
    var miniMaxCodingPlanAPIKey: String?
    var miniMaxCodingPlanCNAPIKey: String?
    var nanoGptAPIKey: String?
    var syntheticAPIKey: String?
    var lastFoundAuthPath: URL?

    func getKimiAPIKey() -> String? { kimiAPIKey }
    func getKimiCNAPIKey() -> String? { kimiCNAPIKey }
    func getMiniMaxCodingPlanAPIKey() -> String? { miniMaxCodingPlanAPIKey }
    func getMiniMaxCodingPlanCNAPIKey() -> String? { miniMaxCodingPlanCNAPIKey }
    func getNanoGptAPIKey() -> String? { nanoGptAPIKey }
    func getSyntheticAPIKey() -> String? { syntheticAPIKey }
}
