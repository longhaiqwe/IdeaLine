// Render the shipping SwiftUI views with synthetic data, without opening the
// user's data store, registering shortcuts, or capturing their desktop.
import AppKit
import SwiftUI

private let canvas = Color(red: 0.93, green: 0.94, blue: 0.90)

private struct DemoCanvas<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.98, green: 0.97, blue: 0.93), canvas], startPoint: .topLeading, endPoint: .bottomTrailing)
            content
        }
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
        .preferredColorScheme(.light)
    }
}

@main
struct ReadmeRenderer {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/images", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("idealine-readme-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = IdeaStore(url: temporary.appendingPathComponent("ideas.json"))
        let subjects = [
            "把一次散步，写成一篇城市观察。\n\n从街角那家小店开始。",
            "读完一本书，只留下一个真正想实践的想法。",
            "为什么好用的小工具，往往只解决一个问题？",
            "周末的小实验：\n给自己留一个没有日程的下午。",
            "做一份自己的灵感清单：\n随手记下，慢慢展开。",
            "整理最近拍的照片，找出三个反复出现的主题。"
        ]
        let date = ISO8601DateFormatter().date(from: "2026-10-21T09:30:00+08:00")!
        let ideas = subjects.enumerated().map { index, text in
            Idea(text: text, color: index % 4, createdAt: date.addingTimeInterval(-Double(index) * 1200), updatedAt: date)
        } + [Idea(text: "已经写完的选题，收纳起来，给新想法留点位置。", color: 1, createdAt: date, updatedAt: date, archived: true)]
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        try JSONEncoder().encode(SavedState(ideas: ideas, draft: Draft())).write(to: store.url)
        let demo = IdeaStore(url: store.url)
        let line = LineState()
        line.capacity = 5
        line.revealed = true

        let hero = DemoCanvas {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("灵感晾台  /  IDEA LINE").font(.system(size: 13, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(accent)
                    Text("把灵感，先晾起来。").font(.system(size: 42, weight: .medium, design: .serif)).foregroundStyle(ink)
                    Text("随手记下一个选题，让它留在抬眼可见的地方。").font(.system(size: 17)).foregroundStyle(inkSecondary)
                }
                .padding(.leading, 64).padding(.top, 42).padding(.bottom, 24)
                ClotheslineView(store: demo, line: line, edit: { _ in }, compose: {}, library: {}).frame(height: 290)
                HStack(spacing: 10) {
                    Text("⌃⌥N  随手记录")
                    Text("·")
                    Text("⌘↵  挂上衣杆")
                    Text("·")
                    Text("拖动便签，整理思路")
                }.font(.system(size: 13)).foregroundStyle(inkSecondary).frame(maxWidth: .infinity).padding(.top, 6)
                Spacer(minLength: 0)
            }
        }
        try render(hero, size: NSSize(width: 1200, height: 560), to: output.appendingPathComponent("clothesline.png"))

        let composer = DemoCanvas {
            ComposerView(store: demo, draft: Draft(text: "一个小观察：\n\n很多好想法，不是想出来的，\n而是在散步、聊天和发呆时冒出来的。\n\n先记下来，再慢慢展开。", color: 0), close: {}, saved: {})
                .frame(width: 600, height: 450)
                .shadow(color: .black.opacity(0.12), radius: 24, y: 12)
        }
        try render(composer, size: NSSize(width: 800, height: 610), to: output.appendingPathComponent("composer.png"))

        let library = DemoCanvas {
            LibraryView(store: demo, compose: {}, edit: { _ in }, export: {})
                .frame(width: 900, height: 690)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(inkBorder, lineWidth: 1))
                .shadow(color: .black.opacity(0.10), radius: 24, y: 12)
        }
        try render(library, size: NSSize(width: 1040, height: 810), to: output.appendingPathComponent("library.png"))
    }

    @MainActor
    private static func render<V: View>(_ view: V, size: NSSize, to url: URL) throws {
        // A non-visible window supplies AppKit layout for native text fields.
        // cacheDisplay renders this view only; no screen pixels are captured.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
        print("Rendered \(url.path)")
        window.close()
    }
}
