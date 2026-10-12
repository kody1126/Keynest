import SwiftUI
import AppKit
import KeynestCore

enum HomeLayoutGeometry {
    static let coordinateSpace = "keynest.home.layout.viewport"
}

struct HomeLayoutCardFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct HomeLayoutCardBodyFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// A window-local gesture session. The event monitor and image live outside
/// the reordering card tree; removing/recreating a source view cannot lose a drag.
@MainActor final class HomeLayoutDragSession: ObservableObject {
    typealias Destination = HomeLayoutReorder.Destination
    struct Token: Equatable { let editing: UUID; let gesture: UUID }
    private struct Target { weak var view: HomeCardDragView? }
    @Published private(set) var draggedID: String?
    @Published private(set) var liveOrder: [String]?
    @Published private(set) var destination: Destination?
    @Published private(set) var settledID: String?
    private var editingNonce: UUID?
    private var dragToken: Token?
    private var allowedIDs = Set<String>()
    private var targets: [String: Target] = [:]
    private var cardFrames: [String: CGRect] = [:]
    private var cardBodyFrames: [String: CGRect] = [:]
    private var framesAreCurrent = true
    private var awaitingScrollFrames = false
    private weak var viewport: HomeLayoutViewportView?
    private weak var previewHost: HomeLayoutPreviewHostView?
    private weak var sourceWindow: NSWindow?
    private weak var scrollView: NSScrollView?
    private var reorder: HomeLayoutReorder?
    private var commit: (([String]) -> Void)?
    private var preview: HomeLayoutDragPreviewView?
    private var previewGrip = CGPoint.zero
    private var previewScale: CGFloat = 1
    private var reduceMotion = false
    private var pointer = CGPoint.zero
    private var eventMonitor: Any?
    private var scrollTimer: Timer?
    private var settling = false
    private var pendingRelease = false
    private var releaseTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?

    func activate(ids: [String]) {
        clear(); editingNonce = UUID(); allowedIDs = Set(ids)
    }

    func updateIDs(_ ids: [String]) {
        // A concurrent vault/catalog edit invalidates the captured ordering.
        if allowedIDs != Set(ids) { endDrag() }
        allowedIDs = Set(ids)
    }

    func updateCardFrames(_ frames: [String: CGRect]) {
        cardFrames = frames.filter { HomeLayoutReorder.valid($0.value) }
        framesAreCurrent = true
        if awaitingScrollFrames, let token = dragToken, let window = sourceWindow {
            awaitingScrollFrames = false
            Task { [weak self, weak window] in
                guard let self, let window else { return }
                self.updateDrag(token: token, point: self.pointer, window: window)
            }
        }
    }

    func updateCardBodyFrames(_ frames: [String: CGRect]) {
        cardBodyFrames = frames.filter { HomeLayoutReorder.valid($0.value) }
    }

    fileprivate func setViewport(_ view: HomeLayoutViewportView) { viewport = view }
    fileprivate func setPreviewHost(_ view: HomeLayoutPreviewHostView) { previewHost = view }
    fileprivate func removePreviewHost(_ view: HomeLayoutPreviewHostView) {
        if previewHost === view { endDrag(); previewHost = nil }
    }
    fileprivate func removeViewport(_ view: HomeLayoutViewportView) {
        if viewport === view { endDrag(); viewport = nil; cardFrames = [:] }
    }
    fileprivate func register(_ view: HomeCardDragView, id: String) {
        if editingNonce != nil { targets[id] = Target(view: view) }
    }
    fileprivate func unregister(_ view: HomeCardDragView, id: String) {
        if targets[id]?.view === view { targets[id] = nil }
        // The stable window monitor owns an active gesture, not this source view.
    }

