import SwiftUI
import AppKit

// MARK: - Design Tokens (Refactoring UI §1.5, §4.1, §5.2.1, §6.2.1)
let ink = Color(red: 0.20, green: 0.23, blue: 0.20) // 主墨色 #333B33
let inkSecondary = Color(red: 0.38, green: 0.42, blue: 0.38) // 次级墨色，严格满足 WCAG 4.5:1
let inkMuted = Color(red: 0.55, green: 0.58, blue: 0.55) // 弱化修饰墨色
let inkBorder = Color(red: 0.20, green: 0.23, blue: 0.20).opacity(0.10) // 边框墨色

let paper = Color(red: 0.97, green: 0.96, blue: 0.92)
let accent = Color(red: 0.69, green: 0.29, blue: 0.17)
let papers: [Color] = [
    Color(red: 1, green: 0.95, blue: 0.77),   // 0: 黄色
    Color(red: 0.88, green: 0.94, blue: 0.86), // 1: 绿色
    Color(red: 0.87, green: 0.93, blue: 0.97), // 2: 蓝色
    Color(red: 0.98, green: 0.87, blue: 0.83)  // 3: 粉色
]
func noteColor(_ i: Int) -> Color { papers[max(0, min(i, papers.count - 1))] }

enum AppTypeScale {
    static let caption: CGFloat = 11
    static let small: CGFloat = 12
    static let lead: CGFloat = 13
    static let body: CGFloat = 15
    static let subhead: CGFloat = 18
    static let title: CGFloat = 26
    static let display: CGFloat = 34
}

let radiusCard: CGFloat = 4
let radiusWindow: CGFloat = 14

final class WritingTextView: NSTextView {
    var submit: (() -> Void)?
    var dismiss: (() -> Void)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 36 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            if hasMarkedText() { return super.performKeyEquivalent(with: event) }
            submit?(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 && !hasMarkedText() { dismiss?(); return }
        super.keyDown(with: event)
    }
}
struct WritingEditor: NSViewRepresentable {
    @Binding var text: String
    var submit: () -> Void
    var dismiss: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let view = WritingTextView()
        view.isRichText = false; view.isAutomaticQuoteSubstitutionEnabled = false
        view.drawsBackground = false; view.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        view.textColor = NSColor(ink); view.textContainerInset = NSSize(width: 0, height: 8)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 510, height: CGFloat.greatestFiniteMagnitude)
        view.string = text; view.delegate = context.coordinator
        view.submit = submit; view.dismiss = dismiss; scroll.documentView = view
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let view = scroll.documentView as? WritingTextView {
            if view.string != text && !view.hasMarkedText() { view.string = text }
            view.submit = submit; view.dismiss = dismiss
        }
    }
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WritingEditor
        init(_ parent: WritingEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let view = notification.object as? NSTextView { parent.text = view.string }
        }
    }
}

