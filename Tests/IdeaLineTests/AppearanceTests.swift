import XCTest
@testable import IdeaLine

final class AppearanceTests: XCTestCase {
    func testPaperTextureResourcesDecodeAtOriginalResolution() {
        let expected = ["relief": 384, "slip": 256, "fibre": 480, "cloud": 240]
        XCTAssertEqual(Set(PaperTexture.tiles.keys), Set(expected.keys))
        for (name, size) in expected {
            XCTAssertEqual(PaperTexture.tiles[name]?.image.width, size, name)
            XCTAssertEqual(PaperTexture.tiles[name]?.image.height, size, name)
        }
    }

    func testExistingInstallAndUnknownPreferenceUseClassic() {
        let suite = "AppearanceTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AppearanceState(defaults: defaults).style, .classic)
        defaults.set("unrecognized", forKey: PaperStyle.defaultsKey)
        XCTAssertEqual(AppearanceState(defaults: defaults).style, .classic)
    }

    func testSwitchSurvivesRestartAndLeavesLinePreferencesUntouched() {
        let suite = "AppearanceTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("right", forKey: LinePosition.defaultsKey)
        defaults.set(true, forKey: LineState.pinnedDefaultsKey)
        let state = AppearanceState(defaults: defaults)
        state.style = .looseleaf
        let restored = AppearanceState(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(restored.style, .looseleaf)
        XCTAssertEqual(LinePosition.saved(in: defaults), .right)
        XCTAssertTrue(defaults.bool(forKey: LineState.pinnedDefaultsKey))
        restored.style = .classic
        XCTAssertEqual(AppearanceState(defaults: defaults).style, .classic)
    }
}
