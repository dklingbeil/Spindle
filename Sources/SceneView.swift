import AppKit
import Combine

/// Shows the desk, keeps it in step with the player, and turns pointer input into playback controls.
///
/// Pointer input arrives through the `pointer…` methods rather than only AppKit's own mouse
/// events, because in wallpaper mode the window sits behind the desktop icons and never
/// receives clicks; the app delegate forwards desktop clicks here instead.
final class SceneView: NSView {
    /// Space taken up by the menu bar and Dock in wallpaper mode, which the desk keeps clear of.
    var insets = NSEdgeInsets() { didSet { needsLayout = true } }

    private enum Gesture {
        case click(Plan.Part)
        /// `offset` is how far the arm's angle is from the pointer's, so the arm doesn't jump when grabbed.
        case arm(start: CGPoint, moved: Bool, offset: Double)
        case fader(startY: CGFloat, startVolume: Double)
    }

    private let stage = Stage()
    private let prefs: Preferences
    private let player: Player
    private var gesture: Gesture?
    private var armTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(prefs: Preferences, player: Player) {
        self.prefs = prefs
        self.player = player
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        layer?.addSublayer(stage.layer)

        prefs.$theme.sink { [weak self] in self?.stage.apply($0) }.store(in: &cancellables)
        player.$volume.sink { [weak self] in self?.stage.setVolume($0) }.store(in: &cancellables)
        player.$track.sink { [weak self] track in
            self?.stage.setTrack(title: track?.title ?? "", artist: track?.artist ?? "")
        }.store(in: &cancellables)
        // Deferred a turn so the player's other properties have settled before they are read:
        // a new cover and the pile it joins change one after the other.
        player.$artwork.combineLatest(player.$history).receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.stage.setCovers(playing: self.player.artwork, history: self.player.history)
        }.store(in: &cancellables)
        player.$isPlaying.receive(on: RunLoop.main).sink { [weak self] playing in
            self?.stage.setSpinning(playing)
            self?.refreshArm(duration: 1.1)
        }.store(in: &cancellables)
        stage.setCovers(playing: player.artwork, history: player.history)

        armTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.player.isPlaying else { return }
            self.refreshArm(duration: 0.5)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.layer.frame = bounds
        CATransaction.commit()
        stage.layout(size: bounds.size, insets: insets, backingScale: window?.backingScaleFactor ?? 2)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    /// The arm tracks the song across the record while it plays and returns to its rest otherwise.
    private func refreshArm(duration: TimeInterval) {
        if case .arm(_, true, _) = gesture { return }
        if player.isPlaying {
            let span = Plan.leadOutAngle - Plan.leadInAngle
            let angle = Plan.leadInAngle + (player.progress ?? 0.1) * span
            stage.setArm(angle: angle, lifted: false, duration: duration)
        } else {
            stage.setArm(angle: 0, lifted: true, duration: duration)
        }
    }

    // MARK: Pointer input, in this view's coordinates

    /// Returns whether the pointer landed on something interactive.
    @discardableResult
    func pointerDown(at point: CGPoint) -> Bool {
        switch stage.part(at: point) {
        case .arm:
            gesture = .arm(start: point, moved: false, offset: stage.armAngle - stage.armAngle(toward: point))
        case .fader:
            gesture = .fader(startY: point.y, startVolume: player.volume)
        case .record:
            gesture = .click(.record)
        case .button:
            gesture = .click(.button)
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
        case .arm(let start, let moved, let offset):
            guard moved || hypot(point.x - start.x, point.y - start.y) > 3 else { return }
            let angle = min(max(stage.armAngle(toward: point) + offset, 0), Plan.maxArmAngle)
            // In the hand, the arm is off the record.
            stage.setArm(angle: angle, lifted: true, duration: 0)
            gesture = .arm(start: start, moved: true, offset: offset)
        case .fader(let startY, let startVolume):
            // The fader travels a fixed distance on the desk, so a drag moves it by the same amount.
            player.setVolume(startVolume + Double((point.y - startY) / stage.faderTravel) * 100)
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
        case .arm(_, true, _):
            // Set down short of the record, the arm goes back to its rest and the music stops.
            let angle = stage.armAngle
            if angle < Plan.leadInAngle - 2 {
                player.pause()
            } else {
                let span = Plan.leadOutAngle - Plan.leadInAngle
                player.seek(toFraction: (angle - Plan.leadInAngle) / span)
            }
            refreshArm(duration: 0.6)
        case .click(let pressed):
            guard stage.part(at: point) == pressed else { return }
            switch pressed {
            case .record, .button: player.togglePlayPause()
            case .sleeve: player.next()
            case .stack: player.previous()
            default: break
            }
        case .fader, nil:
            break
        }
    }

    /// Scrolling anywhere over the turntable moves the volume fader.
    func scrolled(at point: CGPoint, deltaY: CGFloat) {
        switch stage.part(at: point) {
        case .fader, .deck, .record, .arm, .button:
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
