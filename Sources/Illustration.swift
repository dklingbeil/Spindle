import AppKit
import CoreImage
import CoreText

/// A drawing rendered to a bitmap, with the rectangle it covers in the space it was drawn in.
struct Sprite {
    let image: CGImage
    let frame: CGRect

    /// `draw` works in millimetres with y running down, whatever the resolution.
    init(_ frame: CGRect, pixelsPerMM: CGFloat, blur: CGFloat = 0, draw: (CGContext) -> Void) {
        let width = max(Int((frame.width * pixelsPerMM).rounded(.up)), 1)
        let height = max(Int((frame.height * pixelsPerMM).rounded(.up)), 1)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: pixelsPerMM, y: -pixelsPerMM)
        context.translateBy(x: -frame.minX, y: -frame.minY)
        draw(context)
        var image = context.makeImage()!
        if blur > 0 {
            let bounds = CGRect(x: 0, y: 0, width: width, height: height)
            let blurred = CIImage(cgImage: image).applyingGaussianBlur(sigma: blur * pixelsPerMM).cropped(to: bounds)
            image = Self.filters.createCGImage(blurred, from: bounds) ?? image
        }
        self.image = image
        self.frame = frame
    }

    private static let filters = CIContext()
}

/// The artwork: every piece of the desk, drawn flat as seen from above with light from the top left.
enum Illustration {
    // MARK: Colours

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func white(_ alpha: CGFloat) -> CGColor { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: alpha) }
    private static func black(_ alpha: CGFloat) -> CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha) }

    private static let body = (top: rgb(0x2A2B30), bottom: rgb(0x1B1C1F))
    private static let underside = rgb(0x09090B)
    private static let recess = rgb(0x101113)
    private static let key = (top: rgb(0x3B3D43), bottom: rgb(0x2B2C31))
    private static let silver = (light: rgb(0xF1F2F4), mid: rgb(0xC8CBD0), dark: rgb(0x8F939B), deep: rgb(0x5B5F66))
    private static let lettering = rgb(0xA4A7AD)
    private static let lamp = rgb(0xFF4B3A)
    private static let cartridge = rgb(0xE5482F)
    private static let vinyl = rgb(0x0B0B0D)
    private static let cream = rgb(0xEFE8DA)
    private static let vermilion = rgb(0xE2512D)
    private static let navy = rgb(0x1E3350)
    /// After dark everything is dimmed and cooled; only the lamps keep their colour.
    private static let dusk = rgb(0x0A0E1C, 0.34)

    // MARK: Deck

    /// The body, platter and controls: everything on the deck that never moves.
    static func deck(night: Bool, pixelsPerMM: CGFloat) -> Sprite {
        Sprite(Plan.deck.insetBy(dx: -80, dy: -80), pixelsPerMM: pixelsPerMM) { g in
            let shape = CGPath(roundedRect: Plan.deck, cornerWidth: 15, cornerHeight: 15, transform: nil)
            // On the desk: a wide soft shadow from the room, and a tight one where the deck stands.
            g.shadowed(dx: 13, dy: 21, blur: 44, alpha: 0.34) { g.fill(shape, underside) }
            g.shadowed(dx: 3, dy: 5, blur: 9, alpha: 0.42) { g.fill(shape, underside) }
            var lip = CGAffineTransform(translationX: 0, y: 2.4)
            g.fill(shape.copy(using: &lip) ?? shape, underside)
            g.gradient(shape, [body.top, body.bottom], from: CGPoint(x: 0, y: Plan.deck.minY),
                       to: CGPoint(x: 0, y: Plan.deck.maxY))
            g.grain(in: shape, alpha: 0.42)
            g.rim(shape, width: 1.1, [white(0.2), white(0.03)], from: Plan.deck.origin,
                  to: CGPoint(x: Plan.deck.maxX, y: Plan.deck.maxY))

            // Where the dust cover's hinges plug in, along the back edge.
            for x in [-128, 122] as [CGFloat] {
                let slot = CGPath(roundedRect: CGRect(x: x, y: Plan.deck.minY + 4.2, width: 30, height: 5.4), cornerWidth: 2,
                                  cornerHeight: 2, transform: nil)
                g.fill(slot, recess)
                g.rim(slot, width: 0.5, [black(0.7), white(0.14)], from: CGPoint(x: 0, y: Plan.deck.minY + 4.2),
                      to: CGPoint(x: 0, y: Plan.deck.minY + 9.6))
            }
            drawPlatter(g)
            drawLeftControls(g)
            drawArmBase(g)
            drawFaderPanel(g)

            g.text("SPINDLE", at: CGPoint(x: 100, y: 171), size: 8.2, weight: .heavy, color: lettering, tracking: 1.5)
            g.text("DIRECT DRIVE", at: CGPoint(x: 100, y: 176.3), size: 2.7, weight: .semibold,
                   color: lettering.copy(alpha: 0.7)!, tracking: 0.95)
            if night { g.dim(dusk) }
        }
    }

    private static func drawPlatter(_ g: CGContext) {
        let center = Plan.platter
        let radius = Plan.platterRadius
        g.fillCircle(center, radius + 3.2, recess)
        g.strokeCircle(center, radius + 3.2, white(0.07), width: 0.5)
        g.shadowed(dx: 2.5, dy: 4, blur: 6, alpha: 0.6) { g.fillCircle(center, radius, silver.dark) }
        g.metal(center, radius)
        g.strokeCircle(center, radius - 0.5, white(0.7), width: 1)
        g.strokeCircle(center, radius - 3.1, black(0.16), width: 0.4)
        g.strokeCircle(center, radius - 9.6, black(0.2), width: 0.5)
        g.fillCircle(center, radius - 10, rgb(0x121214))
        // The record lies on top, in a layer of its own that turns; its shadow stays here.
        g.shadowed(dx: 1.5, dy: 2.6, blur: 3.2, alpha: 0.7) { g.fillCircle(center, Plan.recordRadius, vinyl) }
    }

    private static func drawLeftControls(_ g: CGContext) {
        // A holder for the 45 rpm adapter, top left.
        let adapter = CGPoint(x: -198, y: -151)
        g.fillCircle(adapter, 21, recess)
        g.shadowed(dx: 1, dy: 1.6, blur: 2.5, alpha: 0.6) { g.fillCircle(adapter, 19, silver.dark) }
        g.metal(adapter, 19)
        g.strokeCircle(adapter, 18.6, white(0.6), width: 0.7)
        g.strokeCircle(adapter, 10, black(0.22), width: 0.5)
        g.fillCircle(adapter, 9.6, silver.mid.copy(alpha: 0.5)!)
        g.fillCircle(adapter, 3.8, recess)

        // The strobe: a lamp that lights the dots on the platter's rim.
        let strobe = CGPoint(x: -207, y: 107)
        g.shadowed(dx: 1.2, dy: 2, blur: 3, alpha: 0.6) { g.fillCircle(strobe, 14.5, silver.dark) }
        g.metal(strobe, 14.5)
        g.strokeCircle(strobe, 14.1, white(0.6), width: 0.7)
        g.fillCircle(strobe, 9.8, rgb(0x232428))
        g.strokeCircle(strobe, 9.8, black(0.5), width: 0.5)
        g.stroke(line(CGPoint(x: strobe.x, y: strobe.y - 8.4), CGPoint(x: strobe.x, y: strobe.y - 3)),
                 silver.light, width: 1.1, cap: .round)
        g.fillCircle(strobeLamp, 2.5, lamp)
        g.fillCircle(CGPoint(x: strobeLamp.x - 0.6, y: strobeLamp.y - 0.7), 0.9, white(0.75))

        button(g, Plan.startButton, corner: 3.2)
        g.text("START · STOP", at: CGPoint(x: Plan.startButton.midX, y: Plan.startButton.midY + 1.1), size: 3.1,
               weight: .semibold, color: lettering, tracking: 0.5, align: .center)

        for (index, speed) in ["33", "45"].enumerated() {
            let face = CGRect(x: -161 + CGFloat(index) * 26, y: 157, width: 22, height: 12)
            button(g, face, corner: 2.2)
            g.text(speed, at: CGPoint(x: face.midX + 2.2, y: face.midY + 1.5), size: 4.2, weight: .semibold,
                   color: lettering, align: .center)
            let light = CGPoint(x: face.minX + 4.2, y: face.midY)
            g.fillCircle(light, 1.25, index == 0 ? lamp : rgb(0x4A1612))
            if index == 0 { g.glow(light, radius: 4.5, lamp.copy(alpha: 0.5)!) }
        }

        // A pop-up lamp that shows where the stylus will land.
        let target = CGPoint(x: 80, y: 153)
        g.shadowed(dx: 1.2, dy: 2, blur: 3, alpha: 0.6) { g.fillCircle(target, 7.6, silver.dark) }
        g.metal(target, 7.6)
        g.strokeCircle(target, 7.2, white(0.6), width: 0.6)
        g.fillCircle(target, 4.2, rgb(0x232428))
        g.fillCircle(CGPoint(x: target.x - 1.6, y: target.y - 2.2), 1.2, rgb(0xFFE9C4))
    }

    private static let strobeLamp = CGPoint(x: -196.2, y: 99.4)

    private static func button(_ g: CGContext, _ rect: CGRect, corner: CGFloat) {
        g.fill(CGPath(roundedRect: rect.insetBy(dx: -1.3, dy: -1.3), cornerWidth: corner + 1.3, cornerHeight: corner + 1.3,
                      transform: nil), recess)
        let face = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        g.gradient(face, [key.top, key.bottom], from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.maxY))
        g.rim(face, width: 0.7, [white(0.28), white(0.02)], from: rect.origin, to: CGPoint(x: rect.minX, y: rect.maxY))
    }

    private static func drawArmBase(_ g: CGContext) {
        let pivot = Plan.pivot
        g.shadowed(dx: 2, dy: 3.2, blur: 5, alpha: 0.6) { g.fillCircle(pivot, 45, silver.dark) }
        g.metal(pivot, 45)
        g.strokeCircle(pivot, 44.5, white(0.65), width: 0.9)
        g.fillCircle(pivot, 37.5, rgb(0x1C1D20))
        g.strokeCircle(pivot, 37.5, black(0.45), width: 0.6)
        // Height scale around the base.
        for step in 0..<48 {
            let angle = CGFloat(step) / 48 * 2 * .pi
            let long = step % 4 == 0
            g.stroke(line(point(pivot, long ? 30.5 : 32, angle), point(pivot, 34.5, angle)),
                     lettering.copy(alpha: long ? 0.8 : 0.45)!, width: 0.45)
        }
        g.metal(pivot, 24)
        g.strokeCircle(pivot, 23.6, white(0.55), width: 0.7)
        g.fillCircle(pivot, 19.5, rgb(0x17181A))

        // Anti-skate dial.
        let dial = CGPoint(x: pivot.x + 58, y: pivot.y + 4)
        g.shadowed(dx: 1.2, dy: 2, blur: 3, alpha: 0.6) { g.fillCircle(dial, 9.6, silver.dark) }
        g.metal(dial, 9.6)
        g.strokeCircle(dial, 9.2, white(0.6), width: 0.6)
        g.fillCircle(dial, 6.4, rgb(0x232428))
        g.stroke(line(CGPoint(x: dial.x, y: dial.y - 5.4), CGPoint(x: dial.x, y: dial.y - 1.6)), silver.light,
                 width: 0.9, cap: .round)

        // Cueing lever.
        let slot = CGRect(x: pivot.x + 42, y: pivot.y + 40, width: 15, height: 32)
        g.fill(CGPath(roundedRect: slot, cornerWidth: 4, cornerHeight: 4, transform: nil), recess)
        g.rim(CGPath(roundedRect: slot, cornerWidth: 4, cornerHeight: 4, transform: nil), width: 0.6,
              [black(0.6), white(0.12)], from: slot.origin, to: CGPoint(x: slot.minX, y: slot.maxY))
        let lever = line(CGPoint(x: slot.midX, y: slot.minY + 8), CGPoint(x: slot.midX, y: slot.maxY - 9))
        g.shadowed(dx: 1, dy: 1.8, blur: 2.4, alpha: 0.6) { g.stroke(lever, silver.mid, width: 5.4, cap: .round) }
        g.stroke(lever, silver.light, width: 1.6, cap: .round)
        g.fillCircle(CGPoint(x: slot.midX, y: slot.maxY - 9), 3.9, rgb(0x232428))

        // The rest the arm parks on.
        let rest = CGPoint(x: pivot.x + 12.5, y: pivot.y + 118)
        g.shadowed(dx: 1.2, dy: 2, blur: 3, alpha: 0.6) { g.fillCircle(rest, 8.2, silver.dark) }
        g.metal(rest, 8.2)
        g.strokeCircle(rest, 7.8, white(0.6), width: 0.6)
        for side in [-1, 1] as [CGFloat] {
            g.fill(CGPath(roundedRect: CGRect(x: rest.x + side * 7.4 - 2.4, y: rest.y - 5.5, width: 4.8, height: 11),
                          cornerWidth: 1.6, cornerHeight: 1.6, transform: nil), rgb(0x232428))
        }
    }

    private static func drawFaderPanel(_ g: CGContext) {
        let x = Plan.faderX
        let panel = CGRect(x: x - 17.5, y: Plan.faderTop - 17, width: 35, height: Plan.faderBottom - Plan.faderTop + 34)
        let shape = CGPath(roundedRect: panel, cornerWidth: 4.5, cornerHeight: 4.5, transform: nil)
        g.fill(shape, rgb(0x16171A))
        g.rim(shape, width: 0.7, [black(0.7), white(0.13)], from: panel.origin, to: CGPoint(x: panel.minX, y: panel.maxY))
        g.stroke(line(CGPoint(x: x, y: Plan.faderTop - 7), CGPoint(x: x, y: Plan.faderBottom + 7)), black(0.9),
                 width: 3.4, cap: .round)
        for step in 0...10 {
            let y = Plan.faderTop + (Plan.faderBottom - Plan.faderTop) * CGFloat(step) / 10
            let long = step % 5 == 0
            g.stroke(line(CGPoint(x: x - (long ? 13 : 10.5), y: y), CGPoint(x: x - 6, y: y)),
                     lettering.copy(alpha: long ? 0.95 : 0.55)!, width: long ? 0.6 : 0.45)
            if long {
                g.text(String(10 - step), at: CGPoint(x: x + 10.5, y: y + 1.05), size: 3, weight: .semibold,
                       color: lettering, align: .center)
            }
        }
        g.text("VOLUME", at: CGPoint(x: x, y: panel.minY - 3.6), size: 2.9, weight: .semibold, color: lettering,
               tracking: 0.9, align: .center)
    }

    /// The cap of the volume fader, centred on the origin.
    static func faderCap(night: Bool, pixelsPerMM: CGFloat) -> Sprite {
        Sprite(CGRect(x: -24, y: -18, width: 48, height: 40), pixelsPerMM: pixelsPerMM) { g in
            let rect = CGRect(x: -14.5, y: -8, width: 29, height: 16)
            let shape = CGPath(roundedRect: rect, cornerWidth: 2.6, cornerHeight: 2.6, transform: nil)
            g.shadowed(dx: 1.6, dy: 3, blur: 4.5, alpha: 0.7) { g.fill(shape, silver.dark) }
            g.gradient(shape, [silver.light, silver.mid, silver.dark], from: CGPoint(x: 0, y: rect.minY),
                       to: CGPoint(x: 0, y: rect.maxY))
            g.rim(shape, width: 0.6, [white(0.9), black(0.25)], from: rect.origin, to: CGPoint(x: rect.minX, y: rect.maxY))
            for y in [-5.2, -3.4, 3.4, 5.2] as [CGFloat] {
                g.stroke(line(CGPoint(x: -11.5, y: y), CGPoint(x: 11.5, y: y)), black(0.2), width: 0.45)
            }
            g.stroke(line(CGPoint(x: -12.5, y: 0), CGPoint(x: 12.5, y: 0)), rgb(0x1B1C1F), width: 1.5)
            if night { g.dim(dusk) }
        }
    }

    // MARK: Record

    /// Everything on the platter that turns: the strobe dots on its rim, the record and its label.
    static func disc(label: CGImage?, night: Bool, pixelsPerMM: CGFloat) -> Sprite {
        let radius = Plan.platterRadius
        return Sprite(CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), pixelsPerMM: pixelsPerMM) { g in
            for (ring, count) in [(radius - 3.9, 188), (radius - 7.3, 176)] {
                for step in 0..<count {
                    g.fillCircle(point(.zero, ring, CGFloat(step) / CGFloat(count) * 2 * .pi), 0.8, rgb(0x33363B, 0.9))
                }
            }
            drawRecord(g, at: .zero, label: label)
            if night { g.dim(dusk) }
        }
    }

    private static func drawRecord(_ g: CGContext, at center: CGPoint, label: CGImage?) {
        let (inner, outer) = (Plan.innerGroove, Plan.outerGroove)
        g.fillCircle(center, Plan.recordRadius, vinyl)
        g.strokeCircle(center, Plan.recordRadius - 0.45, white(0.13), width: 0.5)
        g.fill(ring(center, inner, outer), rgb(0x16161A))
        var random = Random(seed: 7)
        for radius in stride(from: inner + 0.4, to: outer, by: 0.58) {
            g.strokeCircle(center, radius, white(random.next(0.01...0.08)), width: 0.26)
        }
        // The smooth gaps between tracks.
        for gap in [0.19, 0.37, 0.56, 0.77] as [CGFloat] {
            let radius = inner + (outer - inner) * gap
            g.strokeCircle(center, radius, rgb(0x070709), width: 1.25)
            g.strokeCircle(center, radius + 0.85, white(0.07), width: 0.25)
        }

        let disc = CGPath(ellipseIn: square(center, Plan.labelRadius), transform: nil)
        if let label {
            g.saveGState()
            g.addPath(disc)
            g.clip()
            g.image(label, filling: square(center, Plan.labelRadius))
            g.restoreGState()
        } else {
            g.fill(disc, vermilion)
            g.strokeCircle(center, Plan.labelRadius - 6, cream.copy(alpha: 0.85)!, width: 0.7)
            g.text("SPINDLE", at: CGPoint(x: center.x, y: center.y - 19), size: 9.5, weight: .heavy, color: cream,
                   tracking: 1.6, align: .center)
            g.text("33⅓ RPM  ·  STEREO", at: CGPoint(x: center.x, y: center.y + 26), size: 4.4, weight: .semibold,
                   color: cream, tracking: 0.8, align: .center)
        }
        g.strokeCircle(center, Plan.labelRadius - 0.4, black(0.3), width: 0.8)
        g.strokeCircle(center, 17, black(0.12), width: 0.4)
        g.fillCircle(center, 3.9, black(0.9))
    }

    /// Light on the record, and the spindle through its centre. These lie over the turning
    /// disc and stay put, the way reflections do on real vinyl.
    static func sheen(night: Bool, pixelsPerMM: CGFloat) -> Sprite {
        let radius = Plan.platterRadius + 4
        return Sprite(CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), pixelsPerMM: pixelsPerMM) { g in
            drawSheen(g, at: .zero, strength: night ? 0.55 : 1)

            g.saveGState()
            g.addEllipse(in: square(.zero, Plan.platterRadius))
            g.clip()
            // The strobe lights the rim beside it; after dark the target lamp pools on the record.
            let strobe = CGPoint(x: strobeLamp.x - Plan.platter.x, y: strobeLamp.y - Plan.platter.y)
            g.glow(strobe, radius: night ? 34 : 20, lamp.copy(alpha: night ? 0.7 : 0.4)!)
            if night {
                g.glow(CGPoint(x: 96, y: 118), radius: 62, rgb(0xFFD9A0, 0.3))
            }
            g.restoreGState()

            g.shadowed(dx: 0.6, dy: 1, blur: 1.5, alpha: 0.7) { g.fillCircle(.zero, 3.6, silver.mid) }
            g.gradient(CGPath(ellipseIn: square(.zero, 3.6), transform: nil), [silver.light, silver.dark],
                       from: CGPoint(x: -2.5, y: -2.5), to: CGPoint(x: 2.5, y: 2.5))
            g.fillCircle(CGPoint(x: -1, y: -1), 1, white(0.85))
        }
    }

    private static func drawSheen(_ g: CGContext, at center: CGPoint, strength: CGFloat) {
        g.saveGState()
        g.addPath(ring(center, Plan.labelRadius + 0.6, Plan.recordRadius - 0.9))
        g.clip(using: .evenOdd)
        // Two wedges of reflected light, towards the light and directly away from it: each a
        // broad glow with a narrow bright streak down its middle.
        let wedges: [[(CGFloat, CGFloat)]] = [
            [(0, 0), (0.035, 0), (0.125, 0.13), (0.215, 0), (0.535, 0), (0.625, 0.24), (0.715, 0), (1, 0)],
            [(0, 0), (0.098, 0), (0.125, 0.1), (0.152, 0), (0.598, 0), (0.625, 0.18), (0.652, 0), (1, 0)],
        ]
        for wedge in wedges {
            g.conic(center, wedge.map { ($0.0, white($0.1 * strength)) })
        }
        g.restoreGState()
    }

    // MARK: Tonearm

    /// The arm at rest. Its frame is in the deck's space, so it can be turned about `Plan.pivot`.
    static func arm(night: Bool, pixelsPerMM: CGFloat) -> Sprite {
        Sprite(armFrame, pixelsPerMM: pixelsPerMM) { g in
            drawArm(g)
            if night { g.dim(dusk) }
        }
    }

    /// The arm's shadow, which falls further away when the arm is lifted.
    static func armShadow(pixelsPerMM: CGFloat) -> Sprite {
        Sprite(armFrame, pixelsPerMM: pixelsPerMM, blur: 2.2) { g in
            drawArm(g)
            g.dim(black(1))
        }
    }

    private static let armFrame = CGRect(x: Plan.pivot.x - 60, y: Plan.pivot.y - 100, width: 130, height: 360)

    private static func drawArm(_ g: CGContext) {
        g.saveGState()
        g.translateBy(x: Plan.pivot.x, y: Plan.pivot.y)
        let spine = Plan.armSpine

        // Counterweight on a stub behind the pivot.
        g.stroke(line(CGPoint(x: 0, y: -14), CGPoint(x: 0, y: -42)), silver.dark, width: 7.5)
        let weight = CGRect(x: -17.5, y: -74, width: 35, height: 36)
        let across = (CGPoint(x: weight.minX, y: 0), CGPoint(x: weight.maxX, y: 0))
        g.gradient(CGPath(roundedRect: CGRect(x: -12, y: -79, width: 24, height: 8), cornerWidth: 2, cornerHeight: 2,
                          transform: nil), [silver.deep, silver.mid, silver.deep], from: across.0, to: across.1)
        g.gradient(CGPath(roundedRect: weight, cornerWidth: 3.4, cornerHeight: 3.4, transform: nil),
                   [silver.deep, silver.mid, silver.light, silver.mid, silver.deep], from: across.0, to: across.1)
        g.gradient(CGPath(rect: CGRect(x: weight.minX, y: -47, width: weight.width, height: 6.5), transform: nil),
                   [rgb(0x151517), rgb(0x3A3C41), rgb(0x55585E), rgb(0x3A3C41), rgb(0x151517)], from: across.0, to: across.1)
        g.stroke(line(CGPoint(x: weight.minX + 1, y: -56), CGPoint(x: weight.maxX - 1, y: -56)), black(0.22), width: 0.5)
        g.stroke(line(CGPoint(x: weight.minX + 1, y: -66), CGPoint(x: weight.maxX - 1, y: -66)), black(0.22), width: 0.5)

        // The tube: straight out of the pivot, then two bends into the headshell.
        let tube = CGMutablePath()
        tube.move(to: CGPoint(x: 0, y: 6))
        tube.addArc(tangent1End: spine[2], tangent2End: spine[3], radius: 34)
        tube.addArc(tangent1End: spine[3], tangent2End: spine[4], radius: 20)
        tube.addLine(to: spine[4])
        g.stroke(tube, silver.deep, width: 8.8)
        g.stroke(tube, silver.mid, width: 7.4)
        g.stroke(tube, silver.light, width: 2.4)

        // Headshell and cartridge, drawn pointing straight down and turned into place.
        g.saveGState()
        g.translateBy(x: 0, y: Plan.armLength)
        g.rotate(by: Plan.headshellAngle * .pi / 180)
        let lift = line(CGPoint(x: 8, y: -20), CGPoint(x: 21.5, y: -22))
        g.stroke(lift, silver.deep, width: 3.6, cap: .round)
        g.stroke(lift, silver.light, width: 2.2, cap: .round)
        let collar = CGRect(x: -5.8, y: -47, width: 11.6, height: 7)
        g.gradient(CGPath(roundedRect: collar, cornerWidth: 1.2, cornerHeight: 1.2, transform: nil),
                   [silver.deep, silver.light, silver.deep], from: CGPoint(x: collar.minX, y: 0),
                   to: CGPoint(x: collar.maxX, y: 0))
        let shell = CGMutablePath()
        shell.move(to: CGPoint(x: -3.6, y: -40))
        shell.addLine(to: CGPoint(x: 3.6, y: -40))
        shell.addLine(to: CGPoint(x: 3.6, y: -33))
        shell.addArc(tangent1End: CGPoint(x: 9.6, y: -27), tangent2End: CGPoint(x: 9.6, y: 4), radius: 3)
        shell.addArc(tangent1End: CGPoint(x: 9.6, y: 4), tangent2End: CGPoint(x: -9.6, y: 4), radius: 2.6)
        shell.addArc(tangent1End: CGPoint(x: -9.6, y: 4), tangent2End: CGPoint(x: -9.6, y: -27), radius: 2.6)
        shell.addArc(tangent1End: CGPoint(x: -9.6, y: -27), tangent2End: CGPoint(x: -3.6, y: -33), radius: 3)
        shell.addLine(to: CGPoint(x: -3.6, y: -33))
        shell.closeSubpath()
        g.fill(shell, silver.deep)
        g.gradient(shell.copy(using: [CGAffineTransform(scaleX: 0.92, y: 0.985)])!, [silver.light, silver.mid],
                   from: CGPoint(x: 0, y: -40), to: CGPoint(x: 0, y: 4))
        for x in [-5.2, 5.2] as [CGFloat] {
            g.stroke(line(CGPoint(x: x, y: -24), CGPoint(x: x, y: -9)), rgb(0x2A2B2F), width: 1.7, cap: .round)
            g.fillCircle(CGPoint(x: x, y: -16.5), 1.9, silver.deep)
            g.fillCircle(CGPoint(x: x, y: -16.5), 1.2, silver.light)
        }
        let cart = CGRect(x: -7, y: -4, width: 14, height: 15.5)
        g.fill(CGPath(roundedRect: cart, cornerWidth: 1.8, cornerHeight: 1.8, transform: nil), cartridge)
        g.fill(CGPath(roundedRect: CGRect(x: -7, y: 6.8, width: 14, height: 4.7), cornerWidth: 1.6, cornerHeight: 1.6,
                      transform: nil), black(0.28))
        g.fill(CGPath(rect: CGRect(x: -7, y: -4, width: 14, height: 1.6), transform: nil), white(0.25))
        g.restoreGState()

        // Bearing housing over the pivot.
        let housing = CGPath(roundedRect: CGRect(x: -15, y: -15, width: 30, height: 30), cornerWidth: 7.5,
                             cornerHeight: 7.5, transform: nil)
        g.fill(housing, rgb(0x0D0D0F))
        g.gradient(housing.copy(using: [CGAffineTransform(scaleX: 0.94, y: 0.94)])!, [rgb(0x35373C), rgb(0x222327)],
                   from: CGPoint(x: 0, y: -15), to: CGPoint(x: 0, y: 15))
        g.metal(.zero, 8.6)
        g.strokeCircle(.zero, 8.2, white(0.6), width: 0.6)
        g.fillCircle(.zero, 2.6, rgb(0x232428))
        g.restoreGState()
    }

    // MARK: Sleeves

    private static let sleeveFrame: CGRect = {
        let half = Plan.sleeveSide / 2 + 46
        return CGRect(x: -half, y: -half, width: half * 2, height: half * 2)
    }()

    /// A record sleeve lying flat, centred on the origin. With no cover it is Spindle's own.
    static func sleeve(cover: CGImage?, night: Bool, pixelsPerMM: CGFloat) -> Sprite {
        Sprite(sleeveFrame, pixelsPerMM: pixelsPerMM) { g in
            let half = Plan.sleeveSide / 2
            let rect = square(.zero, half)
            let card = CGPath(roundedRect: rect, cornerWidth: 1.8, cornerHeight: 1.8, transform: nil)
            g.shadowed(dx: 8, dy: 13, blur: 26, alpha: 0.3) { g.fill(card, underside) }
            g.shadowed(dx: 1.6, dy: 2.6, blur: 4.5, alpha: 0.4) { g.fill(card, underside) }
            g.saveGState()
            g.addPath(card)
            g.clip()
            if let cover {
                g.image(cover, filling: rect)
            } else {
                drawOwnCover(g, in: rect)
            }
            g.restoreGState()
            finishSleeve(g, card, rect)
            if night { g.dim(dusk) }
        }
    }

    /// Light across the card, a bright edge towards the light, and a hint of the opening on the right.
    private static func finishSleeve(_ g: CGContext, _ card: CGPath, _ rect: CGRect) {
        g.gradient(card, [white(0.13), white(0), black(0.1)], from: rect.origin, to: CGPoint(x: rect.maxX, y: rect.maxY))
        g.grain(in: card, alpha: 0.35)
        g.rim(card, width: 0.8, [white(0.42), black(0.22)], from: rect.origin, to: CGPoint(x: rect.maxX, y: rect.maxY))
        g.stroke(line(CGPoint(x: rect.maxX - 2.3, y: rect.minY + 1), CGPoint(x: rect.maxX - 2.3, y: rect.maxY - 1)),
                 black(0.16), width: 0.5)
    }

    private static func drawOwnCover(_ g: CGContext, in rect: CGRect) {
        g.fill(CGPath(rect: rect, transform: nil), cream)
        let sun = CGPoint(x: rect.maxX - 92, y: rect.minY + 104)
        g.fillCircle(sun, 118, vermilion)
        for radius in [142, 166, 190] as [CGFloat] {
            g.strokeCircle(sun, radius, navy, width: 7)
        }
        g.fill(CGPath(rect: CGRect(x: rect.minX, y: rect.maxY - 112, width: rect.width, height: 112), transform: nil), navy)
        g.text("Spindle", at: CGPoint(x: rect.minX + 22, y: rect.maxY - 50), size: 58, weight: .heavy, color: cream,
               tracking: -1.6)
        g.text("Play a track in Spotify, Spotifast or Apple Music", at: CGPoint(x: rect.minX + 25, y: rect.maxY - 24),
               size: 10.2, weight: .medium, color: cream.copy(alpha: 0.86)!)
    }

    /// What lies under the pile: a plain paper sleeve with a record half out of it.
    static func spare(night: Bool, pixelsPerMM: CGFloat) -> Sprite {
        let half = Plan.sleeveSide / 2
        let record = Plan.spareRecordOffset
        let frame = square(.zero, half).union(square(record, Plan.recordRadius)).insetBy(dx: -46, dy: -46)
        return Sprite(frame, pixelsPerMM: pixelsPerMM) { g in
            g.shadowed(dx: 5, dy: 8, blur: 16, alpha: 0.3) { g.fillCircle(record, Plan.recordRadius, vinyl) }
            drawRecord(g, at: record, label: nil)
            drawSheen(g, at: record, strength: 0.8)
            g.fillCircle(record, 3.6, underside)

            // Plain paper, with a thumb notch in the edge the record comes out of.
            let rect = square(.zero, half)
            let card = CGMutablePath()
            card.move(to: rect.origin)
            card.addLine(to: CGPoint(x: -23, y: rect.minY))
            card.addArc(center: CGPoint(x: 0, y: rect.minY), radius: 23, startAngle: .pi, endAngle: 0, clockwise: true)
            card.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            card.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            card.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            card.closeSubpath()
            g.shadowed(dx: 8, dy: 13, blur: 26, alpha: 0.3) { g.fill(card, underside) }
            g.shadowed(dx: 1.6, dy: 2.6, blur: 4.5, alpha: 0.4) { g.fill(card, underside) }
            g.gradient(card, [rgb(0xDCCBA8), rgb(0xC9B48E)], from: rect.origin, to: CGPoint(x: rect.maxX, y: rect.maxY))
            finishSleeve(g, card, rect)
            if night { g.dim(dusk) }
        }
    }

    // MARK: Words

    /// Title and artist. An empty title draws nothing.
    static func caption(title: String, artist: String, palette: Palette, pixelsPerMM: CGFloat) -> Sprite {
        Sprite(Plan.caption.insetBy(dx: -12, dy: -12), pixelsPerMM: pixelsPerMM) { g in
            guard !title.isEmpty else { return }
            let (left, top, width) = (Plan.caption.minX, Plan.caption.minY, Plan.caption.width)
            let words = {
                g.text("NOW PLAYING", at: CGPoint(x: left + 0.6, y: top + 9), size: 7.4, weight: .semibold,
                       color: palette.quietInk, tracking: 1.5)
                g.text(title, at: CGPoint(x: left, y: top + 33), size: 21, weight: .bold, color: palette.ink,
                       tracking: -0.25, maxWidth: width)
                g.text(artist, at: CGPoint(x: left + 0.3, y: top + 51), size: 12.5, weight: .regular,
                       color: palette.quietInk, maxWidth: width)
            }
            // Over the user's own wallpaper the words need a shadow to stay readable.
            if palette.bare {
                g.shadowed(dx: 0, dy: 1, blur: 5, alpha: 0.8, words)
            } else {
                words()
            }
        }
    }

    /// A sentence in a pill, for telling the listener something the picture can't.
    static func notice(_ words: String, palette: Palette, pixelsPerMM: CGFloat) -> Sprite {
        Sprite(Plan.notice.insetBy(dx: -30, dy: -16), pixelsPerMM: pixelsPerMM) { g in
            let size: CGFloat = 9.6
            let width = min(g.width(of: words, size: size, weight: .medium) + 32, Plan.notice.width + 50)
            let pill = CGRect(x: Plan.notice.midX - width / 2, y: Plan.notice.minY, width: width, height: Plan.notice.height)
            let shape = CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil)
            g.shadowed(dx: 2, dy: 4, blur: 10, alpha: 0.26) { g.fill(shape, palette.notice.fill) }
            g.text(words, at: CGPoint(x: pill.midX, y: pill.midY + size * 0.35), size: size, weight: .medium,
                   color: palette.notice.words, align: .center, maxWidth: width - 26)
        }
    }

    // MARK: Desk

    /// The surface under everything, `size` pixels across, with the deck's centre at `origin`.
    static func desk(palette: Palette, size: CGSize, origin: CGPoint, pixelsPerMM: CGFloat) -> CGImage? {
        guard !palette.bare, size.width >= 1, size.height >= 1 else { return nil }
        let frame = CGRect(x: -origin.x / pixelsPerMM, y: -origin.y / pixelsPerMM, width: size.width / pixelsPerMM,
                           height: size.height / pixelsPerMM)
        return Sprite(frame, pixelsPerMM: pixelsPerMM) { g in
            let surface = CGPath(rect: frame, transform: nil)
            g.gradient(surface, [palette.desk.0, palette.desk.1], from: frame.origin,
                       to: CGPoint(x: frame.maxX, y: frame.maxY))
            if let lamplight = palette.lamplight {
                g.glow(CGPoint(x: -90, y: -70), radius: 860, lamplight)
                g.drawRadialGradient(CGGradient(colorsSpace: nil, colors: [black(0), black(0.34)] as CFArray, locations: nil)!,
                                     startCenter: .zero, startRadius: 480, endCenter: .zero, endRadius: 1150,
                                     options: [.drawsAfterEndLocation])
            } else {
                // Sunlight is soft-edged, so it is drawn small and scaled up.
                let sunlight = Sprite(frame, pixelsPerMM: min(pixelsPerMM, 0.5), blur: 5.5) { drawSunlight($0) }
                g.saveGState()
                g.setAlpha(0.5)
                g.image(sunlight.image, filling: frame)
                g.restoreGState()
            }
            g.grain(in: surface, alpha: palette.night ? 0.5 : 0.4)
        }.image
    }

    /// Light from a window up and to the left, falling across the desk in panes, with the
    /// shadow of a plant on the sill cut out of it.
    private static func drawSunlight(_ g: CGContext) {
        let corner = CGPoint(x: -930, y: -560)
        let (across, down) = (CGPoint(x: 560, y: 64), CGPoint(x: 150, y: 430))
        for column in 0..<3 {
            for row in 0..<2 {
                let (u, v) = (CGFloat(column) * 1.07, CGFloat(row) * 1.07)
                let corners: [(CGFloat, CGFloat)] = [(u, v), (u + 1, v), (u + 1, v + 1), (u, v + 1)]
                let pane = CGMutablePath()
                pane.addLines(between: corners.map { u, v -> CGPoint in
                    let x = corner.x + across.x * u + down.x * v
                    let y = corner.y + across.y * u + down.y * v
                    return CGPoint(x: x, y: y)
                })
                pane.closeSubpath()
                g.fill(pane, rgb(0xFFF6E6))
            }
        }
        g.setBlendMode(.destinationOut)
        frond(g, from: CGPoint(x: 720, y: -560), to: CGPoint(x: 150, y: -262), bend: -80, leaves: 8, length: 190)
        frond(g, from: CGPoint(x: 800, y: -420), to: CGPoint(x: 470, y: -226), bend: 50, leaves: 6, length: 150)
        g.setBlendMode(.normal)
    }

    /// A palm leaf: a curved stem with leaflets down both sides, longest in the middle.
    private static func frond(_ g: CGContext, from base: CGPoint, to tip: CGPoint, bend: CGFloat, leaves: Int,
                              length: CGFloat) {
        let middle = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
        let span = hypot(tip.x - base.x, tip.y - base.y)
        let control = CGPoint(x: middle.x - (tip.y - base.y) / span * bend, y: middle.y + (tip.x - base.x) / span * bend)
        let stem = CGMutablePath()
        stem.move(to: base)
        stem.addQuadCurve(to: tip, control: control)
        g.stroke(stem, black(1), width: 5, cap: .round)
        for leaf in 1...leaves {
            let t = CGFloat(leaf) / CGFloat(leaves + 1)
            let at = CGPoint(x: (1 - t) * (1 - t) * base.x + 2 * t * (1 - t) * control.x + t * t * tip.x,
                             y: (1 - t) * (1 - t) * base.y + 2 * t * (1 - t) * control.y + t * t * tip.y)
            let heading = atan2((1 - t) * (control.y - base.y) + t * (tip.y - control.y),
                                (1 - t) * (control.x - base.x) + t * (tip.x - control.x))
            let reach = length * (0.3 + 0.7 * pow(sin(.pi * (0.12 + 0.88 * t)), 0.7))
            for side in [-1, 1] as [CGFloat] {
                g.saveGState()
                g.translateBy(x: at.x, y: at.y)
                g.rotate(by: heading + side * 0.95)
                g.setFillColor(black(1))
                g.fillEllipse(in: CGRect(x: 0, y: -reach * 0.1, width: reach, height: reach * 0.2))
                g.restoreGState()
            }
        }
    }

    // MARK: Shapes

    private static func square(_ center: CGPoint, _ half: CGFloat) -> CGRect {
        CGRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2)
    }

    private static func ring(_ center: CGPoint, _ inner: CGFloat, _ outer: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: square(center, outer))
        path.addEllipse(in: square(center, inner))
        return path
    }

    private static func line(_ from: CGPoint, _ to: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }

    private static func point(_ center: CGPoint, _ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    /// Fine speckle that takes the plastic look off flat colour, the same on every launch.
    fileprivate static let grainTile: CGImage = {
        let side = 128
        var random = Random(seed: 23)
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in 0..<(side * side) {
            let alpha = UInt8(random.next(0...26))
            let value: UInt8 = random.next(0...1) > 0.5 ? alpha : 0
            pixels[index * 4] = value
            pixels[index * 4 + 1] = value
            pixels[index * 4 + 2] = value
            pixels[index * 4 + 3] = alpha
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }()

    fileprivate static let silverStops: [(CGFloat, CGColor)] = [
        (0, silver.mid), (0.125, silver.light), (0.25, silver.mid), (0.375, silver.dark), (0.5, silver.mid),
        (0.625, silver.light), (0.75, silver.mid), (0.875, silver.dark), (1, silver.mid),
    ]

    fileprivate static let shadow = rgb(0x05070D)

    /// Seeded so the artwork is identical on every launch.
    private struct Random {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next(_ range: ClosedRange<CGFloat>) -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = CGFloat((state >> 33) % 100_000) / 100_000
            return range.lowerBound + unit * (range.upperBound - range.lowerBound)
        }
    }
}

