import CoreGraphics

/// Where everything on the desk sits, seen from straight above. Millimetres, measured from
/// the centre of the deck, with x to the right and y down the screen.
enum Plan {
    /// The pieces that respond to the pointer.
    enum Part {
        case deck, record, arm, fader, button, sleeve, stack
    }

    /// A place a record sleeve can lie: its centre and how far it is turned clockwise.
    struct Slot {
        var center: CGPoint
        var degrees: CGFloat
    }

    // MARK: Deck

    static let deck = CGRect(x: -228, y: -182, width: 456, height: 364)
    static let platter = CGPoint(x: -54, y: 0)
    static let platterRadius: CGFloat = 163
    static let recordRadius: CGFloat = 150.5
    static let labelRadius: CGFloat = 50
    /// The first and last groove, as distances from the spindle.
    static let outerGroove: CGFloat = 146
    static let innerGroove: CGFloat = 60

    static let startButton = CGRect(x: -218, y: 139, width: 50, height: 30)
    /// The volume fader's slot runs from loud at the top to silent at the bottom.
    static let faderX: CGFloat = 203
    static let faderTop: CGFloat = 34
    static let faderBottom: CGFloat = 146

    // MARK: Tonearm

    static let pivot = CGPoint(x: 140, y: -96)
    /// Pivot to stylus.
    static let armLength: CGFloat = 230
    /// The arm's outline in its own space: pivot at the origin, stylus straight down at rest.
    /// The cartridge is angled in from the line between pivot and stylus, as on any S-shaped arm.
    static let headshellAngle: CGFloat = 22
    /// The arm's centre line in its own space: pivot at the origin, stylus straight down at
    /// rest. From the counterweight, through both bends, to the tip of the headshell.
    static let armSpine: [CGPoint] = [
        CGPoint(x: 0, y: -76), .zero, CGPoint(x: 0, y: 92), CGPoint(x: 28.5, y: 159.5),
        CGPoint(x: 16.5, y: 189.2), CGPoint(x: -3.4, y: 238.3),
    ]

    /// Degrees the arm swings in from its rest, clockwise: where the stylus meets the first
    /// and last groove, and the furthest it will go.
    static let leadInAngle = armAngle(stylusRadius: outerGroove)
    static let leadOutAngle = armAngle(stylusRadius: innerGroove)
    static let maxArmAngle = leadOutAngle + 2.5

    private static func armAngle(stylusRadius radius: CGFloat) -> Double {
        let toSpindle = CGPoint(x: platter.x - pivot.x, y: platter.y - pivot.y)
        let distance = hypot(toSpindle.x, toSpindle.y)
        // The triangle pivot, spindle, stylus has all three sides known.
        let cosine = (distance * distance + armLength * armLength - radius * radius) / (2 * distance * armLength)
        let bearing = atan2(-toSpindle.x, toSpindle.y)
        return Double((bearing - acos(cosine)) * 180 / .pi)
    }

    /// The swing that would point the arm at `point`.
    static func armAngle(toward point: CGPoint) -> Double {
        Double(atan2(-(point.x - pivot.x), point.y - pivot.y) * 180 / .pi)
    }

    static func stylus(atArmAngle degrees: Double) -> CGPoint {
        let turn = CGFloat(degrees) * .pi / 180
        return CGPoint(x: pivot.x - armLength * sin(turn), y: pivot.y + armLength * cos(turn))
    }

    // MARK: Sleeves

    static let sleeveSide: CGFloat = 315
    /// The cover of what is playing, left of the deck.
    static let sleeve = Slot(center: CGPoint(x: -438, y: -6), degrees: -4)
    /// Earlier covers pile up right of the deck, bottom first.
    static let stack = [
        Slot(center: CGPoint(x: 440, y: 12), degrees: 8),
        Slot(center: CGPoint(x: 452, y: -4), degrees: -7),
        Slot(center: CGPoint(x: 444, y: 6), degrees: 3),
    ]
    /// A plain sleeve with a record half out lies under the pile.
    static let spare = Slot(center: CGPoint(x: 448, y: 10), degrees: -3)
    static let spareRecordOffset = CGPoint(x: 14, y: -82)

    /// Title and artist, set under the cover.
    static let caption = CGRect(x: -584, y: 188, width: 330, height: 62)

    /// Everything above, with room for shadows; this is what gets fitted to the window.
    static let bounds = CGRect(x: -622, y: -252, width: 1262, height: 516)

    // MARK: Hit testing

    static func part(at point: CGPoint, armAngle: Double, pileIsEmpty: Bool) -> Part? {
        if distance(from: point, toArmAt: armAngle) < 13 { return .arm }
        if abs(point.x - faderX) < 18, point.y > faderTop - 16, point.y < faderBottom + 16 { return .fader }
        if startButton.insetBy(dx: -3, dy: -3).contains(point) { return .button }
        if hypot(point.x - platter.x, point.y - platter.y) < recordRadius { return .record }
        if deck.contains(point) { return .deck }
        if contains(point, in: sleeve, side: sleeveSide) { return .sleeve }
        let pile = [spare] + (pileIsEmpty ? [] : stack)
        if pile.contains(where: { contains(point, in: $0, side: sleeveSide) }) { return .stack }
        let spareRecord = CGPoint(x: spare.center.x + spareRecordOffset.x, y: spare.center.y + spareRecordOffset.y)
        if hypot(point.x - spareRecord.x, point.y - spareRecord.y) < recordRadius { return .stack }
        return nil
    }

    private static func contains(_ point: CGPoint, in slot: Slot, side: CGFloat) -> Bool {
        let local = point.applying(CGAffineTransform(translationX: -slot.center.x, y: -slot.center.y))
            .applying(CGAffineTransform(rotationAngle: -slot.degrees * .pi / 180))
        return abs(local.x) < side / 2 && abs(local.y) < side / 2
    }

    private static func distance(from point: CGPoint, toArmAt degrees: Double) -> CGFloat {
        let toArmSpace = CGAffineTransform(translationX: -pivot.x, y: -pivot.y)
            .concatenating(CGAffineTransform(rotationAngle: -CGFloat(degrees) * .pi / 180))
        let local = point.applying(toArmSpace)
        return zip(armSpine, armSpine.dropFirst()).map { a, b in
            let along = CGPoint(x: b.x - a.x, y: b.y - a.y)
            let t = ((local.x - a.x) * along.x + (local.y - a.y) * along.y) / (along.x * along.x + along.y * along.y)
            let clamped = min(max(t, 0), 1)
            return hypot(local.x - a.x - along.x * clamped, local.y - a.y - along.y * clamped)
        }.min() ?? .infinity
    }
}
