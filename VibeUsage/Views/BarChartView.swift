import SwiftUI

private struct BarData: Identifiable, Equatable {
    let id: String // dayKey or hourKey
    var input: Int = 0
    var output: Int = 0
    var cached: Int = 0
    var total: Int { input + output + cached }
    var cost: Double = 0
    var activeMinutes: Double = 0
}

struct BarChartView: View {
    @Environment(AppState.self) private var appState

    private var isHourly: Bool {
        appState.presentedTimeRange.isHourly
    }

    private var filtered: [UsageBucket] {
        appState.dashboardData.buckets
    }

    private var chartData: [BarData] {
        // Aggregate by hour or day
        var buckets: [String: BarData] = [:]
        for bucket in filtered {
            let key = isHourly ? bucket.hourKey : bucket.dayKey
            if buckets[key] == nil {
                buckets[key] = BarData(id: key)
            }
            buckets[key]!.input += bucket.inputTokens
            // Reasoning tokens are priced as output, matching the web chart's
            // three token tiers: input, output, cache read.
            buckets[key]!.output += bucket.outputTokens + bucket.reasoningOutputTokens
            buckets[key]!.cached += bucket.cachedInputTokens
            buckets[key]!.cost += bucket.estimatedCost ?? 0
        }

        for session in appState.filteredSessions {
            let key = isHourly ? session.hourKey : session.dayKey
            if buckets[key] == nil {
                buckets[key] = BarData(id: key)
            }
            buckets[key]!.activeMinutes += Double(session.activeSeconds) / 60.0
        }

        if isHourly {
            // Generate hourly slots. For `.today` we start at local midnight
            // (slot count grows through the day, 1→24); for `.oneDay` we keep
            // the 24-slot rolling window ending at the current hour.
            let calendar = Calendar.current
            let now = Date()
            let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            let start: Date = {
                if appState.presentedTimeRange == .today {
                    return calendar.startOfDay(for: now)
                }
                return calendar.date(byAdding: .hour, value: -23, to: currentHour) ?? currentHour
            }()
            var result: [BarData] = []

            var hour = start
            while hour <= currentHour {
                let key = ISO8601Parser.utcHourKey(from: hour)
                result.append(buckets[key] ?? BarData(id: key))
                guard let next = calendar.date(byAdding: .hour, value: 1, to: hour) else { break }
                hour = next
            }
            return result
        } else {
            // Fill in all days in range
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let numDays = appState.visibleDayCount
            var result: [BarData] = []

            for i in stride(from: numDays - 1, through: 0, by: -1) {
                let endDay = today
                if let date = calendar.date(byAdding: .day, value: -i, to: endDay) {
                    let key = Formatters.dayKey(from: date, calendar: calendar)
                    result.append(buckets[key] ?? BarData(id: key))
                }
            }
            return result
        }
    }

    private func labelInterval(for count: Int) -> Int {
        if isHourly {
            if count <= 12 { return 3 }
            if count <= 18 { return 4 }
            return 6
        }
        if count <= 3 { return 1 }
        if count <= 7 { return 1 }
        if count <= 15 { return 3 }
        if count <= 45 { return 7 }
        if count <= 100 { return 14 }
        return 30
    }

