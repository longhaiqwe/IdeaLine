import XCTest
@testable import IdeaLine

final class LineLayoutTests: XCTestCase {
    func testZeroWidthDuringStartupProducesFinitePositions() {
        for count in [1, 5] {
            for index in 0..<count {
                XCTAssertTrue(ClotheslineLayout.noteTopInset(index: index, count: count, width: 0).isFinite)
            }
        }
    }

    func testNotesFollowSymmetricClotheslineCurve() {
        XCTAssertEqual(ClotheslineLayout.noteTopInset(index: 2, count: 5, width: 1200), 27)
        XCTAssertEqual(ClotheslineLayout.noteTopInset(index: 0, count: 5, width: 1200),
                       ClotheslineLayout.noteTopInset(index: 4, count: 5, width: 1200), accuracy: 0.001)
    }
}