    fileprivate func beginDrag(id: String, presentation: HomeCardPresentation, order: [String],
                               colorScheme: ColorScheme, reduceMotion: Bool,
                               view: HomeCardDragView, pressedAt: NSPoint, point: NSPoint,
                               commit: @escaping ([String]) -> Void) -> Token? {
        guard let editingNonce, allowedIDs.contains(id), targets[id]?.view === view,
              let window = view.window, let previewHost, previewHost.window === window,
              previewHost.bounds.width > 0, previewHost.bounds.height > 0,
              let viewport, viewport.window === window, let cardFrame = cardBodyFrames[id],
              Set(order) == allowedIDs, let state = HomeLayoutReorder(source: id, order: order) else { return nil }
        endDrag()
        // Only safe displayed metadata is rendered. No screen capture, native
        // Menu/Link rendering, model reference, clipboard, or secret in the image.
        let renderer = ImageRenderer(content: HomeCardDragPresentation(presentation: presentation)
            .frame(width: cardFrame.width, height: cardFrame.height, alignment: .topLeading)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = window.backingScaleFactor
        var renderedImage: NSImage?
        view.effectiveAppearance.performAsCurrentDrawingAppearance { renderedImage = renderer.nsImage }
        guard let image = renderedImage else { return nil }
        let token = Token(editing: editingNonce, gesture: UUID())
        dragToken = token; draggedID = id; sourceWindow = window
        scrollView = view.enclosingScrollView; reorder = state; self.commit = commit
        self.reduceMotion = reduceMotion; liveOrder = order
        let initialPoint = viewport.convert(pressedAt, from: nil)
        previewGrip = CGPoint(x: initialPoint.x - cardFrame.minX, y: initialPoint.y - cardFrame.minY)
        previewScale = reduceMotion ? 1 : 1.015
        let preview = HomeLayoutDragPreviewView(image: image, size: cardFrame.size,
                                               scale: previewScale, reduceMotion: reduceMotion)
        self.preview = preview
        // This subtree belongs exclusively to our representable. Inserting a
        // child directly into NSHostingView's managed tree can put the image
        // behind SwiftUI's drawing layers after a reflow.
        previewHost.addSubview(preview)
        installTracking(token: token, window: window)
        updateDrag(token: token, point: point, window: window)
        return token
    }

    private func installTracking(token: Token, window: NSWindow) {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp, .leftMouseDown, .keyDown]) { [weak self, weak window] event in
            guard let self, let window, self.accepts(token: token, window: window) else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.cancelDrag(animated: true); return nil }
                return event
            }
            if event.type == .leftMouseDown || event.window !== window {
                self.endDrag(); return event
            }
            if event.type == .leftMouseUp {
                self.finishDrag(token: token, point: event.locationInWindow, window: window)
            } else {
                self.updateDrag(token: token, point: event.locationInWindow, window: window)
            }
            return nil
        }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window, self.accepts(token: token, window: window),
                      let viewport = self.viewport else { return }
                let local = viewport.convert(self.pointer, from: nil)
                if self.autoscrollAtViewportEdge(local, viewport: viewport) {
                    self.updateDrag(token: token, point: self.pointer, window: window)
                }
            }
        }
        scrollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    fileprivate func updateDrag(token: Token, point: NSPoint, window: NSWindow) {
        guard accepts(token: token, window: window) else { return }
        pointer = point
        if let previewHost, let preview {
            let local = previewHost.convert(point, from: nil)
            preview.frame = HomeDragPreviewGeometry.frame(pointer: local, grip: previewGrip,
                size: preview.originalSize, scale: previewScale, flipped: previewHost.isFlipped)
        }
        guard framesAreCurrent, let viewport, !viewport.isHiddenOrHasHiddenAncestor,
              var state = reorder else { return }
        let local = viewport.convert(point, from: nil)
        if let next = state.hover(at: local, frames: cardFrames, viewport: viewport.bounds) {
            reorder = state; destination = next; framesAreCurrent = false
            // Spring the actual variable-height masonry layout, not just an outline.
            withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.92)) {
                liveOrder = state.order
            }
        } else { reorder = state }
    }

    fileprivate func finishDrag(token: Token, point: NSPoint, window: NSWindow) {
        guard accepts(token: token, window: window) else { return }
        pointer = point
        stopTracking()
        if !framesAreCurrent {
            pendingRelease = true
            releaseTask = Task { [weak self, weak window] in
                // A fast mouse-up may arrive in the same run-loop turn as live
                // reflow. Wait briefly for measured geometry instead of using
                // stale frames or accidentally cancelling an otherwise valid drop.
                for _ in 0..<10 {
                    try? await Task.sleep(for: .milliseconds(16))
                    guard !Task.isCancelled, let self, let window, self.dragToken == token,
                          self.pendingRelease, !self.settling else { return }
                    if self.framesAreCurrent { self.completeRelease(point: point, window: window); return }
                }
                self?.cancelDrag(animated: true)
            }
        } else { completeRelease(point: point, window: window) }
    }

    private func completeRelease(point: NSPoint, window: NSWindow) {
        guard !settling else { return }
        guard sourceWindow === window, let viewport, let state = reorder else { endDrag(); return }
        pendingRelease = false
        let valid = framesAreCurrent && state.canDrop(at: viewport.convert(point, from: nil),
                                                      frames: cardFrames, viewport: viewport.bounds)
        if valid { commit?(state.order) }
        settlePreview(success: valid)
    }

    private func accepts(token: Token, window: NSWindow) -> Bool {
        !settling && !pendingRelease && editingNonce == token.editing && dragToken == token && sourceWindow === window &&
            viewport?.window === window && draggedID.map { allowedIDs.contains($0) } == true
    }

    @discardableResult private func autoscrollAtViewportEdge(_ point: NSPoint, viewport: HomeLayoutViewportView) -> Bool {
        guard framesAreCurrent, viewport.bounds.contains(point), let scroll = scrollView,
              let document = scroll.documentView else { return false }
        let edge: CGFloat = 36
        let intensity: CGFloat
        if point.y < viewport.bounds.minY + edge { intensity = -(viewport.bounds.minY + edge - point.y) / edge }
        else if point.y > viewport.bounds.maxY - edge { intensity = (point.y - viewport.bounds.maxY + edge) / edge }
        else { return false }
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        origin.y = max(document.bounds.minY, min(max(document.bounds.minY, document.bounds.maxY - clip.bounds.height),
            origin.y + intensity * 10 * (document.isFlipped ? 1 : -1)))
        guard origin != clip.bounds.origin else { return false }
        let shift = (origin.y - clip.bounds.origin.y) * (document.isFlipped ? 1 : -1)
        reorder?.scrolled(by: shift)
        framesAreCurrent = false; awaitingScrollFrames = true
        clip.scroll(to: origin); scroll.reflectScrolledClipView(clip)
        return true
    }

    func cancelDrag(animated: Bool) {
        if animated, dragToken != nil, !settling { settlePreview(success: false) }
        else { endDrag() }
    }

    private func stopTracking() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil; scrollTimer?.invalidate(); scrollTimer = nil
        NSCursor.arrow.set()
    }

    private func settlePreview(success: Bool) {
        guard let token = dragToken, let source = draggedID else { return }
        // Invalidate the deferred mouse-up before cancel starts its return
        // animation. Fresh frames must not revive an explicitly cancelled drag.
        releaseTask?.cancel(); releaseTask = nil; pendingRelease = false
        stopTracking(); settling = true; destination = nil
        // No write occurs for cancel. Clearing the transient order restores the
        // draft captured before this gesture, including earlier unsaved moves.
        withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.92)) { liveOrder = nil }
        settleTask = Task { [weak self] in
            // Allow the restored/committed SwiftUI layout to publish its endpoint.
            try? await Task.sleep(for: .milliseconds(20))
            guard !Task.isCancelled, let self, self.dragToken == token,
                  let preview = self.preview, let viewport = self.viewport,
                  let previewHost = self.previewHost else { return }
            let start = preview.frame
            let startTime = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled && self.dragToken == token {
                let elapsed = ProcessInfo.processInfo.systemUptime - startTime
                let progress: CGFloat = self.reduceMotion ? 1 : CGFloat(1 - exp(-30 * elapsed) * (1 + 30 * elapsed))
                if let frame = self.cardBodyFrames[source] {
                    let target = viewport.convert(frame, to: previewHost)
                    preview.frame = CGRect(x: start.minX + (target.minX - start.minX) * progress,
                        y: start.minY + (target.minY - start.minY) * progress,
                        width: start.width + (target.width - start.width) * progress,
                        height: start.height + (target.height - start.height) * progress)
                }
                if elapsed >= 0.24 || self.reduceMotion { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled, self.dragToken == token else { return }
            self.endDrag()
            if success {
                self.settledID = source
                self.feedbackTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(450))
                    guard !Task.isCancelled else { return }
                    self?.settledID = nil
                }
            }
        }
    }

    func endDrag(token: Token? = nil) {
        if let token, token != dragToken { return }
        stopTracking(); settleTask?.cancel(); settleTask = nil
        releaseTask?.cancel(); releaseTask = nil; pendingRelease = false
        preview?.removeFromSuperview(); preview = nil
        previewGrip = .zero; previewScale = 1
        feedbackTask?.cancel(); feedbackTask = nil; settledID = nil
        draggedID = nil; liveOrder = nil; destination = nil; dragToken = nil
        sourceWindow = nil; scrollView = nil; reorder = nil; commit = nil; settling = false
        framesAreCurrent = true; awaitingScrollFrames = false
    }

    #if KEYNEST_HOME_LAYOUT_QA
    // Test-only controls drive this exact coordinator without synthesizing OS
    // input. This block is absent from the production app.
    func qaLift(id: String, presentation: HomeCardPresentation, order: [String],
                colorScheme: ColorScheme, reduceMotion: Bool, commit: @escaping ([String]) -> Void) -> Bool {
        guard let view = targets[id]?.view, let viewport, let frame = cardBodyFrames[id] else { return false }
        let point = viewport.convert(CGPoint(x: frame.minX + 70, y: frame.minY + 32), to: nil)
        let result = beginDrag(id: id, presentation: presentation, order: order, colorScheme: colorScheme,
                              reduceMotion: reduceMotion, view: view, pressedAt: point, point: point, commit: commit)
        stopTracking() // Buttons control the finite QA sequence, not event injection.
        return result != nil
    }
    func qaMove(over id: String) async {
        guard let token = dragToken, let window = sourceWindow, let viewport, let frame = cardFrames[id] else { return }
        let target = viewport.convert(CGPoint(x: frame.midX, y: frame.minY + 60), to: nil)
        let start = pointer
        for step in 1...36 {
            guard accepts(token: token, window: window) else { return }
            let p = CGFloat(step) / 36
            updateDrag(token: token, point: CGPoint(x: start.x + (target.x - start.x) * p,
                                                    y: start.y + (target.y - start.y) * p), window: window)
            try? await Task.sleep(for: .milliseconds(25))
        }
    }
    func qaRelease(outside: Bool = false) {
        guard let token = dragToken, let window = sourceWindow, let viewport else { return }
        let point = outside ? viewport.convert(CGPoint(x: -20, y: -20), to: nil) : pointer
        finishDrag(token: token, point: point, window: window)
    }
    func qaCancelPendingRelease() async -> Bool {
        guard let token = dragToken, let window = sourceWindow, !settling else { return false }
        var commits = 0
        commit = { _ in commits += 1 }
        framesAreCurrent = false
        finishDrag(token: token, point: pointer, window: window)
        let deferred = pendingRelease
        cancelDrag(animated: true)
        updateCardFrames(cardFrames) // Simulate the late geometry publication.
        try? await Task.sleep(for: .milliseconds(350))
        return deferred && commits == 0 && liveOrder == nil && draggedID == nil
    }
    var qaPreviewDescription: String {
        guard let preview, let host = previewHost else { return "无悬浮图像" }
        let attached = preview.superview === host && host.window === sourceWindow
        return "预览承载：\(attached ? "已连接" : "未连接") · 图像 \(Int(preview.frame.width))×\(Int(preview.frame.height))"
    }
    #endif

    func clear() {
        endDrag(); editingNonce = nil; allowedIDs = []; targets = [:]; cardFrames = [:]; cardBodyFrames = [:]
    }
}