struct ComposerView: View {
    @ObservedObject var store: IdeaStore
    @State var draft: Draft
    var close: () -> Void
    var saved: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 7) {
                    Image(systemName: "wind").foregroundStyle(accent)
                    Text(draft.id == nil ? "新建选题" : "编辑选题")
                        .font(.system(size: AppTypeScale.subhead, weight: .semibold, design: .serif))
                }
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(inkSecondary)
                        .frame(width: 24, height: 24)
                        .background(inkBorder, in: Circle())
                }
                .buttonStyle(.plain)
                .help("关闭并保留草稿 · Esc")
            }
            .padding(.bottom, 20)

            // Editor
            ZStack(alignment: .topLeading) {
                if draft.text.isEmpty {
                    Text("记录新选题或碎片灵感…")
                        .foregroundStyle(inkMuted)
                        .font(.system(size: 20))
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                WritingEditor(text: $draft.text, submit: submit, dismiss: close)
            }
            .frame(maxHeight: .infinity)

            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.red).padding(.vertical, 4)
            }

            Rectangle().fill(inkBorder).frame(height: 1).padding(.vertical, 16)

            // Bottom bar
            HStack(alignment: .center, spacing: 10) {
                ForEach(0..<papers.count, id: \.self) { i in
                    Button { draft.color = i } label: {
                        ZStack {
                            Circle().fill(papers[i]).frame(width: 22, height: 22)
                            if draft.color == i {
                                Circle().stroke(ink, lineWidth: 2).frame(width: 22, height: 22)
                                Circle().fill(ink).frame(width: 6, height: 6)
                            } else {
                                Circle().stroke(inkBorder, lineWidth: 1).frame(width: 22, height: 22)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(["黄色纸张", "绿色纸张", "蓝色纸张", "粉色纸张"][i])
                }

                Text("\(draft.text.count) 字")
                    .font(.system(size: AppTypeScale.caption, design: .monospaced))
                    .foregroundStyle(inkSecondary)
                    .padding(.leading, 8)

                Spacer()

                Button(action: submit) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(draft.id == nil ? "保存至衣杆" : "保存修改").fontWeight(.semibold)
                        Text("⌘↵").font(.system(size: AppTypeScale.caption, design: .monospaced)).opacity(0.7)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(ink, in: RoundedRectangle(cornerRadius: radiusCard * 2))
                }
                .buttonStyle(.plain)
                .disabled(draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        .background(paper)
        .clipShape(RoundedRectangle(cornerRadius: radiusWindow))
        .overlay(RoundedRectangle(cornerRadius: radiusWindow).stroke(inkBorder, lineWidth: 1))
        .foregroundStyle(ink)
        .onExitCommand(perform: close)
        .onChange(of: draft) { _, value in store.draft(value) }
    }
    private func submit() { if store.hang(draft) { saved() } }
}

final class LineState: ObservableObject {
    static let pinnedDefaultsKey = "linePinned"
    private let defaults: UserDefaults
    @Published var position: LinePosition = .saved()
    @Published var revealed = false
    @Published var isPinned: Bool {
        didSet {
            defaults.set(isPinned, forKey: Self.pinnedDefaultsKey)
            if isPinned { revealed = true }
        }
    }
    @Published var page = 0
    @Published var capacity = 5
    @Published var copied: UUID?
    var hitRects: [CGRect] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPinned = defaults.bool(forKey: Self.pinnedDefaultsKey)
        revealed = isPinned
    }

    /// Automatic dismissal respects the pin; an explicit hide also releases it.
    @discardableResult
    func hide(manually: Bool = false) -> Bool {
        guard manually || !isPinned else { return false }
        if manually { isPinned = false }
        revealed = false
        return true
    }
}
struct HitRects: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}
extension View {
    func interactive() -> some View {
        background(GeometryReader { geo in Color.clear.preference(key: HitRects.self, value: [geo.frame(in: .named("line"))]) })
    }
}
enum ClotheslineLayout {
    static func destinationIndex(from index: Int, translation: CGSize, count: Int, position: LinePosition = .top) -> Int {
        let distance = position.isVertical ? translation.height : translation.width
        let crossDistance = position.isVertical ? translation.width : translation.height
        guard count > 0, distance.isFinite, crossDistance.isFinite,
              abs(distance) > abs(crossDistance) else { return index }
        let slot = CGFloat(index) + (distance / position.noteStride).rounded()
        return Int(max(0, min(CGFloat(count - 1), slot)))
    }
    static func noteTopInset(index: Int, count: Int, width: CGFloat) -> CGFloat {
        // NSHostingView can lay out before its panel receives a screen frame.
        guard width.isFinite, width > 0 else { return 4 }
        let x = width / 2 + (CGFloat(index) - CGFloat(count - 1) / 2) * 208
        let f = x / width
        return 4 + 92 * f * (1 - f)
    }
}

