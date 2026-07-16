import SwiftUI

struct UsageRecordsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let rows = appState.dashboardData.recentBuckets
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
                    VStack(spacing: 0) {
                        headerRow(widths: columnWidths)
                        if rows.isEmpty {
                            Text("暂无详细记录")
                                .font(.system(size: 12))
                                .foregroundStyle(AppTheme.tertiaryText)
                                .frame(width: tableWidth, height: 80)
                        } else {
                            ForEach(rows) { bucket in
                                recordRow(bucket, widths: columnWidths)
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
            headerCell("终端", width: widths[1], alignment: .leading)
            headerCell("工具", width: widths[2], alignment: .leading)
            headerCell("模型", width: widths[3], alignment: .leading)
            headerCell("输入 TOKEN", width: widths[4], alignment: .trailing)
            headerCell("输出 TOKEN", width: widths[5], alignment: .trailing)
            headerCell("缓存 TOKEN", width: widths[6], alignment: .trailing)
            headerCell("预估费用", width: widths[7], alignment: .trailing, horizontalPadding: DashboardLayout.recordEdgeInset)
        }
        .frame(height: 38)
        .background(AppTheme.subtleSurface)
        .overlay(alignment: .bottom) { Divider().background(AppTheme.separator) }
    }

    private func recordRow(_ bucket: UsageBucket, widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            valueCell(
                displayDate(bucket.bucketStart),
                width: widths[0],
                alignment: .leading,
                horizontalPadding: DashboardLayout.recordEdgeInset
            )
            valueCell(displayValue(bucket.hostname), width: widths[1], alignment: .leading)
            valueCell(displayValue(bucket.source), width: widths[2], alignment: .leading, badge: true)
            valueCell(displayValue(bucket.model), width: widths[3], alignment: .leading)
            valueCell(Formatters.formatNumber(bucket.inputTokens), width: widths[4], alignment: .trailing)
            valueCell(Formatters.formatNumber(bucket.outputTokens + bucket.reasoningOutputTokens), width: widths[5], alignment: .trailing, emphasized: true)
            valueCell(Formatters.formatNumber(bucket.cachedInputTokens), width: widths[6], alignment: .trailing)
            valueCell(
                Formatters.formatCost(bucket.estimatedCost ?? 0),
                width: widths[7],
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
        badge: Bool = false,
        emphasized: Bool = false,
        cost: Bool = false,
        horizontalPadding: CGFloat = 8
    ) -> some View {
        Text(text)
            .font(.system(size: 11, weight: emphasized || cost ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(cost ? Color(red: 0.06, green: 0.73, blue: 0.51) : (emphasized ? AppTheme.primaryText : AppTheme.secondaryText))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, badge ? 6 : horizontalPadding)
            .padding(.vertical, badge ? 3 : 0)
            .background(badge ? AppTheme.selectionBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: badge ? 4 : 0))
            .frame(width: width, alignment: alignment)
    }

    private func displayDate(_ iso: String) -> String {
        Formatters.formatDateTime(iso)
    }

    private func displayValue(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }
}
