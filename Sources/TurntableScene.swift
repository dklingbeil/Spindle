import SceneKit

/// The 3D model. Everything is in centimetres, the desk surface is y = 0,
/// and the camera looks down the -z axis.
final class TurntableScene {
    /// The pieces that respond to the pointer; each is the `name` of a node.
    enum Part: String {
        case deck, record, arm, knob, sleeve, stack
    }

    /// Degrees the arm swings in from its rest: where the stylus meets the first and last groove.
    static let leadInAngle = 29.0
    static let leadOutAngle = 50.4
    static let maxArmAngle = 53.0

    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let room = SCNNode()
    private let shadowCatcher = SCNNode()
    private let sun = SCNNode()
    private let lampLight = SCNNode()
    private let lampGlow = SCNNode()
    private let ambient = SCNNode()
    private let disc = SCNNode()
    private let sheen = SCNNode()
    private let armPivot = SCNNode()
    private let armTilt = SCNNode()
    private let knob = SCNNode()
    private let labelMaterial = TurntableScene.material(Textures.defaultLabel, roughness: 0.7)
    private let sleeveMaterial = TurntableScene.material(Textures.defaultSleeve, roughness: 0.45)
    private let shadeMaterial = TurntableScene.material(NSColor(red: 0.82, green: 0.74, blue: 0.60, alpha: 1), roughness: 0.9)
    private var stackSleeves: [SCNNode] = []
    private var sunIntensity: CGFloat = 0

    private let plinthTop: CGFloat = 6.1
    private let recordTop: CGFloat = 9.15
    private let platterCenter = (x: CGFloat(-5.5), z: CGFloat(0))
    private let pivot = (x: CGFloat(16.5), z: CGFloat(-10.5))
    private let armLength: CGFloat = 23
    private let lampPosition = SCNVector3(56, 0, -24)

    init() {
        scene.lightingEnvironment.contents = Textures.file("brown_photostudio_02_1k", "hdr")
        buildRoom()
        buildTurntable()
        buildTonearm()
        buildSleeveStand()
        buildStack()
        buildLamp()
        buildLights()

        let camera = SCNCamera()
        camera.fieldOfView = 32
        camera.zNear = 10
        camera.zFar = 800
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -3.1
        camera.bloomThreshold = 1.0
        camera.bloomIntensity = 0.18
        camera.bloomBlurRadius = 10
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 46, 138)
        cameraNode.look(at: SCNVector3(0, 7, 0))
        scene.rootNode.addChildNode(cameraNode)

