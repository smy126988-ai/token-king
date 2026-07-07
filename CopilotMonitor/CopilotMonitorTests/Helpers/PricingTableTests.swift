import XCTest
@testable import OpenCode_Bar

final class PricingTableTests: XCTestCase {

    // MARK: - Coverage

    func testAll6CoveredProvidersReturnNonNilRate() {
        for provider in PricingTable.providersWithPublicPricing {
            XCTAssertNotNil(
                PricingTable.rate(for: provider),
                "Provider \(provider) is in providersWithPublicPricing but rate(for:) returned nil"
            )
        }
    }

    func testProvidersWithPublicPricingContainsExactly6() {
        XCTAssertEqual(
            PricingTable.providersWithPublicPricing.count, 6,
            "Expected 6 covered providers (kimi/kimiCN/claude/zai/nanoGpt/codex); copilot intentionally nil due to Premium-request model"
        )
        let expected: Set<ProviderIdentifier> = [
            .kimi, .kimiCN, .claude, .zaiCodingPlan, .nanoGpt, .codex,
        ]
        XCTAssertEqual(
            Set(PricingTable.providersWithPublicPricing), expected
        )
    }

    // MARK: - Nil cases

    func testCopilotReturnsNil() {
        // Copilot Premium is request-multiplier, not per-token rate.
        XCTAssertNil(PricingTable.rate(for: .copilot))
    }

    func testAntigravityReturnsNil() {
        // Google does not publish per-token pricing for Antigravity.
        XCTAssertNil(PricingTable.rate(for: .antigravity))
    }

    func testOtherUncoveredProvidersReturnNil() {
        // 4 Chinese providers without confirmed public pricing as of 2026-07-07.
        for provider in [ProviderIdentifier.mimo,
                         .volcanoArk, .hunyuan, .zhipuGLM] {
            XCTAssertNil(
                PricingTable.rate(for: provider),
                "Expected nil for \(provider)"
            )
        }
    }

    // MARK: - Sanity

    func testRateValuesArePositive() {
        for provider in PricingTable.providersWithPublicPricing {
            guard let rate = PricingTable.rate(for: provider) else {
                XCTFail("\(provider) returned nil"); continue
            }
            XCTAssertGreaterThan(rate.input, 0, "\(provider).input must be > 0")
            XCTAssertGreaterThan(rate.output, 0, "\(provider).output must be > 0")
            if let cache = rate.cache {
                XCTAssertGreaterThan(cache, 0, "\(provider).cache must be > 0")
            }
        }
    }

    func testOutputRateGreaterOrEqualToInputRate() {
        // Industry-standard: output tokens cost >= input tokens cost.
        // Catches data-entry typos (e.g. swapping input/output columns).
        for provider in PricingTable.providersWithPublicPricing {
            guard let rate = PricingTable.rate(for: provider) else {
                XCTFail("\(provider) returned nil"); continue
            }
            XCTAssertGreaterThanOrEqual(
                rate.output, rate.input,
                "\(provider): output (\(rate.output)) must be >= input (\(rate.input))"
            )
        }
    }

    func testKimiAndKimiCNHaveSameRate() {
        // Both .kimi and .kimiCN use the same Moonshot platform & same
        // representative model. Their rates must be identical.
        XCTAssertEqual(
            PricingTable.rate(for: .kimi),
            PricingTable.rate(for: .kimiCN),
            ".kimi and .kimiCN must return identical rates (same Moonshot platform)"
        )
    }
}