/// Sample the windows beneath the floating panel, even when another app is active.
private struct ClotheslineGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct ClotheslineBackdrop: View {
    var body: some View {
        ClotheslineGlass()
            .overlay {
                // Match the promotional canvas, keeping only a little backdrop tint.
                LinearGradient(
                    colors: [
                        Color(red: 0.98, green: 0.97, blue: 0.93),
                        Color(red: 0.93, green: 0.94, blue: 0.90)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ).opacity(0.94)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.55), lineWidth: 1)
            }
            .padding(4)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ClotheslineView: View {
    @ObservedObject var store: IdeaStore
    @ObservedObject var line: LineState
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.85)))
    private var drag: NoteDrag?
    private struct NoteDrag {
        var id: UUID
        var translation: CGSize
    }
    /// Last drag velocity of a note; kept after release so the swing can settle.
    private struct NotePush {
        var id: UUID
        var tilt: Double
        var at: Date
    }
    @State private var push: NotePush?
    @State private var gustAt = Date.distantPast
    var edit: (Idea) -> Void
    var compose: () -> Void
    var library: () -> Void
    var body: some View {
        GeometryReader { geo in
            let count = max(1, Int(ceil(Double(store.active.count) / Double(line.capacity))))
            let page = min(line.page, count - 1)
            let ideas = Array(store.active.dropFirst(page * line.capacity).prefix(line.capacity))
            Group {
                if line.position.isVertical {
                    VStack(spacing: 8) {
                        ScrollView(.vertical) {
                            ZStack(alignment: .top) {
                                sideRope(count: store.active.count)
                                if store.active.isEmpty {
                                    emptyState.padding(.top, 55)
                                } else {
                                    noteStack(ideas: store.active, page: 0, width: geo.size.width)
                                        .padding(.bottom, 12)
                                }
                            }.frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.never)
                        .interactive()
                        .help("滚动查看更多便签；上下拖动便签调整顺序")
                        toolbar(page: 0, count: 1, isEmpty: store.active.isEmpty)
                        if let error = store.error {
                            Text(error).font(.system(size: AppTypeScale.caption)).foregroundStyle(.red)
                        }
                    }.padding(.bottom, 12)
                } else {
                    ZStack(alignment: .top) {
                        Path { p in
                            p.move(to: CGPoint(x: -10, y: 12))
                            p.addQuadCurve(to: CGPoint(x: geo.size.width + 10, y: 12), control: CGPoint(x: geo.size.width / 2, y: 58))
                        }.stroke(Color(red: 0.57, green: 0.51, blue: 0.40), lineWidth: 1.7).shadow(color: .black.opacity(0.3), radius: 1, y: 1).allowsHitTesting(false)
                        noteStack(ideas: ideas, page: page, width: geo.size.width)
                        if ideas.isEmpty { emptyState.padding(.top, 55) }
                        toolbar(page: page, count: count, isEmpty: ideas.isEmpty)
                            .padding(.top, 228)
                        if let error = store.error {
                            Text(error).font(.system(size: AppTypeScale.caption)).foregroundStyle(.red)
                                .padding(4).background(paper, in: RoundedRectangle(cornerRadius: 4))
                                .padding(.top, 264)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
                .coordinateSpace(name: "line")
                .onPreferenceChange(HitRects.self) { line.hitRects = $0 }
                .offset(line.revealed ? .zero : line.position.hiddenOffset)
                .animation(.spring(response: 0.46, dampingFraction: 0.8), value: line.revealed)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: ideas.map(\.id))
                .background {
                    ClotheslineBackdrop()
                        .opacity(line.revealed ? 1 : 0)
                        .animation(.easeInOut(duration: 0.24), value: line.revealed)
                }
                .onChange(of: line.revealed) { _, shown in if shown { gustAt = Date() } }
        }.preferredColorScheme(.light)
    }

    private var emptyState: some View {
        Button(action: compose) {
            VStack(spacing: 10) {
                Image(systemName: "wind").font(.system(size: 26)).foregroundStyle(accent)
                Text("暂无挂起选题").font(.system(size: AppTypeScale.subhead, weight: .medium, design: .serif))
                Text("\(AppShortcut.newIdea.label)   新建选题").font(.system(size: AppTypeScale.caption, design: .monospaced)).foregroundStyle(inkSecondary)
            }
            .padding(24).background(paper, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(inkBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        }.buttonStyle(.plain).foregroundStyle(ink).interactive()
    }

    private func sideRope(count: Int) -> some View {
        GeometryReader { geo in
            Path { path in
                let x: CGFloat = line.position == .left ? 28 : geo.size.width - 28
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: geo.size.height))
                for index in 0..<count {
                    let y = 34 + CGFloat(index) * line.position.noteStride
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width / 2, y: y))
                }
            }.stroke(Color(red: 0.57, green: 0.51, blue: 0.40), lineWidth: 1.7)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
        }.allowsHitTesting(false)
    }

    private func noteStack(ideas: [Idea], page: Int, width: CGFloat) -> some View {
        let sourceIndex = ideas.firstIndex { $0.id == drag?.id }
        let targetIndex = sourceIndex.map {
            ClotheslineLayout.destinationIndex(from: $0, translation: drag?.translation ?? .zero, count: ideas.count, position: line.position)
        }
        let layout = line.position.isVertical
            ? AnyLayout(VStackLayout(spacing: 24))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
        return layout {
            ForEach(Array(ideas.enumerated()), id: \.element.id) { index, idea in
                HangingNote(idea: idea, copied: line.copied == idea.id, edit: { edit(idea) }, copy: {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(idea.text, forType: .string)
                    line.copied = idea.id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { line.copied = nil }
                }, archive: { store.archive(idea.id, true) },
                motion: NoteMotion(seed: idea.id, live: line.revealed, gustAt: gustAt.addingTimeInterval(0.12 + Double(index) * 0.08),
                                   push: push?.id == idea.id ? push!.tilt : 0, pushedAt: push?.at ?? .distantPast))
                .highPriorityGesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .global)
                        .updating($drag) { value, state, transaction in
                            transaction.animation = nil
                            state = NoteDrag(id: idea.id, translation: value.translation)
                        }
                        .onChanged { value in
                            // A hanging note lags behind a sideways drag.
                            guard !line.position.isVertical else { return }
                            push = NotePush(id: idea.id, tilt: max(-8, min(8, value.velocity.width / 100)), at: value.time)
                        }
                        .onEnded { value in
                            let target = ClotheslineLayout.destinationIndex(from: index, translation: value.translation, count: ideas.count, position: line.position)
                            if target != index {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    _ = store.moveActive(idea.id, to: page * line.capacity + target)
                                }
                            }
                        },
                    including: ideas.count > 1 ? .all : .subviews
                )
                .padding(.top, line.position.isVertical ? 0 : ClotheslineLayout.noteTopInset(index: index, count: ideas.count, width: width))
                .offset(x: line.position.isVertical ? 0 : noteOffset(index: index, count: ideas.count, source: sourceIndex, target: targetIndex),
                        y: line.position.isVertical ? noteOffset(index: index, count: ideas.count, source: sourceIndex, target: targetIndex) : 0)
                .zIndex(drag?.id == idea.id ? 1 : 0)
                .animation(drag?.id == idea.id ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: targetIndex)
                .help(line.position.isVertical ? "点击编辑，上下拖动调整顺序" : "点击编辑，左右拖动调整顺序")
            }
        }.padding(.top, line.position.isVertical ? 20 : 0)
    }

    private func toolbar(page: Int, count: Int, isEmpty: Bool) -> some View {
        let layout = line.position.isVertical
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            HStack(spacing: 12) {
                if !isEmpty {
                    Button(action: compose) {
                        Label("新建选题", systemImage: "plus")
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(ink, in: Capsule()).foregroundStyle(.white)
                    }
                    Divider().frame(height: 12)
                }
                Button(action: library) {
                    Label(isEmpty ? "全部选题" : "全部 \(store.active.count) 条", systemImage: "tray.full")
                        .foregroundStyle(ink)
                }
            }
            if !line.position.isVertical && store.active.count > 1 && line.capacity > 1 {
                Text("拖动便签排序")
                    .font(.system(size: AppTypeScale.caption)).foregroundStyle(inkSecondary)
            }
            if count > 1 {
                HStack(spacing: 12) {
                    Button { line.page = max(0, page - 1) } label: {
                        Image(systemName: line.position.isVertical ? "chevron.up" : "chevron.left")
                    }.disabled(page == 0).help("上一页")
                    Text("\(page + 1) / \(count)").monospacedDigit()
                        .font(.system(size: AppTypeScale.caption)).foregroundStyle(inkSecondary)
                    Button { line.page = min(count - 1, page + 1) } label: {
                        Image(systemName: line.position.isVertical ? "chevron.down" : "chevron.right")
                    }.disabled(page == count - 1).help("下一页")
                }
            }
            Button { line.isPinned.toggle() } label: {
                Label(line.isPinned ? "已固定" : "固定", systemImage: line.isPinned ? "pin.fill" : "pin")
                    .frame(minWidth: 62)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .foregroundStyle(line.isPinned ? Color.white : inkSecondary)
                    .background(line.isPinned ? ink : Color.clear, in: Capsule())
            }
            .help(line.isPinned ? "取消固定，鼠标移开后自动收起" : "固定衣杆，保持展开")
            .accessibilityLabel("固定衣杆")
            .accessibilityValue(line.isPinned ? "已开启" : "已关闭")
        }.buttonStyle(.plain).font(.system(size: AppTypeScale.small, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(inkBorder, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
            .interactive()
    }

    private func noteOffset(index: Int, count: Int, source: Int?, target: Int?) -> CGFloat {
        guard let source, let target, let drag else { return 0 }
        let distance = line.position.isVertical ? drag.translation.height : drag.translation.width
        let crossDistance = line.position.isVertical ? drag.translation.width : drag.translation.height
        guard abs(distance) > abs(crossDistance) else { return 0 }
        let stride = line.position.noteStride
        if index == source {
            return max(-CGFloat(source) * stride, min(CGFloat(count - 1 - source) * stride, distance))
        }
        if source < target && index > source && index <= target { return -stride }
        if source > target && index >= target && index < source { return stride }
        return 0
    }

}
/// Inputs for a note's swing around its peg.
struct NoteMotion {
    var seed: UUID
    var live: Bool
    var gustAt: Date
    var push: Double
    var pushedAt: Date
}

private struct Swaying: ViewModifier {
    var motion: NoteMotion
    var calm: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            // Pause while the line is hidden off screen.
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !motion.live)) { context in
                content.modifier(NoteSwing(time: context.date.timeIntervalSinceReferenceDate, motion: motion, calm: calm))
            }
        }
    }
}

