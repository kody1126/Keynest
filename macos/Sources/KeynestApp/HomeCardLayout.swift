import SwiftUI

/// Cards keep their natural height. The next provider starts in the shortest
/// column instead of waiting for every card in a grid row to finish.
/// A single ForEach retains card identity (and its popover) across reflow.
struct HomeCardLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 anchor: .topLeading,
                                 proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    private func arrangement(width proposedWidth: CGFloat?, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let dimensions = HomeMasonryGeometry.dimensions(width: proposedWidth)
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: dimensions.cardWidth, height: nil)).height }
        return HomeMasonryGeometry.arrange(width: proposedWidth, heights: heights)
    }
}
