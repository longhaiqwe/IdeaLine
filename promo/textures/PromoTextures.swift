// Render UI textures and caption layers for the Blender promo.
// Compiled together with the app sources so colors, type scale and LibraryView
// come from the shipping code. Uses synthetic data only.
import AppKit
import SwiftUI

private let zhCN = Locale(identifier: "zh_CN")
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

// MARK: - Content

private struct NoteContent: Decodable { let text: String; let color: Int; let date: String }
private struct EndCaption: Decodable { let eyebrow, title, tagline, meta, url: String }
private struct KeyCaption: Decodable { let before, keys, after: String }
private struct Captions: Decodable {
    struct Macro: Decodable { let eyebrow, headline: String }
    struct Plain: Decodable { let text: String }
    struct Edges: Decodable { let text: String; let pills: [String] }
    let macro: Macro
    let hotkey, submit: KeyCaption
    let reveal, drag, library: Plain
    let edges: Edges
    let end: EndCaption
}
private struct Content: Decodable {
    let notes: [NoteContent]
    let archived: NoteContent
    let newNote: NoteContent
    let typingChunks: [String]
    let captions: Captions
}

private func idea(_ note: NoteContent, archived: Bool = false) -> Idea {
    let date = ISO8601DateFormatter().date(from: note.date)!
    return Idea(text: note.text, color: note.color, createdAt: date, updatedAt: date, archived: archived)
}

// MARK: - Note face (HangingNote without pin, tilt and shadow)

private struct NoteFace: View {
    let idea: Idea
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(idea.createdAt, format: .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                Spacer()
            }
            .font(.system(size: AppTypeScale.caption, weight: .medium, design: .monospaced))
            .foregroundStyle(inkSecondary)
            Text(idea.text)
                .font(.system(size: AppTypeScale.body, weight: .medium, design: .serif))
                .lineSpacing(4)
                .lineLimit(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack(alignment: .center) {
                Text("点击编辑").font(.system(size: AppTypeScale.caption)).foregroundStyle(inkSecondary)
                Spacer()
                Image(systemName: "doc.on.doc").font(.system(size: AppTypeScale.caption)).foregroundStyle(inkSecondary).frame(width: 24, height: 24)
                Image(systemName: "archivebox").font(.system(size: AppTypeScale.caption)).foregroundStyle(inkSecondary).frame(width: 24, height: 24)
            }
        }
        .padding(14)
        .frame(width: 184, height: 171)
        .background(noteColor(idea.color))
        .overlay(RoundedRectangle(cornerRadius: radiusCard).stroke(inkBorder, lineWidth: 1))
        .foregroundStyle(ink)
    }
}

// MARK: - Composer face (ComposerView with a SwiftUI text body so a caret can be drawn)

private struct ComposerFace: View {
    let text: String
    let caret: Bool
    let color: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Image(systemName: "wind").foregroundStyle(accent)
                    Text("新建选题").font(.system(size: AppTypeScale.subhead, weight: .semibold, design: .serif))
                }
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(inkSecondary)
                    .frame(width: 24, height: 24)
                    .background(inkBorder, in: Circle())
            }
            .padding(.bottom, 20)

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("记录新选题或碎片灵感…").foregroundStyle(inkMuted)
                }
                Text("\(text)\(Text(caret ? "|" : " ").foregroundColor(accent))")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 20))
            .lineSpacing(3)
            .padding(.top, 8)
            .padding(.leading, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Rectangle().fill(inkBorder).frame(height: 1).padding(.vertical, 16)

            HStack(alignment: .center, spacing: 10) {
                ForEach(0..<papers.count, id: \.self) { i in
                    ZStack {
                        Circle().fill(papers[i]).frame(width: 22, height: 22)
                        if color == i {
                            Circle().stroke(ink, lineWidth: 2).frame(width: 22, height: 22)
                            Circle().fill(ink).frame(width: 6, height: 6)
                        } else {
                            Circle().stroke(inkBorder, lineWidth: 1).frame(width: 22, height: 22)
                        }
                    }
                }
                Text("\(text.count) 字")
                    .font(.system(size: AppTypeScale.caption, design: .monospaced))
                    .foregroundStyle(inkSecondary)
                    .padding(.leading, 8)
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("保存至衣杆").fontWeight(.semibold)
                    Text("⌘↵").font(.system(size: AppTypeScale.caption, design: .monospaced)).opacity(0.7)
                }
                .padding(.horizontal, 16).padding(.vertical, 9)
                .foregroundStyle(.white)
                .background(ink.opacity(text.isEmpty ? 0.35 : 1), in: RoundedRectangle(cornerRadius: radiusCard * 2))
            }

            HStack {
                Text("按 ⌘↵ 保存至顶部衣杆，Esc 保留草稿退出")
                    .font(.system(size: AppTypeScale.caption))
                    .foregroundStyle(inkSecondary)
                Spacer()
            }
            .padding(.top, 14)
        }
        .padding(28)
        .frame(width: 600, height: 450)
        .background(paper)
        .overlay(RoundedRectangle(cornerRadius: radiusWindow).stroke(inkBorder, lineWidth: 1))
        .foregroundStyle(ink)
    }
}