/// Idle sway, a gust when the line opens, and the swing that settles after a drag.
private struct NoteSwing: GeometryEffect {
    var time: TimeInterval
    var motion: NoteMotion
    var calm: Double
    var animatableData: Double {
        get { calm }
        set { calm = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let bytes = motion.seed.uuid
        let w = 2 * Double.pi / (3.4 + Double(bytes.1 % 8) * 0.2)
        let phase = Double(bytes.2) / 255 * 2 * .pi
        var degrees = calm * (0.9 * sin(w * time + phase) + 0.3 * sin(2.3 * w * time + phase * 1.7))
        let gust = time - motion.gustAt.timeIntervalSinceReferenceDate
        if gust > 0 { degrees += 3.2 * exp(-gust / 0.6) * sin(2 * .pi * gust) }
        // Hold the tilt between drag events; decay once the pointer stops.
        let settle = max(0, time - motion.pushedAt.timeIntervalSinceReferenceDate - 0.05)
        degrees += motion.push * exp(-settle / 0.35) * cos(2 * .pi * settle / 0.9)
        let pivot = size.width / 2
        return ProjectionTransform(CGAffineTransform(translationX: pivot, y: 0)
            .rotated(by: degrees * .pi / 180).translatedBy(x: -pivot, y: 0))
    }
}

struct HangingNote: View {
    let idea: Idea
    var copied: Bool
    var edit: () -> Void
    var copy: () -> Void
    var archive: () -> Void
    var motion: NoteMotion
    @State private var hover = false
    @State private var arrived = false
    var body: some View {
        VStack(spacing: -11) {
            RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [Color(red: 0.66, green: 0.42, blue: 0.23), Color(red: 0.88, green: 0.70, blue: 0.45), Color(red: 0.66, green: 0.42, blue: 0.23)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 11, height: 29).overlay(Rectangle().fill(.black.opacity(0.25)).frame(width: 9, height: 2)).shadow(radius: 1, y: 1).zIndex(2)
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
                    Text(copied ? "已复制 ✓" : "点击编辑")
                        .font(.system(size: AppTypeScale.caption))
                        .foregroundStyle(copied ? accent : inkSecondary)
                    Spacer()
                    Button(action: copy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: AppTypeScale.caption))
                            .foregroundStyle(inkSecondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("复制选题")

                    Button(action: archive) {
                        Image(systemName: "archivebox")
                            .font(.system(size: AppTypeScale.caption))
                            .foregroundStyle(inkSecondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("收纳选题，可在全部列表中找回")
                }
            }
            .padding(14)
            .frame(width: 184, height: 171)
            .background(noteColor(idea.color), in: RoundedRectangle(cornerRadius: radiusCard))
            .overlay(RoundedRectangle(cornerRadius: radiusCard).stroke(inkBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1) // 接触阴影
            .shadow(color: .black.opacity(hover ? 0.20 : 0.12), radius: hover ? 12 : 5, x: 0, y: hover ? 6 : 3) // 扩散环境光阴影
            .contentShape(Rectangle())
            .onTapGesture(perform: edit)
            .interactive()
            .contextMenu { Button("编辑", action: edit); Button("复制", action: copy); Button("收纳", action: archive) }
        }.foregroundStyle(ink).rotationEffect(.degrees(arrived ? (hover ? 0 : tilt) : -12), anchor: .top)
            .modifier(Swaying(motion: motion, calm: hover ? 0 : 1))
            .scaleEffect(hover ? 1.035 : 1, anchor: .top).onHover { hover = $0 }
            .animation(.spring(response: 0.5, dampingFraction: 0.45), value: hover)
            .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.36)) { arrived = true } }
    }
    private var tilt: Double { Double(idea.id.uuid.0 % 7) - 3 }
}

