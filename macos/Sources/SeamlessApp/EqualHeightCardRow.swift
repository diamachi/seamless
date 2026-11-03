import SwiftUI

/// Shares the measured height so card backgrounds end on the same baseline.
struct EqualHeightCardRow: Layout {
    var spacing: CGFloat = 20

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(660, proposal.width ?? 900)
        let cellWidth = (width - spacing) / 2
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cellWidth = (bounds.width - spacing) / 2
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (cellWidth + spacing), y: bounds.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(width: cellWidth, height: bounds.height))
        }
    }
}
