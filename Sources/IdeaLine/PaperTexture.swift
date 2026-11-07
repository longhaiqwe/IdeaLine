import AppKit
import SwiftUI

/// Original Looseleaf PNG layers, tiled at their published CSS sizes in points.
/// Decode once. Fixed origins keep texture stable during interaction and resizing.
enum PaperStock { case paper, slip }

struct PaperTexture: View {
    var stock: PaperStock = .paper

    private static let resources: Bundle = {
        // build-app.sh copies the SwiftPM bundle into the installed app's Resources.
        if let url = Bundle.main.url(forResource: "IdeaLine_IdeaLine", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        // The standalone README renderer carries the same resource bundle beside it.
        if let executable = Bundle.main.executableURL,
           let bundle = Bundle(url: executable.deletingLastPathComponent().appendingPathComponent("IdeaLine_IdeaLine.bundle")) {
            return bundle
        }
        fatalError("Missing IdeaLine paper resource bundle")
        #endif
    }()

    struct Tile {
        let image: CGImage
        let size: CGFloat
    }

    static let tiles: [String: Tile] = {
        var result: [String: Tile] = [:]
        for (name, size) in [("cloud", 720.0), ("relief", 192.0), ("slip", 128.0), ("fibre", 240.0)] {
            guard let url = resources.url(forResource: name, withExtension: "png", subdirectory: "Paper"),
                  let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                assertionFailure("Missing paper texture: \(name)")
                continue
            }
            result[name] = Tile(image: image, size: size)
        }
        return result
    }()

    var body: some View {
        Canvas { context, size in
            // CSS background-image is front-to-back; Canvas draws back-to-front.
            for name in ["cloud", stock == .paper ? "relief" : "slip", "fibre"] {
                guard let tile = Self.tiles[name] else { continue }
                let image = Image(decorative: tile.image, scale: 1)
                for y in stride(from: 0.0, to: size.height, by: tile.size) {
                    for x in stride(from: 0.0, to: size.width, by: tile.size) {
                        context.draw(image, in: CGRect(x: x, y: y, width: tile.size, height: tile.size))
                    }
                }
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
