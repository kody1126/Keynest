import AppKit
import SceneKit
import SwiftUI
import simd

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

/// Display metadata only. No vault, credential, account, URL or clipboard data
/// crosses into the renderer.
struct KeychainSceneCharm: Identifiable, Equatable {
    let id: String
    let name: String
    let brandID: String?
    let colorName: String
}

/// A press that returns to its starting point is still a drag once it crosses
/// the threshold. This prevents a thrown key from opening a credential panel.
struct KeychainPressState {
    private(set) var moved = false
    mutating func update(distance: Double) {
        if !distance.isFinite || distance >= 6 { moved = true }
    }
}

struct KeychainSceneView: View {
    let charms: [KeychainSceneCharm]
    var selectedID: String? = nil
    var isActive = true
    var resetToken = 0
    var onSelect: (String) -> Void
    var onRingTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        KeychainSceneSurface(charms: charms, selectedID: selectedID, isActive: isActive,
                             reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                             resetToken: resetToken, onSelect: onSelect, onRingTap: onRingTap)
            // The Home showcase provides equivalent keyboard and VoiceOver
            // actions without requiring spatial hit testing in this surface.
            .accessibilityHidden(true)
    }
}

private struct KeychainSceneSurface: NSViewRepresentable {
    let charms: [KeychainSceneCharm]
    let selectedID: String?
    let isActive: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool
    let resetToken: Int
    let onSelect: (String) -> Void
    let onRingTap: () -> Void

    func makeNSView(context: Context) -> KeychainRenderView {
        let view = KeychainRenderView(frame: .zero)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: KeychainRenderView, context: Context) {
        view.configure(charms: charms, selectedID: selectedID, active: isActive,
                       reduceMotion: reduceMotion, reduceTransparency: reduceTransparency,
                       resetToken: resetToken, onSelect: onSelect, onRingTap: onRingTap)
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
        let restAngle: Double
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
    private var charms: [KeychainSceneCharm] = []
    private var selectedID: String?
    private var hoveredIndex: Int?
    private var reducedTransparency = false
    private var builtObjects = false
    private var onSelect: ((String) -> Void)?
    private var onRingTap: (() -> Void)?
    private var tracking: NSTrackingArea?
    private var pressOrigin = CGPoint.zero
    private var press = KeychainPressState()
    private var active = false
    private var reducedMotion = false
    private var lastReset: Int?
    private var timer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private weak var observedClipView: NSClipView?
    private var dragTarget: DragTarget?
    private var dragDepth: CGFloat = 0
    private var grabOffset = SCNVector3Zero
    private var dragGrip = SIMD2<Double>.zero
    private var dragLengthFraction = 1.0
    private var dragPlaneZ: CGFloat = 0
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
        antialiasingMode = device?.supportsTextureSampleCount(8) == true ? .multisampling8X : .multisampling4X
        preferredFramesPerSecond = 60
        rendersContinuously = false
        isPlaying = false
        scene = SCNScene()
        scene?.background.contents = NSColor.clear
        scene?.lightingEnvironment.contents = Self.environmentImage
        scene?.lightingEnvironment.intensity = 0.82
        scene?.rootNode.addChildNode(assembly)
        installCameraAndLights()
        setAccessibilityLabel("钥匙串")
        setAccessibilityHelp("拖动挂件使其摆动，点击挂件复制已绑定密钥，点击金属挂扣定制。")
        installNotifications()
    }

    required init?(coder: NSCoder) { nil }

