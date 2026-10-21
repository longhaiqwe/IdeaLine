import AppKit
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
NSColor(red: 0.95, green: 0.94, blue: 0.89, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 20, y: 20, width: 984, height: 984), xRadius: 220, yRadius: 220).fill()
let rope = NSBezierPath(); rope.move(to: NSPoint(x: 60, y: 770)); rope.curve(to: NSPoint(x: 964, y: 770), controlPoint1: NSPoint(x: 300, y: 655), controlPoint2: NSPoint(x: 720, y: 655)); rope.lineWidth = 7
NSColor(red: 0.44, green: 0.42, blue: 0.32, alpha: 1).setStroke(); rope.stroke()
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.18); shadow.shadowBlurRadius = 28; shadow.shadowOffset = NSSize(width: 2, height: -16); shadow.set()
NSColor(red: 1, green: 0.89, blue: 0.59, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 253, y: 212, width: 518, height: 482), xRadius: 16, yRadius: 16).fill()
NSGraphicsContext.restoreGraphicsState()
NSColor(red: 0.71, green: 0.43, blue: 0.23, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 489, y: 639, width: 46, height: 117), xRadius: 11, yRadius: 11).fill()
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 166, weight: .light), .foregroundColor: NSColor(red: 0.25, green: 0.28, blue: 0.23, alpha: 1)]
("X" as NSString).draw(at: NSPoint(x: 334, y: 393), withAttributes: attributes)
NSColor(red: 0.65, green: 0.57, blue: 0.35, alpha: 0.5).setStroke()
for y in [322, 282] { let p = NSBezierPath(); p.move(to: NSPoint(x: 338, y: y)); p.line(to: NSPoint(x: 683, y: y)); p.lineWidth = 5; p.stroke() }
image.unlockFocus()
let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
