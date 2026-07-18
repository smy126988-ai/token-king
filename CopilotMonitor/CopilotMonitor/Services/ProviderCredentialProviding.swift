import Foundation

protocol ProviderAuthPathProviding: AnyObject {
    var lastFoundAuthPath: URL? { get }
}

protocol KimiCredentialProviding: AnyObject {
    func getKimiAPIKey() -> String?
    func getKimiCNAPIKey() -> String?
}

protocol MiniMaxCredentialProviding: AnyObject {
    func getMiniMaxCodingPlanAPIKey() -> String?
    func getMiniMaxCodingPlanCNAPIKey() -> String?
}

protocol NanoGptCredentialProviding: ProviderAuthPathProviding {
    func getNanoGptAPIKey() -> String?
}

protocol SyntheticCredentialProviding: ProviderAuthPathProviding {
    func getSyntheticAPIKey() -> String?
}

extension TokenManager: KimiCredentialProviding,
    MiniMaxCredentialProviding,
    NanoGptCredentialProviding,
    SyntheticCredentialProviding {}
