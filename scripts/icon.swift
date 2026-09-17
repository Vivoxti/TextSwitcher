import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let s = CGFloat(pixels)
        let rect = NSRect(x: s * 0.07, y: s * 0.07, width: s * 0.86, height: s * 0.86)
        let background = NSBezierPath(roundedRect: rect, xRadius: s * 0.20, yRadius: s * 0.20)
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.30, green: 0.43, blue: 0.95, alpha: 1), ending: NSColor(calibratedRed: 0.35, green: 0.28, blue: 0.78, alpha: 1))!
        gradient.draw(in: background, angle: -90)
        let text = "Aя" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s * 0.35, weight: .medium), .foregroundColor: NSColor.white]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (s - textSize.width) / 2, y: s * 0.38), withAttributes: attributes)
        let arrows = "⇄" as NSString
        let arrowAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: s * 0.26, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.9)]
        let arrowSize = arrows.size(withAttributes: arrowAttributes)
        arrows.draw(at: NSPoint(x: (s - arrowSize.width) / 2, y: s * 0.17), withAttributes: arrowAttributes)
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let png = bitmap.representation(using: .png, properties: [:])!
        let suffix = scale == 2 ? "@2x" : ""
        try png.write(to: URL(fileURLWithPath: "\(directory)/icon_\(size)x\(size)\(suffix).png"))
    }
}
