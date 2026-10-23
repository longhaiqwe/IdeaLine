// Render the cover text layer (1920 x 1080, transparent) using the app's colour tokens.
// Usage: cover-text <icon.png> <out.png>
import AppKit
import SwiftUI

private struct Chip: View {
    let keys: String?
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            if let keys {
                Text(keys).font(.system(size: 15, weight: .semibold, design: .monospaced)).tracking(1)
            }
            Text(text).font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Color.white.opacity(0.86), in: Capsule())
        .overlay(Capsule().stroke(inkBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

private struct Cover: View {
    let icon: NSImage
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack(alignment: .center, spacing: 24) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 92, height: 92)
                    .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
                VStack(alignment: .leading, spacing: 6) {
                    Text("IDEA LINE")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced)).tracking(6)
                        .foregroundStyle(accent)
                    Text("灵感晾台")
                        .font(.custom("Songti SC", size: 72).weight(.semibold))
                        .foregroundStyle(ink)
                }
            }
            Text("把灵感，先晾起来。")
                .font(.custom("Songti SC", size: 30).weight(.medium))
                .foregroundStyle(inkSecondary)
                .padding(.top, 16)
            HStack(spacing: 10) {
                Chip(keys: "⌃⌥N", text: "随手记录")
                Chip(keys: "⌘↵", text: "挂上衣杆")
                Chip(keys: nil, text: "macOS 14+")
            }
            .padding(.top, 24)
        }
        .padding(.leading, 64)
        .padding(.bottom, 52)
        .frame(width: 960, height: 540, alignment: .bottomLeading)
        .shadow(color: Color(red: 0.98, green: 0.97, blue: 0.94).opacity(0.7), radius: 14)
    }
}

@main
struct CoverText {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let args = CommandLine.arguments
        guard let icon = NSImage(contentsOfFile: args[1]) else { throw CocoaError(.fileReadNoSuchFile) }
        let renderer = ImageRenderer(content: Cover(icon: icon).environment(\.colorScheme, .light))
        renderer.scale = 2
        renderer.isOpaque = false
        renderer.proposedSize = ProposedViewSize(width: 960, height: 540)
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: args[2]))
        print("Rendered \(args[2])")
    }
}
