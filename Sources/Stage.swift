import AppKit
import QuartzCore

/// The desk as a stack of layers. Each holds one piece of flat artwork; Core Animation turns
/// the record, swings the arm and slides sleeves about without anything being redrawn.
final class Stage {
    let layer = CALayer()

    private let desk = CALayer()
    private let caption = CALayer()
    private let spare = CALayer()
    private let deck = CALayer()
    private let disc = CALayer()
    private let sheen = CALayer()
    private let fader = CALayer()
    private let armShadow = CALayer()
    private let arm = CALayer()

    /// A sleeve on the desk and the cover it shows; `nil` is Spindle's own.
    private struct Sleeve {
        var cover: NSImage?
        var layer = CALayer()
        /// Which place in the pile it lies in.
        var slot = 0
    }

    private var playing: Sleeve?
    /// Earlier covers, bottom of the pile first.
    private var pile: [Sleeve] = []

    private var size = CGSize.zero
    private var insets = NSEdgeInsets()
    private var backingScale: CGFloat = 2
    private var theme = SceneTheme.daylight
    private var palette = Palette(theme: .daylight, cover: nil)
    private var title = ""
    private var artist = ""
    private var volume = 70.0
    private var spinning = false
    private var armLifted = true
    private(set) var armAngle = 0.0

    /// Points per millimetre, and where the centre of the deck falls in the layer.
    private var zoom: CGFloat = 1
    private var origin = CGPoint.zero
    private var pixelsPerMM: CGFloat { zoom * backingScale }
    private var isLaidOut: Bool { size.width > 0 }

    /// Stacking order. A sleeve on its way to the pile is carried over the top of the deck.
    private enum Level {
        static let desk: CGFloat = 0
        static let caption: CGFloat = 1
        static let spare: CGFloat = 2
        static let pile: CGFloat = 3
        static let playing: CGFloat = 8
        static let deck: CGFloat = 10
        static let carried: CGFloat = 30
    }

    init() {
        let levels: [(CALayer, CGFloat)] = [
            (desk, Level.desk), (caption, Level.caption), (spare, Level.spare), (deck, Level.deck),
            (disc, Level.deck + 1), (sheen, Level.deck + 2), (fader, Level.deck + 3),
            (armShadow, Level.deck + 4), (arm, Level.deck + 5),
        ]
        for (sublayer, level) in levels {
            sublayer.zPosition = level
            layer.addSublayer(sublayer)
        }
        desk.anchorPoint = .zero
        // Drawn at one pixel per point; scaled up sharply, its grain stays grain instead of blurring.
        desk.magnificationFilter = .nearest
    }

    // MARK: Layout

    /// Fits the desk into `size` points, keeping clear of `insets` (the menu bar and Dock).
    func layout(size: CGSize, insets: NSEdgeInsets, backingScale: CGFloat) {
        let unchanged = size == self.size && backingScale == self.backingScale && insets.top == self.insets.top
            && insets.left == self.insets.left && insets.bottom == self.insets.bottom && insets.right == self.insets.right
        guard !unchanged, size.width > 0, size.height > 0 else { return }
        self.size = size
        self.insets = insets
        self.backingScale = backingScale

        let clear = CGRect(x: insets.left, y: insets.bottom, width: size.width - insets.left - insets.right,
                           height: size.height - insets.top - insets.bottom)
        let room = clear.insetBy(dx: clear.width * 0.025, dy: clear.height * 0.05)
        zoom = max(min(room.width / Plan.bounds.width, room.height / Plan.bounds.height), 0.05)
        // Set a little above the middle, which is where the eye takes the middle to be.
        origin = CGPoint(x: room.midX - Plan.bounds.midX * zoom, y: room.midY + Plan.bounds.midY * zoom + room.height * 0.03)
        withoutAnimation { redraw() }
    }

