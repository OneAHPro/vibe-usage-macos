import SwiftUI

struct UsageRecordsView: View {
    @Environment(AppState.self) private var appState

    private let tableWidth: CGFloat = 1_080

    var body: some View {
        let rows = appState.dashboardData.recentBuckets
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

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(spacing: 0) {
                    headerRow
                    if rows.isEmpty {
                        Text("暂无详细记录")
                            .font(.system(size: 12))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .frame(width: tableWidth, height: 80)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, bucket in
                            recordRow(bucket, index: index)
                        }
                    }
                }
                .frame(width: tableWidth)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerCell("日期", width: 130, alignment: .leading)
            headerCell("终端", width: 100, alignment: .leading)
            headerCell("工具", width: 90, alignment: .leading)
            headerCell("模型", width: 150, alignment: .leading)
            headerCell("项目", width: 130, alignment: .leading)
            headerCell("输入 TOKEN", width: 120, alignment: .trailing)
            headerCell("输出 TOKEN", width: 120, alignment: .trailing)
            headerCell("缓存 TOKEN", width: 120, alignment: .trailing)
            headerCell("预估费用", width: 120, alignment: .trailing)
        }
        .frame(height: 38)
        .background(AppTheme.subtleSurface)
        .overlay(alignment: .bottom) { Divider().background(AppTheme.separator) }
    }

    private func recordRow(_ bucket: UsageBucket, index: Int) -> some View {
        HStack(spacing: 0) {
            valueCell(displayDate(bucket.bucketStart), width: 130, alignment: .leading)
            valueCell(displayValue(bucket.hostname), width: 100, alignment: .leading)
            valueCell(displayValue(bucket.source), width: 90, alignment: .leading, badge: true)
            valueCell(displayValue(bucket.model), width: 150, alignment: .leading)
            valueCell(displayValue(bucket.project), width: 130, alignment: .leading)
            valueCell(Formatters.formatNumber(bucket.inputTokens), width: 120, alignment: .trailing)
            valueCell(Formatters.formatNumber(bucket.outputTokens + bucket.reasoningOutputTokens), width: 120, alignment: .trailing, emphasized: true)
            valueCell(Formatters.formatNumber(bucket.cachedInputTokens), width: 120, alignment: .trailing)
            valueCell(Formatters.formatCost(bucket.estimatedCost ?? 0), width: 120, alignment: .trailing, cost: true)
        }
        .frame(height: 38)
        .background(index.isMultiple(of: 2) ? AppTheme.surface : AppTheme.subtleSurface.opacity(0.34))
        .overlay(alignment: .bottom) { Divider().background(AppTheme.separator) }
    }

    private func headerCell(_ text: String, width: CGFloat, alignment: Alignment) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppTheme.secondaryText)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 8)
    }

    private func valueCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment,
        badge: Bool = false,
        emphasized: Bool = false,
        cost: Bool = false
    ) -> some View {
        Text(text)
            .font(.system(size: 11, weight: emphasized || cost ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(cost ? Color(red: 0.06, green: 0.73, blue: 0.51) : (emphasized ? AppTheme.primaryText : AppTheme.secondaryText))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, badge ? 6 : 8)
            .padding(.vertical, badge ? 3 : 0)
            .background(badge ? AppTheme.selectionBackground : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: badge ? 4 : 0))
            .frame(width: width, alignment: alignment)
    }

    private func displayDate(_ iso: String) -> String {
        String(iso.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }

    private func displayValue(_ value: String) -> String {
        value.isEmpty ? "—" : value
    }
}
