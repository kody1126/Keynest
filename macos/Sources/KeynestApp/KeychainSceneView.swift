import AppKit
import SceneKit
import SwiftUI

/// Small deterministic state used by the renderer and by headless checks.
/// It has no scene, display clock, credential or window dependency.
struct KeychainPendulumState: Sendable {
    var angle = 0.0
    var velocity = 0.0
    var extensionOffset = 0.0
    var radialVelocity = 0.0

    var energy: Double { abs(angle) + abs(velocity) + abs(extensionOffset) + abs(radialVelocity) }

    mutating func drag(toAngle targetAngle: Double, extension targetExtension: Double,
                       elapsed: Double, reduceMotion: Bool) {
        let dt = Self.bounded(elapsed, 1.0 / 240.0, 0.06)
        let oldAngle = angle, oldExtension = extensionOffset
        angle = Self.bounded(targetAngle, -0.85, 0.85)
        extensionOffset = Self.bounded(targetExtension, -0.28, 0.38)
        velocity = reduceMotion ? 0 : Self.bounded((angle - oldAngle) / dt, -4, 4)
        radialVelocity = reduceMotion ? 0 : Self.bounded((extensionOffset - oldExtension) / dt, -2, 2)
    }

    mutating func advance(length: Double, coupling: Double = 0, ringVelocity: Double = 0, elapsed: Double) {
        let dt = Self.bounded(elapsed, 0, 1.0 / 120.0)
        let length = Self.bounded(length, 0.5, 3)
        let acceleration = -11.5 * sin(angle) / length - 2.3 * velocity
            + Self.bounded(coupling, -3, 3) - Self.bounded(ringVelocity, -3, 3) * 0.7
        velocity = Self.bounded(velocity + acceleration * dt, -4, 4)
        angle = Self.bounded(angle + velocity * dt, -0.90, 0.90)
        radialVelocity = Self.bounded(radialVelocity + (-extensionOffset * 42 - radialVelocity * 9) * dt, -3, 3)
        extensionOffset = Self.bounded(extensionOffset + radialVelocity * dt, -0.28, 0.38)
    }

    mutating func stop() { velocity = 0; radialVelocity = 0 }
    mutating func reset() { self = Self() }
    mutating func release(idleElapsed: Double, reduceMotion: Bool) {
        // A pointer held still has no release momentum. Position is retained,
        // so ordinary gravity can still return the pendant naturally.
        if reduceMotion || !idleElapsed.isFinite || idleElapsed >= 0.12 { stop() }
    }

    private static func bounded(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value.isFinite ? value : 0))
    }
}

/// An entirely local, decorative object. It never receives credentials or
/// observes AppModel; its display clock cannot invalidate the Home catalog.
struct KeychainSceneView: View {
    var brandIDs: [String]
    var isActive: Bool
    var resetToken: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var accessibilityReset = 0

    init(brandIDs: [String] = ["openai", "anthropic", "google"],
         isActive: Bool = true, resetToken: Int = 0) {
        self.brandIDs = brandIDs
        self.isActive = isActive
        self.resetToken = resetToken
    }

    var body: some View {
        KeychainSceneSurface(brandIDs: brandIDs, isActive: isActive,
                             reduceMotion: reduceMotion, resetToken: resetToken,
                             accessibilityReset: accessibilityReset)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("装饰钥匙串")
            .accessibilityHint("可以拖动圆环或挂件；不会复制、修改或显示密钥。")
            .accessibilityAction(named: Text("复位钥匙串")) { accessibilityReset += 1 }
    }
}

private struct KeychainSceneSurface: NSViewRepresentable {
    let brandIDs: [String]
    let isActive: Bool
    let reduceMotion: Bool
    let resetToken: Int
    let accessibilityReset: Int

    func makeNSView(context: Context) -> KeychainRenderView {
        let view = KeychainRenderView(frame: .zero)
        view.configure(brandIDs: brandIDs, active: isActive, reduceMotion: reduceMotion,
                       resetToken: resetToken, accessibilityReset: accessibilityReset)
        return view
    }

    func updateNSView(_ view: KeychainRenderView, context: Context) {
        view.configure(brandIDs: brandIDs, active: isActive, reduceMotion: reduceMotion,
                       resetToken: resetToken, accessibilityReset: accessibilityReset)
    }

