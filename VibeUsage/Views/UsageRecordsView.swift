import SwiftUI

struct UsageRecordsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let rows = appState.dashboardData.recentRows
        let tableHeight: CGFloat = rows.isEmpty ? 118 : CGFloat(rows.count + 1) * 38

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("详细记录")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text("显示 \(rows.count) 条")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            GeometryReader { geometry in
                let tableWidth = max(geometry.size.width, DashboardLayout.recordMinimumTableWidth)
                let columnWidths = DashboardLayout.recordColumnWidths(for: tableWidth)

                ScrollView(.horizontal, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        headerRow(widths: columnWidths)
                        if rows.isEmpty {
                            Text("暂无详细记录")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.tertiaryText)
                                .frame(width: tableWidth, height: 80)
                        } else {
                            ForEach(rows) { row in
                                recordRow(row, widths: columnWidths)
                            }
                        }
                    }
                    .frame(width: tableWidth)
                    .background {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(AppTheme.surface)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(AppTheme.primaryText.opacity(0.22), lineWidth: 1)
                    }
                }
            }
            .frame(height: tableHeight)
        }
    }

    private func headerRow(widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            headerCell("日期", width: widths[0], alignment: .leading, horizontalPadding: DashboardLayout.recordEdgeInset)
            headerCell("模型", width: widths[1], alignment: .leading)
            headerCell("首字", width: widths[2], alignment: .center)
            headerCell("输入 TOKEN", width: widths[3], alignment: .trailing)
            headerCell("输出 TOKEN", width: widths[4], alignment: .trailing)
            headerCell("缓存 TOKEN", width: widths[5], alignment: .trailing)
            headerCell("预估费用", width: widths[6], alignment: .trailing, horizontalPadding: DashboardLayout.recordEdgeInset)
        }
        .frame(height: 38)
        .background(AppTheme.subtleSurface)
        .overlay(alignment: .bottom) { Divider().background(AppTheme.separator) }
    }

    private func recordRow(_ row: UsageRecordRow, widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            valueCell(
                row.date,
                width: widths[0],
                alignment: .leading,
                horizontalPadding: DashboardLayout.recordEdgeInset
            )
            valueCell(row.model, width: widths[1], alignment: .leading)
            firstResponseBadge(row, width: widths[2])
            valueCell(row.inputTokens, width: widths[3], alignment: .trailing)
            valueCell(row.outputTokens, width: widths[4], alignment: .trailing, emphasized: true)
            valueCell(row.cachedTokens, width: widths[5], alignment: .trailing)
            valueCell(
                row.estimatedCost,
                width: widths[6],
                alignment: .trailing,
                cost: true,
                horizontalPadding: DashboardLayout.recordEdgeInset
            )
        }
        .frame(height: 38)
        .background(AppTheme.surface)
        .overlay(alignment: .bottom) { Divider().background(AppTheme.separator) }
    }

    private func headerCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment,
        horizontalPadding: CGFloat = 8
    ) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppTheme.secondaryText)
            .padding(.horizontal, horizontalPadding)
            .frame(width: width, alignment: alignment)
    }

    private func valueCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment,
        emphasized: Bool = false,
        cost: Bool = false,
        horizontalPadding: CGFloat = 8
    ) -> some View {
        Text(text)
            .font(.system(size: 11, weight: emphasized || cost ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(cost ? Color(red: 0.06, green: 0.73, blue: 0.51) : (emphasized ? AppTheme.primaryText : AppTheme.secondaryText))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, horizontalPadding)
            .frame(width: width, alignment: alignment)
    }

    private func firstResponseBadge(_ row: UsageRecordRow, width: CGFloat) -> some View {
        Text(row.firstResponseTime)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(firstResponseForeground(row.firstResponseTier))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(firstResponseBackground(row.firstResponseTier))
            .clipShape(Capsule())
            .frame(width: width, alignment: .center)
    }

    private func firstResponseForeground(_ tier: FirstResponseTimeTier) -> Color {
        switch tier {
        case .fast:
            Color(red: 0.08, green: 0.55, blue: 0.24)
        case .slow:
            Color(red: 0.84, green: 0.31, blue: 0.24)
        case .critical:
            Color(red: 0.76, green: 0.08, blue: 0.11)
        case .unavailable:
            AppTheme.tertiaryText
        }
    }

    private func firstResponseBackground(_ tier: FirstResponseTimeTier) -> Color {
        switch tier {
        case .fast:
            Color(red: 0.18, green: 0.72, blue: 0.34).opacity(0.14)
        case .slow:
            Color(red: 0.95, green: 0.42, blue: 0.34).opacity(0.14)
        case .critical:
            Color(red: 0.88, green: 0.12, blue: 0.16).opacity(0.24)
        case .unavailable:
            .clear
        }
    }
}
