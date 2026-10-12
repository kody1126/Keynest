import Foundation
import CoreGraphics

/// Pure pointer-based ordering. A latch covers the card that yielded its slot:
/// reflow under a stationary pointer must never trigger a second, reverse move.
struct HomeLayoutReorder {
    struct Destination: Equatable {
        let id: String
        let before: Bool
    }
    let source: String
    let original: [String]
    private(set) var order: [String]
    private var yieldedRegion: CGRect?

    init?(source: String, order: [String]) {
        guard order.contains(source), Set(order).count == order.count else { return nil }
        self.source = source; original = order; self.order = order
    }

    mutating func hover(at point: CGPoint, frames: [String: CGRect], viewport: CGRect) -> Destination? {
        guard viewport.contains(point), point.x.isFinite, point.y.isFinite else { return nil }
        if let yieldedRegion, yieldedRegion.contains(point) { return nil }
        yieldedRegion = nil
        // The inner band avoids accidental changes while brushing card edges.
        let hits = frames.filter { id, frame in
            id != source && order.contains(id) && Self.valid(frame) &&
                frame.insetBy(dx: min(12, frame.width / 8), dy: min(12, frame.height / 8)).contains(point)
        }
        guard hits.count == 1, let hit = hits.first else { return nil }
        // Crossing an item moves past it in the direction of travel. Using the
        // vertical half alone makes same-row drags from a top grip do nothing.
        guard let sourceIndex = order.firstIndex(of: source), let targetIndex = order.firstIndex(of: hit.key) else { return nil }
        let destination = Destination(id: hit.key, before: targetIndex < sourceIndex)
        let next = Self.moving(source, to: destination, in: order)
        guard next != order else { return nil }
        order = next
        yieldedRegion = hit.value.insetBy(dx: -10, dy: -10)
        return destination
    }

    mutating func scrolled(by delta: CGFloat) {
        if let region = yieldedRegion { yieldedRegion = region.offsetBy(dx: 0, dy: -delta) }
    }

    func canDrop(at point: CGPoint, frames: [String: CGRect], viewport: CGRect) -> Bool {
        guard viewport.contains(point), point.x.isFinite, point.y.isFinite else { return false }
        // Include the moving placeholder. Releasing in the toolbar, blank tail,
        // outside the viewport, or ambiguous geometry cancels this gesture.
        return frames.filter { order.contains($0.key) && Self.valid($0.value) && $0.value.contains(point) }.count == 1
    }

    static func moving(_ source: String, to destination: Destination, in order: [String]) -> [String] {
        guard source != destination.id, order.contains(source), order.contains(destination.id),
              Set(order).count == order.count else { return order }
        var result = order.filter { $0 != source }
        guard let index = result.firstIndex(of: destination.id) else { return order }
        result.insert(source, at: index + (destination.before ? 0 : 1))
        return result
    }

    static func valid(_ frame: CGRect) -> Bool {
        !frame.isNull && !frame.isInfinite && frame.minX.isFinite && frame.minY.isFinite &&
            frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0
    }
}

/// Deterministic masonry geometry shared by the live Layout and headless checks.
enum HomeMasonryGeometry {
    static let spacing: CGFloat = 16
    static func dimensions(width proposed: CGFloat?) -> (width: CGFloat, columns: Int, cardWidth: CGFloat) {
        let width = proposed.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 300
        let columns = max(1, Int((width + spacing) / (300 + spacing)))
        return (width, columns, min(440, max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))))
    }
    static func arrange(width proposed: CGFloat?, heights: [CGFloat]) -> (size: CGSize, frames: [CGRect]) {
        let d = dimensions(width: proposed)
        var bottoms = Array(repeating: CGFloat.zero, count: d.columns)
        var frames: [CGRect] = []
        for proposedHeight in heights {
            let height = proposedHeight.isFinite ? max(0, proposedHeight) : 0
            let column = bottoms.indices.min { bottoms[$0] < bottoms[$1] } ?? 0
            frames.append(CGRect(x: CGFloat(column) * (d.cardWidth + spacing), y: bottoms[column], width: d.cardWidth, height: height))
            bottoms[column] += height + spacing
        }
        return (CGSize(width: d.width, height: max(0, (bottoms.max() ?? 0) - spacing)), frames)
    }
}

enum HomeDragPreviewGeometry {
    static func frame(pointer: CGPoint, grip: CGPoint, size: CGSize, scale: CGFloat, flipped: Bool) -> CGRect {
        let scaled = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: pointer.x - grip.x * scale,
                      y: flipped ? pointer.y - grip.y * scale : pointer.y - (scaled.height - grip.y * scale),
                      width: scaled.width, height: scaled.height)
    }
}