/// SwiftUI owns the overlay's placement/z-order. Only this native view owns its
/// image subview, so live reordering cannot replace or cover the drag preview.
struct HomeLayoutPreviewBridge: NSViewRepresentable {
    let session: HomeLayoutDragSession
    func makeNSView(context: Context) -> HomeLayoutPreviewHostView { HomeLayoutPreviewHostView() }
    func updateNSView(_ view: HomeLayoutPreviewHostView, context: Context) {
        view.session = session
        session.setPreviewHost(view)
    }
    static func dismantleNSView(_ view: HomeLayoutPreviewHostView, coordinator: ()) {
        view.session?.removePreviewHost(view)
    }
}

final class HomeLayoutPreviewHostView: NSView {
    weak var session: HomeLayoutDragSession?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// This single bridge is sized to the ScrollView, outside the custom card
/// Layout. Its flipped bounds share SwiftUI's named viewport coordinate space.
struct HomeLayoutViewportBridge: NSViewRepresentable {
    let session: HomeLayoutDragSession
    func makeNSView(context: Context) -> HomeLayoutViewportView { HomeLayoutViewportView() }
    func updateNSView(_ view: HomeLayoutViewportView, context: Context) {
        view.session = session
        session.setViewport(view)
    }
    static func dismantleNSView(_ view: HomeLayoutViewportView, coordinator: ()) {
        view.session?.removeViewport(view)
    }
}

final class HomeLayoutViewportView: NSView {
    weak var session: HomeLayoutDragSession?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct HomeLayoutEditingCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let group: HomeProviderGroup
    let index: Int
    let count: Int
    @ObservedObject var dragSession: HomeLayoutDragSession
    let move: (Int) -> Void
    let order: [String]
    let commit: ([String]) -> Void