struct LibraryNoteCard: View {
    let idea: Idea
    var edit: () -> Void
    var toggleArchive: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(idea.createdAt, format: .dateTime.year().month().day())
                    .font(.system(size: AppTypeScale.caption, design: .monospaced))
                    .foregroundStyle(inkSecondary)
                Spacer()
                Button(action: toggleArchive) {
                    Text(idea.archived ? "恢复挂起" : "收纳")
                        .font(.system(size: AppTypeScale.caption, weight: .medium))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help(idea.archived ? "恢复挂起至顶部衣杆" : "收纳至归档")
            }

            Text(idea.text)
                .font(.system(size: AppTypeScale.body, design: .serif))
                .lineSpacing(5)
                .lineLimit(6)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)

            HStack {
                Text("点击编辑")
                    .font(.system(size: AppTypeScale.caption))
                    .foregroundStyle(inkSecondary)
                    .opacity(hover ? 1 : 0.6)
                Spacer()
                Image(systemName: "pencil")
                    .font(.system(size: AppTypeScale.caption))
                    .foregroundStyle(inkSecondary)
                    .opacity(hover ? 1 : 0)
            }
        }
        .padding(18)
        .background(noteColor(idea.color), in: RoundedRectangle(cornerRadius: radiusCard))
        .overlay(RoundedRectangle(cornerRadius: radiusCard).stroke(inkBorder, lineWidth: 1))
        .shadow(color: .black.opacity(hover ? 0.12 : 0.04), radius: hover ? 6 : 2, x: 0, y: hover ? 3 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
        .onHover { hover = $0 }
        .animation(.easeInOut(duration: 0.15), value: hover)
    }
}

