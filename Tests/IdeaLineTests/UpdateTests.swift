import AppKit
import XCTest
@testable import IdeaLine

final class UpdateTests: XCTestCase {
    private let key = Data(repeating: 1, count: 32).base64EncodedString()

    func testUnconfiguredBuildDoesNotStartNetworkUpdater() {
        XCTAssertFalse(UpdateConfiguration(info: [:]).isReady)
        XCTAssertNotNil(UpdateConfiguration(info: [:]).problem)
    }

    func testRequiresHTTPSFeedAndEd25519PublicKeyTogether() {
        for feed in ["", "http://example.com/appcast.xml", "file:///tmp/appcast.xml", "https://", "https://user:password@example.com/appcast.xml"] {
            XCTAssertFalse(UpdateConfiguration(info: ["SUFeedURL": feed, "SUPublicEDKey": key]).isReady, feed)
        }
        for invalidKey in ["", "not-a-key", Data(repeating: 1, count: 31).base64EncodedString()] {
            XCTAssertFalse(UpdateConfiguration(info: ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": invalidKey]).isReady)
        }
        XCTAssertTrue(UpdateConfiguration(info: ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": key]).isReady)
    }

    func testAutomaticDownloadsRequireStartedUpdaterAndAutomaticChecks() {
        XCTAssertFalse(UpdateMenuState(isReady: false, canCheck: false, automaticChecks: true, automaticDownloads: true, allowsAutomaticUpdates: true).canToggleDownloads)
        XCTAssertFalse(UpdateMenuState(isReady: true, canCheck: true, automaticChecks: false, automaticDownloads: true, allowsAutomaticUpdates: true).canToggleDownloads)
        XCTAssertFalse(UpdateMenuState(isReady: true, canCheck: true, automaticChecks: true, automaticDownloads: false, allowsAutomaticUpdates: false).canToggleDownloads)
        XCTAssertTrue(UpdateMenuState(isReady: true, canCheck: false, automaticChecks: true, automaticDownloads: false, allowsAutomaticUpdates: true).canToggleDownloads)
    }

    func testUnavailableUpdaterExplainsSetupInsteadOfClaimingLatestVersion() {
        let state = UpdateMenuState(isReady: false)
        XCTAssertEqual(state.actionTitle, "检查更新…")
        XCTAssertTrue(state.canSelectCheck)
        XCTAssertFalse(state.canToggleChecks)
    }

    func testInProgressCheckCannotBeRepeatedButPendingUpdateCanBeOpened() {
        XCTAssertFalse(UpdateMenuState(isReady: true, canCheck: false).canSelectCheck)
        let reminder = UpdateMenuState(isReady: true, canCheck: false, availableVersion: "1.2.0")
        XCTAssertTrue(reminder.canSelectCheck)
        XCTAssertEqual(reminder.actionTitle, "更新至 1.2.0…")
        XCTAssertEqual(reminder.symbolName, "arrow.down.circle")
        XCTAssertEqual(UpdateMenuState(isReady: true).symbolName, "wind")
    }

    func testNativeMenusKeepUnconfiguredTogglesDisabledAfterAppKitValidation() {
        _ = NSApplication.shared
        let controller = UpdateController()
        let statusMenu = NSMenu()
        let appMenu = NSMenu()
        controller.addItems(to: statusMenu)
        controller.addItems(to: appMenu)
        // XCTest's bundle has no feed; this must not create or start Sparkle.
        controller.start()
        XCTAssertFalse(controller.state.isReady)
        for menu in [statusMenu, appMenu] {
            menu.update()
            XCTAssertEqual(menu.items.map(\.title), ["检查更新…", "自动检查更新", "自动下载并安装更新"])
            XCTAssertTrue(menu.items[0].isEnabled)
            XCTAssertFalse(menu.items[1].isEnabled)
            XCTAssertFalse(menu.items[2].isEnabled)
            XCTAssertEqual(menu.items[1].state, .off)
            XCTAssertEqual(menu.items[2].state, .off)
        }
    }
}
