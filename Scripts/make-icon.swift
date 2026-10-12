// Draws the app icon and writes every size macOS needs into the asset catalog.
// Run from the repository root:  swift Scripts/make-icon.swift
import AppKit

let output = URL(fileURLWithPath: "Sources/Assets.xcassets/AppIcon.appiconset")

func draw(_ context: CGContext, size: CGFloat) {
    let unit = size / 1024
    context.scaleBy(x: unit, y: unit)

    // The rounded tile, with the margin and corner radius of a standard macOS icon.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(tilePath)
    context.setFillColor(CGColor(red: 0.93, green: 0.88, blue: 0.79, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let wood = [CGColor(red: 0.96, green: 0.92, blue: 0.84, alpha: 1),
                CGColor(red: 0.84, green: 0.72, blue: 0.56, alpha: 1)] as CFArray
    context.drawLinearGradient(CGGradient(colorsSpace: nil, colors: wood, locations: [0, 1])!,
                               start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

    // Record
    let center = CGPoint(x: 470, y: 500)
    func circle(_ radius: CGFloat) -> CGRect {
        CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: CGColor(gray: 0, alpha: 0.45))
    context.setFillColor(CGColor(gray: 0.07, alpha: 1))
    context.fillEllipse(in: circle(310))
    context.restoreGState()
    context.setLineWidth(2)
    for radius in stride(from: CGFloat(130), to: 300, by: 9) {
        context.setStrokeColor(CGColor(gray: 1, alpha: Int(radius) % 4 == 0 ? 0.10 : 0.05))
        context.strokeEllipse(in: circle(radius))
    }
    // Sheen
    for (angle, strength) in [(CGFloat(2.1), CGFloat(0.16)), (5.25, 0.10)] {
        for step in -20...20 {
            let a = angle + CGFloat(step) * 0.012
            let wedge = CGMutablePath()
            wedge.move(to: center)
            wedge.addArc(center: center, radius: 304, startAngle: a, endAngle: a + 0.014, clockwise: false)
            wedge.closeSubpath()
            context.addPath(wedge)
            context.setFillColor(CGColor(gray: 1, alpha: strength * (1 - abs(CGFloat(step)) / 20)))
            context.fillPath()
        }
    }
    context.setFillColor(CGColor(red: 0.87, green: 0.42, blue: 0.19, alpha: 1))
    context.fillEllipse(in: circle(112))
    context.setStrokeColor(CGColor(gray: 1, alpha: 0.75))
    context.setLineWidth(6)
    context.strokeEllipse(in: circle(82))
    context.setFillColor(CGColor(gray: 0.92, alpha: 1))
    context.fillEllipse(in: circle(15))

    // Tonearm
    let pivot = CGPoint(x: 800, y: 790)
    let stylus = CGPoint(x: 640, y: 380)
    context.setShadow(offset: CGSize(width: -8, height: -12), blur: 14, color: CGColor(gray: 0, alpha: 0.4))
    context.setLineCap(.round)
    context.setStrokeColor(CGColor(gray: 0.80, alpha: 1))
    context.setLineWidth(22)
    context.move(to: pivot)
    context.addLine(to: stylus)
    context.strokePath()
    context.setFillColor(CGColor(gray: 0.15, alpha: 1))
    context.fillEllipse(in: CGRect(x: pivot.x - 52, y: pivot.y - 52, width: 104, height: 104))
    context.translateBy(x: stylus.x, y: stylus.y)
    context.rotate(by: atan2(stylus.y - pivot.y, stylus.x - pivot.x) + .pi / 2)
    context.fill(CGRect(x: -30, y: -50, width: 60, height: 100))
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