struct LibraryView: View {
    @ObservedObject var store: IdeaStore
    var compose: () -> Void
    var edit: (Idea) -> Void
    var export: () -> Void
    @State private var query = ""
    @State private var archived = false
    private var ideas: [Idea] { store.state.ideas.filter { $0.archived == archived && (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query)) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("IDEA LINE  /  X")
                        .font(.system(size: AppTypeScale.caption, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(accent)
                    Text("灵感晾台")
                        .font(.system(size: AppTypeScale.display, weight: .medium, design: .serif))
                    Text(archived ? "已收纳选题列表与归档管理。" : "全部选题列表与归档管理。")
                        .font(.system(size: AppTypeScale.small))
                        .foregroundStyle(inkSecondary)
                }
                Spacer()
                Button(action: compose) {
                    Label("新建选题  \(AppShortcut.newIdea.label)", systemImage: "plus")
                        .font(.system(size: AppTypeScale.small, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(ink, in: RoundedRectangle(cornerRadius: radiusCard * 2))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: [.control, .option])
            }

            // Tabs & Search Bar
            HStack(spacing: 16) {
                Picker("分类", selection: $archived) {
                    Text("衣杆上 · \(store.active.count)").tag(false)
                    Text("已收纳 · \(store.state.ideas.count - store.active.count)").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 230)

                Spacer()

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: AppTypeScale.caption))
                        .foregroundStyle(inkSecondary)
                    TextField(archived ? "搜索已收纳…" : "搜索选题…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: AppTypeScale.small))
                        .frame(width: 150)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: AppTypeScale.caption))
                                .foregroundStyle(inkMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(inkBorder, lineWidth: 1))
            }

