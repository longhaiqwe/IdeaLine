import AppKit
import Carbon
import XCTest
@testable import IdeaLine

final class ShortcutTests: XCTestCase {
    func testNewIdeaShortcutWorksWithCapsLockAndNoLatinCharacters() {
        _ = NSApplication.shared
        let window = KeyWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        var opened = 0
        window.onNew = { opened += 1 }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                    modifierFlags: [.control, .option, .capsLock],
                                    timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                    characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                                    keyCode: UInt16(kVK_ANSI_N))!
        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertEqual(opened, 1)
    }

    func testOldShortcutDoesNotOpenNewIdea() {
        _ = NSApplication.shared
        let window = KeyWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        var opened = 0
        window.onNew = { opened += 1 }
        let combinations: [(Int, NSEvent.ModifierFlags)] = [(kVK_ANSI_M, [.control, .option]), (kVK_ANSI_N, [.command, .option]), (kVK_ANSI_N, [.control, .option, .command])]
        for (code, flags) in combinations {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                        characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                                        keyCode: UInt16(code))!
            _ = window.performKeyEquivalent(with: event)
        }
        XCTAssertEqual(opened, 0)
    }
}
