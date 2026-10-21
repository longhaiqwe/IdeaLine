import AppKit
import Sparkle

/// Owns Sparkle and both menus; builds without a feed never start an updater.
final class UpdateController: NSObject, NSMenuItemValidation, SPUStandardUserDriverDelegate {
    private var controller: SPUStandardUpdaterController?
    private var problem: String?
    private var availableVersion: String?
    private var menuItems: [NSMenuItem] = []
    var onStateChange: ((UpdateMenuState) -> Void)?
    var prepareForInteraction: (() -> Void)?

    var state: UpdateMenuState {
        guard let updater = controller?.updater, problem == nil else { return UpdateMenuState(isReady: false) }
        return UpdateMenuState(isReady: true, canCheck: updater.canCheckForUpdates,
                               automaticChecks: updater.automaticallyChecksForUpdates,
                               automaticDownloads: updater.automaticallyDownloadsUpdates,
                               allowsAutomaticUpdates: updater.allowsAutomaticUpdates,
                               availableVersion: availableVersion)
    }

    func start() {
        guard controller == nil else { return }
        let config = UpdateConfiguration(info: Bundle.main.infoDictionary ?? [:])
        problem = config.problem
        guard config.isReady else { refresh(); return }
        let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        controller = updater
        do { try updater.updater.start() }
        catch { problem = "更新服务无法启动：\(error.localizedDescription)" }
        refresh()
    }

    func addItems(to menu: NSMenu) {
        for (title, action) in [("检查更新…", #selector(checkForUpdates)),
                                ("自动检查更新", #selector(toggleChecks)),
                                ("自动下载并安装更新", #selector(toggleDownloads))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menuItems.append(item)
        }
        refresh()
    }

    func refresh() {
        let current = state
        for item in menuItems {
            if item.action == #selector(checkForUpdates) { item.title = current.actionTitle }
            if item.action == #selector(toggleChecks) { item.state = current.automaticChecks ? .on : .off }
            if item.action == #selector(toggleDownloads) { item.state = current.automaticDownloads ? .on : .off }
            item.isEnabled = validateMenuItem(item)
        }
        onStateChange?(current)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(checkForUpdates): return state.canSelectCheck
        case #selector(toggleChecks): return state.canToggleChecks
        case #selector(toggleDownloads): return state.canToggleDownloads
        default: return true
        }
    }

    @objc private func checkForUpdates() {
        prepareForInteraction?()
        NSApp.activate(ignoringOtherApps: true)
        guard problem == nil, let controller else {
            let alert = NSAlert()
            alert.messageText = "暂时无法检查更新"
            alert.informativeText = problem ?? "更新服务尚未启动，请稍后再试。"
            alert.addButton(withTitle: "好")
            alert.runModal()
            return
        }
        guard state.canSelectCheck else { return }
        controller.checkForUpdates(nil)
    }

    @objc private func toggleChecks() {
        guard state.canToggleChecks, let updater = controller?.updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
        refresh()
    }

    @objc private func toggleDownloads() {
        guard state.canToggleDownloads, let updater = controller?.updater else { return }
        updater.automaticallyDownloadsUpdates.toggle()
        refresh()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Background checks announce themselves in the menu bar, even while writing.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate, !state.userInitiated else { return }
        availableVersion = update.displayVersionString
        refresh()
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableVersion = nil
        refresh()
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableVersion = nil
        refresh()
    }
}
