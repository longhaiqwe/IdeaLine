import SwiftUI

/// Presentation preferences are independent of the user's notes and drafts.
enum PaperStyle: String, CaseIterable {
    case classic, looseleaf
    static let defaultsKey = "paperStyle"
    var title: String { self == .classic ? "经典纸张" : "手绘纸张" }
    static func saved(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .classic
    }
    var canvas: Color { self == .classic ? paper : Color(red: 0.97, green: 0.95, blue: 0.89) }
    var sage: Color { Color(red: 0.62, green: 0.72, blue: 0.68) }
    func note(_ index: Int) -> Color {
        guard self == .looseleaf else { return noteColor(index) }
        let colors = [Color(red: 0.96, green: 0.86, blue: 0.58),
                      Color(red: 0.76, green: 0.84, blue: 0.72),
                      Color(red: 0.75, green: 0.84, blue: 0.88),
                      Color(red: 0.93, green: 0.75, blue: 0.67)]
        return colors[max(0, min(index, colors.count - 1))]
    }
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
    func body(content: Content) -> some View {
        content.background {
            if style == .looseleaf {
                ZStack {
                    if raised { DrawnPaper().fill(ink).offset(x: 3, y: 4) }
                    DrawnPaper().fill(fill)
                    DrawnPaper().stroke(ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                }
            } else {
                RoundedRectangle(cornerRadius: radius).fill(fill)
                    .overlay(RoundedRectangle(cornerRadius: radius).stroke(inkBorder, lineWidth: 1))
            }
        }
    }
}

extension View {
    func paperSurface(_ fill: Color, radius: CGFloat = radiusCard, raised: Bool = true) -> some View {
        modifier(PaperSurface(fill: fill, radius: radius, raised: raised))
    }
}