    private var presentation: HomeCardPresentation {
        let copiedID: UUID?
        if case .secret(let id) = model.copyFeedback { copiedID = id } else { copiedID = nil }
        return HomeCardPresentation(group: group, copiedEntryID: copiedID)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("第 \(index + 1) 项").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 0)
                Button { move(-1) } label: { Image(systemName: "arrow.up").frame(width: 23, height: 23) }
                    .disabled(index == 0)
                    .help("前移 \(group.name)")
                    .accessibilityLabel("前移 \(group.name)")
                    .accessibilityIdentifier("keynest.home.layout.up.\(group.id)")
                Button { move(1) } label: { Image(systemName: "arrow.down").frame(width: 23, height: 23) }
                    .disabled(index == count - 1)
                    .help("后移 \(group.name)")
                    .accessibilityLabel("后移 \(group.name)")
                    .accessibilityIdentifier("keynest.home.layout.down.\(group.id)")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            HomeProviderCard(group: group)
                .disabled(true)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: HomeLayoutCardBodyFrames.self,
                            value: [group.id: geometry.frame(in: .named(HomeLayoutGeometry.coordinateSpace))])
                    }
                }
                .opacity(dragSession.draggedID == group.id ? 0.001 : 1)
                .overlay {
                    if dragSession.draggedID == group.id {
                        RoundedRectangle(cornerRadius: 16).fill(Color.accentColor.opacity(0.025))
                            .overlay(RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.accentColor.opacity(0.20), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                            .allowsHitTesting(false)
                    } else if dragSession.settledID == group.id {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
                .overlay {
                    HomeLayoutDragSource(presentation: presentation, id: group.id, colorScheme: colorScheme,
                                         reduceMotion: reduceMotion, dragSession: dragSession, order: order, commit: commit)
                        .accessibilityHidden(true)
                }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: HomeLayoutCardFrames.self,
                    value: [group.id: geometry.frame(in: .named(HomeLayoutGeometry.coordinateSpace))])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(group.name)，第 \(index + 1) 项，共 \(count) 项")
        .accessibilityIdentifier("keynest.home.layout.card.\(group.id)")
    }
}

