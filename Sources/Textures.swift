import AppKit
import CoreImage

/// Textures that are drawn in code at launch rather than shipped as image files.
enum Textures {
    /// A photo-scanned texture or lighting image bundled with the app (see README for credits).
    static func file(_ name: String, _ ext: String = "jpg") -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
    }

    /// Sunlight through window blinds, projected by the key light.
    static let blinds = render(1024, 1024, blur: 4) { context, bounds in
        context.setFillColor(gray: 0.38, alpha: 1)
        context.fill(bounds)
        context.setFillColor(gray: 1, alpha: 1)
        for slat in 0..<26 {
            context.fill(CGRect(x: 0, y: 6 + CGFloat(slat) * 40, width: 1024, height: 27))
        }
        context.setFillColor(gray: 0.38, alpha: 1)
        context.fill(CGRect(x: 380, y: 0, width: 18, height: 1024))
        context.fill(CGRect(x: 760, y: 0, width: 18, height: 1024))
    }

    static let grooves = render(1024, 1024) { context, bounds in
        var random = Random(seed: 11)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = bounds.width / 2
        context.setFillColor(gray: 0.025, alpha: 1)
        context.fillEllipse(in: bounds)
        context.setLineWidth(1)
        for r in stride(from: radius * 0.37, to: radius * 0.965, by: 2) {
            context.setStrokeColor(gray: 1, alpha: random.next(0.015...0.07))
            context.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        // The smooth gaps between tracks.
        context.setLineWidth(5)
        for gap in [0.50, 0.61, 0.70, 0.81, 0.90] {
            let r = radius * gap
            context.setStrokeColor(gray: 0.01, alpha: 1)
            context.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
    }

    /// Roughness for the record: grooved bands scatter light, the gaps between tracks are mirror-smooth.
    static let grooveRoughness = render(1024, 1024) { context, bounds in
        var random = Random(seed: 5)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = bounds.width / 2
        context.setFillColor(gray: 0.14, alpha: 1)
        context.fill(bounds)
        context.setLineWidth(2.5)
        for r in stride(from: radius * 0.37, to: radius * 0.965, by: 2) {
            context.setStrokeColor(gray: random.next(0.36...0.5), alpha: 1)
            context.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        context.setLineWidth(5)
        context.setStrokeColor(gray: 0.1, alpha: 1)
        for gap in [0.50, 0.61, 0.70, 0.81, 0.90] {
            let r = radius * gap
            context.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
    }

    /// Two fixed highlight wedges, laid over the spinning record the way light sits on real vinyl.
    static let sheen = render(1024, 1024, blur: 3) { context, bounds in
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = bounds.width / 2
        let wedges: [(angle: CGFloat, width: CGFloat, strength: CGFloat)] = [(118, 12, 0.20), (298, 9, 0.11)]
        for step in 0..<720 {
            let degrees = CGFloat(step) / 2
            let alpha = wedges.reduce(CGFloat(0)) { sum, wedge in
                let distance = abs((degrees - wedge.angle + 540).truncatingRemainder(dividingBy: 360) - 180)
                return sum + wedge.strength * exp(-pow(distance / wedge.width, 2))
            }
            guard alpha > 0.004 else { continue }
            let start = degrees * .pi / 180
            let end = (degrees + 0.6) * .pi / 180
            let slice = CGMutablePath()
            slice.addArc(center: center, radius: radius * 0.96, startAngle: start, endAngle: end, clockwise: false)
            slice.addArc(center: center, radius: radius * 0.37, startAngle: end, endAngle: start, clockwise: true)
            slice.closeSubpath()
            context.addPath(slice)
            context.setFillColor(gray: 1, alpha: alpha)
            context.fillPath()
        }
    }

    static let defaultLabel = render(512, 512) { context, bounds in
        context.setFillColor(red: 0.85, green: 0.42, blue: 0.20, alpha: 1)
        context.fill(bounds)
        context.setStrokeColor(gray: 1, alpha: 0.75)
        context.setLineWidth(5)
        context.strokeEllipse(in: bounds.insetBy(dx: 60, dy: 60))
        text("SPINDLE", size: 40, weight: .bold, in: CGRect(x: 0, y: 330, width: 512, height: 60), context: context)
        text("33⅓ RPM", size: 24, weight: .medium, in: CGRect(x: 0, y: 130, width: 512, height: 40), context: context)
    }

    static let defaultSleeve = render(1024, 1024) { context, bounds in
        let colors = [CGColor(red: 0.13, green: 0.28, blue: 0.34, alpha: 1),
                      CGColor(red: 0.86, green: 0.45, blue: 0.24, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bounds.maxY),
                                   end: CGPoint(x: bounds.maxX, y: 0), options: [])
        text("Spindle", size: 170, weight: .semibold, serif: true,
             in: CGRect(x: 0, y: 480, width: 1024, height: 220), context: context)
        text("Play a track in Spotify, Spotifast or Apple Music", size: 36, weight: .medium,
             in: CGRect(x: 0, y: 380, width: 1024, height: 60), context: context)
    }

    private static func text(_ string: String, size: CGFloat, weight: NSFont.Weight, serif: Bool = false,
                             in rect: CGRect, context: CGContext) {
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if serif, let descriptor = font.fontDescriptor.withDesign(.serif) {
            font = NSFont(descriptor: descriptor, size: size) ?? font
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSAttributedString(string: string, attributes: [
            .font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph, .kern: size * 0.04,
        ]).draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func render(_ width: Int, _ height: Int, blur: CGFloat = 0,
                               _ draw: (CGContext, CGRect) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        draw(context, bounds)
        let image = context.makeImage()!
        guard blur > 0 else { return image }
        let blurred = CIImage(cgImage: image).clampedToExtent().applyingGaussianBlur(sigma: blur).cropped(to: bounds)
        return CIContext().createCGImage(blurred, from: bounds) ?? image
    }

    /// Seeded so the grain looks the same on every launch.
    private struct Random {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) % 100_000) / 100_000
        }

        mutating func next(_ range: ClosedRange<CGFloat>) -> CGFloat {
            range.lowerBound + next() * (range.upperBound - range.lowerBound)
        }
    }
}
