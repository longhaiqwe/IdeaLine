import XCTest
@testable import IdeaLine

final class ReorderTests: XCTestCase {
    var folder: URL!
    var url: URL { folder.appendingPathComponent("ideas.json") }
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }

    func testMoveBothDirectionsPersistsWithoutChangingContentOrDraft() {
        let store = IdeaStore(url: url)
        for text in ["C", "B", "A"] { XCTAssertTrue(store.hang(Draft(text: text))) }
        XCTAssertTrue(store.draft(Draft(text: "未完成草稿")))
        let original = store.active
        XCTAssertTrue(store.moveActive(original[0].id, to: 2))
        XCTAssertEqual(store.active, [original[1], original[2], original[0]])
        XCTAssertEqual(IdeaStore(url: url).active, store.active)
        XCTAssertEqual(IdeaStore(url: url).state.draft.text, "未完成草稿")
        XCTAssertTrue(store.moveActive(original[0].id, to: 0))
        XCTAssertEqual(store.active, original)
    }

    func testArchivedNotesKeepTheirPositionsAndInvalidMovesAreIgnored() {
        let store = IdeaStore(url: url)
        for text in ["C", "归档", "A"] { XCTAssertTrue(store.hang(Draft(text: text))) }
        let archived = store.active[1].id
        XCTAssertTrue(store.archive(archived, true))
        let first = store.active[0].id
        XCTAssertTrue(store.moveActive(first, to: 1))
        XCTAssertEqual(store.active.map(\.text), ["C", "A"])
        XCTAssertEqual(store.state.ideas[1].id, archived)
        XCTAssertFalse(store.moveActive(archived, to: 0))
        XCTAssertFalse(store.moveActive(UUID(), to: 0))
        XCTAssertFalse(store.moveActive(first, to: -1))
        XCTAssertFalse(store.moveActive(first, to: 2))
        XCTAssertEqual(IdeaStore(url: url).active.map(\.text), ["C", "A"])
    }

    func testFailedSaveDoesNotApplyNewOrder() throws {
        let store = IdeaStore(url: url)
        for text in ["B", "A"] { XCTAssertTrue(store.hang(Draft(text: text))) }
        let original = store.active
        try FileManager.default.removeItem(at: url)
        try FileManager.default.removeItem(at: folder)
        try Data().write(to: folder)
        XCTAssertFalse(store.moveActive(original[0].id, to: 1))
        XCTAssertEqual(store.active, original)
        XCTAssertNotNil(store.error)
    }

    func testDragChoosesNearestSlotAndClampsToVisibleNotes() {
        XCTAssertEqual(ClotheslineLayout.destinationIndex(from: 1, translation: CGSize(width: 220, height: 5), count: 5), 2)
        XCTAssertEqual(ClotheslineLayout.destinationIndex(from: 3, translation: CGSize(width: -430, height: 5), count: 5), 1)
        XCTAssertEqual(ClotheslineLayout.destinationIndex(from: 1, translation: CGSize(width: -900, height: 0), count: 5), 0)
        XCTAssertEqual(ClotheslineLayout.destinationIndex(from: 1, translation: CGSize(width: 900, height: 0), count: 5), 4)
        XCTAssertEqual(ClotheslineLayout.destinationIndex(from: 1, translation: CGSize(width: 30, height: 0), count: 5), 1)
        XCTAssertEqual(ClotheslineLayout.destinationIndex(from: 1, translation: CGSize(width: 220, height: 300), count: 5), 1)
    }
}
