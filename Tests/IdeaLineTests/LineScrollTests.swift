import AppKit
import SwiftUI
import XCTest
@testable import IdeaLine

final class LineScrollTests: XCTestCase {
    @MainActor
    func testSidebarsFillAvailableHeightAndWheelReachesRemainingNotes() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = IdeaStore(url: folder.appendingPathComponent("ideas.json"))
        for index in 1...10 { XCTAssertTrue(store.hang(Draft(text: "便签 \(index)"))) }
        for position in [LinePosition.left, .right] {
            let line = LineState()
            line.position = position
            line.capacity = 3
            line.page = 2 // A previous horizontal page must not hide sidebar notes.
            line.revealed = true
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 286, height: 940), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let host = NSHostingView(rootView: ClotheslineView(store: store, line: line, edit: { _ in }, compose: {}, library: {}))
            host.sizingOptions = []
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            let scroll = try XCTUnwrap(findScroll(in: host), "Sidebars need a native scroll container for mouse wheels and trackpads")
            XCTAssertFalse(scroll.hasVerticalScroller, "Keep native scrolling without a visible scrollbar")
            XCTAssertGreaterThan(scroll.contentView.bounds.height, 850, "Use the free space above the compact toolbar")
            let document = try XCTUnwrap(scroll.documentView)
            XCTAssertGreaterThan(document.frame.height, 2100, "All ten notes must be present, not just three")
            XCTAssertEqual(scroll.contentView.bounds.minY, 0, accuracy: 1)
            // A real wheel event must move the native clip view, without posting to the user's desktop.
            let event = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -180, wheel2: 0, wheel3: 0))
            scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: event)))
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            XCTAssertGreaterThan(scroll.contentView.bounds.minY, 0)
            let end = max(0, document.frame.height - scroll.contentView.bounds.height)
            document.scroll(CGPoint(x: 0, y: end))
            XCTAssertEqual(scroll.contentView.bounds.minY, end, accuracy: 1, "The last note must be reachable")
            XCTAssertTrue(line.hitRects.contains { $0.contains(CGPoint(x: 140, y: 800)) }, "Gaps in the scroll area must still receive wheel events")
        }
    }

    private func findScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.findScroll(in: $0) }.first
    }
}