            // Card Grid or Empty State
            ScrollView {
                if ideas.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: query.isEmpty ? "wind" : "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(accent.opacity(0.7))
                        Text(query.isEmpty ? (archived ? "暂无已收纳选题" : "暂无挂起选题") : "未找到匹配选题")
                            .font(.system(size: AppTypeScale.subhead, weight: .medium, design: .serif))
                        Text(query.isEmpty ? (archived ? "在选题卡片上点击「收纳」可将选题移至此处。" : "按 \(AppShortcut.newIdea.label) 新建选题，按 ⌘↵ 保存至衣杆。") : "可更换关键词重新搜索。")
                            .font(.system(size: AppTypeScale.caption))
                            .foregroundStyle(inkSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                        ForEach(ideas) { idea in
                            LibraryNoteCard(idea: idea, edit: { edit(idea) }, toggleArchive: {
                                store.archive(idea.id, !idea.archived)
                            })
                        }
                    }
                    .padding(.vertical, 6)
                }
            }

            if let error = store.error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            // Footer
            HStack {
                Text("本地存储 · 自动保存")
                Spacer()
                Button("导出 Markdown", action: export).buttonStyle(.plain).foregroundStyle(accent)
            }
            .font(.system(size: AppTypeScale.caption))
            .foregroundStyle(inkSecondary)
        }
        .padding(32)
        .background(paper)
        .foregroundStyle(ink)
        .frame(minWidth: 680, minHeight: 520)
        .preferredColorScheme(.light)
    }
}
