import XCTest
@testable import OpenCode_Bar

final class NewProviderTests: XCTestCase {

    // MARK: - MiMo

    func testMimoProviderIdentifierAndType() {
        let provider = MimoProvider()
        XCTAssertEqual(provider.identifier, .mimo)
        XCTAssertEqual(provider.type, .quotaBased)
    }

    func testMimoProviderThrowsAuthenticationFailedWithoutKey() async {
        let provider = MimoProvider(apiKey: nil)
        do {
            _ = try await provider.fetch()
            XCTFail("Expected authentication failure without API key")
        } catch let error as ProviderError {
            if case .authenticationFailed = error {
                // expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMimoProviderReturnsQuotaBasedWithKey() async throws {
        let provider = MimoProvider(apiKey: "test-key")
        let result = try await provider.fetch()

        guard case .quotaBased(let remaining, let entitlement, let overagePermitted) = result.usage else {
            XCTFail("Expected quota-based usage")
            return
        }
        XCTAssertEqual(remaining, 100)
        XCTAssertEqual(entitlement, 100)
        XCTAssertFalse(overagePermitted)
    }

    // MARK: - Hunyuan

    func testHunyuanProviderIdentifierAndType() {
        let provider = HunyuanProvider()
        XCTAssertEqual(provider.identifier, .hunyuan)
        XCTAssertEqual(provider.type, .quotaBased)
    }

    func testHunyuanProviderThrowsAuthenticationFailedWithoutKey() async {
        let provider = HunyuanProvider(apiKey: nil)
        do {
            _ = try await provider.fetch()
            XCTFail("Expected authentication failure without API key")
        } catch let error as ProviderError {
            if case .authenticationFailed = error {
                // expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHunyuanProviderReturnsQuotaBasedWithKey() async throws {
        let provider = HunyuanProvider(apiKey: "test-key")
        let result = try await provider.fetch()

        guard case .quotaBased(let remaining, let entitlement, let overagePermitted) = result.usage else {
            XCTFail("Expected quota-based usage")
            return
        }
        XCTAssertEqual(remaining, 100)
        XCTAssertEqual(entitlement, 100)
        XCTAssertFalse(overagePermitted)
    }

    // MARK: - Zhipu GLM

    func testZhipuGLMProviderIdentifierAndType() {
        let provider = ZhipuGLMProvider()
        XCTAssertEqual(provider.identifier, .zhipuGLM)
        XCTAssertEqual(provider.type, .quotaBased)
    }

    func testZhipuGLMProviderThrowsAuthenticationFailedWithoutKey() async {
        let provider = ZhipuGLMProvider(apiKey: nil)
        do {
            _ = try await provider.fetch()
            XCTFail("Expected authentication failure without API key")
        } catch let error as ProviderError {
            if case .authenticationFailed = error {
                // expected
            } else {
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testZhipuGLMProviderReturnsQuotaBasedWithKey() async throws {
        let provider = ZhipuGLMProvider(apiKey: "test-key")
        let result = try await provider.fetch()

        guard case .quotaBased(let remaining, let entitlement, let overagePermitted) = result.usage else {
            XCTFail("Expected quota-based usage")
            return
        }
        XCTAssertEqual(remaining, 100)
        XCTAssertEqual(entitlement, 100)
        XCTAssertFalse(overagePermitted)
    }
}
