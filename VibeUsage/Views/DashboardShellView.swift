import AppKit
import SwiftUI

struct DashboardShellView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: DashboardLayout.sidebarWidth)

            Divider()
                .background(AppTheme.separator)

            mainContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.subtleSurface)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(AppTheme.primaryText, lineWidth: 1.5)
                    Text("V")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(AppTheme.primaryText)
                }
                .frame(width: 19, height: 19)

                Text("VibeCafé")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppTheme.primaryText)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 28)

            sidebarSectionTitle("数据")
            sidebarItem("Vibe Usage", icon: "chart.bar.fill", selected: true) {}
            sidebarItem("排行榜", icon: "list.number") {
                openURL("\(AppConfig.defaultApiUrl)/usage/rank")
            }
            sidebarItem("数据详情", icon: "doc.text.magnifyingglass") {
                openURL("\(AppConfig.defaultApiUrl)/usage")
            }

            sidebarSectionTitle("应用")
                .padding(.top, 22)
            sidebarItem("同步数据", icon: "arrow.triangle.2.circlepath") {
                refreshData()
            }
            sidebarItem("设置", icon: "gearshape") {
                SettingsWindowController.shared.show(appState: appState)
            }

            Spacer(minLength: 20)

            VStack(alignment: .leading, spacing: 12) {
                syncStatusLabel

                HStack {
                    Text("Vibe Usage")
                    Spacer()
                    Text(appVersion)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(AppTheme.tertiaryText)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("退出应用", systemImage: "power")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(18)
        }
        .background(AppTheme.subtleSurface)
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: DashboardLayout.contentSpacing) {
                    statusBanner

                    if appState.codexRateLimitEnabled || appState.claudeRateLimitEnabled {
                        RateLimitCardView()
                            .zIndex(30)
                    }

                    if appState.isInitialDataLoad || (!appState.hasLoadedUsageData && appState.buckets.isEmpty) {
                        loadingState
                    } else if !appState.hasAnyData {
                        emptyState
                    } else {
                        dashboardContent
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppTheme.subtleSurface)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Vibe Usage")
                        .font(.system(size: 25, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppTheme.primaryText)

                    if AppConfig.isDev {
                        Text("DEBUG")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                Text("AI 使用与成本仪表盘")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Spacer()

            DashboardActionButton(title: "详情", icon: "arrow.up.right") {
                openURL("\(AppConfig.defaultApiUrl)/usage")
            }
            DashboardActionButton(title: "排行榜", icon: "list.number") {
                openURL("\(AppConfig.defaultApiUrl)/usage/rank")
            }
            DashboardActionButton(title: "同步数据", icon: "arrow.clockwise", disabled: appState.syncStatus == .syncing) {
                refreshData()
            }
            DashboardActionButton(title: "设置", icon: "gearshape") {
                SettingsWindowController.shared.show(appState: appState)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AppTheme.surface)
        .overlay(alignment: .bottom) { Divider().background(AppTheme.separator) }
    }

    private var statusBanner: some View {
        HStack(spacing: 8) {
            statusIcon
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(1)
            Spacer()
            Button {
                refreshData()
            } label: {
                HStack(spacing: 4) {
                    Text("立即更新")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(appState.syncStatus == .syncing)
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }

    private var dashboardContent: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: DashboardLayout.contentSpacing) {
                FilterTagsView()
                    .zIndex(20)
                SummaryCardsView()
                analyticsSection
                DistributionChartsView()
                UsageRecordsView()
            }
            .opacity(appState.isRefreshingData ? 0.72 : 1)

            if appState.isRefreshingData {
                loadingPill
                    .padding(.top, 70)
                    .transition(.opacity)
                    .zIndex(40)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isRefreshingData)
    }

    private var analyticsSection: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DashboardLayout.contentSpacing) {
                BarChartView()
                    .frame(minWidth: 430)
                ActivityHeatmapView()
                    .frame(minWidth: 430)
            }
            .frame(minWidth: 900)

            VStack(spacing: DashboardLayout.contentSpacing) {
                BarChartView()
                ActivityHeatmapView()
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            DashboardMetricPlaceholder()
            RoundedRectangle(cornerRadius: 7)
                .fill(AppTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
                .frame(height: 236)
        }
        .redacted(reason: .placeholder)
        .overlay { loadingPill }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(AppTheme.tertiaryText)
            Text("暂无数据")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
            Text("完成同步后，使用数据会在这里展示")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.tertiaryText)
            Button("同步数据") { refreshData() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
    }

    private var loadingPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("加载中")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(AppTheme.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.syncStatus {
        case .syncing:
            ProgressView().controlSize(.mini)
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
        case .idle, .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color(red: 0.06, green: 0.73, blue: 0.51))
        }
    }

    private var syncStatusLabel: some View {
        HStack(spacing: 6) {
            statusIcon
                .font(.system(size: 10))
            Text(statusText)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.tertiaryText)
                .lineLimit(2)
        }
    }

    private var statusText: String {
        switch appState.syncStatus {
        case .syncing:
            return "正在同步数据…"
        case .error(let message):
            return message
        case .idle, .success:
            if let lastSyncTime = appState.lastSyncTime {
                return "上次同步：\(Formatters.formatRelativeTime(lastSyncTime))"
            }
            return "已就绪，等待首次同步"
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "v\(version ?? "1.0")"
    }

    private func sidebarSectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(AppTheme.tertiaryText)
            .padding(.horizontal, 18)
            .padding(.bottom, 7)
    }

    private func sidebarItem(
        _ title: String,
        icon: String,
        selected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(selected ? AppTheme.primaryText : AppTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(selected ? AppTheme.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.separator, lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func refreshData() {
        Task {
            async let sync: Void = appState.triggerSync()
            async let limits: Void = appState.refreshAllRateLimits()
            _ = await (sync, limits)
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct DashboardActionButton: View {
    let title: String
    let icon: String
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.secondaryText)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(AppTheme.raisedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(AppTheme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
    }
}

private struct DashboardMetricPlaceholder: View {
    var body: some View {
        DashboardMetricLayout(spacing: 8) {
            ForEach(0..<10, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 7)
                    .fill(AppTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.separator, lineWidth: 1))
                    .frame(height: 70)
            }
        }
    }
}
