import XCTest
@testable import OpenCode_Bar

final class KimiPlanMapperTests: XCTestCase {

    func testIntermediateMapsToModerato() {
        XCTAssertEqual(
            KimiPlanMapper.presetName(for: "LEVEL_INTERMEDIATE", limit: "100", region: "REGION_CN"),
            "Moderato"
        )
    }

    func testVivaceMapsToVivace() {
        XCTAssertEqual(
            KimiPlanMapper.presetName(for: "LEVEL_VIVACE", limit: "100", region: "REGION_GLOBAL"),
            "Vivace"
        )
    }

    func testUnmappedLevelFallsBackToLegacyStrippedLowercased() {
        XCTAssertEqual(
            KimiPlanMapper.presetName(for: "LEVEL_UNKNOWN_TIER", limit: "100", region: "REGION_CN"),
            "unknown_tier"
        )
    }

    func testNilLevelReturnsNil() {
        XCTAssertNil(KimiPlanMapper.presetName(for: nil, limit: nil, region: nil))
    }

    func testMappingIsCaseInsensitiveForLevelPrefix() {
        XCTAssertEqual(
            KimiPlanMapper.presetName(for: "level_intermediate", limit: "100", region: "REGION_CN"),
            "Moderato"
        )
    }
}
