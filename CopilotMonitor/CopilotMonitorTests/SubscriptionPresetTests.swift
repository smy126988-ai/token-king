import XCTest
@testable import OpenCode_Bar

final class SubscriptionPresetTests: XCTestCase {
    func testPresetSupportsNativeCNY() {
        let p = SubscriptionPreset(name: "Ultra 极速版", cost: 124.86, cnyCost: 899)
        XCTAssertEqual(p.cnyCost, 899)
        XCTAssertEqual(p.cost, 124.86, accuracy: 0.01)
    }

    func testUSDPresetHasNilCNY() {
        let p = SubscriptionPreset(name: "Pro", cost: 20)
        XCTAssertNil(p.cnyCost)
    }

    func testKimiChinaPresetsHaveDomesticCNY() {
        let presets = ProviderSubscriptionPresets.presets(family: .kimi, region: .china)
        XCTAssertEqual(presets.first { $0.name == "Andante" }?.cnyCost, 49)
        XCTAssertEqual(presets.first { $0.name == "Moderato" }?.cnyCost, 99)
        XCTAssertEqual(presets.first { $0.name == "Allegretto" }?.cnyCost, 199)
        XCTAssertEqual(presets.first { $0.name == "Allegro" }?.cnyCost, 699)
        XCTAssertNil(presets.first { $0.name == "Vivace" })
    }

    func testKimiGlobalPresetsAreUSDOnly() {
        let presets = ProviderSubscriptionPresets.presets(family: .kimi, region: .global)
        XCTAssertNil(presets.first { $0.name == "Andante" })
        XCTAssertEqual(presets.first { $0.name == "Vivace" }?.cost, 199)
        XCTAssertTrue(presets.allSatisfy { $0.cnyCost == nil })
    }

    func testMiniMaxCNPresetsHaveDomesticCNY() {
        let presets = ProviderSubscriptionPresets.presets(family: .minimax, region: .china)
        XCTAssertEqual(presets.first { $0.name == "Ultra" }?.cnyCost, 469)
        XCTAssertEqual(presets.first { $0.name == "Max" }?.cnyCost, 119)
    }

    func testMiniMaxGlobalPresetsUseUSDOnly() {
        let presets = ProviderSubscriptionPresets.presets(family: .minimax, region: .global)
        XCTAssertNil(presets.first { $0.name == "Ultra" }?.cnyCost)
        XCTAssertEqual(presets.first { $0.name == "Max" }?.cost, 50)
    }

    func testCodexPresetsIncludeBothProTiers() {
        let presets = ProviderSubscriptionPresets.presets(family: .codex, region: .global)
        let pro100 = presets.first { $0.name == "Pro $100" }
        let pro200 = presets.first { $0.name == "Pro $200" }
        XCTAssertNotNil(pro100)
        XCTAssertNotNil(pro200)
        XCTAssertEqual(pro100?.cost, 100)
        XCTAssertEqual(pro200?.cost, 200)
    }

    func testNewProvidersHavePresets() {
        XCTAssertFalse(ProviderSubscriptionPresets.presets(for: .mimo).isEmpty)
        XCTAssertFalse(ProviderSubscriptionPresets.presets(for: .volcanoArk).isEmpty)
        XCTAssertFalse(ProviderSubscriptionPresets.presets(for: .hunyuan).isEmpty)
        XCTAssertFalse(ProviderSubscriptionPresets.presets(for: .zhipuGLM).isEmpty)
    }
}
