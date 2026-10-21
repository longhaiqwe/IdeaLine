import XCTest
@testable import IdeaLine

final class StoreTests: XCTestCase {
    var folder: URL!
    override func setUpWithError() throws { folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    var url: URL { folder.appendingPathComponent("ideas.json") }
    func testCreateEditArchiveRestoreAndReload() {
        let store = IdeaStore(url: url)
        XCTAssertFalse(store.hang(Draft(text: " \n ")))
        XCTAssertTrue(store.hang(Draft(text: "中文灵感\nhttps://x.com/example", color: 2)))
        let id = store.active[0].id
        XCTAssertTrue(store.hang(Draft(id: id, text: "修改后的灵感", color: 1)))
        XCTAssertEqual(store.active.count, 1)
        XCTAssertEqual(store.active[0].id, id)
        XCTAssertTrue(store.archive(id, true)); XCTAssertEqual(store.active.count, 0)
        let reloaded = IdeaStore(url: url)
        XCTAssertEqual(reloaded.state.ideas[0].text, "修改后的灵感")
        XCTAssertTrue(reloaded.state.ideas[0].archived)
        XCTAssertTrue(reloaded.archive(id, false)); XCTAssertEqual(reloaded.active.count, 1)
    }
    func testDraftSurvivesRelaunchAndClearsAfterSubmission() {
        let store = IdeaStore(url: url)
        XCTAssertTrue(store.draft(Draft(text: "还没写完 🧠", color: 3)))
        let reloaded = IdeaStore(url: url)
        XCTAssertEqual(reloaded.state.draft.text, "还没写完 🧠")
        XCTAssertEqual(reloaded.state.draft.color, 3)
        XCTAssertTrue(reloaded.hang(reloaded.state.draft))
        XCTAssertEqual(IdeaStore(url: url).state.draft.text, "")
    }
    func testCorruptFileIsNotOverwritten() throws {
        let original = Data("not valid json".utf8); try original.write(to: url)
        let store = IdeaStore(url: url)
        XCTAssertNotNil(store.error)
        XCTAssertFalse(store.hang(Draft(text: "新灵感")))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testWriteFailureDoesNotPretendToSave() throws {
        let parentFile = folder.appendingPathComponent("not-a-directory")
        try Data().write(to: parentFile)
        let store = IdeaStore(url: parentFile.appendingPathComponent("ideas.json"))
        XCTAssertFalse(store.hang(Draft(text: "不能丢的想法")))
        XCTAssertTrue(store.active.isEmpty); XCTAssertNotNil(store.error)
    }
    func testNoCapacityLimitAndExportIncludesArchive() {
        let store = IdeaStore(url: url)
        for i in 0..<40 { XCTAssertTrue(store.hang(Draft(text: "选题 \(i)"))) }
        XCTAssertEqual(store.active.count, 40)
        let id = store.active[0].id; XCTAssertTrue(store.archive(id, true))
        XCTAssertTrue(store.markdown().contains("已收纳")); XCTAssertTrue(store.markdown().contains("选题 0")); XCTAssertTrue(store.markdown().contains("选题 39"))
    }
}