// MARK: - Clothesline toolbar (top position)

private struct Toolbar: View {
    let total: Int
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                Label("新建选题", systemImage: "plus")
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(ink, in: Capsule()).foregroundStyle(.white)
                Divider().frame(height: 12)
                Label("全部 \(total) 条", systemImage: "tray.full").foregroundStyle(ink)
            }
            Text("拖动便签排序").font(.system(size: AppTypeScale.caption)).foregroundStyle(inkSecondary)
        }
        .font(.system(size: AppTypeScale.small, weight: .medium))
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Color.white.opacity(0.78), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(inkBorder, lineWidth: 0.5))
        .padding(1)
        .fixedSize()
    }
}

// MARK: - Desktop (wallpaper + menu bar), 1600 x 1000 pt

private struct Desktop: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.97, green: 0.95, blue: 0.90), Color(red: 0.91, green: 0.92, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.99, green: 0.86, blue: 0.62)).frame(width: 900).blur(radius: 170).offset(x: -520, y: 380)
            Circle().fill(Color(red: 0.78, green: 0.88, blue: 0.80)).frame(width: 820).blur(radius: 180).offset(x: 560, y: 120)
            Circle().fill(Color(red: 0.80, green: 0.88, blue: 0.96)).frame(width: 760).blur(radius: 170).offset(x: 200, y: 640)
            Circle().fill(Color(red: 0.97, green: 0.80, blue: 0.74)).frame(width: 640).blur(radius: 160).offset(x: -80, y: 760)
            HStack(spacing: 18) {
                Spacer()
                Image(systemName: "wind").font(.system(size: 14, weight: .semibold))
                Image(systemName: "wifi").font(.system(size: 13, weight: .semibold))
                Image(systemName: "battery.75percent").font(.system(size: 15))
                Text("10月23日 周五  10:30").font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 22)
            .frame(height: 25)
            .background(Color.white.opacity(0.42))
        }
        .frame(width: 1600, height: 1000)
        .clipped()
    }
}

// MARK: - Keycap legends

private struct KeyLegend: View {
    let symbol: String?
    let glyph: String?
    let word: String?
    var body: some View {
        VStack(spacing: 10) {
            if let symbol { Image(systemName: symbol).font(.system(size: 74, weight: .regular)) }
            if let glyph { Text(glyph).font(.system(size: 120, weight: .regular)) }
            if let word { Text(word).font(.system(size: 34, weight: .medium)) }
        }
        .foregroundStyle(Color.black)
    }
}

// MARK: - Captions on a 960 x 540 canvas, rendered at 2x

private struct KeyChip: View {
    let keys: String
    var body: some View {
        Text(keys)
            .font(.system(size: 19, weight: .semibold, design: .monospaced))
            .tracking(2)
            .padding(.horizontal, 11).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.94)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(ink.opacity(0.22), lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
    }
}

private struct CaptionCanvas<C: View>: View {
    let content: C
    init(@ViewBuilder content: () -> C) { self.content = content() }
    var body: some View {
        VStack {
            Spacer()
            content
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(ink)
                .shadow(color: Color(red: 0.98, green: 0.97, blue: 0.94).opacity(0.95), radius: 9)
                .padding(.bottom, 44)
        }
        .frame(width: 960, height: 540)
    }
}

private struct EndCard: View {
    let c: EndCaption
    let show: String
    var body: some View {
        VStack(spacing: 0) {
            Text(c.eyebrow)
                .font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(6)
                .foregroundStyle(accent).opacity(show == "eyebrow" ? 1 : 0)
            Text(c.title)
                .font(.custom("Songti SC", size: 46).weight(.semibold))
                .foregroundStyle(ink).padding(.top, 10).opacity(show == "title" ? 1 : 0)
            Text(c.tagline)
                .font(.custom("Songti SC", size: 20).weight(.medium))
                .foregroundStyle(inkSecondary).padding(.top, 10).opacity(show == "tagline" ? 1 : 0)
            Text(c.meta)
                .font(.system(size: 11.5)).foregroundStyle(inkSecondary)
                .padding(.top, 34).opacity(show == "meta" ? 1 : 0)
            Text(c.url)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(accent).padding(.top, 8).opacity(show == "url" ? 1 : 0)
            Spacer()
        }
        .padding(.top, 296)
        .frame(width: 960, height: 540)
    }
}