    func configure(charms: [KeychainSceneCharm], selectedID: String?, active: Bool,
                   reduceMotion: Bool, reduceTransparency: Bool, resetToken: Int,
                   onSelect: @escaping (String) -> Void, onRingTap: @escaping () -> Void) {
        guard !disposed else { return }
        self.onSelect = onSelect; self.onRingTap = onRingTap
        self.active = active
        let bounded = Array(charms.prefix(8))
        if self.charms != bounded || reducedTransparency != reduceTransparency || !builtObjects {
            self.charms = bounded
            reducedTransparency = reduceTransparency
            buildObjects()
            builtObjects = true
        }
        if self.selectedID != selectedID {
            self.selectedID = selectedID
            updateHighlight()
        }
        if reducedMotion != reduceMotion {
            reducedMotion = reduceMotion
            cancelDrag()
            settle()
        }
        if lastReset != resetToken {
            lastReset = resetToken
            resetPose()
        }
        if !canInteract { cancelDrag() }
        if !canRun { stopClock() }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let aspect = max(0.25, bounds.width / max(1, bounds.height))
        cameraNode.camera?.orthographicScale = max(2.24, (charmSpan + 1.0) / aspect)
        updateBackingResolution()
        observeClipView()
        if !canInteract { cancelDrag() }
        if !canRun { stopClock() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeClipView()
        updateBackingResolution()
        if !canInteract { cancelDrag() }
        if !canRun { stopClock() }
        needsDisplay = true
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBackingResolution()
    }

    private func updateBackingResolution() {
        // Keep the Metal drawable at the display pixel density, including when
        // moving a window between Retina and standard-resolution screens.
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        if layer?.contentsScale != scale { layer?.contentsScale = scale }
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidHide() { super.viewDidHide(); cancelDrag(); stopClock() }
    override func viewDidUnhide() { super.viewDidUnhide(); needsDisplay = true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area); tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        guard dragTarget == nil else { return }
        let hit = objectHit(at: convert(event.locationInWindow, from: nil))
        let index: Int?
        if case .pendant(let value)? = hit?.0 { index = value } else { index = nil }
        if hoveredIndex != index { hoveredIndex = index; updateHighlight() }
        if hit != nil { NSCursor.openHand.set() } else { NSCursor.arrow.set() }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = nil; updateHighlight()
        if dragTarget == nil { NSCursor.arrow.set() }
    }

    private func updateHighlight() {
        for i in pendants.indices {
            let emphasized = hoveredIndex == i || charms[i].id == selectedID
            pendants[i].charm.enumerateChildNodes { node, _ in
                guard node.name == "glass" || node.name == "logo" else { return }
                node.geometry?.firstMaterial?.emission.contents = emphasized
                    ? Self.tint(charms[i].colorName).withAlphaComponent(0.12) : NSColor.black
                node.geometry?.firstMaterial?.emission.intensity = emphasized ? 0.20 : 0
            }
        }
        needsDisplay = true
    }

    private var canInteract: Bool {
        !disposed && active && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty &&
        window != nil && window?.occlusionState.contains(.visible) == true
    }

    private var canRun: Bool { canInteract && NSApp.isActive }

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
                    if name == NSApplication.didResignActiveNotification || !self.canInteract { self.cancelDrag() }
                    if !self.canRun { self.stopClock() }
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
        onSelect = nil; onRingTap = nil
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
        if dragTarget == nil {
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
        // solver is needed for these bounded chains with a short lifetime.
    }

    private func applyPose() {
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0
        assembly.position = SCNVector3(Float(ringPosition.x), Float(ringPosition.y), 0)
        assembly.eulerAngles.y = CGFloat(ringPosition.x * 0.08)
        for i in pendants.indices {
            let item = pendants[i]
            let length = item.length + item.extensionOffset
            item.pivot.eulerAngles.z = CGFloat(item.restAngle + item.angle)
            item.charm.position.y = CGFloat(-length)
            // Keep the brand's face angle stable while the chain swings in its
            // own plane. Rotating it independently made the held point slip.
            item.charm.eulerAngles.y = CGFloat(item.yaw)
            for (index, link) in item.links.enumerated() {
                let fraction = (Double(index) + 0.5) / Double(item.links.count)
                link.position = SCNVector3(0, -length * fraction, 0)
            }
        }
        SCNTransaction.commit()
        needsDisplay = true
    }

    private func objectHit(at point: CGPoint) -> (DragTarget, SCNHitTestResult)? {
        // SCNView uses AppKit points on macOS, with the same bottom-left
        // origin as projectPoint/unprojectPoint. Do not apply a Metal Y flip.
        for hit in hitTest(point, options: [.searchMode: SCNHitTestSearchMode.all.rawValue]) {
            var node: SCNNode? = hit.node
            while let current = node, current !== assembly {
                if let name = current.name, name.hasPrefix("pendant-"),
                   let index = Int(name.dropFirst(8)), pendants.indices.contains(index) {
                    return (.pendant(index), hit)
                }
                if current.name == "main-ring" { return (.ring, hit) }
                node = current.parent
            }
        }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard canInteract else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let (target, hit) = objectHit(at: point) else { return }
        pressOrigin = point; press = KeychainPressState()
        let selected: Int?
        if case .pendant(let index) = target { selected = index } else { selected = nil }
        dragDepth = projectPoint(hit.worldCoordinates).z
        let origin: SCNVector3
        if let selected, pendants.indices.contains(selected) {
            dragTarget = .pendant(selected)
            pendants[selected].motion.stop()
            ringVelocity = .zero
            let item = pendants[selected]
            dragLengthFraction = 1
            if let name = hit.node.name, name.hasPrefix("chain-link-"),
               let linkIndex = Int(name.dropFirst(11)), item.links.indices.contains(linkIndex) {
                dragLengthFraction = (Double(linkIndex) + 0.5) / Double(item.links.count)
            }
            let localGrip = item.pivot.convertPosition(hit.worldCoordinates, from: nil)
            let length = item.length + item.extensionOffset
            dragGrip = SIMD2(Double(localGrip.x), Double(localGrip.y) + length * dragLengthFraction)
            dragPlaneZ = assembly.convertPosition(hit.worldCoordinates, from: nil).z
            origin = item.charm.convertPosition(SCNVector3Zero, to: nil)
        } else {
            dragTarget = .ring
            ringVelocity = .zero
            origin = assembly.position
            previousRingPosition = ringPosition
        }
        grabOffset = SCNVector3(origin.x - hit.worldCoordinates.x, origin.y - hit.worldCoordinates.y, origin.z - hit.worldCoordinates.z)
        previousDragTime = ProcessInfo.processInfo.systemUptime
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let target = dragTarget, active, !disposed else { return }
        let point = convert(event.locationInWindow, from: nil)
        press.update(distance: hypot(Double(point.x - pressOrigin.x), Double(point.y - pressOrigin.y)))
        guard press.moved else { return }
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
            // Intersect the pointer ray with the original grip plane, then
            // solve for the held point itself rather than moving the charm's
            // origin and rotating it away from the pointer a second time.
            let near = assembly.convertPosition(unprojectPoint(SCNVector3(point.x, point.y, 0)), from: nil)
            let far = assembly.convertPosition(unprojectPoint(SCNVector3(point.x, point.y, 1)), from: nil)
            let dz = far.z - near.z
            guard abs(dz) > 0.000_001 else { return }
            let t = (dragPlaneZ - near.z) / dz
            let anchor = pendants[index].pivot.position
            let targetPoint = SIMD2(Double(near.x + t * (far.x - near.x) - anchor.x),
                                    Double(near.y + t * (far.y - near.y) - anchor.y))
            let item = pendants[index], f = dragLengthFraction
            guard let solution = KeychainDragGeometry.solve(grabPoint: dragGrip, target: targetPoint,
                initialLength: (item.length + item.extensionOffset) * f,
                angleRange: (item.restAngle - 0.85)...(item.restAngle + 0.85),
                lengthRange: ((item.length - 0.28) * f)...((item.length + 0.38) * f)) else { return }
            pendants[index].motion.drag(toAngle: solution.angle - item.restAngle,
                                        extension: solution.length / f - item.length,
                                        elapsed: dt, reduceMotion: reducedMotion)
        }
        applyPose()
        startClock()
    }