    private func redraw() {
        let night = palette.night
        drawDesk()
        drawCaption()
        show(Illustration.spare(night: night, pixelsPerMM: pixelsPerMM), in: spare)
        settle(spare, into: Plan.spare)
        show(Illustration.deck(night: night, pixelsPerMM: pixelsPerMM), in: deck)
        drawDisc()
        show(Illustration.sheen(night: night, pixelsPerMM: pixelsPerMM), in: sheen, at: Plan.platter)
        show(Illustration.faderCap(night: night, pixelsPerMM: pixelsPerMM), in: fader)
        show(Illustration.arm(night: night, pixelsPerMM: pixelsPerMM), in: arm, anchor: Plan.pivot, at: Plan.pivot)
        show(Illustration.armShadow(pixelsPerMM: pixelsPerMM), in: armShadow, anchor: Plan.pivot, at: Plan.pivot)
        for sleeve in pile {
            draw(sleeve)
            settle(sleeve.layer, into: Plan.stack[sleeve.slot])
        }
        if let playing {
            draw(playing)
            settle(playing.layer, into: Plan.sleeve)
        }
        positionFader()
        positionArm()
    }

    private func drawDesk() {
        // The desk is all soft gradients, so one pixel per point is plenty.
        desk.contents = Illustration.desk(palette: palette, size: size,
                                          origin: CGPoint(x: origin.x, y: size.height - origin.y), pixelsPerMM: zoom)
        desk.bounds = CGRect(origin: .zero, size: size)
    }

    private func drawCaption() {
        show(Illustration.caption(title: title, artist: artist, palette: palette, pixelsPerMM: pixelsPerMM), in: caption)
    }

    private func drawDisc() {
        let label = playing?.cover.flatMap(Self.bitmap)
        show(Illustration.disc(label: label, night: palette.night, pixelsPerMM: pixelsPerMM), in: disc, at: Plan.platter)
    }

    private func draw(_ sleeve: Sleeve) {
        let cover = sleeve.cover.flatMap(Self.bitmap)
        show(Illustration.sleeve(cover: cover, night: palette.night, pixelsPerMM: pixelsPerMM), in: sleeve.layer, at: nil)
    }

    /// Puts `sprite` in `layer` so that `anchor`, a point in the sprite's own space, lands on
    /// `position` on the desk. With no position the layer stays where it is.
    private func show(_ sprite: Sprite, in layer: CALayer, anchor: CGPoint = .zero, at position: CGPoint? = .zero) {
        layer.contents = sprite.image
        layer.bounds = CGRect(x: 0, y: 0, width: sprite.frame.width * zoom, height: sprite.frame.height * zoom)
        layer.anchorPoint = CGPoint(x: (anchor.x - sprite.frame.minX) / sprite.frame.width,
                                    y: 1 - (anchor.y - sprite.frame.minY) / sprite.frame.height)
        if let position { layer.position = point(position) }
    }

    private func settle(_ layer: CALayer, into slot: Plan.Slot) {
        layer.position = point(slot.center)
        layer.transform = Self.turn(slot.degrees)
    }

