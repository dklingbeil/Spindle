import Combine
import SceneKit

/// Shows the scene, keeps it in step with the player, and turns pointer input into playback controls.
///
/// Pointer input arrives through the `pointer…` methods rather than only AppKit's own mouse
/// events, because in wallpaper mode the window sits behind the desktop icons and never
/// receives clicks; the app delegate forwards desktop clicks here instead.
final class SceneView: SCNView {
    /// Space to leave under the caption, so the Dock doesn't cover it in wallpaper mode.
    var captionInset: CGFloat = 14 { didSet { needsLayout = true } }

    private enum Gesture {
        case click(TurntableScene.Part)
        case arm(start: CGPoint, moved: Bool, angle: Double)
        case knob(startY: CGFloat, startVolume: Double)
    }

    private let stage = TurntableScene()
    private let prefs: Preferences
    private let player: Player
    private let caption = NSTextField(labelWithString: "")
    private var gesture: Gesture?
    private var armTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(prefs: Preferences, player: Player) {
        self.prefs = prefs
        self.player = player
        super.init(frame: .zero, options: nil)
        scene = stage.scene
        pointOfView = stage.cameraNode
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 30

        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.7)
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        caption.shadow = shadow
        caption.textColor = NSColor(white: 1, alpha: 0.92)
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingTail
        let font = NSFont.systemFont(ofSize: 15, weight: .medium)
        caption.font = font.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: 15) } ?? font
        addSubview(caption)

        prefs.$theme.sink { [weak self] theme in
            self?.stage.apply(theme)
            self?.backgroundColor = theme == .bare ? .clear : .black
        }.store(in: &cancellables)
        player.$artwork.sink { [weak self] in self?.stage.setArtwork($0) }.store(in: &cancellables)
        player.$history.sink { [weak self] in self?.stage.setHistory($0) }.store(in: &cancellables)
        player.$volume.sink { [weak self] in self?.stage.setVolume($0) }.store(in: &cancellables)
        player.$track.sink { [weak self] track in
            self?.caption.stringValue = track.map { "\($0.title)  ·  \($0.artist)" } ?? ""
            self?.needsLayout = true
        }.store(in: &cancellables)
        // Deferred a turn so the player's other properties have settled before they are read.
        player.$isPlaying.receive(on: RunLoop.main).sink { [weak self] playing in
            self?.stage.setSpinning(playing)
            self?.refreshArm(duration: 1.1)
        }.store(in: &cancellables)

        armTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.player.isPlaying else { return }
            self.refreshArm(duration: 0.5)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        caption.sizeToFit()
        let width = min(caption.frame.width, bounds.width - 40)
        caption.frame = NSRect(x: (bounds.width - width) / 2, y: captionInset, width: width, height: caption.frame.height)
    }

    /// The arm tracks the song across the record while it plays and returns to its rest otherwise.
    private func refreshArm(duration: TimeInterval) {
        if case .arm(_, true, _) = gesture { return }
        if player.isPlaying {
            let span = TurntableScene.leadOutAngle - TurntableScene.leadInAngle
            let angle = TurntableScene.leadInAngle + (player.progress ?? 0.1) * span
            stage.setArm(angle: angle, lifted: false, duration: duration)
        } else {
            stage.setArm(angle: 0, lifted: true, duration: duration)
        }
    }

    private func part(at point: CGPoint) -> TurntableScene.Part? {
        TurntableScene.part(of: hitTest(point, options: nil).first?.node)
    }

    // MARK: Pointer input, in this view's coordinates

    /// Returns whether the pointer landed on something interactive.
    @discardableResult
    func pointerDown(at point: CGPoint) -> Bool {
        switch part(at: point) {
        case .arm:
            gesture = .arm(start: point, moved: false, angle: 0)
        case .knob:
            gesture = .knob(startY: point.y, startVolume: player.volume)
        case .record:
            gesture = .click(.record)
        case .sleeve:
            gesture = .click(.sleeve)
        case .stack:
            gesture = .click(.stack)
        case .deck, nil:
            gesture = nil
        }
        return gesture != nil
    }

    func pointerDragged(to point: CGPoint) {
        switch gesture {
        case .arm(let start, let moved, let lastAngle):
            guard moved || hypot(point.x - start.x, point.y - start.y) > 3 else { return }
            let near = unprojectPoint(SCNVector3(point.x, point.y, 0))
            let far = unprojectPoint(SCNVector3(point.x, point.y, 1))
            let angle = stage.armAngle(from: near, to: far) ?? lastAngle
            stage.setArm(angle: angle, lifted: false, duration: 0)
            gesture = .arm(start: start, moved: true, angle: angle)
        case .knob(let startY, let startVolume):
            player.setVolume(startVolume + Double(point.y - startY) * 0.6)
        case .click, nil:
            break
        }
    }

    func pointerUp(at point: CGPoint) {
        let finished = gesture
        gesture = nil
        switch finished {
        case .arm(_, false, _):
            player.togglePlayPause()
        case .arm(_, true, let angle):
            // Set down short of the record, the arm goes back to its rest and the music stops.
            if angle < TurntableScene.leadInAngle - 2 {
                player.pause()
            } else {
                let span = TurntableScene.leadOutAngle - TurntableScene.leadInAngle
                player.seek(toFraction: (angle - TurntableScene.leadInAngle) / span)
            }
            refreshArm(duration: 0.6)
        case .click(let pressed):
            guard part(at: point) == pressed else { return }
            switch pressed {
            case .record: player.togglePlayPause()
            case .sleeve: player.next()
            case .stack: player.previous()
            default: break
            }
        case .knob, nil:
            break
        }
    }

    /// Scrolling anywhere over the turntable turns the volume knob.
    func scrolled(at point: CGPoint, deltaY: CGFloat) {
        switch part(at: point) {
        case .knob, .deck, .record, .arm:
            player.setVolume(player.volume + Double(deltaY) * 0.5)
        case .sleeve, .stack, nil:
            break
        }
    }

    // MARK: AppKit events, used in window mode

    private func location(of event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseDown(with event: NSEvent) {
        if !pointerDown(at: location(of: event)) {
            window?.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) { pointerDragged(to: location(of: event)) }

    override func mouseUp(with event: NSEvent) { pointerUp(at: location(of: event)) }

    override func scrollWheel(with event: NSEvent) { scrolled(at: location(of: event), deltaY: event.scrollingDeltaY) }
}