        setArm(angle: 0, lifted: true, duration: 0)
    }

    // MARK: Updates

    func apply(_ theme: SceneTheme) {
        let night = theme == .midnight
        room.isHidden = theme == .bare
        shadowCatcher.isHidden = theme != .bare
        scene.background.contents = theme == .bare ? NSColor.clear : NSColor.black

        sun.isHidden = night
        // Without the blinds in front of it the same light is far brighter.
        sun.light?.gobo?.contents = theme == .daylight ? Textures.blinds : nil
        sun.light?.intensity = sunIntensity * (theme == .daylight ? 1 : 0.6)
        lampLight.isHidden = !night
        lampGlow.isHidden = !night
        shadeMaterial.emission.contents = night ? NSColor(red: 1, green: 0.72, blue: 0.42, alpha: 1) : NSColor.black
        shadeMaterial.emission.intensity = 2.2
        ambient.light?.intensity = night ? 20 : 50
        ambient.light?.color = night ? NSColor(red: 0.5, green: 0.6, blue: 1, alpha: 1) : NSColor.white
        scene.lightingEnvironment.intensity = night ? 0.06 : 0.45
        sheen.opacity = night ? 0.4 : 1

    }

    func setArtwork(_ image: NSImage?) {
        labelMaterial.diffuse.contents = image ?? Textures.defaultLabel
        sleeveMaterial.diffuse.contents = image ?? Textures.defaultSleeve
    }

    /// `covers` is newest first; the newest ends up on top of the pile.
    func setHistory(_ covers: [NSImage]) {
        for (level, sleeve) in stackSleeves.enumerated() {
            let index = covers.count - 1 - level
            sleeve.isHidden = index < 0
            if index >= 0 { sleeve.geometry?.materials[4].diffuse.contents = covers[index] }
        }
    }

    func setSpinning(_ spinning: Bool) {
        if spinning {
            guard disc.action(forKey: "spin") == nil else { return }
            // 33⅓ rpm, clockwise seen from above.
            disc.runAction(.repeatForever(.rotateBy(x: 0, y: -2 * .pi, z: 0, duration: 1.8)), forKey: "spin")
        } else {
            disc.removeAction(forKey: "spin")
        }
    }

    func setArm(angle: Double, lifted: Bool, duration: TimeInterval) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration
        armPivot.eulerAngles.y = -CGFloat(angle) * .pi / 180
        armTilt.eulerAngles.x = lifted ? -0.065 : 0
        SCNTransaction.commit()
    }

    func setVolume(_ volume: Double) {
        knob.eulerAngles.y = -CGFloat(volume / 100 - 0.5) * 1.5 * .pi
    }

    /// The arm angle that would put the stylus under a pointer ray, found where the ray meets the record's surface.
    func armAngle(from near: SCNVector3, to far: SCNVector3) -> Double? {
        guard far.y != near.y else { return nil }
        let t = (recordTop - near.y) / (far.y - near.y)
        let x = near.x + (far.x - near.x) * t
        let z = near.z + (far.z - near.z) * t
        let degrees = Double(atan2(-(x - pivot.x), z - pivot.z)) * 180 / .pi
        return min(max(degrees, 0), Self.maxArmAngle)
    }

    static func part(of node: SCNNode?) -> Part? {
        var current = node
        while let candidate = current {
            if let part = candidate.name.flatMap(Part.init) { return part }
            current = candidate.parent
        }
        return nil
    }

    // MARK: Materials

    private static func material(_ contents: Any?, metalness: Double = 0, roughness: Double = 0.6) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = contents
        material.metalness.contents = NSNumber(value: metalness)
        material.roughness.contents = NSNumber(value: roughness)
        return material
    }

    /// A photo-scanned surface: colour, bumps and shine each come from their own image, tiled `repeats` times.
    private static func scanned(_ name: String, repeats: (x: CGFloat, y: CGFloat) = (1, 1),
                                quarterTurn: Bool = false) -> SCNMaterial {
        let material = material(Textures.file(name + "_diff"))
        material.normal.contents = Textures.file(name + "_nor")
        material.roughness.contents = Textures.file(name + "_rough")
        for property in [material.diffuse, material.normal, material.roughness] {
            property.wrapS = .repeat
            property.wrapT = .repeat
            property.mipFilter = .linear
            property.maxAnisotropy = 16
            let scale = SCNMatrix4MakeScale(repeats.x, repeats.y, 1)
            property.contentsTransform = quarterTurn ? SCNMatrix4Mult(scale, SCNMatrix4MakeRotation(.pi / 2, 0, 0, 1)) : scale
        }
        return material
    }

    private static let chrome = material(NSColor(white: 0.95, alpha: 1), metalness: 1, roughness: 0.12)
    private static let aluminium = material(NSColor(white: 0.88, alpha: 1), metalness: 1, roughness: 0.3)
    private static let satinBlack = material(NSColor(white: 0.035, alpha: 1), roughness: 0.38)
    private static let rubber = material(NSColor(white: 0.025, alpha: 1), roughness: 0.85)
    private static let brass = material(NSColor(red: 0.86, green: 0.68, blue: 0.36, alpha: 1), metalness: 1, roughness: 0.24)
    private static let card = material(NSColor(white: 0.92, alpha: 1), roughness: 0.75)
    private static let oak = scanned("oak_veneer_01")

    // MARK: Construction

    @discardableResult
    private func add(_ geometry: SCNGeometry, _ materials: [SCNMaterial], x: CGFloat = 0, y: CGFloat = 0,
                     z: CGFloat = 0, to parent: SCNNode) -> SCNNode {
        geometry.materials = materials
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(x, y, z)
        parent.addChildNode(node)
        return node
    }

    private func box(_ width: CGFloat, _ height: CGFloat, _ length: CGFloat, chamfer: CGFloat) -> SCNBox {
        let box = SCNBox(width: width, height: height, length: length, chamferRadius: chamfer)
        box.chamferSegmentCount = 8
        return box
    }

    private func buildRoom() {
        scene.rootNode.addChildNode(room)
        add(SCNBox(width: 600, height: 6, length: 150, chamferRadius: 0),
            [Self.scanned("wood_table_001", repeats: (4, 1), quarterTurn: true)], y: -3, z: 30, to: room)
        add(SCNPlane(width: 600, height: 300),
            [Self.scanned("beige_wall_001", repeats: (3, 1.5))], y: 140, z: -45, to: room)

        // On the user's own wallpaper there is no desk, so shadows land on an otherwise invisible floor.
        let floor = SCNMaterial()
        floor.lightingModel = .shadowOnly
        let plane = add(SCNPlane(width: 400, height: 250), [floor], y: 0.02, z: 20, to: shadowCatcher)
        plane.eulerAngles.x = -.pi / 2
        scene.rootNode.addChildNode(shadowCatcher)
    }

    private func buildTurntable() {
        let deck = SCNNode()
        deck.name = Part.deck.rawValue
        scene.rootNode.addChildNode(deck)

        // Three turned feet: a rubber pad under a tapered aluminium cone.
        for (x, z) in [(-17.0, 12.5), (17.0, 12.5), (0.0, -13.0)] {
            add(Lathe.geometry([(2.3, 0), (2.3, 0.35), (2.0, 0.4), (0, 0.4)], segments: 48),
                [Self.rubber], x: x, z: z, to: deck)
            add(Lathe.geometry([(2.0, 0.4), (2.6, 1.5), (2.6, 1.65), (0, 1.65)], segments: 48),
                [Self.aluminium], x: x, z: z, to: deck)
        }
        add(box(44, 4.5, 35, chamfer: 0.9), [Self.oak], y: plinthTop - 2.25, to: deck)

        let platter = SCNNode()
        platter.name = Part.record.rawValue
        platter.position = SCNVector3(platterCenter.x, 0, platterCenter.z)
        deck.addChildNode(platter)
        add(Lathe.geometry([(4, plinthTop), (4, plinthTop + 0.35), (0, plinthTop + 0.35)], segments: 48),
            [Self.satinBlack], to: platter)
        // A heavy platter with a polished rim and a groove turned into its edge.
        let platterBottom = plinthTop + 0.35
        add(Lathe.geometry([
            (14.6, platterBottom), (15.2, platterBottom + 0.5), (15.2, platterBottom + 1.0),
            (15.05, platterBottom + 1.1), (15.05, platterBottom + 1.25), (15.2, platterBottom + 1.35),
            (15.2, platterBottom + 2.15), (15.05, platterBottom + 2.35), (14.8, platterBottom + 2.45),
            (0, platterBottom + 2.45),
        ]), [Self.aluminium], to: platter)
        add(Lathe.geometry(Lathe.disc(radius: 14.75, bottom: platterBottom + 2.45, top: recordTop - 0.2, bevel: 0.06)),
            [Self.rubber], to: platter)

        disc.position = SCNVector3(0, recordTop - 0.1, 0)
        platter.addChildNode(disc)
        let vinylEdge = Self.material(NSColor(white: 0.015, alpha: 1), roughness: 0.2)
        let vinylFace = Self.material(Textures.grooves)
        vinylFace.roughness.contents = Textures.grooveRoughness
        let vinyl = SCNCylinder(radius: 15, height: 0.2)
        vinyl.radialSegmentCount = 128
        add(vinyl, [vinylEdge, vinylFace, vinylEdge], to: disc)
        let label = SCNCylinder(radius: 5, height: 0.03)
        label.radialSegmentCount = 64
        add(label, [Self.card, labelMaterial, Self.card], y: 0.1, to: disc)

        let glint = SCNMaterial()
        glint.lightingModel = .constant
        glint.diffuse.contents = Textures.sheen
        glint.blendMode = .add
        glint.writesToDepthBuffer = false
        sheen.geometry = SCNPlane(width: 30, height: 30)
        sheen.geometry?.materials = [glint]
        sheen.eulerAngles.x = -.pi / 2
        sheen.position = SCNVector3(0, recordTop + 0.03, 0)
        sheen.castsShadow = false
        platter.addChildNode(sheen)

        add(Lathe.geometry([(0.36, recordTop), (0.36, recordTop + 0.75), (0.2, recordTop + 0.95), (0, recordTop + 0.95)],
                           segments: 24), [Self.chrome], to: platter)

        knob.name = Part.knob.rawValue
        knob.position = SCNVector3(-19, plinthTop, 14.2)
        deck.addChildNode(knob)
        add(Lathe.geometry([(1.75, 0), (1.75, 0.25), (1.5, 0.3), (1.5, 1.35), (1.35, 1.5), (0, 1.5)], segments: 48),
            [Self.aluminium], to: knob)
        add(SCNCylinder(radius: 0.16, height: 0.04),
            [Self.material(NSColor(red: 0.95, green: 0.4, blue: 0.12, alpha: 1), roughness: 0.4)],
            y: 1.51, z: -0.95, to: knob)

        // Speed buttons, front right.
        for x in [13.5, 16.5] as [CGFloat] {
            add(Lathe.geometry([(0.85, 0), (0.85, 0.3), (0.75, 0.4), (0, 0.4)], segments: 32),
                [Self.satinBlack], x: x, y: plinthTop, z: 14.6, to: deck)
        }
    }

    /// Built pointing at the viewer (+z) from its pivot, which is where it rests.
    private func buildTonearm() {
        let pivotHeight = recordTop + 1.15 - plinthTop
        let base = SCNNode()
        base.position = SCNVector3(pivot.x, plinthTop, pivot.z)
        scene.rootNode.addChildNode(base)
        add(Lathe.geometry([(2.5, 0), (2.5, 0.3), (2.2, 0.5), (1.7, 0.6), (1.7, pivotHeight - 1.0),
                            (1.5, pivotHeight - 0.85), (0, pivotHeight - 0.85)], segments: 48),
            [Self.aluminium], to: base)
        // The rest the arm parks on, and the cueing lever beside the pillar.
        add(SCNCylinder(radius: 0.38, height: pivotHeight), [Self.aluminium], y: pivotHeight / 2, z: 15, to: base)
        add(box(2.0, 0.7, 1.1, chamfer: 0.2), [Self.satinBlack], y: pivotHeight + 0.2, z: 15, to: base)
        let lever = add(SCNCapsule(capRadius: 0.22, height: 3.4), [Self.satinBlack], x: 3.4, y: 1.4, z: 1.5, to: base)
        lever.eulerAngles = SCNVector3(CGFloat.pi / 2 - 0.5, 0, 0)

        armPivot.name = Part.arm.rawValue
        armPivot.position = SCNVector3(0, pivotHeight, 0)
        base.addChildNode(armPivot)
        add(Lathe.geometry([(1.45, -0.8), (1.6, -0.6), (1.6, 0.6), (1.45, 0.8), (0, 0.8)], segments: 48),
            [Self.satinBlack], to: armPivot)
        add(Lathe.geometry([(0.6, 0.8), (0.6, 1.0), (0.45, 1.1), (0, 1.1)], segments: 24), [Self.chrome], to: armPivot)
        armPivot.addChildNode(armTilt)

        let lengthwise = SCNVector3(CGFloat.pi / 2, 0, 0)
        // A tapered tube, a stub out the back for the counterweight, and the turned weight itself.
        add(SCNCone(topRadius: 0.27, bottomRadius: 0.44, height: armLength - 1), [Self.satinBlack],
            z: (armLength - 1) / 2, to: armTilt).eulerAngles = lengthwise
        add(SCNCylinder(radius: 0.3, height: 7), [Self.chrome], z: -3.5, to: armTilt).eulerAngles = lengthwise
        add(Lathe.geometry([(1.3, -1.7), (1.55, -1.45), (1.55, 1.45), (1.3, 1.7), (0, 1.7)], segments: 48),
            [Self.aluminium], z: -5.2, to: armTilt).eulerAngles = lengthwise
        add(Lathe.geometry([(1.3, -1.7), (0, -1.7)], segments: 48), [Self.aluminium], z: -5.2, to: armTilt)
            .eulerAngles = SCNVector3(-CGFloat.pi / 2, 0, 0)

        add(box(1.7, 0.22, 3.8, chamfer: 0.1), [Self.aluminium], y: -0.05, z: armLength - 0.4, to: armTilt)
        add(box(1.25, 0.8, 2.0, chamfer: 0.12),
            [Self.material(NSColor(red: 0.62, green: 0.1, blue: 0.07, alpha: 1), roughness: 0.3)],
            y: -0.55, z: armLength, to: armTilt)
        add(SCNCone(topRadius: 0.1, bottomRadius: 0.02, height: 0.25), [Self.chrome], y: -1.05, z: armLength, to: armTilt)
        add(SCNCapsule(capRadius: 0.11, height: 2.6), [Self.chrome], x: 1.5, y: 0.1, z: armLength + 1.1, to: armTilt)
            .eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2 - 0.25)

        // The arm itself is too thin to grab; this invisible block around it takes the pointer instead.
        let ghost = SCNMaterial()
        ghost.colorBufferWriteMask = []
        ghost.writesToDepthBuffer = false
        add(SCNBox(width: 4.5, height: 3, length: armLength + 10, chamferRadius: 0), [ghost],
            z: (armLength - 4) / 2, to: armTilt).castsShadow = false
    }

    private func buildSleeveStand() {
        let stand = SCNNode()
        stand.name = Part.sleeve.rawValue
        stand.position = SCNVector3(-46, 0, -6)
        stand.eulerAngles.y = 0.22
        scene.rootNode.addChildNode(stand)
        add(box(35, 1.8, 8, chamfer: 0.5), [Self.oak], y: 0.9, to: stand)

        let lean = SCNNode()
        lean.position = SCNVector3(0, 1.5, 0.6)
        lean.eulerAngles.x = -0.2
        stand.addChildNode(lean)
        add(SCNBox(width: 31.5, height: 31.5, length: 0.4, chamferRadius: 0.06),
            [sleeveMaterial, Self.card, Self.card, Self.card, Self.card, Self.card], y: 15.75, to: lean)
    }

    private func buildStack() {
        let stack = SCNNode()
        stack.name = Part.stack.rawValue
        stack.position = SCNVector3(41, 0, 10)
        scene.rootNode.addChildNode(stack)

        // A record half out of a plain sleeve is always there, so "previous" has something
        // to click before any history exists.
        let kraft = Self.material(NSColor(red: 0.66, green: 0.53, blue: 0.38, alpha: 1), roughness: 0.9)
        let spare = SCNCylinder(radius: 15, height: 0.2)
        spare.radialSegmentCount = 96
        let spareFace = Self.material(Textures.grooves)
        spareFace.roughness.contents = Textures.grooveRoughness
        add(spare, [Self.rubber, spareFace, Self.rubber], x: -9, y: 0.1, z: 3, to: stack)
        add(SCNBox(width: 31.5, height: 0.3, length: 31.5, chamferRadius: 0.05), [kraft], y: 0.36, to: stack)
            .eulerAngles.y = 0.12

        for (level, turn) in [-0.16, 0.2, -0.05].enumerated() {
            let art = Self.material(NSColor.white, roughness: 0.45)
            let sleeve = add(SCNBox(width: 31.5, height: 0.4, length: 31.5, chamferRadius: 0.06),
                             [Self.card, Self.card, Self.card, Self.card, art, Self.card],
                             y: 0.72 + CGFloat(level) * 0.42, to: stack)
            sleeve.eulerAngles.y = CGFloat(turn)
            sleeve.isHidden = true
            stackSleeves.append(sleeve)
        }
    }

    private func buildLamp() {
        let lamp = SCNNode()
        lamp.position = lampPosition
        room.addChildNode(lamp)
        add(Lathe.geometry([(7.5, 0), (7.5, 0.5), (7.0, 0.9), (3.0, 1.6), (1.6, 2.6), (1.0, 4.5), (0.7, 7),
                            (0.7, 25), (0, 25)], segments: 64), [Self.brass], to: lamp)
        shadeMaterial.isDoubleSided = true
        add(Lathe.geometry([(11.5, 21), (7.5, 35)], segments: 64), [shadeMaterial], to: lamp).castsShadow = false
    }

    private func buildLights() {
        // Physically based lights fall off with the square of distance, and at this scale they
        // are a long way off, so brightness is given as it should arrive at the deck.
        func spot(_ node: SCNNode, at position: SCNVector3, temperature: CGFloat, brightness: CGFloat, spread: CGFloat) {
            let target = SCNVector3(0, 8, 0)
            let distance = sqrt(pow(position.x - target.x, 2) + pow(position.y - target.y, 2) + pow(position.z - target.z, 2))
            let light = SCNLight()
            light.type = .spot
            light.temperature = temperature
            light.intensity = brightness * distance * distance
            light.spotInnerAngle = spread * 0.7
            light.spotOuterAngle = spread
            light.castsShadow = true
            light.shadowMapSize = CGSize(width: 4096, height: 4096)
            light.shadowSampleCount = 32
            light.shadowRadius = 8
            light.shadowColor = NSColor(white: 0, alpha: 0.65)
            light.zNear = 20
            light.zFar = 700
            node.light = light
            node.position = position
            node.look(at: target)
            scene.rootNode.addChildNode(node)
        }
        spot(sun, at: SCNVector3(-150, 180, 190), temperature: 5200, brightness: 95, spread: 55)
        sunIntensity = sun.light?.intensity ?? 0

        // At night the lamp does the work: a shadow-casting light from inside its shade,
        // plus a soft glow that reaches the wall behind it.
        let bulb = SCNVector3(lampPosition.x, 29, lampPosition.z)
        spot(lampLight, at: bulb, temperature: 3000, brightness: 34, spread: 150)
        lampLight.light?.spotInnerAngle = 60
        let glow = SCNLight()
        glow.type = .omni
        glow.temperature = 2900
        glow.intensity = 12 * 60 * 60
        lampGlow.light = glow
        lampGlow.position = bulb
        scene.rootNode.addChildNode(lampGlow)

        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        scene.rootNode.addChildNode(ambient)
    }
}
