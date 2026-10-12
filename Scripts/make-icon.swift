// Draws the app icon and writes every size macOS needs into the asset catalog.
// Run from the repository root:  swift Scripts/make-icon.swift
import AppKit

let output = URL(fileURLWithPath: "Sources/Assets.xcassets/AppIcon.appiconset")

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

/// The icon is the deck itself, seen from above as it is on the desktop: the tile is its
/// body, with the platter, a record and the tonearm on it.
func draw(_ context: CGContext, size: CGFloat) {
    let unit = size / 1024
    context.scaleBy(x: unit, y: unit)

    func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    /// A turned metal disc: bright towards the light, top left, and directly away from it.
    func metal(_ center: CGPoint, _ radius: CGFloat) {
        let (light, mid, dark) = (rgb(0xF1F2F4), rgb(0xC8CBD0), rgb(0x8F939B))
        context.saveGState()
        context.addEllipse(in: circle(center, radius))
        context.clip()
        CGContextDrawConicGradient(context, gradient([mid, dark, mid, light, mid, dark, mid, light, mid]), center, 0)
        context.restoreGState()
    }

    // The rounded tile, with the margin and corner radius of a standard macOS icon.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.4))
    context.addPath(tilePath)
    context.setFillColor(rgb(0x1B1C1F))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    context.drawLinearGradient(gradient([rgb(0x303136), rgb(0x18191C)]), start: CGPoint(x: 0, y: tile.maxY),
                               end: CGPoint(x: 0, y: tile.minY), options: [])
    // A lit edge along the top.
    context.addPath(tilePath)
    context.setLineWidth(8)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.26), rgb(0xFFFFFF, 0)]), start: CGPoint(x: 0, y: tile.maxY),
                               end: CGPoint(x: 0, y: tile.midY), options: [])
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    // Platter, with strobe dots round its rim.
    let center = CGPoint(x: 476, y: 500)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 6, height: -12), blur: 26, color: CGColor(gray: 0, alpha: 0.6))
    context.setFillColor(rgb(0x8F939B))
    context.fillEllipse(in: circle(center, 330))
    context.restoreGState()
    metal(center, 330)
    context.setStrokeColor(rgb(0xFFFFFF, 0.7))
    context.setLineWidth(3)
    context.strokeEllipse(in: circle(center, 328))
    context.setFillColor(rgb(0x33363B, 0.9))
    for step in 0..<110 {
        let angle = CGFloat(step) / 110 * 2 * .pi
        context.fillEllipse(in: circle(CGPoint(x: center.x + 316 * cos(angle), y: center.y + 316 * sin(angle)), 3.2))
    }

    // Record.
    context.saveGState()
    context.setShadow(offset: CGSize(width: 4, height: -7), blur: 9, color: CGColor(gray: 0, alpha: 0.7))
    context.setFillColor(rgb(0x0B0B0D))
    context.fillEllipse(in: circle(center, 298))
    context.restoreGState()
    context.setFillColor(rgb(0x16161A))
    context.fillEllipse(in: circle(center, 288))
    context.setLineWidth(1.6)
    for radius in stride(from: CGFloat(124), to: 286, by: 6) {
        context.setStrokeColor(rgb(0xFFFFFF, Int(radius) % 4 == 0 ? 0.09 : 0.045))
        context.strokeEllipse(in: circle(center, radius))
    }
    context.setStrokeColor(rgb(0x070709))
    context.setLineWidth(5)
    for radius in [164, 206, 252] as [CGFloat] {
        context.strokeEllipse(in: circle(center, radius))
    }
    // Two wedges of reflected light.
    context.saveGState()
    context.addEllipse(in: circle(center, 296))
    context.addEllipse(in: circle(center, 112))
    context.clip(using: .evenOdd)
    let clear = rgb(0xFFFFFF, 0)
    CGContextDrawConicGradient(context, gradient(
        [clear, clear, rgb(0xFFFFFF, 0.3), clear, clear, rgb(0xFFFFFF, 0.17), clear, clear],
        [0, 0.29, 0.375, 0.46, 0.79, 0.875, 0.96, 1]), center, 0)
    context.restoreGState()

    // Label and spindle.
    context.setFillColor(rgb(0xE2512D))
    context.fillEllipse(in: circle(center, 108))
    context.setStrokeColor(rgb(0xEFE8DA, 0.85))
    context.setLineWidth(5)
    context.strokeEllipse(in: circle(center, 82))
    context.setStrokeColor(rgb(0x000000, 0.3))
    context.setLineWidth(3)
    context.strokeEllipse(in: circle(center, 107))
    metal(center, 15)

    // Tonearm base, top right.
    let pivot = CGPoint(x: 812, y: 800)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 4, height: -8), blur: 12, color: CGColor(gray: 0, alpha: 0.6))
    context.setFillColor(rgb(0x8F939B))
    context.fillEllipse(in: circle(pivot, 82))
    context.restoreGState()
    metal(pivot, 82)
    context.setFillColor(rgb(0x1C1D20))
    context.fillEllipse(in: circle(pivot, 64))

    // The arm: a tube with two bends, a counterweight behind the pivot and a cartridge in front.
    let stylus = CGPoint(x: 612, y: 392)
    let tube = CGMutablePath()
    tube.move(to: pivot)
    tube.addCurve(to: CGPoint(x: 668, y: 468), control1: CGPoint(x: 770, y: 660), control2: CGPoint(x: 742, y: 520))
    context.saveGState()
    context.setShadow(offset: CGSize(width: 8, height: -14), blur: 12, color: CGColor(gray: 0, alpha: 0.55))
    context.setLineCap(.round)
    context.addPath(tube)
    context.setStrokeColor(rgb(0x5B5F66))
    context.setLineWidth(27)
    context.strokePath()
    context.restoreGState()
    context.setLineCap(.round)
    for (color, width) in [(rgb(0xC8CBD0), CGFloat(22)), (rgb(0xF1F2F4), 8)] {
        context.addPath(tube)
        context.setStrokeColor(color)
        context.setLineWidth(width)
        context.strokePath()
    }
    // Counterweight.
    context.saveGState()
    context.translateBy(x: pivot.x, y: pivot.y)
    context.rotate(by: atan2(pivot.y - 660, pivot.x - 770) - .pi / 2)
    let weight = CGRect(x: -44, y: 34, width: 88, height: 86)
    context.addPath(CGPath(roundedRect: weight, cornerWidth: 10, cornerHeight: 10, transform: nil))
    context.clip()
    context.drawLinearGradient(gradient([rgb(0x5B5F66), rgb(0xC8CBD0), rgb(0xF1F2F4), rgb(0xC8CBD0), rgb(0x5B5F66)]),
                               start: CGPoint(x: weight.minX, y: 0), end: CGPoint(x: weight.maxX, y: 0), options: [])
    context.restoreGState()
    // Bearing over the pivot.
    context.setFillColor(rgb(0x26272B))
    context.fillEllipse(in: circle(pivot, 40))
    metal(pivot, 22)
    // Headshell and cartridge.
    context.saveGState()
    context.translateBy(x: stylus.x, y: stylus.y)
    context.rotate(by: atan2(stylus.y - 468, stylus.x - 668) + .pi / 2)
    context.setShadow(offset: CGSize(width: 6, height: -10), blur: 10, color: CGColor(gray: 0, alpha: 0.5))
    context.addPath(CGPath(roundedRect: CGRect(x: -27, y: -4, width: 54, height: 100), cornerWidth: 9, cornerHeight: 9,
                           transform: nil))
    context.setFillColor(rgb(0xE4E6E9))
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)
    context.addPath(CGPath(roundedRect: CGRect(x: -21, y: -30, width: 42, height: 52), cornerWidth: 7, cornerHeight: 7,
                           transform: nil))
    context.setFillColor(rgb(0xE5482F))
    context.fillPath()
    context.restoreGState()

    context.restoreGState()
}

func png(pixels: Int) -> Data {
    let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(context, size: CGFloat(pixels))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try png(pixels: points * scale).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.write(
    to: output.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(images.count) icons to \(output.path)")
