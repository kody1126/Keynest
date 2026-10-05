import SwiftUI
import AppKit
import KeynestCore

enum HomeLayoutGeometry {
    static let coordinateSpace = "keynest.home.layout.viewport"
}

struct HomeLayoutCardFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

/// A window-local gesture session. No system drag session or pasteboard is used.
/// Both the edit nonce and gesture nonce must match before a release can commit.
@MainActor final class HomeLayoutDragSession: ObservableObject {
    struct Destination: Equatable {
        let id: String
        let before: Bool
    }
    struct Token: Equatable {
        let editing: UUID
        let gesture: UUID
    }
    private struct Target { weak var view: HomeCardDragView? }
    @Published private(set) var draggedID: String?
    @Published private(set) var destination: Destination?
    private var editingNonce: UUID?
    private var dragToken: Token?
    private var allowedIDs = Set<String>()
    private var targets: [String: Target] = [:]
    private var cardFrames: [String: CGRect] = [:]
    private var framesAreCurrent = true
    private weak var viewport: HomeLayoutViewportView?
    private weak var sourceView: HomeCardDragView?
    private weak var sourceWindow: NSWindow?
    private var preview: HomeLayoutDragPreviewView?

    func activate(ids: [String]) {
        clear()
        editingNonce = UUID()
        allowedIDs = Set(ids)
    }

    func updateIDs(_ ids: [String]) {
        allowedIDs = Set(ids)
        if let draggedID, !allowedIDs.contains(draggedID) { endDrag() }
        if let destination, !allowedIDs.contains(destination.id) { self.destination = nil }
    }

    func updateCardFrames(_ frames: [String: CGRect]) {
        cardFrames = frames.filter { _, frame in
            !frame.isNull && !frame.isInfinite && frame.width > 0 && frame.height > 0
        }
        framesAreCurrent = true
    }

    fileprivate func setViewport(_ view: HomeLayoutViewportView) { viewport = view }

    fileprivate func removeViewport(_ view: HomeLayoutViewportView) {
        if viewport === view { endDrag(); viewport = nil; cardFrames = [:] }
    }

    fileprivate func register(_ view: HomeCardDragView, id: String) {
        guard editingNonce != nil else { return }
        targets[id] = Target(view: view)
    }

    fileprivate func unregister(_ view: HomeCardDragView, id: String) {
        if targets[id]?.view === view { targets[id] = nil }
        if sourceView === view { endDrag() }
    }

    fileprivate func beginDrag(id: String, title: String, view: HomeCardDragView,
                               point: NSPoint) -> Token? {
        guard let editingNonce, allowedIDs.contains(id), targets[id]?.view === view,
              let window = view.window, let content = window.contentView else { return nil }
        endDrag()
        let token = Token(editing: editingNonce, gesture: UUID())
        dragToken = token; draggedID = id; sourceView = view; sourceWindow = window
        let preview = HomeLayoutDragPreviewView(title: title)
        self.preview = preview
        content.addSubview(preview, positioned: .above, relativeTo: nil)
        updateDrag(token: token, point: point, window: window)
        return token
    }

    fileprivate func updateDrag(token: Token, point: NSPoint, window: NSWindow, scrollAtEdge: Bool = false) {
        guard accepts(token: token, window: window) else { return }
        if scrollAtEdge, let viewport, viewport.window === window {
            autoscrollAtViewportEdge(viewport.convert(point, from: nil), viewport: viewport)
        }
        let next = target(at: point, window: window)
        if destination != next { destination = next }
        if let content = window.contentView, let preview {
            let local = content.convert(point, from: nil)
            let width: CGFloat = 240, height: CGFloat = 62
            let preferredY = content.isFlipped ? local.y + 14 : local.y - height - 14
            preview.frame = NSRect(
                x: max(content.bounds.minX + 6, min(content.bounds.maxX - width - 6, local.x + 16)),
                y: max(content.bounds.minY + 6, min(content.bounds.maxY - height - 6, preferredY)),
                width: width, height: height)
        }
    }

    fileprivate func finishDrag(token: Token, point: NSPoint, window: NSWindow) -> (String, Destination)? {
        guard accepts(token: token, window: window), let source = draggedID else { return nil }
        let result = target(at: point, window: window).map { (source, $0) }
        endDrag(token: token)
        return result
    }

    private func accepts(token: Token, window: NSWindow) -> Bool {
        editingNonce == token.editing && dragToken == token && sourceWindow === window &&
            sourceView?.window === window && draggedID.map { allowedIDs.contains($0) } == true
    }

    private func target(at point: NSPoint, window: NSWindow) -> Destination? {
        guard framesAreCurrent, let viewport, viewport.window === window,
              !viewport.isHiddenOrHasHiddenAncestor else { return nil }
        // Native children of SwiftUI Layout can share unpositioned AppKit
        // frames. Resolve actual SwiftUI geometry instead of guessing from them.
        let local = viewport.convert(point, from: nil)
        guard viewport.bounds.contains(local) else { return nil }
        let matches = cardFrames.filter { id, frame in
            id != draggedID && allowedIDs.contains(id) && frame.contains(local)
        }
        // Ambiguous/stale geometry must never choose an arbitrary dictionary item.
        guard matches.count == 1, let match = matches.first else { return nil }
        return Destination(id: match.key, before: local.y < match.value.midY)
    }

