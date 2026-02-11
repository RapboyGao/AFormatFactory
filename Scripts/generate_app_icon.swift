import AppKit
import Foundation

let args = CommandLine.arguments
let outputDirectory = args.count > 1 ? args[1] : ".build/AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)

try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let iconSpecs: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.56, blue: 0.88, alpha: 1),
        NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.62, alpha: 1)
    ])!

    let radius = max(10, size * 0.22)
    let shape = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.03, dy: size * 0.03), xRadius: radius, yRadius: radius)
    gradient.draw(in: shape, angle: -90)

    let shine = NSBezierPath(roundedRect: NSRect(x: size * 0.09, y: size * 0.55, width: size * 0.82, height: size * 0.30), xRadius: radius * 0.6, yRadius: radius * 0.6)
    NSColor(calibratedWhite: 1.0, alpha: 0.16).setFill()
    shine.fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let fontSize = size * 0.33
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
        .kern: fontSize * 0.02
    ]

    let text = NSAttributedString(string: "AF", attributes: attrs)
    let textRect = NSRect(x: 0, y: size * 0.31, width: size, height: fontSize * 1.2)
    text.draw(in: textRect)

    image.unlockFocus()
    return image
}

for (filename, size) in iconSpecs {
    let icon = drawIcon(size: size)
    guard
        let tiffData = icon.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiffData),
        let pngData = rep.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to render \(filename)"])
    }

    let fileURL = outputURL.appendingPathComponent(filename)
    try pngData.write(to: fileURL)
}

print("Iconset generated at \(outputURL.path)")
