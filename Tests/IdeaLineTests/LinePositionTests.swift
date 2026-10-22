import XCTest
@testable import IdeaLine

final class LinePositionTests: XCTestCase {
    // A secondary display can have a negative origin and a reserved menu bar / Dock.
    let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900)
    let visible = CGRect(x: -1440, y: -130, width: 1440, height: 806)

    func testPanelsStayInsideVisibleScreenAndAttachToSelectedEdge() {
        for position in LinePosition.allCases {
            let panel = position.panelFrame(in: visible)
            XCTAssertTrue(visible.contains(panel))
            switch position {
            case .top: XCTAssertEqual(panel.maxY, visible.maxY)
            case .bottom: XCTAssertEqual(panel.minY, visible.minY)
            case .left: XCTAssertEqual(panel.minX, visible.minX)
            case .right: XCTAssertEqual(panel.maxX, visible.maxX)
            }
        }
    }

    func testOnlySelectedEdgeTriggersAndGapKeepsPanelOpen() {
        let points: [LinePosition: CGPoint] = [
            .top: CGPoint(x: screen.midX, y: screen.maxY - 1),
            .bottom: CGPoint(x: screen.midX, y: screen.minY + 1),
            .left: CGPoint(x: screen.minX + 1, y: screen.midY),
            .right: CGPoint(x: screen.maxX - 1, y: screen.midY)
        ]
        for position in LinePosition.allCases {
            for (edge, point) in points {
                XCTAssertEqual(position.isAtEdge(point, of: screen), edge == position)
            }
            let panel = position.panelFrame(in: visible)
            let zone = position.interactionZone(panel: panel, screen: screen)
            XCTAssertTrue(zone.contains(panel))
            XCTAssertTrue(zone.contains(points[position]!))
            XCTAssertFalse(position.isAtEdge(CGPoint(x: screen.maxX + 20, y: screen.maxY), of: screen))
        }
    }

    func testCapacityUsesCorrectAxisAndReservesToolbarSpace() {
        XCTAssertEqual(LinePosition.top.capacity(in: visible), 6)
        XCTAssertEqual(LinePosition.bottom.capacity(in: visible), 6)
        XCTAssertEqual(LinePosition.left.capacity(in: visible), 3)
        XCTAssertEqual(LinePosition.right.capacity(in: visible), 3)
        for position in LinePosition.allCases {
            XCTAssertEqual(position.capacity(in: .zero), 1)
        }
    }

    func testVerticalDragReordersAndIgnoresCrossAxisMotion() {
        for position in [LinePosition.left, .right] {
            XCTAssertEqual(ClotheslineLayout.destinationIndex(from: 0, translation: CGSize(width: 5, height: 220), count: 3, position: position), 1)
            XCTAssertEqual(ClotheslineLayout.destinationIndex(from: 2, translation: CGSize(width: 5, height: -430), count: 3, position: position), 0)
            XCTAssertEqual(ClotheslineLayout.destinationIndex(from: 1, translation: CGSize(width: 300, height: 220), count: 3, position: position), 1)
            XCTAssertEqual(ClotheslineLayout.destinationIndex(from: 1, translation: CGSize(width: 0, height: 900), count: 3, position: position), 2)
        }
        XCTAssertEqual(ClotheslineLayout.destinationIndex(from: 1, translation: CGSize(width: -220, height: 5), count: 3, position: .bottom), 0)
    }

    func testPositionPreferenceRoundTripsAndDefaultsToTop() {
        let suite = "LinePositionTests-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LinePosition.saved(in: defaults), .top)
        for position in LinePosition.allCases {
            defaults.set(position.rawValue, forKey: LinePosition.defaultsKey)
            XCTAssertEqual(LinePosition.saved(in: UserDefaults(suiteName: suite)!), position)
        }
        defaults.set("unknown", forKey: LinePosition.defaultsKey)
        XCTAssertEqual(LinePosition.saved(in: defaults), .top)
    }
}
