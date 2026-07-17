import SwiftUI

struct LeaderboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: DashboardLayout.contentSpacing) {
                statusStrip

                if appState.leaderboardData == nil && appState.isLoadingLeaderboard {
                    loadingState
                } else if let data = appState.leaderboardData {
                    personalRankSection(data)
                    usageSection(title: "今日榜") {
                        pairedBoards(
                            leftTitle: "预估消费",
                            leftRows: data.quotaDailyTop,
                            leftMetric: .cost,
                            rightTitle: "Token",
                            rightRows: data.tokenDailyTop,
                            rightMetric: .tokens
                        )
                    }
                    usageSection(title: "昨日榜") {
                        LeaderboardBoardCard(
                            title: "预估消费",
                            rows: data.quotaYesterdayTop,
                            metric: .cost,
                            quotaPerUnit: appState.quotaPerUnit
                        )
                    }
                    usageSection(title: "累计榜") {
                        pairedBoards(
                            leftTitle: "预估消费",
                            leftRows: data.quotaTotalTop,
                            leftMetric: .cost,
                            rightTitle: "Token",
                            rightRows: data.tokenTotalTop,
                            rightMetric: .tokens
                        )
                    }
                } else {
                    errorState
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            if appState.leaderboardData == nil {
                await appState.fetchLeaderboard()
            }
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(AppTheme.secondaryText)

            if let updatedAt = appState.leaderboardUpdatedAt {
                Text("更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("new 系统实时榜单")
            }

            if appState.isLoadingLeaderboard {
                ProgressView()
                    .controlSize(.mini)
            }

            if appState.leaderboardData != nil,
               let error = appState.leaderboardError
            {
                Text(error)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await appState.fetchLeaderboard() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(appState.isLoadingLeaderboard)
        }
        .font(.system(size: 11))
        .foregroundStyle(AppTheme.secondaryText)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.separator, lineWidth: 1)
        }
    }

    private func personalRankSection(_ data: LeaderboardData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("我的排名")

            ViewThatFits(in: .horizontal) {
                HStack(spacing: DashboardLayout.contentSpacing) {
                    PersonalRankCard(
                        title: "今日消费排名",
                        value: data.myDailyQuotaRank,
                        quotaPerUnit: appState.quotaPerUnit
                    )
                    .frame(minWidth: 260)

                    PersonalRankCard(
                        title: "昨日消费排名",
                        value: data.myYesterdayQuotaRank,
                        quotaPerUnit: appState.quotaPerUnit
                    )
                    .frame(minWidth: 260)
                }

                VStack(spacing: DashboardLayout.contentSpacing) {
                    PersonalRankCard(
                        title: "今日消费排名",
                        value: data.myDailyQuotaRank,
                        quotaPerUnit: appState.quotaPerUnit
                    )
                    PersonalRankCard(
                        title: "昨日消费排名",
                        value: data.myYesterdayQuotaRank,
                        quotaPerUnit: appState.quotaPerUnit
                    )
                }
            }
        }
    }

    private func pairedBoards(
        leftTitle: String,
        leftRows: [LeaderboardRow],
        leftMetric: LeaderboardMetric,
        rightTitle: String,
        rightRows: [LeaderboardRow],
        rightMetric: LeaderboardMetric
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DashboardLayout.contentSpacing) {
                LeaderboardBoardCard(
                    title: leftTitle,
                    rows: leftRows,
                    metric: leftMetric,
                    quotaPerUnit: appState.quotaPerUnit
                )
                .frame(minWidth: 340)

                LeaderboardBoardCard(
                    title: rightTitle,
                    rows: rightRows,
                    metric: rightMetric,
                    quotaPerUnit: appState.quotaPerUnit
                )
                .frame(minWidth: 340)
            }

            VStack(spacing: DashboardLayout.contentSpacing) {
                LeaderboardBoardCard(
                    title: leftTitle,
                    rows: leftRows,
                    metric: leftMetric,
                    quotaPerUnit: appState.quotaPerUnit
                )
                LeaderboardBoardCard(
                    title: rightTitle,
                    rows: rightRows,
                    metric: rightMetric,
                    quotaPerUnit: appState.quotaPerUnit
                )
            }
        }
    }

    private func usageSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(title)
            content()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(AppTheme.primaryText)
    }

    private var loadingState: some View {
        VStack(spacing: DashboardLayout.contentSpacing) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 7)
                    .fill(AppTheme.surface)
                    .frame(height: 180)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(AppTheme.separator, lineWidth: 1)
                    }
            }
        }
        .redacted(reason: .placeholder)
        .overlay {
            ProgressView("正在加载排行榜…")
                .font(.system(size: 11))
                .controlSize(.small)
        }
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(AppTheme.tertiaryText)
            Text("排行榜加载失败")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppTheme.primaryText)
            Text(appState.leaderboardError ?? "暂时无法读取 new 系统排行榜")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.tertiaryText)
            Button("重新加载") {
                Task { await appState.fetchLeaderboard() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.separator, lineWidth: 1)
        }
    }
}

