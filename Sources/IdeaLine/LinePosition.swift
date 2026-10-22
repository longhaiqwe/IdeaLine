import AppKit

/// Screen geometry uses AppKit coordinates; view offsets use SwiftUI coordinates.
enum LinePosition: String, CaseIterable {
    case top, bottom, left, right

    static let defaultsKey = "linePosition"
    var title: String {
        switch self {
        case .top: return "上方"
        case .bottom: return "下方"
        case .left: return "左侧"
        case .right: return "右侧"
        }
    }
    var isVertical: Bool { self == .left || self == .right }
    var noteStride: CGFloat { isVertical ? 213 : 208 }

    static func saved(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? .top
    }

    func panelFrame(in frame: CGRect) -> CGRect {
        let depth = min(286, isVertical ? frame.width : frame.height)
        switch self {
        case .top: return CGRect(x: frame.minX, y: frame.maxY - depth, width: frame.width, height: depth)
        case .bottom: return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: depth)
        case .left: return CGRect(x: frame.minX, y: frame.minY, width: depth, height: frame.height)
        case .right: return CGRect(x: frame.maxX - depth, y: frame.minY, width: depth, height: frame.height)
        }
    }

    func capacity(in frame: CGRect) -> Int {
        max(1, Int(((isVertical ? frame.height : frame.width) - (isVertical ? 140 : 70)) / noteStride))
    }

    func isAtEdge(_ point: CGPoint, of screen: CGRect) -> Bool {
        guard point.x >= screen.minX, point.x <= screen.maxX,
              point.y >= screen.minY, point.y <= screen.maxY else { return false }
        switch self {
        case .top: return point.y >= screen.maxY - 3
        case .bottom: return point.y <= screen.minY + 3
        case .left: return point.x <= screen.minX + 3
        case .right: return point.x >= screen.maxX - 3
        }
    }

    /// Include the gap occupied by a menu bar or Dock, so crossing it does not dismiss the panel.
    func interactionZone(panel: CGRect, screen: CGRect) -> CGRect {
        switch self {
        case .top: return CGRect(x: panel.minX, y: panel.minY, width: panel.width, height: screen.maxY - panel.minY)
        case .bottom: return CGRect(x: panel.minX, y: screen.minY, width: panel.width, height: panel.maxY - screen.minY)
        case .left: return CGRect(x: screen.minX, y: panel.minY, width: panel.maxX - screen.minX, height: panel.height)
        case .right: return CGRect(x: panel.minX, y: panel.minY, width: screen.maxX - panel.minX, height: panel.height)
        }
    }

    var hiddenOffset: CGSize {
        switch self {
        case .top: return CGSize(width: 0, height: -310)
        case .bottom: return CGSize(width: 0, height: 310)
        case .left: return CGSize(width: -310, height: 0)
        case .right: return CGSize(width: 310, height: 0)
        }
    }
}