    private func autoscrollAtViewportEdge(_ point: NSPoint, viewport: HomeLayoutViewportView) {
        guard viewport.bounds.contains(point), let scroll = sourceView?.enclosingScrollView,
              let document = scroll.documentView else { return }
        let edge: CGFloat = 28
        let direction: CGFloat
        if point.y < viewport.bounds.minY + edge { direction = -1 }
        else if point.y > viewport.bounds.maxY - edge { direction = 1 }
        else { return }
        let clip = scroll.contentView
        var origin = clip.bounds.origin
        let delta = direction * 16 * (document.isFlipped ? 1 : -1)
        origin.y = max(document.bounds.minY, min(document.bounds.maxY - clip.bounds.height, origin.y + delta))
        guard origin != clip.bounds.origin else { return }
        framesAreCurrent = false
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
    }

    func endDrag(token: Token? = nil) {
        if let token, token != dragToken { return }
        preview?.removeFromSuperview(); preview = nil
        draggedID = nil; destination = nil; dragToken = nil
        sourceView = nil; sourceWindow = nil
    }

    func clear() {
        endDrag(); editingNonce = nil; allowedIDs = []; targets = [:]; cardFrames = [:]
        framesAreCurrent = true
    }
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
    let group: HomeProviderGroup
    let index: Int
    let count: Int
    @ObservedObject var dragSession: HomeLayoutDragSession
    let move: (Int) -> Void
    let drop: (String, String, Bool) -> Void

    private var destination: HomeLayoutDragSession.Destination? {
        dragSession.destination.flatMap { $0.id == group.id ? $0 : nil }
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
                .overlay {
                    HomeLayoutDragSource(title: group.name, id: group.id, dragSession: dragSession, drop: drop)
                        .accessibilityHidden(true)
                }
        }
        .opacity(dragSession.draggedID == group.id ? 0.52 : 1)
        .overlay(alignment: destination?.before == false ? .bottom : .top) {
            if let destination {
                HStack(spacing: 6) {
                    Capsule().fill(Color.accentColor).frame(height: 3)
                    Text(destination.before ? "放在此平台之前" : "放在此平台之后")
                        .font(.caption2.weight(.medium)).fixedSize()
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                }
                .allowsHitTesting(false)
                .offset(y: destination.before ? -8 : 8)
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
    let title: String
    let id: String
    let dragSession: HomeLayoutDragSession
    let drop: (String, String, Bool) -> Void

    func makeNSView(context: Context) -> HomeCardDragView { HomeCardDragView() }
    func updateNSView(_ view: HomeCardDragView, context: Context) {
        view.configure(title: title, id: id, session: dragSession, drop: drop)
    }
    static func dismantleNSView(_ view: HomeCardDragView, coordinator: ()) { view.detach() }
}

private final class HomeCardDragView: NSView {
    private var title = ""
    private var providerID = ""
    private weak var session: HomeLayoutDragSession?
    private var drop: ((String, String, Bool) -> Void)?
    private var pressedAt: NSPoint?
    private var token: HomeLayoutDragSession.Token?

    func configure(title: String, id: String, session: HomeLayoutDragSession,
                   drop: @escaping (String, String, Bool) -> Void) {
        if self.session !== session || providerID != id { detach() }
        self.title = title; providerID = id; self.session = session; self.drop = drop
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
        guard let origin = pressedAt, let session, let window else { return }
        let point = event.locationInWindow
        if token == nil {
            guard hypot(point.x - origin.x, point.y - origin.y) >= 6 else { return }
            token = session.beginDrag(id: providerID, title: title, view: self, point: point)
        }
        guard let token else { return }
        session.updateDrag(token: token, point: point, window: window, scrollAtEdge: true)
        NSCursor.closedHand.set()
    }
    override func mouseUp(with event: NSEvent) {
        defer { token = nil; pressedAt = nil; NSCursor.openHand.set() }
        guard let token, let session, let window else { return }
        if let (source, target) = session.finishDrag(token: token, point: event.locationInWindow, window: window) {
            drop?(source, target.id, target.before)
        }
    }
    override func cancelOperation(_ sender: Any?) { cancel() }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancel() }
        super.viewWillMove(toWindow: newWindow)
    }
    override func viewDidHide() { super.viewDidHide(); cancel() }

    private func cancel() {
        if let token { session?.endDrag(token: token) }
        token = nil; pressedAt = nil; NSCursor.arrow.set()
    }
    func detach() {
        cancel(); session?.unregister(self, id: providerID)
        session = nil; drop = nil
    }
}

/// The preview contains only the platform title, takes no events or focus, and
/// is removed immediately on release, cancellation, lock, or leaving Home.
private final class HomeLayoutDragPreviewView: NSView {
    private let title: String
    init(title: String) {
        self.title = title
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 62))
        setAccessibilityElement(false)
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.withAlphaComponent(0.96).setFill()
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        shape.fill(); NSColor.controlAccentColor.setStroke(); shape.lineWidth = 2; shape.stroke()
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 16, y: 21, width: 208, height: 22), withAttributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph
        ])
    }
}