    override func mouseUp(with event: NSEvent) {
        guard let target = dragTarget else { return }
        let point = convert(event.locationInWindow, from: nil)
        press.update(distance: hypot(Double(point.x - pressOrigin.x), Double(point.y - pressOrigin.y)))
        if !press.moved {
            dragTarget = nil
            NSCursor.openHand.set()
            switch target {
            case .pendant(let index): onSelect?(charms[index].id)
            case .ring: onRingTap?()
            }
            return
        }
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
        camera.orthographicScale = 2.24
        camera.zNear = 0.1; camera.zFar = 40
        camera.wantsHDR = true
        camera.exposureOffset = -0.65
        camera.wantsExposureAdaptation = false
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 9)
        cameraNode.look(at: SCNVector3(0, 0.04, 0))
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
        fill.light?.intensity = 220; fill.light?.color = NSColor(calibratedRed: 0.73, green: 0.88, blue: 1, alpha: 1)
        fill.position = SCNVector3(3, 2, 4); scene?.rootNode.addChildNode(fill)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 100; scene?.rootNode.addChildNode(ambient)
    }

    private var charmSpan: Double { Double(max(0, charms.count - 1)) * (charms.count > 5 ? 0.48 : 0.62) }
    private var ringRadius: Double { max(1.85, charmSpan * 1.48 + 0.35) }

    private func buildObjects() {
        stopClock(); cancelDrag(); hoveredIndex = nil
        assembly.childNodes.forEach { $0.removeFromParentNode() }
        pendants.removeAll()
        let silver = Self.metal(NSColor(calibratedWhite: 0.80, alpha: 1), roughness: 0.14)
        let radius = ringRadius
        // Only the lower open arc enters the scene, like a hanging clasp seen
        // close up. Its upper ends continue beyond the viewport, never forming
        // the flat closed ellipse that competed with the charms.
        for (pipe, inset, depth) in [(0.064, 0.0, 0.0), (0.019, 0.050, -0.042)] {
            let arc = Self.claspArc(radius: radius - inset, baseY: 1.18 + inset,
                                    pipe: pipe, depth: depth, material: silver)
            arc.name = "main-ring"
            assembly.addChildNode(arc)
        }

        let count = charms.count
        let span = charmSpan
        for (i, metadata) in charms.enumerated() {
            let fraction = count <= 1 ? 0.5 : Double(i) / Double(count - 1)
            let x = -span + 2 * span * fraction
            let y = 1.18 + radius - sqrt(max(0, radius * radius - x * x))
            let pivot = SCNNode(); pivot.name = "pendant-\(i)"
            pivot.position = SCNVector3(x, y, 0)
            assembly.addChildNode(pivot)
            let collar = Self.loop(radius: 0.105, pipe: 0.023, material: silver)
            collar.name = "main-ring"
            collar.scale.y = 1.2; collar.eulerAngles.y = 0.65
            pivot.addChildNode(collar)
            let length = y - (i.isMultiple(of: 2) ? 0.50 : 0.20)
            let linkCount = max(5, Int(length / 0.085))
            var links: [SCNNode] = []
            for j in 0..<linkCount {
                let link = Self.loop(radius: 0.044, pipe: 0.013, material: silver)
                link.name = "chain-link-\(j)"
                link.scale.y = 1.5
                link.eulerAngles.y = j.isMultiple(of: 2) ? 0.08 : 1.2
                pivot.addChildNode(link); links.append(link)
            }
            let charm = Self.blenderCharm(metadata, opaque: reducedTransparency, silver: silver, compact: count > 5)
            pivot.addChildNode(charm)
            pendants.append(Pendant(pivot: pivot, charm: charm, links: links, length: length,
                                    yaw: i.isMultiple(of: 2) ? -0.20 : 0.25,
                                    restAngle: (fraction - 0.5) * 0.16))
        }
        resetPose()
        updateHighlight()
        needsLayout = true
    }

    private static func claspArc(radius: Double, baseY: Double, pipe: Double,
                                 depth: Double, material: SCNMaterial) -> SCNNode {
        let segments = 180, sides = 20
        var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], indices: [Int32] = []
        for i in 0...segments {
            let angle = -1.42 + 2.84 * Double(i) / Double(segments)
            for j in 0...sides {
                let around = 2 * Double.pi * Double(j) / Double(sides)
                let nx = sin(angle) * cos(around), ny = -cos(angle) * cos(around), nz = sin(around)
                vertices.append(SCNVector3(radius * sin(angle) + pipe * nx,
                                           baseY + radius * (1 - cos(angle)) + pipe * ny,
                                           depth + pipe * nz))
                normals.append(SCNVector3(nx, ny, nz))
                if i < segments && j < sides {
                    let a = Int32(i * (sides + 1) + j), b = a + Int32(sides + 1)
                    indices += [a, b, a + 1, a + 1, b, b + 1]
                }
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    private static func loop(radius: CGFloat, pipe: CGFloat, material: SCNMaterial) -> SCNNode {
        let torus = SCNTorus(ringRadius: radius, pipeRadius: pipe)
        torus.ringSegmentCount = 40; torus.pipeSegmentCount = 12; torus.materials = [material]
        let node = SCNNode(geometry: torus); node.eulerAngles.x = .pi / 2
        return node
    }

    private static func blenderCharm(_ charm: KeychainSceneCharm, opaque: Bool, silver: SCNMaterial, compact: Bool) -> SCNNode {
        let root = SCNNode()
        let model = SCNNode()
        // Blender exports a Y-up key with its attachment hole at y=1.
        let brandAsset = charm.brandID.flatMap { KeychainMeshAsset.bundled(named: $0, brandCharm: true) }
        let scale: CGFloat = brandAsset == nil ? (compact ? 0.62 : 0.74) : compact ? 0.66 : 0.93
        model.scale = SCNVector3(scale, scale, scale)
        model.position.y = -scale
        root.addChildNode(model)
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = tint(charm.colorName)
        glass.metalness.contents = 0.08
        glass.roughness.contents = 0.10
        glass.clearCoat.contents = 1.0
        glass.clearCoatRoughness.contents = 0.05
        glass.transparency = opaque ? 1 : 0.66
        glass.transparencyMode = .dualLayer
        glass.fresnelExponent = 2.8
        glass.reflective.contents = environmentImage
        glass.reflective.intensity = 0.48
        let rgba = KeychainMeshAsset.brandColor(charm.brandID) ?? [0.12, 0.20, 0.26, 1]
        let logo = metal(NSColor(srgbRed: rgba[0], green: rgba[1], blue: rgba[2], alpha: 1), roughness: 0.22)
        logo.metalness.contents = 0.10
        logo.clearCoat.contents = 1.0
        logo.clearCoatRoughness.contents = 0.06
        logo.roughness.contents = 0.24
        // An opaque enamel face preserves small cutouts and color. Glass is
        // reserved for the unbranded key; see-through logos doubled their edges.
        logo.transparency = 1
        logo.transparencyMode = .dualLayer
        logo.fresnelExponent = 2.0
        if let brandAsset {
            let attachment = brandAsset.brandAttachment()
            addMeshes(brandAsset, to: model, glass: glass, silver: silver, logo: logo,
                      replacingAttachment: attachment != nil)
            if let attachment { model.addChildNode(solidConnector(attachment, material: silver)) }
        } else if let asset = KeychainMeshAsset.bundled(named: "glass-key-v1") {
            addMeshes(asset, to: model, glass: glass, silver: silver, logo: logo)
        } else {
            // Graceful native fallback if a development bundle has no art.
            let body = SCNBox(width: 0.95, height: 1.02, length: 0.26, chamferRadius: 0.18)
            body.materials = [glass]
            let node = SCNNode(geometry: body); node.name = "glass"; node.position.y = 0.4; model.addChildNode(node)
            let shaft = SCNBox(width: 0.22, height: 1.05, length: 0.24, chamferRadius: 0.06)
            shaft.materials = [glass]
            let stem = SCNNode(geometry: shaft); stem.position.y = -0.5; model.addChildNode(stem)
            for y: CGFloat in [-0.63, -0.9] {
                let tooth = SCNBox(width: 0.43, height: 0.18, length: 0.24, chamferRadius: 0.05)
                tooth.materials = [glass]; let n = SCNNode(geometry: tooth)
                n.position = SCNVector3(0.12, y, 0); model.addChildNode(n)
            }
        }
        // Include holes in a logo's clickable area without drawing a plaque.
        let bounds = model.boundingBox
        let proxyGeometry = SCNBox(width: bounds.max.x - bounds.min.x,
                                   height: bounds.max.y - bounds.min.y,
                                   length: bounds.max.z - bounds.min.z + 0.01, chamferRadius: 0)
        let pickOnly = SCNMaterial(); pickOnly.colorBufferWriteMask = []
        pickOnly.writesToDepthBuffer = false; pickOnly.readsFromDepthBuffer = false
        proxyGeometry.materials = [pickOnly]
        let proxy = SCNNode(geometry: proxyGeometry)
        proxy.castsShadow = false
        proxy.position = SCNVector3((bounds.min.x + bounds.max.x) / 2,
                                    (bounds.min.y + bounds.max.y) / 2,
                                    (bounds.min.z + bounds.max.z) / 2)
        model.addChildNode(proxy)
        let connector = loop(radius: 0.071, pipe: 0.020, material: silver)
        connector.eulerAngles.y = 0.3; root.addChildNode(connector)
        return root
    }

    private static func addMeshes(_ asset: KeychainMeshAsset, to parent: SCNNode,
                                  glass: SCNMaterial, silver: SCNMaterial, logo: SCNMaterial,
                                  replacingAttachment: Bool = false) {
        for mesh in asset.meshes {
            if replacingAttachment && mesh.role == "metal" && mesh.name.hasSuffix("-attachment") { continue }
            let vertices = stride(from: 0, to: mesh.positions.count, by: 3).map {
                SCNVector3(mesh.positions[$0], mesh.positions[$0 + 1], mesh.positions[$0 + 2])
            }
            let normals = stride(from: 0, to: mesh.normals.count, by: 3).map {
                SCNVector3(mesh.normals[$0], mesh.normals[$0 + 1], mesh.normals[$0 + 2])
            }
            let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [element])
            geometry.materials = [mesh.role == "glass" ? glass : mesh.role == "logo" ? logo : silver]
            let node = SCNNode(geometry: geometry); node.name = mesh.role
            parent.addChildNode(node)
        }
    }

    private static func solidConnector(_ attachment: KeychainMeshAsset.Attachment, material: SCNMaterial) -> SCNNode {
        let start = SIMD3<Float>(attachment.bodyPoint), end = SIMD3<Float>(attachment.ringPoint)
        let delta = end - start
        let cylinder = SCNCylinder(radius: CGFloat(attachment.radius), height: CGFloat(simd_length(delta)))
        cylinder.radialSegmentCount = 20
        cylinder.materials = [material]
        let node = SCNNode(geometry: cylinder)
        node.name = "metal"
        node.simdPosition = (start + end) / 2
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(delta))
        return node
    }

    private static func tint(_ name: String) -> NSColor {
        switch name {
        case "lavender": return NSColor(srgbRed: 0.72, green: 0.65, blue: 0.98, alpha: 1)
        case "mint": return NSColor(srgbRed: 0.49, green: 0.86, blue: 0.72, alpha: 1)
        case "amber": return NSColor(srgbRed: 0.98, green: 0.75, blue: 0.40, alpha: 1)
        case "rose": return NSColor(srgbRed: 0.98, green: 0.65, blue: 0.75, alpha: 1)
        case "graphite": return NSColor(srgbRed: 0.54, green: 0.62, blue: 0.73, alpha: 1)
        default: return NSColor(srgbRed: 0.55, green: 0.84, blue: 0.98, alpha: 1)
        }
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
