import SwiftUI

struct HeatmapCellTarget: Equatable {
    let row: Int
    let hour: Int
}

struct DailyHeatmapCellTarget: Equatable {
    let row: Int
    let column: Int
}

enum DashboardLayout {
    static let sidebarWidth: CGFloat = 188
    static let contentSpacing: CGFloat = 12
    static let leaderboardSectionSpacing: CGFloat = 48
    static let chartAxisLabelWidth: CGFloat = 46
    static let heatmapWeekdayLabelWidth: CGFloat = 30
    static let heatmapColumnSpacing: CGFloat = 4
    static let heatmapRowSpacing: CGFloat = 7
    static let recordColumnTitles = [
        "日期", "模型", "首字", "输入 TOKEN", "输出 TOKEN", "缓存 TOKEN", "预估费用",
    ]
    static let recordMinimumTableWidth: CGFloat = 820
    static let recordEdgeInset: CGFloat = 16
    private static let recordBaseColumnWidths: [CGFloat] = [135, 155, 85, 105, 110, 110, 120]
    private static let recordExtraWidthWeights: [CGFloat] = [0.18, 0.26, 0.08, 0.10, 0.12, 0.12, 0.14]

    static func summaryColumnCount(for width: CGFloat) -> Int {
        width >= 900 ? 5 : 2
    }

    static func analyticsColumnCount(for width: CGFloat) -> Int {
        width >= 900 ? 2 : 1
    }

    static func heatmapCellSize(for width: CGFloat) -> CGFloat {
        let spacingCount: CGFloat = 24
        let available = width - heatmapWeekdayLabelWidth - heatmapColumnSpacing * spacingCount
        return min(max(available / 24, 5), 14)
    }

    static func heatmapGridWidth(cellSize: CGFloat) -> CGFloat {
        heatmapWeekdayLabelWidth
            + heatmapColumnSpacing * 24
            + cellSize * 24
    }

    static func heatmapPlotHeight(cellSize: CGFloat) -> CGFloat {
        cellSize * 7 + heatmapRowSpacing * 6
    }

    static func dailyHeatmapColumnCount(dataWeekCount: Int) -> Int {
        max(24, dataWeekCount)
    }

    static func dailyHeatmapLeadingColumnCount(dataWeekCount: Int) -> Int {
        max(dailyHeatmapColumnCount(dataWeekCount: dataWeekCount) - dataWeekCount, 0)
    }

    static func dailyHeatmapCellTarget(
        at point: CGPoint,
        cellSize: CGFloat,
        columnCount: Int,
        weekdayLabelWidth: CGFloat = 18,
        columnSpacing: CGFloat = 4,
        rowSpacing: CGFloat = 4
    ) -> DailyHeatmapCellTarget? {
        guard cellSize > 0, columnCount > 0 else { return nil }

        let firstCellX = weekdayLabelWidth + columnSpacing
        let localX = point.x - firstCellX
        guard localX >= 0, point.y >= 0 else { return nil }

        let columnStep = cellSize + columnSpacing
        let rowStep = cellSize + rowSpacing
        let column = Int(localX / columnStep)
        let row = Int(point.y / rowStep)

        guard (0..<columnCount).contains(column), (0..<7).contains(row) else { return nil }
        guard localX - CGFloat(column) * columnStep < cellSize else { return nil }
        guard point.y - CGFloat(row) * rowStep < cellSize else { return nil }
        return DailyHeatmapCellTarget(row: row, column: column)
    }

    static func heatmapCellTarget(
        at point: CGPoint,
        cellSize: CGFloat
    ) -> HeatmapCellTarget? {
        guard cellSize > 0 else { return nil }

        let firstCellX = heatmapWeekdayLabelWidth + heatmapColumnSpacing
        let localX = point.x - firstCellX
        guard localX >= 0, point.y >= 0 else { return nil }

        let columnStep = cellSize + heatmapColumnSpacing
        let rowStep = cellSize + heatmapRowSpacing
        let hour = Int(localX / columnStep)
        let row = Int(point.y / rowStep)

        guard (0..<24).contains(hour), (0..<7).contains(row) else { return nil }
        guard localX - CGFloat(hour) * columnStep < cellSize else { return nil }
        guard point.y - CGFloat(row) * rowStep < cellSize else { return nil }
        return HeatmapCellTarget(row: row, hour: hour)
    }

