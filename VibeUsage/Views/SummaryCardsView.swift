import SwiftUI

struct SummaryCardsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let metrics = appState.dashboardData.metrics
        DashboardMetricLayout(spacing: 8) {
            StatCard(label: "预估费用", value: Formatters.formatCost(metrics.estimatedCost), color: Color(red: 0.06, green: 0.73, blue: 0.51))
            StatCard(label: "总 Token", value: Formatters.formatNumber(metrics.totalTokens))
            StatCard(label: "输入 Token", value: Formatters.formatNumber(metrics.inputTokens))
            StatCard(label: "输出 Token", value: Formatters.formatNumber(metrics.outputTokens))
            StatCard(label: "缓存 Token", value: Formatters.formatNumber(metrics.cachedTokens), color: AppTheme.secondaryText)
            StatCard(label: "活跃时长", value: Formatters.formatDuration(metrics.activeSeconds), color: Color(red: 0.23, green: 0.51, blue: 0.96))
            StatCard(label: "总时长", value: Formatters.formatDuration(metrics.durationSeconds))
            StatCard(label: "会话数", value: Formatters.formatNumber(metrics.sessionCount))
            StatCard(label: "总消息数", value: Formatters.formatNumber(metrics.messageCount))
            StatCard(label: "用户消息数", value: Formatters.formatNumber(metrics.userMessageCount))
        }
        .animation(.easeInOut(duration: 0.28), value: metrics)
    }
}

private struct StatCard: View {
    let label: String
    let value: String
    var color: Color = AppTheme.primaryText

    // Reserve fixed line-box heights so all cards render at exactly the same height,
    // even when minimumScaleFactor shrinks the value glyphs in narrower columns.
    private let labelHeight: CGFloat = 14   // 12pt font
    private let valueHeight: CGFloat = 24   // 20pt font

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
                .frame(height: labelHeight, alignment: .leading)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, minHeight: valueHeight, maxHeight: valueHeight, alignment: .leading)
                .clipped()
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(AppTheme.surface)
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.separator, lineWidth: 1)
        )
    }
}
