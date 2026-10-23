import XCTest
@testable import LiveGraded
import CoreImage

final class LiveGradedLooksTests: XCTestCase {

    func testAllSixPresetsInstantiate() {
        XCTAssertEqual(LookPreset.allCases.count, 6, "MVP must contain exactly 6 hero looks")
        XCTAssertEqual(LookPreset.cleanPunch.rawValue, 0, "Clean Punch must be case 0 (Default Launch - Option A)")
    }

    func testCubeDataPrebakeGeneratesValidData() {
        let presets = LUTPresets.shared
        for preset in LookPreset.allCases {
            let data = presets.cubeData(for: preset)
            XCTAssertFalse(data.isEmpty, "Cube data for \(preset.displayName) must not be empty")
            let expectedSize = 32 * 32 * 32 * 4 * MemoryLayout<Float>.size
            XCTAssertEqual(data.count, expectedSize, "Cube data size must match 32x32x32 RGBA float buffer")

            let filter = presets.createFreshFilter(for: preset)
            XCTAssertNotNil(filter, "Fresh filter for \(preset.displayName) must instantiate")
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

    func testPortra400DayPrebakesSafelyWithoutCrash() {
        let presets = LUTPresets.shared
        let data = presets.cubeData(for: .portra400Day)
        XCTAssertFalse(data.isEmpty, "Portra 400 cube data must prebake without error")
    }
}