    static func visibleChartLabelIndices(count: Int, interval: Int) -> [Int] {
        guard count > 0 else { return [] }
        return Array(stride(from: 0, to: count, by: max(interval, 1)))
    }

    static func filterContainerHeight(
        rowHeight: CGFloat,
        panelHeight _: CGFloat?,
        verticalGap _: CGFloat
    ) -> CGFloat {
        rowHeight
    }

    static func filterDropdownX(
        index: Int,
        buttonCount: Int,
        availableWidth: CGFloat,
        gap: CGFloat,
        panelWidth: CGFloat
    ) -> CGFloat {
        guard buttonCount > 0, availableWidth > panelWidth else { return 0 }
        let count = CGFloat(buttonCount)
        let buttonWidth = (availableWidth - gap * CGFloat(buttonCount - 1)) / count
        let buttonCenter = CGFloat(index) * (buttonWidth + gap) + buttonWidth / 2
        let centered = buttonCenter - panelWidth / 2
        return min(max(0, centered), availableWidth - panelWidth)
    }

    static func filterOverlayFrame(
        buttonFrame: CGRect,
        panelSize: CGSize,
        viewportSize: CGSize,
        gap: CGFloat = 6,
        edgeInset: CGFloat = 4
    ) -> CGRect {
        let availableWidth = max(viewportSize.width - edgeInset * 2, 0)
        let availableHeight = max(viewportSize.height - edgeInset * 2, 0)
        let width = min(panelSize.width, availableWidth)
        let height = min(panelSize.height, availableHeight)
        let minX = edgeInset
        let maxX = max(edgeInset, viewportSize.width - edgeInset - width)
        let x = min(max(buttonFrame.midX - width / 2, minX), maxX)

        let belowY = buttonFrame.maxY + gap
        let aboveY = buttonFrame.minY - gap - height
        let maxY = max(edgeInset, viewportSize.height - edgeInset - height)
        let y: CGFloat
        if belowY + height <= viewportSize.height - edgeInset {
            y = belowY
        } else if aboveY >= edgeInset {
            y = aboveY
        } else {
            y = min(max(belowY, edgeInset), maxY)
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func shouldDismissFilter(
        at point: CGPoint,
        protectedFrames: [CGRect]
    ) -> Bool {
        !protectedFrames.contains { $0.contains(point) }
    }

    static func recordColumnWidths(for availableWidth: CGFloat) -> [CGFloat] {
        let tableWidth = max(availableWidth, recordMinimumTableWidth)
        let extraWidth = tableWidth - recordMinimumTableWidth
        return zip(recordBaseColumnWidths, recordExtraWidthWeights).map { base, weight in
            base + extraWidth * weight
        }
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

struct DashboardPairLayout: Layout {
    var spacing: CGFloat
    var minimumHorizontalWidth: CGFloat

    struct Cache {
        var width: CGFloat = -1
        var isHorizontal = false
        var sizes: [CGSize] = []
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) -> CGSize {
        let width = max(proposal.width ?? minimumHorizontalWidth, 0)
        updateMeasurements(width: width, subviews: subviews, cache: &cache)
        let height: CGFloat
        if cache.isHorizontal {
            height = cache.sizes.map(\.height).max() ?? 0
        } else {
            height = cache.sizes.map(\.height).reduce(0, +)
                + spacing * CGFloat(max(cache.sizes.count - 1, 0))
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Cache
    ) {
        updateMeasurements(width: bounds.width, subviews: subviews, cache: &cache)

        if cache.isHorizontal {
            let itemWidth = max((bounds.width - spacing) / 2, 0)
            for index in subviews.indices {
                subviews[index].place(
                    at: CGPoint(
                        x: bounds.minX + CGFloat(index) * (itemWidth + spacing),
                        y: bounds.minY
                    ),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: itemWidth, height: cache.sizes[index].height)
                )
            }
        } else {
            var y = bounds.minY
            for index in subviews.indices {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: bounds.width, height: cache.sizes[index].height)
                )
                y += cache.sizes[index].height + spacing
            }
        }
    }

    private func updateMeasurements(
        width: CGFloat,
        subviews: Subviews,
        cache: inout Cache
    ) {
        guard cache.width != width || cache.sizes.count != subviews.count else { return }
        cache.width = width
        cache.isHorizontal = width >= minimumHorizontalWidth
        let childWidth = cache.isHorizontal ? max((width - spacing) / 2, 0) : width
        cache.sizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: childWidth, height: nil))
        }
    }
}