private enum LeaderboardMetric: Equatable {
    case cost
    case tokens
}

private struct PersonalRankCard: View {
    let title: String
    let value: LeaderboardPersonalRank?
    let quotaPerUnit: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)

            Text(LeaderboardPresentation.rankLabel(value))
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(AppTheme.primaryText)

            if let value {
                HStack(spacing: 14) {
                    Label(
                        LeaderboardPresentation.costLabel(
                            quota: value.quota,
                            quotaPerUnit: quotaPerUnit
                        ),
                        systemImage: "dollarsign.circle"
                    )
                    Label(
                        Formatters.formatNumber(value.tokenUsed),
                        systemImage: "number"
                    )
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AppTheme.secondaryText)
            } else {
                Text("暂无使用记录")
                    .font(.system(size: 10))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.separator, lineWidth: 1)
        }
    }
}

private struct LeaderboardBoardCard: View {
    let title: String
    let rows: [LeaderboardRow]
    let metric: LeaderboardMetric
    let quotaPerUnit: Double

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                Text("用户")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(AppTheme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)

            Divider()
                .overlay(AppTheme.separator)

            if rows.isEmpty {
                Text("暂无排行数据")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 82)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    leaderboardRow(row, rank: index + 1)
                    if index < rows.count - 1 {
                        Divider()
                            .overlay(AppTheme.separator.opacity(0.7))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(AppTheme.separator, lineWidth: 1)
        }
    }

    private func leaderboardRow(_ row: LeaderboardRow, rank: Int) -> some View {
        HStack(spacing: 9) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(rankColor(rank))
                .frame(width: 24, alignment: .leading)

            LeaderboardAvatar(row: row)

            Text(row.preferredName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(primaryValue(row))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.06, green: 0.73, blue: 0.51))

                if metric == .cost {
                    Text("\(Formatters.formatNumber(row.tokenUsed)) Token")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(AppTheme.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .contentShape(Rectangle())
    }

    private func primaryValue(_ row: LeaderboardRow) -> String {
        switch metric {
        case .cost:
            LeaderboardPresentation.costLabel(
                quota: row.quota ?? 0,
                quotaPerUnit: quotaPerUnit
            )
        case .tokens:
            Formatters.formatNumber(row.tokenUsed)
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: Color(red: 0.95, green: 0.70, blue: 0.20)
        case 2: Color(red: 0.68, green: 0.72, blue: 0.78)
        case 3: Color(red: 0.76, green: 0.48, blue: 0.28)
        default: AppTheme.tertiaryText
        }
    }
}

private struct LeaderboardAvatar: View {
    let row: LeaderboardRow

    var body: some View {
        Group {
            if let value = row.avatarURL,
               let url = URL(string: value)
            {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    initialBadge
                }
            } else {
                initialBadge
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(Circle())
    }

    private var initialBadge: some View {
        ZStack {
            Circle()
                .fill(badgeColor.opacity(0.18))
            Text(String(row.preferredName.prefix(1)).uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(badgeColor)
        }
    }

    private var badgeColor: Color {
        let palette: [Color] = [
            .blue, .cyan, .green, .indigo, .orange, .pink, .purple, .teal,
        ]
        let total = row.preferredName.unicodeScalars.reduce(0) {
            $0 &+ Int($1.value)
        }
        return palette[abs(total) % palette.count]
    }
}