/// The overlay receives ordinary window mouse events, including background
/// first-click events. Every target is a weak view in this same Home session.
private struct HomeLayoutDragSource: NSViewRepresentable {
    let presentation: HomeCardPresentation
    let id: String
    let colorScheme: ColorScheme
    let reduceMotion: Bool
    let dragSession: HomeLayoutDragSession
    let order: [String]
    let commit: ([String]) -> Void

    func makeNSView(context: Context) -> HomeCardDragView { HomeCardDragView() }
    func updateNSView(_ view: HomeCardDragView, context: Context) {
        view.configure(presentation: presentation, id: id, colorScheme: colorScheme,
                       reduceMotion: reduceMotion, session: dragSession, order: order, commit: commit)
    }
    static func dismantleNSView(_ view: HomeCardDragView, coordinator: ()) { view.detach() }
}

private final class HomeCardDragView: NSView {
    private var presentation: HomeCardPresentation?
    private var colorScheme = ColorScheme.light
    private var reduceMotion = false
    private var providerID = ""
    private weak var session: HomeLayoutDragSession?
    private var order: [String] = []
    private var commit: (([String]) -> Void)?
    private var pressedAt: NSPoint?
    private var token: HomeLayoutDragSession.Token?

    func configure(presentation: HomeCardPresentation, id: String, colorScheme: ColorScheme,
                   reduceMotion: Bool, session: HomeLayoutDragSession, order: [String],
                   commit: @escaping ([String]) -> Void) {
        if self.session !== session || providerID != id { detach() }
        self.presentation = presentation; self.colorScheme = colorScheme
        self.reduceMotion = reduceMotion; providerID = id; self.session = session; self.order = order; self.commit = commit
        session.register(self, id: id)
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        // A fresh press cancels any incomplete old gesture, including synthetic
        // event sequences that did not deliver a matching mouseUp.
        session?.endDrag(); token = nil
        pressedAt = event.locationInWindow
        window?.makeFirstResponder(self)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let origin = pressedAt, let session, let window, let presentation, let commit else { return }
        let point = event.locationInWindow
        if token == nil {
            guard hypot(point.x - origin.x, point.y - origin.y) >= 6 else { return }
            token = session.beginDrag(id: providerID, presentation: presentation, order: order, colorScheme: colorScheme,
                                      reduceMotion: reduceMotion, view: self, pressedAt: origin, point: point, commit: commit)
        }
        guard let token else { return }
        session.updateDrag(token: token, point: point, window: window)
        NSCursor.closedHand.set()
    }
    override func mouseUp(with event: NSEvent) {
        defer { token = nil; pressedAt = nil; NSCursor.openHand.set() }
        guard let token, let session, let window else { return }
        session.finishDrag(token: token, point: event.locationInWindow, window: window)
    }
    override func cancelOperation(_ sender: Any?) { session?.cancelDrag(animated: true); resetPress() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { resetPress() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidHide() { super.viewDidHide(); resetPress() }

    private func resetPress() {
        token = nil; pressedAt = nil; NSCursor.arrow.set()
    }
    func detach() {
        resetPress(); session?.unregister(self, id: providerID)
        session = nil; commit = nil; presentation = nil; order = []
    }
}

/// A static Retina rendering of the displayed card metadata. It takes no events
/// or focus and is removed on release, cancellation, lock, or leaving Home.
private final class HomeLayoutDragPreviewView: NSView {
    private let image: NSImage
    let originalSize: CGSize
    init(image: NSImage, size: CGSize, scale: CGFloat, reduceMotion: Bool) {
        self.image = image; originalSize = size
        super.init(frame: NSRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale)))
        setAccessibilityElement(false)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = reduceMotion ? 0.12 : 0.20
        layer?.shadowRadius = reduceMotion ? 7 : 14
        layer?.shadowOffset = CGSize(width: 0, height: -5)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }
}
