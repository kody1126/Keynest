import Foundation
import CoreGraphics

@main struct HomeLayoutChecks {
    static func main() {
        var assertions = 0
        func check(_ value: Bool, _ message: String) {
            assertions += 1
            precondition(value, message)
        }
        let ids = ["a", "b", "c", "d", "e"]
        let viewport = CGRect(x: 0, y: 0, width: 1000, height: 750)
        func frames(_ order: [String], width: CGFloat = 1000) -> [String: CGRect] {
            let heights: [String: CGFloat] = ["a": 220, "b": 350, "c": 180, "d": 260, "e": 200]
            let layout = HomeMasonryGeometry.arrange(width: width, heights: order.map { heights[$0] ?? 220 })
            return Dictionary(uniqueKeysWithValues: zip(order, layout.frames))
        }
        func inside(_ frame: CGRect, y: CGFloat = 24) -> CGPoint { CGPoint(x: frame.midX, y: frame.minY + y) }
        check(HomeLayoutReorder(source: "unknown", order: ids) == nil, "missing source rejected")
        check(HomeLayoutReorder(source: "a", order: ["a", "a"]) == nil, "duplicate IDs rejected")
        var state = HomeLayoutReorder(source: "a", order: ids)!
        let initial = frames(ids)
        let topGripTarget = inside(initial["b"]!)
        check(state.hover(at: topGripTarget, frames: initial, viewport: viewport) == .init(id: "b", before: false), "same-row top grip crosses target without requiring lower half")
        check(state.order == ["b", "a", "c", "d", "e"], "hover updates order before any release")
        check(state.original == ids, "original draft retained")
        let changed = frames(state.order)
        for _ in 0..<100 {
            check(state.hover(at: topGripTarget, frames: changed, viewport: viewport) == nil, "stationary reflow must not oscillate")
            check(state.order == ["b", "a", "c", "d", "e"], "hover latch preserves slot")
        }
        let newTarget = inside(changed["c"]!)
        check(state.hover(at: newTarget, frames: changed, viewport: viewport) != nil, "leaving latched target allows next crossing")
        check(state.order == ["b", "c", "a", "d", "e"], "continued cross-column movement")
        let reverseFrames = frames(state.order)
        check(state.hover(at: inside(reverseFrames["b"]!), frames: reverseFrames, viewport: viewport) != nil, "gesture can reverse without waiting for completion")
        check(state.order == ids, "reverse restores initial order")
        check(state.canDrop(at: inside(frames(state.order)["a"]!), frames: frames(state.order), viewport: viewport), "placeholder itself accepts release")
        check(!state.canDrop(at: CGPoint(x: 400, y: -1), frames: initial, viewport: viewport), "outside release invalid")
        check(!state.canDrop(at: CGPoint(x: 400, y: 740), frames: initial, viewport: viewport), "blank tail release invalid")
        check(!state.canDrop(at: CGPoint(x: CGFloat.infinity, y: 1), frames: initial, viewport: viewport), "nonfinite release invalid")
        var overlap = initial; overlap["b"] = initial["c"]
        check(!state.canDrop(at: inside(initial["c"]!), frames: overlap, viewport: viewport), "ambiguous release fails closed")
        var ambiguous = HomeLayoutReorder(source: "a", order: ids)!
        check(ambiguous.hover(at: inside(initial["c"]!), frames: overlap, viewport: viewport) == nil, "ambiguous hover fails closed")
        check(ambiguous.order == ids, "ambiguous hover does not mutate")
        var edge = HomeLayoutReorder(source: "a", order: ids)!
        check(edge.hover(at: CGPoint(x: initial["b"]!.minX + 2, y: 2), frames: initial, viewport: viewport) == nil, "edge brush does not reorder")
        // Cancellation discards only this state's working order. A second drag
        // starts from an already edited draft, not from the saved/default order.
        let priorDraft = ["b", "c", "a", "d", "e"]
        var second = HomeLayoutReorder(source: "e", order: priorDraft)!
        _ = second.hover(at: inside(frames(priorDraft)["b"]!), frames: frames(priorDraft), viewport: viewport)
        check(second.original == priorDraft, "cancel restores immediately preceding draft")
        check(second.order != second.original, "second gesture made a tentative change")
        var scrolling = HomeLayoutReorder(source: "a", order: ids)!
        _ = scrolling.hover(at: topGripTarget, frames: initial, viewport: viewport)
        scrolling.scrolled(by: 400)
        var scrolledFrames = frames(scrolling.order)
        // New content moves under a stationary pointer during edge scrolling.
        scrolledFrames["d"] = CGRect(x: 340, y: 0, width: 300, height: 220)
        scrolledFrames["a"] = CGRect(x: 0, y: -500, width: 300, height: 220)
        scrolledFrames["b"] = CGRect(x: 0, y: -800, width: 300, height: 350)
        scrolledFrames["e"] = CGRect(x: 0, y: 800, width: 300, height: 200)
        check(scrolling.hover(at: topGripTarget, frames: scrolledFrames, viewport: viewport) != nil, "scroll displacement releases stationary pointer latch")
        for width: CGFloat in [0, 280, 650, 1000, 1380] {
            for order in [ids, ids.reversed().map { $0 }, ["c", "a", "e", "b", "d"]] {
                let geometry = HomeMasonryGeometry.arrange(width: width, heights: order.map { $0 == "b" ? 350 : 220 })
                check(geometry.frames.count == order.count, "masonry retains every card")
                for i in geometry.frames.indices {
                    for j in geometry.frames.indices where j > i {
                        check(!geometry.frames[i].intersects(geometry.frames[j]), "variable-height frames never overlap")
                    }
                }
            }
        }
        let first = HomeMasonryGeometry.arrange(width: 1000, heights: [220, 350, 180, 260]).frames
        check(first[3].minX == first[2].minX && first[3].minY == 196, "shortest column fills first without row gaps")
        for flipped in [true, false] {
            for scale: CGFloat in [1, 1.015] {
                for grip in [CGPoint(x: 5, y: 7), CGPoint(x: 180, y: 140), CGPoint(x: 310, y: 290)] {
                    for pointer in [CGPoint(x: -50, y: 100), CGPoint(x: 850, y: -20)] {
                        let r = HomeDragPreviewGeometry.frame(pointer: pointer, grip: grip, size: CGSize(width: 330, height: 300), scale: scale, flipped: flipped)
                        let reconstructed = CGPoint(x: r.minX + grip.x * scale, y: flipped ? r.minY + grip.y * scale : r.maxY - grip.y * scale)
                        check(abs(reconstructed.x - pointer.x) < 0.0001 && abs(reconstructed.y - pointer.y) < 0.0001, "original grip follows 1:1 in both AppKit orientations/reduced motion")
                    }
                }
            }
        }
        // Arbitrary catalog lengths still preserve a permutation for every pair.
        let many = (0..<180).map(String.init)
        for source in many {
            for target in ["0", "79", "80", "179"] where source != target {
                let moved = HomeLayoutReorder.moving(source, to: .init(id: target, before: false), in: many)
                check(moved.count == many.count && Set(moved) == Set(many), "pagination-sized moves cannot duplicate/drop IDs")
            }
        }
        print("Home layout checks passed: \(assertions) assertions; no window, vault, network, or clipboard.")
    }
}