    /// A point on the desk, in the layer's coordinates.
    private func point(_ onDesk: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + onDesk.x * zoom, y: origin.y - onDesk.y * zoom)
    }

    /// A point in the layer's coordinates, on the desk.
    private func onDesk(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / zoom, y: (origin.y - point.y) / zoom)
    }

    private static func turn(_ degrees: CGFloat) -> CATransform3D {
        // Layers measure angles anticlockwise; the desk is laid out clockwise.
        CATransform3DMakeRotation(-degrees * .pi / 180, 0, 0, 1)
    }

    private static func bitmap(_ image: NSImage) -> CGImage? {
        image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private func withoutAnimation(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }

    private func crossfade(_ layer: CALayer, over duration: CFTimeInterval) {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "crossfade")
    }

    // MARK: Updates

    func apply(_ theme: SceneTheme) {
        guard theme != self.theme else { return }
        self.theme = theme
        palette = Palette(theme: theme, cover: playing?.cover)
        guard isLaidOut else { return }
        crossfade(layer, over: 0.6)
        withoutAnimation { redraw() }
    }

    func setTrack(title: String, artist: String) {
        guard title != self.title || artist != self.artist else { return }
        self.title = title
        self.artist = artist
        guard isLaidOut else { return }
        crossfade(caption, over: 0.5)
        withoutAnimation { drawCaption() }
    }

    /// `history` is newest first; the newest ends up on top of the pile.
    func setCovers(playing cover: NSImage?, history: [NSImage]) {
        let earlier = Array(history.prefix(Plan.stack.count).reversed())
        let unchanged = playing != nil && playing?.cover === cover && pile.count == earlier.count
            && zip(pile, earlier).allSatisfy { $0.cover === $1 }
        guard !unchanged else { return }

        // Sleeves are matched to covers, so one that is wanted again is moved rather than redrawn:
        // the cover that was playing is carried to the pile, and the rest of the pile stays put.
        let wasPlaying = playing
        var unclaimed = pile + [playing].compactMap { $0 }
        var freeSlots = Array(Plan.stack.indices)
        pile = earlier.map { image in
            guard let index = unclaimed.firstIndex(where: { $0.cover === image }) else { return Sleeve(cover: image, slot: -1) }
            var sleeve = unclaimed.remove(at: index)
            if sleeve.layer === wasPlaying?.layer {
                sleeve.slot = -1
            } else {
                freeSlots.removeAll { $0 == sleeve.slot }
            }
            return sleeve
        }
        for index in pile.indices where pile[index].slot < 0 {
            pile[index].slot = freeSlots.isEmpty ? 0 : freeSlots.removeFirst()
        }
        let kept = unclaimed.firstIndex { $0.layer === wasPlaying?.layer && $0.cover === cover }
        let arriving = kept.map { unclaimed.remove(at: $0) } ?? Sleeve(cover: cover)
        playing = arriving
        palette = Palette(theme: theme, cover: cover)

        for sleeve in unclaimed { dismiss(sleeve.layer) }
        for sleeve in pile {
            if sleeve.layer.superlayer == nil {
                add(sleeve, to: Plan.stack[sleeve.slot])
            } else if sleeve.layer === wasPlaying?.layer, isLaidOut {
                carry(sleeve.layer, to: Plan.stack[sleeve.slot])
            }
        }
        if arriving.layer.superlayer == nil {
            add(arriving, to: Plan.sleeve, slidingFrom: wasPlaying == nil ? nil : CGPoint(x: -54, y: 0))
        }
        restack()
        guard isLaidOut else { return }
        crossfade(disc, over: 0.6)
        crossfade(desk, over: 1.4)
        crossfade(caption, over: 0.6)
        withoutAnimation {
            drawDisc()
            drawDesk()
            drawCaption()
        }
    }

    /// Puts each sleeve at its height in the pile, except one still being carried there.
    private func restack() {
        for (level, sleeve) in pile.enumerated() where sleeve.layer.animation(forKey: "journey") == nil {
            sleeve.layer.zPosition = Level.pile + CGFloat(level)
        }
        playing?.layer.zPosition = Level.playing
    }

    /// Lays a new sleeve on the desk. Given an offset, it fades in while sliding from there.
    private func add(_ sleeve: Sleeve, to slot: Plan.Slot, slidingFrom offset: CGPoint? = nil) {
        layer.addSublayer(sleeve.layer)
        guard isLaidOut else { return }
        withoutAnimation {
            draw(sleeve)
            settle(sleeve.layer, into: slot)
        }
        guard let offset else { return }
        let slide = CABasicAnimation(keyPath: "position")
        slide.fromValue = point(CGPoint(x: slot.center.x + offset.x, y: slot.center.y + offset.y))
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        let arrival = CAAnimationGroup()
        arrival.animations = [slide, fade]
        arrival.duration = 0.75
        arrival.beginTime = sleeve.layer.convertTime(CACurrentMediaTime(), from: nil) + 0.25
        arrival.fillMode = .backwards
        arrival.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        sleeve.layer.add(arrival, forKey: "arrival")
    }

    /// Picks a sleeve up, carries it over the deck and lays it on the pile.
    private func carry(_ sleeve: CALayer, to slot: Plan.Slot) {
        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = sleeve.presentation()?.position ?? sleeve.position
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = sleeve.value(forKeyPath: "transform.rotation.z")
        let lift = CAKeyframeAnimation(keyPath: "transform.scale")
        lift.values = [1, 1.06, 1]
        lift.keyTimes = [0, 0.45, 1]
        let journey = CAAnimationGroup()
        journey.animations = [move, turn, lift]
        journey.duration = 1
        journey.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.2, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in self?.restack() }
        sleeve.zPosition = Level.carried
        settle(sleeve, into: slot)
        sleeve.add(journey, forKey: "journey")
        CATransaction.commit()
    }

    private func dismiss(_ sleeve: CALayer) {
        guard isLaidOut else { return sleeve.removeFromSuperlayer() }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.5)
        CATransaction.setCompletionBlock { sleeve.removeFromSuperlayer() }
        sleeve.opacity = 0
        CATransaction.commit()
    }

    func setSpinning(_ spinning: Bool) {
        guard spinning != self.spinning else { return }
        self.spinning = spinning
        // 33⅓ rpm, clockwise. The platter takes a moment to get up to speed and to stop, and
        // under steady acceleration covers half the ground it would at full speed.
        let period: CFTimeInterval = 1.8
        let rampTime: CFTimeInterval = spinning ? 0.9 : 1.4
        let rotation = "transform.rotation.z"
        let start = ((disc.presentation() ?? disc).value(forKeyPath: rotation) as? NSNumber)?.doubleValue ?? 0
        let end = start - .pi * rampTime / period
        let now = disc.convertTime(CACurrentMediaTime(), from: nil)
        disc.removeAnimation(forKey: "ramp")
        disc.removeAnimation(forKey: "spin")

        let ramp = CABasicAnimation(keyPath: rotation)
        ramp.fromValue = start
        ramp.toValue = end
        ramp.duration = rampTime
        ramp.beginTime = now
        ramp.timingFunction = spinning ? CAMediaTimingFunction(controlPoints: 1 / 3, 0, 2 / 3, 1 / 3)
            : CAMediaTimingFunction(controlPoints: 1 / 3, 2 / 3, 2 / 3, 1)
        // Held at its end so there is no gap before the steady turn takes over.
        ramp.fillMode = .forwards
        ramp.isRemovedOnCompletion = false
        withoutAnimation { disc.setValue(end, forKeyPath: rotation) }
        disc.add(ramp, forKey: "ramp")
        guard spinning else { return }

        let spin = CABasicAnimation(keyPath: rotation)
        spin.fromValue = end
        spin.toValue = end - 2 * .pi
        spin.duration = period
        spin.beginTime = now + rampTime
        spin.repeatCount = .infinity
        // Smooth enough for a slow turn without asking a fast display for every frame.
        spin.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        disc.add(spin, forKey: "spin")
    }

    func setArm(angle: Double, lifted: Bool, duration: TimeInterval) {
        armAngle = angle
        armLifted = lifted
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setDisableActions(duration == 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        positionArm()
        CATransaction.commit()
    }

    private func positionArm() {
        let turn = Self.turn(CGFloat(armAngle))
        // Lifted, the arm comes a touch closer and its shadow falls further off and fainter.
        arm.transform = armLifted ? CATransform3DScale(turn, 1.012, 1.012, 1) : turn
        armShadow.transform = turn
        let fall = armLifted ? CGPoint(x: 6.5, y: 11) : CGPoint(x: 2.2, y: 3.8)
        armShadow.position = point(CGPoint(x: Plan.pivot.x + fall.x, y: Plan.pivot.y + fall.y))
        armShadow.opacity = armLifted ? 0.36 : 0.55
    }

    func setVolume(_ volume: Double) {
        self.volume = volume
        withoutAnimation { positionFader() }
    }

    private func positionFader() {
        let travel = Plan.faderBottom - Plan.faderTop
        fader.position = point(CGPoint(x: Plan.faderX, y: Plan.faderBottom - travel * CGFloat(volume) / 100))
    }

    // MARK: Pointer

    /// What lies under a point given in the layer's coordinates.
    func part(at point: CGPoint) -> Plan.Part? {
        Plan.part(at: onDesk(point), armAngle: armAngle, pileIsEmpty: pile.isEmpty)
    }

    /// The swing that would point the arm at a point given in the layer's coordinates.
    func armAngle(toward point: CGPoint) -> Double {
        Plan.armAngle(toward: onDesk(point))
    }

    /// How far the fader moves between silent and full volume, in points.
    var faderTravel: CGFloat { (Plan.faderBottom - Plan.faderTop) * zoom }
}