    var body: some View {
        @Bindable var state = appState
        let data = chartData
        let maximumTotal = max(data.map(\.total).max() ?? 0, 1)
        let maximumCost = max(data.map(\.cost).max() ?? 0, 0.001)
        let maximumActiveMinutes = max(data.map(\.activeMinutes).max() ?? 0, 0.1)

        VStack(spacing: 0) {
            // Header
            HStack {
                Label(isHourly ? "每小时趋势" : "每日趋势", systemImage: "waveform.path.ecg")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(ChartMode.allCases, id: \.self) { mode in
                        Button(action: { state.chartMode = mode }) {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: state.chartMode == mode ? .medium : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(state.chartMode == mode ? AppTheme.selectionBackground : Color.clear)
                                .foregroundStyle(state.chartMode == mode ? AppTheme.primaryText : AppTheme.secondaryText)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2)
                .background(AppTheme.subtleSurface)
                .clipShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.bottom, 14)

            // The bars/tooltip/x-axis live in a child view that owns the hover
            // state. The expensive `chartData` aggregation is computed here in
            // the parent and passed down, so a hover change only re-renders the
            // lightweight child — it never re-runs the O(n) aggregation. This,
            // plus the single hover region inside ChartContent, keeps the
            // popover ScrollView smooth when the cursor passes over the chart.
            ChartContent(
                data: data,
                chartMode: state.chartMode,
                isHourly: isHourly,
                maxTotal: maximumTotal,
                maxCost: maximumCost,
                maxActiveMinutes: maximumActiveMinutes,
                labelInterval: labelInterval(for: data.count)
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface)
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }

}

private struct ChartContent: View {
    let data: [BarData]
    let chartMode: ChartMode
    let isHourly: Bool
    let maxTotal: Int
    let maxCost: Double
    let maxActiveMinutes: Double
    let labelInterval: Int

    private let yAxisWidth: CGFloat = 44
    private let chartAxisGap: CGFloat = 6

    @State private var hoveredIndex: Int?
    @State private var scroll = ScrollWatcher()

    private var visibleLabelIndices: [Int] {
        DashboardLayout.visibleChartLabelIndices(count: data.count, interval: labelInterval)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Chart
            HStack(alignment: .bottom, spacing: 6) {
                // Y-axis
                VStack(alignment: .trailing) {
                    Group {
                        switch chartMode {
                        case .token:
                            Text(Formatters.formatNumber(maxTotal))
                        case .cost:
                            Text(Formatters.formatCost(maxCost))
                        case .activeTime:
                            Text(Formatters.formatDuration(Int(maxActiveMinutes * 60)))
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    Spacer()
                    Text("0")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppTheme.tertiaryText)
                        .lineLimit(1)
                }
                .frame(width: yAxisWidth)
                .frame(height: 150)
                .clipped()

                // Bars
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(data) { bar in
                        VStack(spacing: 0) {
                            switch chartMode {
                            case .token:
                                let inputH = CGFloat(bar.input) / CGFloat(maxTotal) * 150
                                let outputH = CGFloat(bar.output) / CGFloat(maxTotal) * 150
                                let cachedH = CGFloat(bar.cached) / CGFloat(maxTotal) * 150
                                // Output (top, white)
                                Rectangle()
                                    .fill(AppTheme.primaryText.opacity(0.9))
                                    .frame(height: outputH)
                                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
                                // Input (bottom, zinc)
                                Rectangle()
                                    .fill(AppTheme.secondaryText)
                                    .frame(height: inputH)
                                Rectangle()
                                    .fill(AppTheme.quaternaryText)
                                    .frame(height: cachedH)
                            case .cost:
                                let costH = CGFloat(bar.cost) / CGFloat(maxCost) * 150
                                Rectangle()
                                    .fill(Color(red: 0.2, green: 0.8, blue: 0.5))
                                    .frame(height: costH)
                                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
                            case .activeTime:
                                let activeH = CGFloat(bar.activeMinutes) / CGFloat(maxActiveMinutes) * 150
                                Rectangle()
                                    .fill(Color(red: 0.38, green: 0.6, blue: 1.0))
                                    .frame(height: activeH)
                                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 150, alignment: .bottom)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity)
                .overlay {
                    GeometryReader { geo in
                        // ONE hover tracking area for the whole bar strip
                        // (replaces the former per-bar .onHover — 24–90
                        // NSTrackingAreas). While the popover is being
                        // scrolled we drop hit-testing entirely so the wheel
                        // events flow straight to the ScrollView and no hover
                        // fires; that, plus the .active guard below, keeps the
                        // chart subtree static during a scroll so it no longer
                        // stutters / sticks.
                        Color.clear
                            .contentShape(Rectangle())
                            .allowsHitTesting(!scroll.isScrolling)
                            .onContinuousHover(coordinateSpace: .local) { phase in
                                switch phase {
                                case .active(let p):
                                    guard !scroll.isScrolling,
                                          !data.isEmpty, geo.size.width > 0 else { return }
                                    let barW = geo.size.width / CGFloat(data.count)
                                    let idx = min(max(Int(p.x / barW), 0), data.count - 1)
                                    if hoveredIndex != idx { hoveredIndex = idx }
                                case .ended:
                                    if hoveredIndex != nil { hoveredIndex = nil }
                                }
                            }

                        if let idx = hoveredIndex, data.indices.contains(idx) {
                            let bar = data[idx]
                            let barW = geo.size.width / CGFloat(data.count)
                            let cx = barW * (CGFloat(idx) + 0.5)
                            let tooltipInset = min(CGFloat(80), max(geo.size.width / 2, 0))
                            let clampedX = min(max(cx, tooltipInset), max(tooltipInset, geo.size.width - tooltipInset))

                            tooltip(for: bar)
                                .position(x: clampedX, y: 40)
                                .allowsHitTesting(false)
                        }
                    }
                }
            }

            // X-axis
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.clear)
                    .frame(width: yAxisWidth)
                Rectangle()
                    .fill(.clear)
                    .frame(width: chartAxisGap)
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        ForEach(visibleLabelIndices, id: \.self) { index in
                            if data.indices.contains(index) {
                                let bar = data[index]
                                Text(isHourly ? Formatters.formatHourShort(bar.id) : Formatters.formatDateShort(bar.id))
                                    .font(.system(size: 11))
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .frame(width: DashboardLayout.chartAxisLabelWidth)
                                    .position(
                                        x: xLabelX(for: index, plotWidth: geometry.size.width),
                                        y: 12
                                    )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }
            .padding(.top, 8)
            .frame(height: 28)
        }
        .onAppear { scroll.start() }
        .onDisappear { scroll.stop() }
        .onChange(of: scroll.isScrolling) { _, scrolling in
            // Hide the tooltip as soon as a scroll starts so it doesn't hang
            // frozen over the moving content until the gesture ends.
            if scrolling, hoveredIndex != nil { hoveredIndex = nil }
        }
    }

    private func xLabelX(for index: Int, plotWidth: CGFloat) -> CGFloat {
        guard !data.isEmpty, plotWidth > 0 else { return 0 }
        let raw = plotWidth * (CGFloat(index) + 0.5) / CGFloat(data.count)
        let inset = min(DashboardLayout.chartAxisLabelWidth / 2, plotWidth / 2)
        return min(max(raw, inset), max(inset, plotWidth - inset))
    }

    @ViewBuilder
    private func tooltip(for bar: BarData) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(isHourly ? Formatters.formatHourShort(bar.id) : Formatters.formatDateShort(bar.id))
                .foregroundStyle(AppTheme.primaryText)
                .fontWeight(.medium)

            switch chartMode {
            case .token:
                Text("总 Token: \(Formatters.formatNumber(bar.total))")
                    .foregroundStyle(AppTheme.primaryText)
                HStack(spacing: 8) {
                    Text("输入: \(Formatters.formatNumber(bar.input))")
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("输出: \(Formatters.formatNumber(bar.output))")
                        .foregroundStyle(AppTheme.secondaryText)
                }
                if bar.cached > 0 {
                    Text("缓存: \(Formatters.formatNumber(bar.cached))")
                        .foregroundStyle(AppTheme.tertiaryText)
                }
                Text("费用: \(Formatters.formatCost(bar.cost))")
                    .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.5))
            case .cost:
                Text("费用: \(Formatters.formatCost(bar.cost))")
                    .foregroundStyle(Color(red: 0.2, green: 0.8, blue: 0.5))
            case .activeTime:
                Text("活跃时长: \(Formatters.formatDuration(Int(bar.activeMinutes * 60)))")
                    .foregroundStyle(Color(red: 0.38, green: 0.6, blue: 1.0))
            }
        }
        .font(.system(size: 11))
        .padding(8)
        .background(AppTheme.tooltipBackground)
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.separator, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
        .fixedSize()
    }
}
