import XCTest
@testable import LiveGraded
import CoreImage

final class LiveGradedLooksTests: XCTestCase {

    func testAllSixPresetsInstantiate() {
        XCTAssertEqual(LookPreset.allCases.count, 6, "MVP must contain exactly 6 hero looks")
        XCTAssertEqual(LookPreset.cleanPunch.rawValue, 0, "Clean Punch must be case 0 (Default Launch - Option A)")
    }

    func testFilterPrebakeGeneratesValidData() {
        let presets = LUTPresets.shared
        for preset in LookPreset.allCases {
            let filter = presets.filter(for: preset)
            XCTAssertNotNil(filter, "Filter for \(preset.displayName) must exist")
            XCTAssertEqual(filter.name, "CIColorCube")
            let data = filter.value(forKey: "inputCubeData") as? Data
            XCTAssertNotNil(data, "Cube data for \(preset.displayName) must not be nil")
            let expectedSize = 32 * 32 * 32 * 4 * MemoryLayout<Float>.size
            XCTAssertEqual(data?.count, expectedSize, "Cube data size must match 32x32x32 RGBA float buffer")
        }
    }

    func testDefaultPresetIsOptionACleanPunch() {
        XCTAssertEqual(LookPreset.cleanPunch.displayName, "Clean Punch")
        XCTAssertEqual(LookPreset.cleanPunch.subtitle, "Instant Share Polish")
    }

    func testRahilFilmicSignatureLookExists() {
        XCTAssertEqual(LookPreset.rahilFilmic.displayName, "Rahil Filmic")
        XCTAssertEqual(LookPreset.rahilFilmic.subtitle, "35mm Analog Warmth")
    }
}