// MARK: - Rendering

@MainActor
private func save<V: View>(_ view: V, size: CGSize?, scale: CGFloat, to url: URL) throws -> CGSize {
    let root = view
        .environment(\.locale, zhCN)
        .environment(\.timeZone, shanghai)
        .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: root)
    renderer.scale = scale
    renderer.isOpaque = false
    if let size { renderer.proposedSize = ProposedViewSize(size) }
    guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url)
    return CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
}

/// LibraryView contains AppKit-backed controls, so it goes through NSHostingView like render-readme.
@MainActor
private func saveHosted<V: View>(_ view: V, size: NSSize, scale: CGFloat, to url: URL) throws {
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height)
        .environment(\.locale, zhCN).environment(\.timeZone, shanghai))
    host.frame = NSRect(origin: .zero, size: size)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try png.write(to: url)
    window.close()
}

/// The yellow note from scripts/make-icon.swift, cropped to the note (518 x 482).
private func saveIconNote(to url: URL) throws {
    let scale: CGFloat = 2
    let size = NSSize(width: 518, height: 482)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(red: 1, green: 0.89, blue: 0.59, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 166, weight: .light), .foregroundColor: NSColor(red: 0.25, green: 0.28, blue: 0.23, alpha: 1)]
    ("X" as NSString).draw(at: NSPoint(x: 334 - 253, y: 393 - 212), withAttributes: attributes)
    NSColor(red: 0.65, green: 0.57, blue: 0.35, alpha: 0.5).setStroke()
    for y in [322, 282] {
        let p = NSBezierPath(); p.move(to: NSPoint(x: 338 - 253, y: y - 212)); p.line(to: NSPoint(x: 683 - 253, y: y - 212)); p.lineWidth = 5; p.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// macOS-style arrow pointer, tip at (6, 4) pt on a 32 x 32 pt canvas (y down).
private func saveCursor(to url: URL) throws {
    let scale: CGFloat = 8
    let size = NSSize(width: 32, height: 32)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let points: [(CGFloat, CGFloat)] = [(0, 0), (0, 16.5), (4, 12.6), (6.9, 19.2), (9.3, 18.2), (6.5, 11.8), (11.9, 11.8)]
    let path = NSBezierPath()
    for (i, p) in points.enumerated() {
        let point = NSPoint(x: 6 + p.0, y: size.height - 4 - p.1)
        if i == 0 { path.move(to: point) } else { path.line(to: point) }
    }
    path.close()
    path.lineJoinStyle = .round
    path.lineWidth = 1.6
    NSColor.white.setStroke(); path.stroke()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

@main
struct PromoTextures {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let args = CommandLine.arguments
        let contentURL = URL(fileURLWithPath: args[1])
        let out = URL(fileURLWithPath: args[2], isDirectory: true)
        let fm = FileManager.default
        for sub in ["notes", "composer", "ui", "keys", "captions"] {
            try fm.createDirectory(at: out.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        let content = try JSONDecoder().decode(Content.self, from: Data(contentsOf: contentURL))
        var manifest: [String: [String: Double]] = [:]
        func record(_ key: String, _ size: CGSize) { manifest[key] = ["w": Double(size.width), "h": Double(size.height)] }

        // Notes
        for (i, note) in content.notes.enumerated() {
            record("notes/note_\(i).png", try save(NoteFace(idea: idea(note)), size: CGSize(width: 184, height: 171), scale: 4, to: out.appendingPathComponent("notes/note_\(i).png")))
        }
        record("notes/note_new.png", try save(NoteFace(idea: idea(content.newNote)), size: CGSize(width: 184, height: 171), scale: 4, to: out.appendingPathComponent("notes/note_new.png")))

        // Composer typing states: state_<chunks>_<caret>.png
        var typed = ""
        for k in 0...content.typingChunks.count {
            if k > 0 { typed += content.typingChunks[k - 1] }
            for caret in [0, 1] {
                let name = String(format: "composer/state_%02d_%d.png", k, caret)
                record(name, try save(ComposerFace(text: typed, caret: caret == 1, color: content.newNote.color), size: CGSize(width: 600, height: 450), scale: 3, to: out.appendingPathComponent(name)))
            }
        }

        // Toolbar before/after the new note
        let total = content.notes.count
        record("ui/toolbar_before.png", try save(Toolbar(total: total), size: nil, scale: 4, to: out.appendingPathComponent("ui/toolbar_before.png")))
        record("ui/toolbar_after.png", try save(Toolbar(total: total + 1), size: nil, scale: 4, to: out.appendingPathComponent("ui/toolbar_after.png")))

        // Desktop
        record("ui/desktop.png", try save(Desktop(), size: CGSize(width: 1600, height: 1000), scale: 2, to: out.appendingPathComponent("ui/desktop.png")))

        // Library window, using the shipping LibraryView with a temporary store
        let temporary = fm.temporaryDirectory.appendingPathComponent("idealine-promo-\(UUID())", isDirectory: true)
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: temporary) }
        let storeURL = temporary.appendingPathComponent("ideas.json")
        let ideas = [idea(content.newNote)] + content.notes.map { idea($0) } + [idea(content.archived, archived: true)]
        try JSONEncoder().encode(SavedState(ideas: ideas, draft: Draft())).write(to: storeURL)
        let store = IdeaStore(url: storeURL)
        try saveHosted(LibraryView(store: store, compose: {}, edit: { _ in }, export: {}), size: NSSize(width: 900, height: 690), scale: 3, to: out.appendingPathComponent("ui/library.png"))
        record("ui/library.png", CGSize(width: 900, height: 690))

        // Icon note
        try saveIconNote(to: out.appendingPathComponent("ui/icon_note.png"))
        record("ui/icon_note.png", CGSize(width: 518, height: 482))
        try saveCursor(to: out.appendingPathComponent("ui/cursor.png"))
        record("ui/cursor.png", CGSize(width: 32, height: 32))

        // Keycap legends (black on transparent; Blender uses them as masks)
        let keys: [(String, KeyLegend, CGSize)] = [
            ("keys/ctrl.png", KeyLegend(symbol: "control", glyph: nil, word: "control"), CGSize(width: 256, height: 256)),
            ("keys/opt.png", KeyLegend(symbol: "option", glyph: nil, word: "option"), CGSize(width: 256, height: 256)),
            ("keys/n.png", KeyLegend(symbol: nil, glyph: "N", word: nil), CGSize(width: 256, height: 256)),
            ("keys/cmd.png", KeyLegend(symbol: "command", glyph: nil, word: "command"), CGSize(width: 256, height: 256)),
            ("keys/ret.png", KeyLegend(symbol: "return", glyph: nil, word: "return"), CGSize(width: 512, height: 256)),
        ]
        for (name, view, size) in keys {
            record(name, try save(view.frame(width: size.width, height: size.height), size: size, scale: 2, to: out.appendingPathComponent(name)))
        }

        // Captions (1920 x 1080 transparent layers)
        let c = content.captions
        let full = CGSize(width: 960, height: 540)
        func caption<V: View>(_ name: String, _ view: V) throws {
            _ = try save(view, size: full, scale: 2, to: out.appendingPathComponent("captions/\(name).png"))
        }
        try caption("macro", VStack(alignment: .leading, spacing: 12) {
            Spacer()
            Text(c.macro.eyebrow).font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(accent)
            Text(c.macro.headline).font(.custom("Songti SC", size: 38).weight(.semibold)).foregroundStyle(ink)
        }
        .shadow(color: Color(red: 0.98, green: 0.97, blue: 0.94).opacity(0.9), radius: 12)
        .padding(.leading, 60).padding(.bottom, 54)
        .frame(width: 960, height: 540, alignment: .bottomLeading))
        for (name, k) in [("hotkey", c.hotkey), ("submit", c.submit)] {
            try caption(name, CaptionCanvas { HStack(spacing: 8) { Text(k.before); KeyChip(keys: k.keys); Text(k.after).padding(.leading, -6) } })
        }
        try caption("reveal", CaptionCanvas { Text(c.reveal.text) })
        try caption("drag", CaptionCanvas { Text(c.drag.text) })
        try caption("library", CaptionCanvas { Text(c.library.text) })
        try caption("edges", CaptionCanvas { Text(c.edges.text).padding(.bottom, 44) })
        for (i, _) in c.edges.pills.enumerated() {
            try caption("edges_pill_\(i)", CaptionCanvas {
                HStack(spacing: 8) {
                    ForEach(Array(c.edges.pills.enumerated()), id: \.offset) { j, pill in
                        Text(pill)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .foregroundStyle(j == i ? Color.white : inkSecondary)
                            .background(j == i ? ink : Color.white.opacity(0.85), in: Capsule())
                            .overlay(Capsule().stroke(inkBorder, lineWidth: 1))
                    }
                }
            })
        }
        for part in ["eyebrow", "title", "tagline", "meta", "url"] {
            try caption("end_\(part)", EndCard(c: c.end, show: part))
        }

        let json = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: out.appendingPathComponent("manifest.json"))
        print("Rendered \(manifest.count) textures and captions to \(out.path)")
    }
}
