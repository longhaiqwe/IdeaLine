import AppKit
import SwiftUI
import Carbon

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class KeyWindow: NSWindow {
    var onNew: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if AppShortcut.newIdea.matches(event) {
            onNew?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
final class LinePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        hidesOnDeactivate = false; ignoresMouseEvents = true
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = IdeaStore()
    let line = LineState()
    private let updates = UpdateController()
    private var status: NSStatusItem!
    private var linePanel: LinePanel!
    private var lineScreen: NSScreen?
    private var positionItems: [NSMenuItem] = []
    private var composer: FloatingPanel?
    private var library: NSWindow?
    private var shortcuts: HotKeys!
    private var timer: Timer?
    private var peekUntil = Date.distantPast
    private var enteredEdge: Date?
    private var awaySince: Date?
    private var menuOpen = false
    private var suppressed = false
    private var monitors: [Any] = []
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMainMenu()
        linePanel = LinePanel()
        let host = NSHostingView(rootView: ClotheslineView(store: store, line: line, edit: { [weak self] in self?.openEditor($0) }, compose: { [weak self] in self?.openEditor() }, library: { [weak self] in self?.openLibrary() }))
        host.sizingOptions = []; linePanel.contentView = host
        placeLine(); linePanel.orderFrontRegardless()
        setupMenu()
        updates.prepareForInteraction = { [weak self] in self?.hideLine() }
        updates.onStateChange = { [weak self] state in
            guard let self else { return }
            self.status.button?.image = NSImage(systemSymbolName: state.symbolName, accessibilityDescription: state.availableVersion == nil ? "灵感晾台" : "灵感晾台有新版本")
            self.status.button?.image?.isTemplate = true
            self.status.button?.toolTip = state.availableVersion.map { "灵感晾台 \($0) 可更新" } ?? "灵感晾台 · \(AppShortcut.newIdea.label) 新建选题"
        }
        updates.start()
        shortcuts = HotKeys()
        let captureOK = shortcuts.register(.newIdea, id: 1) { [weak self] in self?.openEditor() }
        let lineOK = shortcuts.register(.toggleLine, id: 2) { [weak self] in self?.toggleLine() }
        if !captureOK || !lineOK {
            let failed = [(captureOK, "新建选题：\(AppShortcut.newIdea.label)"),
                          (lineOK, "展开 / 收起衣杆：\(AppShortcut.toggleLine.label)")]
                .filter { !$0.0 }.map { $0.1 }.joined(separator: "\n")
            DispatchQueue.main.async { self.alert("快捷键注册失败", "\(failed)\n可能已被其他应用占用。仍可从菜单栏打开书写窗口与衣杆。") }
        }
        // Also handle app-targeted key events, including accessibility automation.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            if AppShortcut.newIdea.matches(event) {
                self?.openEditor()
                return nil
            }
            if AppShortcut.toggleLine.matches(event) {
                self?.toggleLine()
                return nil
            }
            return event
        }) { monitors.append(monitor) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        let click: (NSEvent) -> Void = { [weak self] _ in
            guard let self, let screen = self.pointerScreen else { return }
            if NSEvent.mouseLocation.y >= screen.visibleFrame.maxY {
                self.suppressed = true; self.hideLine()
            }
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: click) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { event in click(event); return event }) { monitors.append(monitor) }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.placeLine() }
        if !UserDefaults.standard.bool(forKey: "didWelcome") {
            openLibrary(); UserDefaults.standard.set(true, forKey: "didWelcome")
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { openLibrary(); return true }
    private var pointerScreen: NSScreen? { NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main }
    private func placeLine() {
        guard let screen = pointerScreen else { return }
        lineScreen = screen
        let frame = screen.visibleFrame
        linePanel.setFrame(line.position.panelFrame(in: frame), display: true)
        line.capacity = line.position.capacity(in: frame)
    }
    private func reveal(seconds: Double = 3) {
        placeLine(); linePanel.orderFrontRegardless(); line.revealed = true
        peekUntil = Date().addingTimeInterval(seconds); awaySince = nil
    }
    private func hideLine(manually: Bool = false) {
        guard line.hide(manually: manually) else { return }
        linePanel.ignoresMouseEvents = true; enteredEdge = nil; awaySince = nil
    }
    @objc private func toggleLine() { if line.revealed { hideLine(manually: true) } else { reveal(seconds: 6) } }
    private func tick() {
        guard !menuOpen, composer?.isVisible != true || line.isPinned else { return }
        let mouse = NSEvent.mouseLocation
        let now = Date()
        guard let screen = pointerScreen else { return }
        // Only the selected screen edge triggers a peek.
        let atEdge = line.position.isAtEdge(mouse, of: screen.frame)
        if !atEdge { suppressed = false }
        if !line.revealed {
            if atEdge && !suppressed {
                if enteredEdge == nil { enteredEdge = now }
                if now.timeIntervalSince(enteredEdge!) > 0.3 { reveal(seconds: 1) }
            } else { enteredEdge = nil }
            return
        }
        // Keep a mouse gesture captured even when it crosses transparent gaps
        // or leaves the panel. Resume hit testing and auto-hide after release.
        if !linePanel.ignoresMouseEvents && NSEvent.pressedMouseButtons & 1 != 0 {
            awaySince = nil
            return
        }
        let local = NSPoint(x: mouse.x - linePanel.frame.minX, y: linePanel.frame.maxY - mouse.y)
        linePanel.ignoresMouseEvents = !line.hitRects.contains { $0.insetBy(dx: -8, dy: -8).contains(local) }
        let zone = line.position.interactionZone(panel: linePanel.frame, screen: (lineScreen ?? screen).frame)
        if line.isPinned || zone.contains(mouse) || now < peekUntil { awaySince = nil }
        else {
            if awaySince == nil { awaySince = now }
            if now.timeIntervalSince(awaySince!) > 0.55 { hideLine() }
        }
    }
    @objc private func changeLinePosition(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let position = LinePosition(rawValue: value) else { return }
        hideLine()
        line.position = position
        UserDefaults.standard.set(position.rawValue, forKey: LinePosition.defaultsKey)
        line.page = 0
        line.hitRects = []
        positionItems.forEach { $0.state = ($0.representedObject as? String) == value ? .on : .off }
        reveal(seconds: 6)
    }
    @objc func newIdea() { openEditor() }
    func openEditor(_ idea: Idea? = nil) {
        if composer?.isVisible == true {
            composer?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if let content = composer?.contentView,
               let textView = findWritingTextView(in: content) {
                composer?.makeFirstResponder(textView)
            }
            return
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier { previousApp = NSWorkspace.shared.frontmostApplication }
        let draft: Draft
        if let idea {
            // Keep a pending new thought safe instead of replacing it with an edit.
            if !store.state.draft.text.isEmpty && store.state.draft.id != idea.id {
                let alert = NSAlert(); alert.messageText = "当前有未保存的草稿"; alert.informativeText = "书写窗口中仍有正在编辑的草稿。请先保存或关闭当前草稿，再编辑该便签。"; alert.addButton(withTitle: "查看草稿"); alert.runModal()
                draft = store.state.draft
            } else { draft = Draft(id: idea.id, text: idea.text, color: idea.color) }
        } else { draft = store.state.draft }
        let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 450), styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = "新建选题 · 灵感晾台"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true; panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.hidesOnDeactivate = false
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: ComposerView(store: store, draft: draft, close: { [weak self] in self?.closeEditor() }, saved: { [weak self] in
            self?.closeEditor(); self?.line.page = 0; self?.reveal(seconds: 3.5)
        }).preferredColorScheme(.light))
        if let screen = pointerScreen { let f = screen.visibleFrame; panel.setFrameOrigin(NSPoint(x: f.midX - 300, y: f.midY - 190)) }
        composer = panel; hideLine(); NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil)
    }
    private func closeEditor() {
        composer?.orderOut(nil); composer = nil
        previousApp?.activate(options: []); previousApp = nil
    }
    @objc func openLibrary() {
        if library == nil {
            let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 630), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "灵感晾台"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.onNew = { [weak self] in self?.openEditor() }
            window.contentView = NSHostingView(rootView: LibraryView(store: store, compose: { [weak self] in self?.openEditor() }, edit: { [weak self] in self?.openEditor($0) }, export: { [weak self] in self?.exportMarkdown() }))
            window.center(); library = window
        }
        hideLine(); NSApp.activate(ignoringOtherApps: true); library?.makeKeyAndOrderFront(nil)
    }
    @objc func exportMarkdown() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "灵感晾台.md"; panel.title = "导出全部选题（含已收纳）"
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            do { try store.markdown().write(to: url, atomically: true, encoding: .utf8) }
            catch { alert("导出失败", error.localizedDescription) }
        }
    }
    @objc private func showData() { NSWorkspace.shared.selectFile(store.url.path, inFileViewerRootedAtPath: store.url.deletingLastPathComponent().path) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func showAbout() {
        hideLine()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "灵感晾台", .credits: NSAttributedString(string: "用一张便签，留住一个选题。\n更新服务由 Sparkle 提供。")])
    }
    private func setupMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "wind", accessibilityDescription: "灵感晾台")
        status.button?.toolTip = "灵感晾台 · \(AppShortcut.newIdea.label) 新建选题"
        let menu = NSMenu(); menu.delegate = self
        func item(_ title: String, _ action: Selector, _ shortcut: AppShortcut? = nil) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: shortcut?.key ?? ""); i.target = self
            if let shortcut { i.keyEquivalentModifierMask = shortcut.modifiers }
            menu.addItem(i)
        }
        item("新建选题", #selector(newIdea), .newIdea)
        item("展开 / 收起衣杆", #selector(toggleLine), .toggleLine)
        item("全部选题", #selector(openLibrary))
        let positionMenu = NSMenu(title: "晾台位置")
        for position in LinePosition.allCases {
            let option = NSMenuItem(title: position.title, action: #selector(changeLinePosition(_:)), keyEquivalent: "")
            option.target = self
            option.representedObject = position.rawValue
            option.state = line.position == position ? .on : .off
            positionMenu.addItem(option)
            positionItems.append(option)
        }
        let positionItem = NSMenuItem(title: "晾台位置", action: nil, keyEquivalent: "")
        positionItem.submenu = positionMenu
        menu.addItem(positionItem)
        menu.addItem(.separator())
        item("导出 Markdown…", #selector(exportMarkdown)); item("打开数据文件夹", #selector(showData))
        menu.addItem(.separator())
        item("关于灵感晾台", #selector(showAbout))
        updates.addItems(to: menu)
        menu.addItem(.separator()); item("退出灵感晾台", #selector(quit))
        status.menu = menu
    }
    private func findWritingTextView(in view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView { return tv }
        for sub in view.subviews {
            if let found = findWritingTextView(in: sub) { return found }
        }
        return nil
    }
    private func buildMainMenu() {
        let main = NSMenu()
        let app = NSMenuItem()
        app.submenu = NSMenu()
        app.submenu?.delegate = self
        let about = NSMenuItem(title: "关于灵感晾台", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        app.submenu?.addItem(about)
        if let menu = app.submenu { updates.addItems(to: menu) }
        app.submenu?.addItem(.separator())
        app.submenu?.addItem(withTitle: "退出灵感晾台", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(app)

        let file = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "文件")
        let newItem = NSMenuItem(title: "新建选题", action: #selector(newIdea), keyEquivalent: AppShortcut.newIdea.key)
        newItem.keyEquivalentModifierMask = AppShortcut.newIdea.modifiers
        newItem.target = self
        fileMenu.addItem(newItem)
        file.submenu = fileMenu
        main.addItem(file)

        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "编辑")
        for (name, action, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] { submenu.addItem(withTitle: name, action: action, keyEquivalent: key) }
        edit.submenu = submenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }
    private func alert(_ title: String, _ detail: String) { let a = NSAlert(); a.messageText = title; a.informativeText = detail; a.runModal() }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); monitors.forEach { NSEvent.removeMonitor($0) } }
}
extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; hideLine(); updates.refresh() }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; suppressed = true }
}
