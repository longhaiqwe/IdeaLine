import SwiftUI

/// Presentation preferences are independent of the user's notes and drafts.
enum PaperStyle: String, CaseIterable {
    case classic, looseleaf
    static let defaultsKey = "paperStyle"
    var title: String { self == .classic ? "经典纸张" : "手绘纸张" }
    static func saved(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .classic
    }
    var canvas: Color { self == .classic ? paper : NotebookPalette.sheet }
    var sage: Color { self == .classic ? Color(red: 0.62, green: 0.72, blue: 0.68) : NotebookPalette.desk }
    var foreground: Color { self == .classic ? ink : NotebookPalette.ink }
    var secondaryInk: Color { self == .classic ? inkSecondary : NotebookPalette.inkMuted }
    var mutedInk: Color { self == .classic ? inkMuted : NotebookPalette.inkMuted }
    var borderInk: Color { self == .classic ? inkBorder : NotebookPalette.ink.opacity(0.10) }
    var toolbar: Color { self == .classic ? paper : NotebookPalette.slip }
    func note(_ index: Int) -> Color {
        guard self == .looseleaf else { return noteColor(index) }
        // Index 0 is the existing default. Keep the stored model and classic colors intact.
        // Green/blue/pink: official Notebook colors lightened to 200 (--cap 0 --strength 0).
        let colors = [NotebookPalette.sheet,
                      Color(red: 236 / 255.0, green: 245 / 255.0, blue: 221 / 255.0),
                      Color(red: 226 / 255.0, green: 238 / 255.0, blue: 248 / 255.0),
                      Color(red: 251 / 255.0, green: 225 / 255.0, blue: 222 / 255.0)]
        return colors[max(0, min(index, colors.count - 1))]
    }

}

/// Looseleaf Notebook palette, shared with the clothesline-ui skill.
enum NotebookPalette {
    static let sheet = Color(red: 248 / 255.0, green: 245 / 255.0, blue: 238 / 255.0)
    static let desk = Color(red: 168 / 255.0, green: 200 / 255.0, blue: 187 / 255.0)
    static let slip = Color(red: 251 / 255.0, green: 248 / 255.0, blue: 241 / 255.0)
    static let ink = Color(red: 42 / 255.0, green: 36 / 255.0, blue: 32 / 255.0)
    static let inkMuted = Color(red: 74 / 255.0, green: 67 / 255.0, blue: 60 / 255.0)
    static let shadow = Color(red: 58 / 255.0, green: 44 / 255.0, blue: 30 / 255.0)
    static let marker = Color(red: 223 / 255.0, green: 107 / 255.0, blue: 60 / 255.0)
}

final class AppearanceState: ObservableObject {
    private let defaults: UserDefaults
    @Published var style: PaperStyle {
        didSet { defaults.set(style.rawValue, forKey: PaperStyle.defaultsKey) }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        style = .saved(in: defaults)
    }
}

private struct PaperStyleKey: EnvironmentKey {
    static let defaultValue = PaperStyle.classic
}
extension EnvironmentValues {
    var paperStyle: PaperStyle {
        get { self[PaperStyleKey.self] }
        set { self[PaperStyleKey.self] = newValue }
    }
}

/// Update the environment without replacing the editor or resetting its draft.
struct StyledRoot<Content: View>: View {
    @ObservedObject var appearance: AppearanceState
    let content: Content
    init(appearance: AppearanceState, @ViewBuilder content: () -> Content) {
        self.appearance = appearance
        self.content = content()
    }
    var body: some View { content.environment(\.paperStyle, appearance.style) }
}

/// Fixed curves keep outlines stable during text entry, layout and animation.
struct DrawnPaper: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 2, dy: 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 7, y: r.minY + 1))
        p.addCurve(to: CGPoint(x: r.maxX - 6, y: r.minY), control1: CGPoint(x: r.width * 0.34, y: r.minY - 1), control2: CGPoint(x: r.width * 0.7, y: r.minY + 3))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 7), control: CGPoint(x: r.maxX + 1, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX - 1, y: r.maxY - 6), control1: CGPoint(x: r.maxX - 2, y: r.height * 0.35), control2: CGPoint(x: r.maxX + 1, y: r.height * 0.7))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 7, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY + 1))
        p.addCurve(to: CGPoint(x: r.minX + 6, y: r.maxY - 1), control1: CGPoint(x: r.width * 0.67, y: r.maxY - 2), control2: CGPoint(x: r.width * 0.3, y: r.maxY + 1))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - 7), control: CGPoint(x: r.minX - 1, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX + 1, y: r.minY + 7), control1: CGPoint(x: r.minX + 2, y: r.height * 0.68), control2: CGPoint(x: r.minX - 1, y: r.height * 0.3))
        p.addQuadCurve(to: CGPoint(x: r.minX + 7, y: r.minY + 1), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}

struct PaperSurface: ViewModifier {
    @Environment(\.paperStyle) private var style
    var fill: Color
    var radius: CGFloat = radiusCard
    var raised = true
    var stock: PaperStock = .paper
    func body(content: Content) -> some View {
        content.background {
            if style == .looseleaf {
                ZStack {
                    if raised { DrawnPaper().fill(NotebookPalette.shadow).offset(x: 3, y: 4) }
                    DrawnPaper().fill(fill)
                    PaperTexture(stock: stock).clipShape(DrawnPaper())
                    DrawnPaper().stroke(NotebookPalette.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            } else {
                RoundedRectangle(cornerRadius: radius).fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: radius).stroke(inkBorder, lineWidth: 1))
            }
        }
    }
}

extension View {
    func paperSurface(_ fill: Color, radius: CGFloat = radiusCard, raised: Bool = true, stock: PaperStock = .paper) -> some View {
        modifier(PaperSurface(fill: fill, radius: radius, raised: raised, stock: stock))
    }
}
