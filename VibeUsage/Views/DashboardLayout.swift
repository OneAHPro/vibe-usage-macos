import SwiftUI

enum DashboardLayout {
    static let sidebarWidth: CGFloat = 188
    static let contentSpacing: CGFloat = 12

    static func summaryColumnCount(for width: CGFloat) -> Int {
        width >= 900 ? 5 : 2
    }

    static func analyticsColumnCount(for width: CGFloat) -> Int {
        width >= 900 ? 2 : 1
    }
}

struct DashboardMetricLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 900
        let columns = DashboardLayout.summaryColumnCount(for: width)
        let itemWidth = max((width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 0)
        let rowHeights = measuredRowHeights(subviews: subviews, columns: columns, itemWidth: itemWidth)
        return CGSize(
            width: width,
            height: rowHeights.reduce(0, +) + spacing * CGFloat(max(rowHeights.count - 1, 0))
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let columns = DashboardLayout.summaryColumnCount(for: bounds.width)
        let itemWidth = max((bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns), 0)
        let rowHeights = measuredRowHeights(subviews: subviews, columns: columns, itemWidth: itemWidth)
        var y = bounds.minY

        for index in subviews.indices {
            let row = index / columns
            let column = index % columns
            let x = bounds.minX + CGFloat(column) * (itemWidth + spacing)
            subviews[index].place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: itemWidth, height: rowHeights[row])
            )
            if column == columns - 1 || index == subviews.count - 1 {
                y += rowHeights[row] + spacing
            }
        }
    }

    private func measuredRowHeights(
        subviews: Subviews,
        columns: Int,
        itemWidth: CGFloat
    ) -> [CGFloat] {
        let rowCount = Int(ceil(Double(subviews.count) / Double(columns)))
        return (0..<rowCount).map { row in
            let start = row * columns
            let end = min(start + columns, subviews.count)
            return subviews[start..<end]
                .map { $0.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil)).height }
                .max() ?? 0
        }
    }
}