    static func dismantleNSView(_ view: KeychainRenderView, coordinator: ()) { view.shutDown() }
}

@MainActor private final class KeychainRenderView: SCNView {
    private struct Pendant {
        let pivot: SCNNode
        let charm: SCNNode
        let links: [SCNNode]
        let length: Double
        let yaw: Double
        var motion = KeychainPendulumState()
        var angle: Double { get { motion.angle } set { motion.angle = newValue } }
        var velocity: Double { get { motion.velocity } set { motion.velocity = newValue } }
        var extensionOffset: Double { get { motion.extensionOffset } set { motion.extensionOffset = newValue } }
        var radialVelocity: Double { get { motion.radialVelocity } set { motion.radialVelocity = newValue } }
    }
    private enum DragTarget { case ring, pendant(Int) }
    private let assembly = SCNNode()
    private let cameraNode = SCNNode()
    private var pendants: [Pendant] = []
    private var brands: [String] = []
    private var active = false
    private var reducedMotion = false
    private var lastReset: (Int, Int)?
    private var timer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private weak var observedClipView: NSClipView?
    private var dragTarget: DragTarget?
    private var dragDepth: CGFloat = 0
    private var grabOffset = SCNVector3Zero
    private var previousDragTime = 0.0
    private var lastTick = 0.0
    private var motionStarted = 0.0
    private var restTicks = 0
    private var ringPosition = SIMD2<Double>.zero
    private var ringVelocity = SIMD2<Double>.zero
    private var previousRingPosition = SIMD2<Double>.zero
    private var disposed = false

    override init(frame: NSRect, options: [String: Any]? = nil) {
        super.init(frame: frame, options: options)
        backgroundColor = .clear
        allowsCameraControl = false
        autoenablesDefaultLighting = false
        antialiasingMode = .multisampling4X
        preferredFramesPerSecond = 60
        rendersContinuously = false
        isPlaying = false
        scene = SCNScene()
        scene?.background.contents = NSColor.clear
        scene?.lightingEnvironment.contents = Self.environmentImage
        scene?.lightingEnvironment.intensity = 0.8
        scene?.rootNode.addChildNode(assembly)
        installCameraAndLights()
        setAccessibilityLabel("装饰钥匙串")
        setAccessibilityHelp("拖动圆环或挂件，仅作装饰，不执行密钥操作。")
        installNotifications()
    }

    required init?(coder: NSCoder) { nil }

    func configure(brandIDs: [String], active: Bool, reduceMotion: Bool,
                   resetToken: Int, accessibilityReset: Int) {
        guard !disposed else { return }
        // Names only select bundled images. Never accept file paths or URLs.
        let safeBrands = Array(brandIDs.filter {
            !$0.isEmpty && $0.utf8.count < 60 && $0.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains($0)
            }
        }.prefix(3))
        if brands != safeBrands || pendants.isEmpty {
            brands = safeBrands
            buildObjects()
        }
        self.active = active
        if reducedMotion != reduceMotion {
            reducedMotion = reduceMotion
            dragTarget = nil
            settle()
        }
        if lastReset?.0 != resetToken || lastReset?.1 != accessibilityReset {
            lastReset = (resetToken, accessibilityReset)
            resetPose()
        }
        if !canRun { cancelDrag(); stopClock() }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let aspect = max(0.25, bounds.width / max(1, bounds.height))
        cameraNode.camera?.orthographicScale = max(1.57, 2.30 / aspect)
        observeClipView()
        if !canRun { cancelDrag(); stopClock() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeClipView()
        if !canRun { cancelDrag(); stopClock() }
        needsDisplay = true
    }

    override func viewDidHide() { super.viewDidHide(); cancelDrag(); stopClock() }
    override func viewDidUnhide() { super.viewDidUnhide(); needsDisplay = true }
    override func resetCursorRects() {
        // A cursor affordance is local to the artwork, not the whole homepage.
        addCursorRect(bounds.insetBy(dx: bounds.width * 0.17, dy: 8), cursor: .openHand)
    }

    private var canRun: Bool {
        !disposed && active && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty &&
        window != nil && window?.occlusionState.contains(.visible) == true && NSApp.isActive
    }

