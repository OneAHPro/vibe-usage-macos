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
                    populatedSections(data)
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

    private func populatedSections(_ data: LeaderboardData) -> some View {
        VStack(alignment: .leading, spacing: DashboardLayout.leaderboardSectionSpacing) {
            personalRankSection(data)
            usageSection(title: "今日榜") {
                splitBoards(title: "美金消耗", rows: data.quotaDailyTop, firstCount: 5)
            }
            usageSection(title: "昨日榜") {
                splitBoards(title: "美金消耗", rows: data.quotaYesterdayTop, firstCount: 10)
            }
            usageSection(title: "总排行") {
                splitBoards(title: "美金消耗", rows: data.quotaTotalTop, firstCount: 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

            HStack(spacing: DashboardLayout.contentSpacing) {
                PersonalRankCard(
                    title: "今日消费排名",
                    value: data.myDailyQuotaRank,
                    quotaPerUnit: appState.quotaPerUnit
                )
                .frame(width: 240)

                PersonalRankCard(
                    title: "昨日消费排名",
                    value: data.myYesterdayQuotaRank,
                    quotaPerUnit: appState.quotaPerUnit
                )
                .frame(width: 240)
            }
        }
    }

    private func splitBoards(
        title: String,
        rows: [LeaderboardRow],
        firstCount: Int
    ) -> some View {
        let segments = LeaderboardPresentation.splitRows(rows, firstCount: firstCount)

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DashboardLayout.contentSpacing) {
                LeaderboardBoardCard(
                    title: title,
                    rows: segments[0].rows,
                    metric: .cost,
                    quotaPerUnit: appState.quotaPerUnit,
                    rankOffset: segments[0].rankOffset
                )
                .frame(minWidth: 340)

                LeaderboardBoardCard(
                    title: title,
                    rows: segments[1].rows,
                    metric: .cost,
                    quotaPerUnit: appState.quotaPerUnit,
                    rankOffset: segments[1].rankOffset
                )
                .frame(minWidth: 340)
            }

            VStack(spacing: DashboardLayout.contentSpacing) {
                LeaderboardBoardCard(
                    title: title,
                    rows: segments[0].rows,
                    metric: .cost,
                    quotaPerUnit: appState.quotaPerUnit,
                    rankOffset: segments[0].rankOffset
                )
                LeaderboardBoardCard(
                    title: title,
                    rows: segments[1].rows,
                    metric: .cost,
                    quotaPerUnit: appState.quotaPerUnit,
                    rankOffset: segments[1].rankOffset
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

private enum LeaderboardTableColumn: Hashable {
    case rank
    case user
    case tokens
    case cost

    var title: String {
        switch self {
        case .rank: "#"
        case .user: "用户"
        case .tokens: "Token"
        case .cost: "美金消耗"
        }
    }
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
    let rankOffset: Int

    private let leaderboardRowHeight: CGFloat = 44

    init(
        title: String,
        rows: [LeaderboardRow],
        metric: LeaderboardMetric,
        quotaPerUnit: Double,
        rankOffset: Int = 0
    ) {
        self.title = title
        self.rows = rows
        self.metric = metric
        self.quotaPerUnit = quotaPerUnit
        self.rankOffset = rankOffset
    }

    private var leaderboardColumns: [LeaderboardTableColumn] {
        if metric == .cost {
            return [.rank, .user, .tokens, .cost]
        }
        if rows.contains(where: { $0.quota != nil }) {
            return [.rank, .user, .cost, .tokens]
        }
        return [.rank, .user, .tokens]
    }

    private var primaryColumn: LeaderboardTableColumn {
        metric == .cost ? .cost : .tokens
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: leaderboardRowHeight)
            .background(AppTheme.surface)

            Divider()
                .overlay(AppTheme.separator)

            leaderboardColumnHeader

            Divider()
                .overlay(AppTheme.separator.opacity(0.7))

            if rows.isEmpty {
                Text("暂无排行数据")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 82)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    leaderboardRow(row, rank: rankOffset + index + 1)
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

    private var leaderboardColumnHeader: some View {
        HStack(spacing: 10) {
            ForEach(leaderboardColumns, id: \.self) { column in
                framedColumn(column) {
                    Text(column.title)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: leaderboardRowHeight)
        .background(AppTheme.surface)
    }

    private func leaderboardRow(_ row: LeaderboardRow, rank: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(leaderboardColumns, id: \.self) { column in
                framedColumn(column) {
                    Text(value(for: column, row: row, rank: rank))
                        .font(rowFont(for: column))
                        .foregroundStyle(rowColor(for: column, rank: rank))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: leaderboardRowHeight)
        .background(AppTheme.surface)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func framedColumn<Content: View>(
        _ column: LeaderboardTableColumn,
        @ViewBuilder content: () -> Content
    ) -> some View {
        switch column {
        case .rank:
            content()
                .frame(width: 26, alignment: .leading)
        case .user:
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .tokens, .cost:
            content()
                .frame(width: 86, alignment: .trailing)
        }
    }

    private func value(
        for column: LeaderboardTableColumn,
        row: LeaderboardRow,
        rank: Int
    ) -> String {
        switch column {
        case .rank:
            "\(rank)."
        case .user:
            row.preferredName
        case .tokens:
            Formatters.formatNumber(row.tokenUsed)
        case .cost:
            if let quota = row.quota {
                LeaderboardPresentation.costLabel(
                    quota: quota,
                    quotaPerUnit: quotaPerUnit
                )
            } else {
                "—"
            }
        }
    }

    private func rowFont(for column: LeaderboardTableColumn) -> Font {
        switch column {
        case .rank:
            .system(size: 11, weight: .bold, design: .monospaced)
        case .user:
            .system(size: 12, weight: .medium)
        case .tokens, .cost:
            .system(
                size: 11,
                weight: column == primaryColumn ? .semibold : .regular,
                design: .monospaced
            )
        }
    }

    private func rowColor(for column: LeaderboardTableColumn, rank: Int) -> Color {
        if column == .rank {
            return rankColor(rank)
        }
        if column == primaryColumn {
            return AppTheme.costAccent
        }
        if column == .user {
            return AppTheme.primaryText
        }
        return AppTheme.secondaryText
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
