import SwiftUI

struct ActivityHeatmapView: View {
    @Environment(AppState.self) private var appState

    private let weekdays: [(value: Int, label: String)] = [
        (2, "周一"), (3, "周二"), (4, "周三"), (5, "周四"),
        (6, "周五"), (7, "周六"), (1, "周日"),
    ]

    var body: some View {
        let heatmap = ActivityHeatmap(sessions: appState.dashboardData.sessions)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                Text("分时活跃")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("按活跃时长")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .foregroundStyle(AppTheme.secondaryText)

            VStack(spacing: 7) {
                ForEach(weekdays, id: \.value) { weekday in
                    HStack(spacing: 4) {
                        Text(weekday.label)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .frame(width: 30, alignment: .leading)

                        ForEach(0..<24, id: \.self) { hour in
                            heatCell(
                                intensity: heatmap.intensity(weekday: weekday.value, hour: hour),
                                seconds: heatmap.value(weekday: weekday.value, hour: hour)
                            )
                        }
                    }
                }

                HStack(spacing: 4) {
                    Color.clear.frame(width: 30, height: 1)
                    ForEach(0..<24, id: \.self) { hour in
                        Text(hour.isMultiple(of: 3) ? String(format: "%02d", hour) : "")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppTheme.tertiaryText)
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            HStack(spacing: 4) {
                Spacer()
                Text("少")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.tertiaryText)
                ForEach(0..<6, id: \.self) { step in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(activityColor(intensity: Double(step) / 5))
                        .frame(width: 10, height: 10)
                }
                Text("多")
                    .font(.system(size: 9))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 236, alignment: .topLeading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }

    private func heatCell(intensity: Double, seconds: Int) -> some View {
        RoundedRectangle(cornerRadius: 2.5)
            .fill(activityColor(intensity: intensity))
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .help(seconds > 0 ? Formatters.formatDuration(seconds) : "暂无活动")
    }

    private func activityColor(intensity: Double) -> Color {
        guard intensity > 0 else { return AppTheme.separator.opacity(0.55) }
        return Color(red: 0.23, green: 0.51, blue: 0.96)
            .opacity(0.18 + min(max(intensity, 0), 1) * 0.72)
    }
}
