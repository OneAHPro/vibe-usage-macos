import SwiftUI

struct ActivityHeatmapView: View {
    @Environment(AppState.self) private var appState
    @State private var metric: HeatmapMetric = .token

    private let weekdays: [(value: Int, label: String)] = [
        (2, "周一"), (3, "周二"), (4, "周三"), (5, "周四"),
        (6, "周五"), (7, "周六"), (1, "周日"),
    ]

    var body: some View {
        let heatmap = appState.activityHeatmap(for: metric)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                Text("分时活跃")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                metricSelector
            }
            .foregroundStyle(AppTheme.secondaryText)

            HeatmapGrid(heatmap: heatmap, metric: metric, weekdays: weekdays)
            .frame(height: 154)
            .overlay {
                if appState.isLoadingHeatmap {
                    AppTheme.surface
                        .overlay {
                            VStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在加载分时数据…")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppTheme.tertiaryText)
                            }
                        }
                }
            }

            HStack(spacing: 4) {
                Spacer()
                Text("少")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.tertiaryText)
                ForEach(0..<7, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(activityColor(intensity: Double(step + 1) / 7))
                        .frame(width: 10, height: 10)
                }
                Text("多")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(AppTheme.surface)
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }

    private func activityColor(intensity: Double) -> Color {
        guard intensity > 0 else { return AppTheme.separator.opacity(0.55) }
        let clamped = min(max(intensity, 0), 1)
        if metric == .cost {
            return AppTheme.costAccent.opacity(0.18 + clamped * 0.78)
        }
        return AppTheme.primaryText.opacity(0.18 + clamped * 0.68)
    }

    private var metricSelector: some View {
        HStack(spacing: 0) {
            ForEach(HeatmapMetric.allCases, id: \.rawValue) { option in
                Button {
                    metric = option
                } label: {
                    Text(option.label)
                        .font(.system(size: 10, weight: metric == option ? .semibold : .regular))
                        .foregroundStyle(metric == option ? AppTheme.surface : AppTheme.secondaryText)
                        .frame(minWidth: 42, minHeight: 22)
                        .background(metric == option ? AppTheme.primaryText : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(AppTheme.selectionBackground)
        .clipShape(Capsule())
    }
}

private struct HeatmapGrid: View {
    let heatmap: ActivityHeatmap
    let metric: HeatmapMetric
    let weekdays: [(value: Int, label: String)]

    @State private var hoveredTarget: HeatmapCellTarget?
    @State private var scroll = ScrollWatcher()

    var body: some View {
        GeometryReader { proxy in
            let cellSize = DashboardLayout.heatmapCellSize(for: proxy.size.width)
            let gridWidth = DashboardLayout.heatmapGridWidth(cellSize: cellSize)
            let plotHeight = DashboardLayout.heatmapPlotHeight(cellSize: cellSize)

            VStack(spacing: DashboardLayout.heatmapRowSpacing) {
                ZStack(alignment: .topLeading) {
                    VStack(spacing: DashboardLayout.heatmapRowSpacing) {
                        ForEach(weekdays, id: \.value) { weekday in
                            HStack(spacing: DashboardLayout.heatmapColumnSpacing) {
                                Text(weekday.label)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(AppTheme.tertiaryText)
                                    .frame(
                                        width: DashboardLayout.heatmapWeekdayLabelWidth,
                                        alignment: .leading
                                    )

                                ForEach(0..<24, id: \.self) { hour in
                                    RoundedRectangle(cornerRadius: 2.5)
                                        .fill(activityColor(
                                            intensity: heatmap.intensity(
                                                weekday: weekday.value,
                                                hour: hour
                                            )
                                        ))
                                        .frame(width: cellSize, height: cellSize)
                                }
                            }
                        }
                    }

                    GeometryReader { geometry in
                        Color.clear
                            .contentShape(Rectangle())
                            .allowsHitTesting(!scroll.isScrolling)
                            .onContinuousHover(coordinateSpace: .local) { phase in
                                switch phase {
                                case .active(let point):
                                    guard !scroll.isScrolling else { return }
                                    let target = DashboardLayout.heatmapCellTarget(
                                        at: point,
                                        cellSize: cellSize
                                    )
                                    if hoveredTarget != target { hoveredTarget = target }
                                case .ended:
                                    if hoveredTarget != nil { hoveredTarget = nil }
                                }
                            }

                        if let target = hoveredTarget,
                           weekdays.indices.contains(target.row) {
                            let weekday = weekdays[target.row]
                            let cellCenter = heatmapCellCenter(target, cellSize: cellSize)
                            let horizontalInset = min(CGFloat(98), geometry.size.width / 2)
                            let tooltipX = min(
                                max(cellCenter.x, horizontalInset),
                                max(horizontalInset, geometry.size.width - horizontalInset)
                            )
                            let tooltipY = cellCenter.y < 52
                                ? min(cellCenter.y + 40, geometry.size.height - 25)
                                : cellCenter.y - 36

                            tooltip(
                                weekday: weekday.label,
                                hour: target.hour,
                                value: heatmap.value(
                                    weekday: weekday.value,
                                    hour: target.hour
                                )
                            )
                            .position(x: tooltipX, y: tooltipY)
                            .allowsHitTesting(false)
                        }
                    }
                }
                .frame(width: gridWidth, height: plotHeight)

                HStack(spacing: DashboardLayout.heatmapColumnSpacing) {
                    Color.clear
                        .frame(width: DashboardLayout.heatmapWeekdayLabelWidth, height: 1)
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hour.isMultiple(of: 3) ? String(format: "%02d", hour) : "")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .frame(width: cellSize)
                    }
                }
                .frame(width: gridWidth)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .onAppear { scroll.start() }
        .onDisappear { scroll.stop() }
        .onChange(of: scroll.isScrolling) { _, scrolling in
            if scrolling, hoveredTarget != nil {
                hoveredTarget = nil
            }
        }
    }

    private func activityColor(intensity: Double) -> Color {
        guard intensity > 0 else { return AppTheme.separator.opacity(0.55) }
        let clamped = min(max(intensity, 0), 1)
        if metric == .cost {
            return AppTheme.costAccent.opacity(0.18 + clamped * 0.78)
        }
        return AppTheme.primaryText.opacity(0.18 + clamped * 0.68)
    }

    private func heatmapCellCenter(
        _ target: HeatmapCellTarget,
        cellSize: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: DashboardLayout.heatmapWeekdayLabelWidth
                + DashboardLayout.heatmapColumnSpacing
                + CGFloat(target.hour) * (cellSize + DashboardLayout.heatmapColumnSpacing)
                + cellSize / 2,
            y: CGFloat(target.row) * (cellSize + DashboardLayout.heatmapRowSpacing)
                + cellSize / 2
        )
    }

    private func tooltip(
        weekday: String,
        hour: Int,
        value: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(weekday)  \(String(format: "%02d:00", hour))")
                .fontWeight(.semibold)
                .foregroundStyle(AppTheme.primaryText)
            Text(tooltipValue(value))
                .foregroundStyle(tooltipValueColor(value))
        }
        .font(.system(size: 11))
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(AppTheme.tooltipBackground)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(AppTheme.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .fixedSize()
        .allowsHitTesting(false)
    }

    private func tooltipValue(_ value: Double) -> String {
        switch metric {
        case .token:
            return "Token: \(Formatters.formatExactNumber(Int(value.rounded())))"
        case .cost:
            return "费用: \(Formatters.formatCost(value))"
        }
    }

    private func tooltipValueColor(_ value: Double) -> Color {
        guard value > 0 else { return AppTheme.tertiaryText }
        return metric == .cost ? AppTheme.costAccent : AppTheme.secondaryText
    }
}
