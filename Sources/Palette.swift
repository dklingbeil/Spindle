import AppKit

/// A colour as lightness, colourfulness and hue (OKLCH), where equal steps look equal to the
/// eye. That makes it possible to keep a cover's hue while choosing how light and how vivid.
struct Tone {
    /// 0 is black, 1 is white.
    var lightness: Double
    /// 0 is grey; about 0.3 is as vivid as a screen gets.
    var chroma: Double
    /// Radians.
    var hue: Double

    func color(alpha: CGFloat = 1) -> CGColor {
        // Colours a screen can't show are pulled towards grey until they fit.
        var chroma = chroma
        for _ in 0..<24 {
            let rgb = Self.linearRGB(lightness, chroma * cos(hue), chroma * sin(hue))
            if rgb.allSatisfy({ $0 >= -0.0005 && $0 <= 1.0005 }) { break }
            chroma *= 0.9
        }
        let rgb = Self.linearRGB(lightness, chroma * cos(hue), chroma * sin(hue)).map { channel -> CGFloat in
            let value = min(max(channel, 0), 1)
            return CGFloat(value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055)
        }
        return CGColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: alpha)
    }

    init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    /// From sRGB components in 0...1.
    init(red: Double, green: Double, blue: Double) {
        let linear = [red, green, blue].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        let l = cbrt(0.4122214708 * linear[0] + 0.5363325363 * linear[1] + 0.0514459929 * linear[2])
        let m = cbrt(0.2119034982 * linear[0] + 0.6806995451 * linear[1] + 0.1073969566 * linear[2])
        let s = cbrt(0.0883024619 * linear[0] + 0.2817188376 * linear[1] + 0.6299787005 * linear[2])
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        chroma = hypot(a, b)
        hue = atan2(b, a)
    }

    private static func linearRGB(_ lightness: Double, _ a: Double, _ b: Double) -> [Double] {
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        return [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
        ]
    }
}

/// The colours of the desk, taken from the cover of whatever is playing.
struct Palette {
    /// The desk fades from the first colour, top left, to the second, bottom right.
    var desk: (CGColor, CGColor)
    /// At night a pool of lamplight sits behind the deck.
    var lamplight: CGColor?
    var ink: CGColor
    var quietInk: CGColor
    /// A notice is a pill in the colour of the ink, with words in the colour of the desk.
    var notice: (fill: CGColor, words: CGColor)
    var night: Bool
    /// Nothing behind the deck but the user's own wallpaper.
    var bare: Bool

    init(theme: SceneTheme, cover: NSImage?) {
        // With no cover, or a grey one, the desk is a warm neutral.
        let key = cover.flatMap(Self.keyColor) ?? Tone(lightness: 0.6, chroma: 0.02, hue: 1.25)
        let hue = key.hue
        let strength = min(key.chroma / 0.09, 1)
        night = theme == .midnight
        bare = theme == .bare

        switch theme {
        case .daylight:
            desk = (Tone(lightness: 0.925, chroma: 0.012 + 0.036 * strength, hue: hue).color(),
                    Tone(lightness: 0.865, chroma: 0.016 + 0.046 * strength, hue: hue).color())
            lamplight = nil
            ink = Tone(lightness: 0.24, chroma: 0.035, hue: hue).color()
            quietInk = Tone(lightness: 0.24, chroma: 0.035, hue: hue).color(alpha: 0.62)
            notice = (Tone(lightness: 0.27, chroma: 0.04, hue: hue).color(alpha: 0.92),
                      Tone(lightness: 0.96, chroma: 0.012, hue: hue).color())
        case .midnight:
            desk = (Tone(lightness: 0.2, chroma: 0.012 + 0.03 * strength, hue: hue).color(),
                    Tone(lightness: 0.14, chroma: 0.01 + 0.025 * strength, hue: hue).color())
            lamplight = Tone(lightness: 0.41, chroma: 0.025 + 0.055 * strength, hue: hue).color()
            ink = Tone(lightness: 0.94, chroma: 0.02, hue: hue).color()
            quietInk = Tone(lightness: 0.94, chroma: 0.02, hue: hue).color(alpha: 0.6)
            notice = (Tone(lightness: 0.93, chroma: 0.02, hue: hue).color(alpha: 0.94),
                      Tone(lightness: 0.2, chroma: 0.03, hue: hue).color())
        case .bare:
            desk = (.clear, .clear)
            lamplight = nil
            ink = CGColor(gray: 1, alpha: 0.96)
            quietInk = CGColor(gray: 1, alpha: 0.72)
            notice = (CGColor(gray: 0, alpha: 0.78), CGColor(gray: 1, alpha: 1))
        }
    }

    /// The colour a person would name if asked what colour the cover is: the most common
    /// vivid hue, rather than an average that turns everything to mud.
    private static func keyColor(of image: NSImage) -> Tone? {
        let side = 32
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        let binCount = 24
        var weights = [Double](repeating: 0, count: binCount)
        var tones: [(tone: Tone, weight: Double, bin: Int)] = []
        for index in 0..<(side * side) {
            let tone = Tone(red: Double(pixels[index * 4]) / 255, green: Double(pixels[index * 4 + 1]) / 255,
                            blue: Double(pixels[index * 4 + 2]) / 255)
            // Vivid mid-tones count for most; near-black and near-white say little about hue.
            let weight = pow(tone.chroma, 1.5) * max(0.15, 1 - abs(tone.lightness - 0.6) * 1.6)
            let turn = (tone.hue / (2 * .pi) + 1).truncatingRemainder(dividingBy: 1)
            let bin = min(Int(turn * Double(binCount)), binCount - 1)
            weights[bin] += weight
            tones.append((tone, weight, bin))
        }
        // Neighbouring hues are counted together so one colour isn't split across two bins.
        let smoothed = (0..<binCount).map { bin -> Double in
            let neighbours = weights[(bin + 1) % binCount] + weights[(bin + binCount - 1) % binCount]
            return weights[bin] + 0.6 * neighbours
        }
        guard let best = smoothed.indices.max(by: { smoothed[$0] < smoothed[$1] }), smoothed[best] > 0 else { return nil }

        var (a, b, chroma, total) = (0.0, 0.0, 0.0, 0.0)
        for (tone, weight, bin) in tones where min(abs(bin - best), binCount - abs(bin - best)) <= 1 {
            a += cos(tone.hue) * weight
            b += sin(tone.hue) * weight
            chroma += tone.chroma * weight
            total += weight
        }
        guard total > 0 else { return nil }
        // How much of the cover is coloured at all: a mostly grey cover gives a mostly grey desk.
        let coverage = min(tones.reduce(0) { $0 + $1.tone.chroma } / Double(tones.count) / 0.05, 1)
        return Tone(lightness: 0.6, chroma: chroma / total * coverage, hue: atan2(b, a))
    }
}
