import XCTest
@testable import IdeaLine

final class LinePinTests: XCTestCase {
    func testPinKeepsEveryEdgeOpenAndCanBeReleased() {
        let suite = "LinePinTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let line = LineState(defaults: defaults)
        XCTAssertFalse(line.isPinned)
        XCTAssertFalse(line.revealed)
        for position in LinePosition.allCases {
            line.position = position
            line.isPinned = true
            XCTAssertTrue(line.revealed)
            XCTAssertFalse(line.hide(), "Moving away or opening a menu must respect the pin")
            XCTAssertTrue(line.revealed)
            line.isPinned = false
            XCTAssertTrue(line.revealed, "Unpinning should leave time to interact before auto-hide")
            XCTAssertTrue(line.hide())
            XCTAssertFalse(line.revealed)
        }
    }

    func testRestartRestoresPinAndManualHideClearsIt() {
        let suite = "LinePinTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let line = LineState(defaults: defaults)
        line.isPinned = true
        let restored = LineState(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertTrue(restored.isPinned)
        XCTAssertTrue(restored.revealed)
        XCTAssertTrue(restored.hide(manually: true))
        XCTAssertFalse(restored.isPinned)
        XCTAssertFalse(restored.revealed)
        let restarted = LineState(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertFalse(restarted.isPinned)
        XCTAssertFalse(restarted.revealed)
    }
}