// MARK: Drawing

/// Shorthand for the handful of operations the artwork is built from.
private extension CGContext {
    enum Alignment { case left, center, right }

    var pixelsPerUnit: CGFloat { hypot(ctm.a, ctm.b) }

    func fill(_ path: CGPath, _ color: CGColor) {
        addPath(path)
        setFillColor(color)
        fillPath()
    }

    func stroke(_ path: CGPath, _ color: CGColor, width: CGFloat, cap: CGLineCap = .butt) {
        addPath(path)
        setStrokeColor(color)
        setLineWidth(width)
        setLineCap(cap)
        setLineJoin(.round)
        strokePath()
    }

    func fillCircle(_ center: CGPoint, _ radius: CGFloat, _ color: CGColor) {
        setFillColor(color)
        fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    func strokeCircle(_ center: CGPoint, _ radius: CGFloat, _ color: CGColor, width: CGFloat) {
        setStrokeColor(color)
        setLineWidth(width)
        strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    private func makeGradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
        CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    }

    /// Fills `path` with colours running from one point to another.
    func gradient(_ path: CGPath, _ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
        saveGState()
        addPath(path)
        clip()
        drawLinearGradient(makeGradient(colors), start: start, end: end,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }

    /// A line just inside the edge of `path`, shaded from one point to another: the lit and
    /// shaded edges that make a flat shape read as a solid one.
    func rim(_ path: CGPath, width: CGFloat, _ colors: [CGColor], from start: CGPoint, to end: CGPoint) {
        saveGState()
        addPath(path)
        clip()
        addPath(path)
        setLineWidth(width * 2)
        replacePathWithStrokedPath()
        clip()
        drawLinearGradient(makeGradient(colors), start: start, end: end,
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        restoreGState()
    }

    /// Colours running round `center`, clockwise from three o'clock, within the current clip.
    func conic(_ center: CGPoint, _ stops: [(CGFloat, CGColor)]) {
        CGContextDrawConicGradient(self, makeGradient(stops.map(\.1), stops.map(\.0)), center, 0)
    }

    /// A turned metal disc: bright towards the light and directly away from it.
    func metal(_ center: CGPoint, _ radius: CGFloat) {
        saveGState()
        addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        clip()
        conic(center, Illustration.silverStops)
        restoreGState()
    }

    /// Light spreading from a point and fading to nothing at `radius`.
    func glow(_ center: CGPoint, radius: CGFloat, _ color: CGColor) {
        drawRadialGradient(makeGradient([color, color.copy(alpha: color.alpha * 0.35)!, color.copy(alpha: 0)!], [0, 0.45, 1]),
                           startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    /// Draws with a soft shadow falling `dx` right and `dy` down.
    func shadowed(dx: CGFloat, dy: CGFloat, blur: CGFloat, alpha: CGFloat, _ draw: () -> Void) {
        saveGState()
        // Shadows ignore the current transform: they are set in pixels, with y running up.
        let scale = pixelsPerUnit
        setShadow(offset: CGSize(width: dx * scale, height: -dy * scale), blur: blur * scale,
                  color: Illustration.shadow.copy(alpha: alpha))
        beginTransparencyLayer(auxiliaryInfo: nil)
        draw()
        endTransparencyLayer()
        restoreGState()
    }

    func grain(in path: CGPath, alpha: CGFloat) {
        saveGState()
        addPath(path)
        clip()
        setAlpha(alpha)
        let side = CGFloat(Illustration.grainTile.width) / pixelsPerUnit
        draw(Illustration.grainTile, in: CGRect(x: 0, y: 0, width: side, height: side), byTiling: true)
        restoreGState()
    }

    /// Washes `color` over everything drawn so far, leaving what is still transparent alone.
    func dim(_ color: CGColor) {
        saveGState()
        setBlendMode(.sourceAtop)
        setFillColor(color)
        fill(boundingBoxOfClipPath)
        restoreGState()
    }

    /// Draws `image` the right way up, scaled to cover `rect` and centred on it.
    func image(_ image: CGImage, filling rect: CGRect) {
        let scale = max(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        saveGState()
        interpolationQuality = .high
        translateBy(x: rect.midX - size.width / 2, y: rect.midY + size.height / 2)
        scaleBy(x: 1, y: -1)
        draw(image, in: CGRect(origin: .zero, size: size))
        restoreGState()
    }

    /// How wide `string` would be drawn by `text`.
    func width(of string: String, size: CGFloat, weight: NSFont.Weight, tracking: CGFloat = 0) -> CGFloat {
        let line = typeset(string, size: size, weight: weight, color: CGColor(gray: 0, alpha: 1), tracking: tracking)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func typeset(_ string: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, tracking: CGFloat,
                         maxWidth: CGFloat? = nil) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            .kern: tracking,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
        guard let maxWidth, CTLineGetTypographicBounds(line, nil, nil, nil) > Double(maxWidth) else { return line }
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        return CTLineCreateTruncatedLine(line, Double(maxWidth), .end, ellipsis) ?? line
    }

    /// One line of text with its baseline at `point`, shortened with an ellipsis past `maxWidth`.
    func text(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, color: CGColor,
              tracking: CGFloat = 0, align: Alignment = .left, maxWidth: CGFloat? = nil) {
        let line = typeset(string, size: size, weight: weight, color: color, tracking: tracking, maxWidth: maxWidth)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let x = switch align {
        case .left: point.x
        case .center: point.x - width / 2
        case .right: point.x - width
        }
        saveGState()
        // The drawing space runs down the page, so glyphs are flipped back upright.
        textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        textPosition = CGPoint(x: x, y: point.y)
        CTLineDraw(line, self)
        restoreGState()
    }
}
