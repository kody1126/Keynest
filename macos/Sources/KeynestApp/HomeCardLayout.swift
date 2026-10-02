import SwiftUI

/// Cards keep their natural height. The next provider starts in the shortest
/// column instead of waiting for every card in a grid row to finish.
/// A single ForEach retains card identity (and its popover) across reflow.
struct HomeCardLayout: Layout {
    private let minimumCardWidth: CGFloat = 300
    private let maximumCardWidth: CGFloat = 440
    private let spacing: CGFloat = 16

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
        // SwiftUI can probe with an unspecified, zero, or infinite width.
        let width = proposedWidth.flatMap { $0.isFinite ? max(0, $0) : nil } ?? minimumCardWidth
        guard !subviews.isEmpty else { return (CGSize(width: width, height: 0), []) }
        let columnCount = max(1, Int((width + spacing) / (minimumCardWidth + spacing)))
        let cardWidth = min(maximumCardWidth, max(0, (width - CGFloat(columnCount - 1) * spacing) / CGFloat(columnCount)))
        let cardProposal = ProposedViewSize(width: cardWidth, height: nil)
        var columnBottoms = Array(repeating: CGFloat.zero, count: columnCount)
        var frames: [CGRect] = []
        frames.reserveCapacity(subviews.count)

        for subview in subviews {
            // Strict comparison gives ties a stable left-to-right order.
            let column = columnBottoms.indices.min { columnBottoms[$0] < columnBottoms[$1] } ?? 0
            let height = subview.sizeThatFits(cardProposal).height
            frames.append(CGRect(x: CGFloat(column) * (cardWidth + spacing), y: columnBottoms[column],
                                 width: cardWidth, height: height))
            columnBottoms[column] += height + spacing
        }
        return (CGSize(width: width, height: max(0, (columnBottoms.max() ?? 0) - spacing)), frames)
    }
}