    private func installNotifications() {
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSView.boundsDidChangeNotification] {
            notificationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let objectID = note.object.map { ObjectIdentifier($0 as AnyObject) }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name == NSWindow.didChangeOcclusionStateNotification,
                       objectID != self.window.map(ObjectIdentifier.init) { return }
                    if name == NSView.boundsDidChangeNotification,
                       objectID != self.observedClipView.map(ObjectIdentifier.init) { return }
                    if !self.canRun { self.cancelDrag(); self.stopClock() }
                    else { self.needsDisplay = true }
                }
            })
        }
    }

    private func observeClipView() {
        var ancestor = superview
        while let view = ancestor {
            if let clip = view as? NSClipView {
                observedClipView = clip
                // NSScrollView already posts these for its own bookkeeping.
                return
            }
            ancestor = view.superview
        }
        observedClipView = nil
    }

    func shutDown() {
        guard !disposed else { return }
        disposed = true
        dragTarget = nil
        stopClock()
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        notificationTokens.removeAll()
        scene = nil
    }

    private func startClock() {
        guard canRun, !reducedMotion else { return }
        if timer == nil {
            lastTick = ProcessInfo.processInfo.systemUptime
            motionStarted = lastTick
            restTicks = 0
            let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            scene?.isPaused = false
            isPlaying = true
            rendersContinuously = true
        }
    }

    private func stopClock() {
        timer?.invalidate(); timer = nil
        isPlaying = false
        rendersContinuously = false
        scene?.isPaused = true
        needsDisplay = true
    }

    private func cancelDrag() {
        if dragTarget != nil { NSCursor.arrow.set() }
        dragTarget = nil
    }

    private func settle() {
        ringVelocity = .zero
        for i in pendants.indices { pendants[i].velocity = 0; pendants[i].radialVelocity = 0 }
        stopClock()
    }

    private func resetPose() {
        dragTarget = nil
        ringPosition = .zero; ringVelocity = .zero
        for i in pendants.indices {
            pendants[i].angle = 0; pendants[i].velocity = 0
            pendants[i].extensionOffset = 0; pendants[i].radialVelocity = 0
        }
        applyPose()
        stopClock()
    }

    private func tick() {
        guard canRun, !reducedMotion else { stopClock(); return }
        let now = ProcessInfo.processInfo.systemUptime
        // Bounded substeps prevent a wake, debugger stop or delayed frame from
        // injecting a large impulse into the otherwise tiny simulation.
        let delta = min(1.0 / 30.0, max(0, now - lastTick))
        lastTick = now
        let steps = max(1, Int(ceil(delta / (1.0 / 120.0))))
        let dt = delta / Double(steps)
        for _ in 0..<steps { integrate(dt: dt) }
        applyPose()
        let energy = pendants.reduce(0.0) {
            $0 + abs($1.velocity) + abs($1.angle) + abs($1.radialVelocity) + abs($1.extensionOffset)
        } + abs(ringPosition.x) + abs(ringPosition.y) + abs(ringVelocity.x) + abs(ringVelocity.y)
        restTicks = dragTarget == nil && energy < 0.024 ? restTicks + 1 : 0
        if restTicks > 18 { resetPose() }
        // Even a held pointer or a degenerate event sequence cannot spin the
        // render loop forever. A later drag event starts a fresh clock.
        else if now - motionStarted > 12 { settle() }
    }

    private func integrate(dt: Double) {
        if case .ring? = dragTarget {} else {
            ringVelocity += (-ringPosition * 24 - ringVelocity * 6.7) * dt
            ringPosition += ringVelocity * dt
        }
        let angles = pendants.map(\.angle)
        for i in pendants.indices {
            if case .pendant(let selected)? = dragTarget, selected == i { continue }
            var coupling = 0.0
            if i > 0 { coupling += (angles[i - 1] - angles[i]) * 0.5 }
            if i + 1 < angles.count { coupling += (angles[i + 1] - angles[i]) * 0.5 }
            pendants[i].motion.advance(length: pendants[i].length, coupling: coupling,
                                       ringVelocity: ringVelocity.x, elapsed: dt)
        }
        // Gentle angular coupling is intentional: no full rigid-body collision
        // solver is needed for four decorative chains with a short lifetime.
    }

    private func applyPose() {
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        assembly.position = SCNVector3(Float(ringPosition.x), Float(ringPosition.y), 0)
        assembly.eulerAngles.y = CGFloat(ringPosition.x * 0.08)
        for i in pendants.indices {
            let item = pendants[i]
            let length = item.length + item.extensionOffset
            item.pivot.eulerAngles.z = CGFloat(item.angle)
            item.pivot.eulerAngles.x = CGFloat(sin(item.angle) * 0.14)
            item.charm.position.y = CGFloat(-length)
            item.charm.eulerAngles.y = CGFloat(item.yaw + item.angle * 0.36)
            let slack = max(0, -item.extensionOffset)
            for (index, link) in item.links.enumerated() {
                let fraction = (Double(index) + 0.5) / Double(item.links.count)
                link.position = SCNVector3(Float(sin(fraction * .pi) * slack * 0.28), Float(-length * fraction), 0)
            }
        }
        SCNTransaction.commit()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard active, !disposed else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]).first else { return }
        var node: SCNNode? = hit.node
        var selected: Int?
        while let current = node, current !== assembly {
            if let name = current.name, name.hasPrefix("pendant-"), let index = Int(name.dropFirst(8)) { selected = index; break }
            node = current.parent
        }
        dragDepth = projectPoint(hit.worldCoordinates).z
        let origin: SCNVector3
        if let selected, pendants.indices.contains(selected) {
            dragTarget = .pendant(selected)
            pendants[selected].motion.stop()
            origin = pendants[selected].charm.convertPosition(SCNVector3Zero, to: nil)
        } else {
            dragTarget = .ring
            ringVelocity = .zero
            origin = assembly.position
            previousRingPosition = ringPosition
        }
        grabOffset = SCNVector3(origin.x - hit.worldCoordinates.x, origin.y - hit.worldCoordinates.y, origin.z - hit.worldCoordinates.z)
        previousDragTime = ProcessInfo.processInfo.systemUptime
        NSCursor.closedHand.set()
        startClock()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let target = dragTarget, active, !disposed else { return }
        let point = convert(event.locationInWindow, from: nil)
        let world = unprojectPoint(SCNVector3(point.x, point.y, dragDepth))
        let desired = SCNVector3(world.x + grabOffset.x, world.y + grabOffset.y, world.z + grabOffset.z)
        let now = ProcessInfo.processInfo.systemUptime
        let dt = max(1.0 / 240.0, min(0.06, now - previousDragTime))
        previousDragTime = now
        switch target {
        case .ring:
            previousRingPosition = ringPosition
            ringPosition = SIMD2(clamp(Double(desired.x), -0.85, 0.85), clamp(Double(desired.y), -0.32, 0.40))
            ringVelocity = reducedMotion ? .zero : (ringPosition - previousRingPosition) / dt
            ringVelocity.x = clamp(ringVelocity.x, -3, 3); ringVelocity.y = clamp(ringVelocity.y, -3, 3)
        case .pendant(let index):
            let local = pendants[index].pivot.parent?.convertPosition(desired, from: nil) ?? desired
            let anchor = pendants[index].pivot.position
            let dx = Double(local.x - anchor.x), dy = Double(local.y - anchor.y)
            pendants[index].motion.drag(toAngle: atan2(dx, -dy),
                                        extension: hypot(dx, dy) - pendants[index].length,
                                        elapsed: dt, reduceMotion: reducedMotion)
        }
        applyPose()
        startClock()
    }

    override func mouseUp(with event: NSEvent) {
        guard let target = dragTarget else { return }
        let idleElapsed = ProcessInfo.processInfo.systemUptime - previousDragTime
        switch target {
        case .pendant(let index):
            pendants[index].motion.release(idleElapsed: idleElapsed, reduceMotion: reducedMotion)
        case .ring:
            if reducedMotion || idleElapsed >= 0.12 { ringVelocity = .zero }
        }
        dragTarget = nil
        NSCursor.openHand.set()
        if reducedMotion { settle() } else { startClock() }
    }

    override func cancelOperation(_ sender: Any?) {
        guard dragTarget != nil else { return }
        dragTarget = nil
        NSCursor.arrow.set()
        if reducedMotion { settle() } else { startClock() }
    }

    private func installCameraAndLights() {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 1.57
        camera.zNear = 0.1; camera.zFar = 40
        camera.wantsHDR = true
        camera.exposureOffset = -0.15
        camera.wantsExposureAdaptation = false
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 9)
        cameraNode.look(at: SCNVector3(0, -0.12, 0))
        scene?.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 650; key.light?.color = NSColor(white: 1, alpha: 1)
        key.eulerAngles = SCNVector3(-0.65, -0.45, 0)
        key.light?.castsShadow = true; key.light?.shadowMode = .deferred
        key.light?.shadowRadius = 5; key.light?.shadowSampleCount = 8
        key.light?.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.light?.shadowColor = NSColor(calibratedWhite: 0.25, alpha: 0.16)
        scene?.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .omni
        fill.light?.intensity = 350; fill.light?.color = NSColor(calibratedRed: 0.73, green: 0.88, blue: 1, alpha: 1)
        fill.position = SCNVector3(3, 2, 4); scene?.rootNode.addChildNode(fill)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 80; scene?.rootNode.addChildNode(ambient)
    }

    private func buildObjects() {
        stopClock(); dragTarget = nil
        assembly.childNodes.forEach { $0.removeFromParentNode() }
        pendants.removeAll()
        let silver = Self.metal(NSColor(calibratedWhite: 0.72, alpha: 1), roughness: 0.19)
        let ring = SCNTorus(ringRadius: 1.65, pipeRadius: 0.073)
        ring.ringSegmentCount = 112; ring.pipeSegmentCount = 20; ring.materials = [silver]
        let ringNode = SCNNode(geometry: ring)
        ringNode.name = "main-ring"; ringNode.position = SCNVector3(0, 1.46, 0)
        ringNode.eulerAngles.x = 1.28
        assembly.addChildNode(ringNode)
        // A fine second split-ring edge makes the metal read as an object with
        // thickness instead of a flat stroked circle.
        let seam = SCNTorus(ringRadius: 1.65, pipeRadius: 0.028)
        seam.ringSegmentCount = 112; seam.pipeSegmentCount = 10; seam.materials = [silver]
        let seamNode = SCNNode(geometry: seam)
        seamNode.position = SCNVector3(0, 1.47, -0.079); seamNode.eulerAngles.x = 1.28
        assembly.addChildNode(seamNode)

        let ids = ["keynest"] + brands
        let anchors = [-1.34, -0.53, 0.43, 1.27]
        let lengths = [0.61, 0.87, 0.64, 0.81]
        let yaws = [-0.24, 0.14, -0.18, 0.29]
        for (i, id) in ids.enumerated() {
            let x = anchors[i]
            let arc = sqrt(max(0, 1.65 * 1.65 - x * x))
            let pivot = SCNNode(); pivot.name = "pendant-\(i)"
            pivot.position = SCNVector3(Float(x), Float(1.46 - arc * sin(1.28)), Float(arc * cos(1.28)))
            assembly.addChildNode(pivot)
            let collar = Self.loop(radius: 0.11, pipe: 0.024, material: silver)
            collar.scale.y = 1.25; collar.position.y = 0.035
            collar.eulerAngles.y = 0.38
            pivot.addChildNode(collar)
            let count = max(5, Int(lengths[i] / 0.10))
            var links: [SCNNode] = []
            for j in 0..<count {
                let link = Self.loop(radius: 0.044, pipe: 0.012, material: silver)
                link.scale.y = 1.5
                link.eulerAngles.y = j.isMultiple(of: 2) ? 0.10 : 1.1
                pivot.addChildNode(link); links.append(link)
            }
            let charm = id == "keynest" ? Self.keyCharm(silver: silver) : Self.brandCharm(id: id, silver: silver)
            pivot.addChildNode(charm)
            pendants.append(Pendant(pivot: pivot, charm: charm, links: links,
                                    length: lengths[i], yaw: yaws[i]))
        }
        resetPose()
    }

    private static func loop(radius: CGFloat, pipe: CGFloat, material: SCNMaterial) -> SCNNode {
        let torus = SCNTorus(ringRadius: radius, pipeRadius: pipe)
        torus.ringSegmentCount = 24; torus.pipeSegmentCount = 8; torus.materials = [material]
        let node = SCNNode(geometry: torus); node.eulerAngles.x = .pi / 2
        return node
    }

    private static func keyCharm(silver: SCNMaterial) -> SCNNode {
        let root = SCNNode()
        let connector = loop(radius: 0.069, pipe: 0.018, material: silver)
        connector.position.y = -0.02; root.addChildNode(connector)
        let blue = metal(NSColor(calibratedRed: 0.38, green: 0.77, blue: 0.92, alpha: 1), roughness: 0.20)
        blue.metalness.contents = 0.60
        let head = loop(radius: 0.185, pipe: 0.061, material: blue)
        head.position.y = -0.29; root.addChildNode(head)
        let innerRim = loop(radius: 0.128, pipe: 0.016, material: silver)
        innerRim.position = SCNVector3(0, -0.29, 0.014); root.addChildNode(innerRim)
        let shaft = SCNBox(width: 0.108, height: 0.49, length: 0.112, chamferRadius: 0.026)
        shaft.materials = [blue]
        let shaftNode = SCNNode(geometry: shaft); shaftNode.position = SCNVector3(0, -0.685, 0)
        root.addChildNode(shaftNode)
        for y: Float in [-0.69, -0.87] {
            let tooth = SCNBox(width: 0.195, height: 0.105, length: 0.112, chamferRadius: 0.024)
            tooth.materials = [blue]
            let node = SCNNode(geometry: tooth); node.position = SCNVector3(0.058, y, 0)
            root.addChildNode(node)
        }
        return root
    }

    private static func brandCharm(id: String, silver: SCNMaterial) -> SCNNode {
        let root = SCNNode()
        let connector = loop(radius: 0.074, pipe: 0.019, material: silver)
        connector.position.y = -0.02; root.addChildNode(connector)
        let body = SCNCylinder(radius: 0.293, height: 0.095)
        body.radialSegmentCount = 56; body.materials = [silver]
        let node = SCNNode(geometry: body)
        node.eulerAngles.x = .pi / 2; node.position.y = -0.365
        root.addChildNode(node)
        let enamel = SCNCylinder(radius: 0.265, height: 0.099)
        enamel.radialSegmentCount = 56
        let face = metal(NSColor(calibratedWhite: 0.97, alpha: 1), roughness: 0.28)
        face.metalness.contents = 0.10; enamel.materials = [face]
        let faceNode = SCNNode(geometry: enamel)
        faceNode.eulerAngles.x = .pi / 2; faceNode.position = SCNVector3(0, -0.365, 0.008)
        root.addChildNode(faceNode)
        if let url = Bundle.main.resourceURL?.appendingPathComponent("ProviderIcons").appendingPathComponent(id + ".png"),
           let image = NSImage(contentsOf: url) {
            let logo = SCNPlane(width: 0.39, height: 0.39)
            let material = SCNMaterial(); material.lightingModel = .constant
            material.diffuse.contents = image; material.isDoubleSided = false
            logo.materials = [material]
            let logoNode = SCNNode(geometry: logo); logoNode.position = SCNVector3(0, -0.365, 0.061)
            root.addChildNode(logoNode)
        }
        return root
    }

    private static func metal(_ color: NSColor, roughness: CGFloat) -> SCNMaterial {
        let material = SCNMaterial(); material.lightingModel = .physicallyBased
        material.diffuse.contents = color; material.metalness.contents = 0.95
        material.roughness.contents = roughness
        material.locksAmbientWithDiffuse = true
        return material
    }

    /// Original studio softboxes, generated in memory. No video frames, web
    /// textures, file caches or user data are used for the metal reflections.
    private static let environmentImage: NSImage = {
        let image = NSImage(size: NSSize(width: 1024, height: 512))
        image.lockFocus()
        let gradient = NSGradient(colorsAndLocations:
            (NSColor(calibratedWhite: 0.25, alpha: 1), 0),
            (NSColor(calibratedWhite: 0.85, alpha: 1), 0.22),
            (NSColor.white, 0.31),
            (NSColor(calibratedWhite: 0.32, alpha: 1), 0.48),
            (NSColor(calibratedRed: 0.76, green: 0.85, blue: 0.92, alpha: 1), 0.68),
            (NSColor.white, 0.78),
            (NSColor(calibratedWhite: 0.34, alpha: 1), 1))!
        gradient.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 512), angle: 0)
        NSColor(white: 1, alpha: 0.85).setFill()
        NSBezierPath(roundedRect: NSRect(x: 170, y: 300, width: 180, height: 155), xRadius: 22, yRadius: 22).fill()
        NSColor(white: 1, alpha: 0.70).setFill()
        NSBezierPath(roundedRect: NSRect(x: 690, y: 100, width: 95, height: 320), xRadius: 18, yRadius: 18).fill()
        image.unlockFocus()
        return image
    }()

    private func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(upper, max(lower, value.isFinite ? value : 0))
    }
}
