import AppKit
import SwiftUI

enum DashboardPage: Equatable {
    case usage
    case leaderboard
    case settings

    var title: String {
        switch self {
        case .usage: "Vibe Usage"
        case .leaderboard: "排行榜"
        case .settings: "设置"
        }
    }

    var subtitle: String {
        switch self {
        case .usage: "AI 使用与成本仪表盘"
        case .leaderboard: "new 系统实时用量排名"
        case .settings: "账号、远程数据与应用偏好"
        }
    }
}

private final class PassthroughFilterClickView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct FilterOutsideClickMonitor: NSViewRepresentable {
    let protectedFrames: [CGRect]
    let onOutsideClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughFilterClickView()
        context.coordinator.start(monitoring: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.protectedFrames = protectedFrames
        context.coordinator.onOutsideClick = onOutsideClick
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var protectedFrames: [CGRect] = []
        var onOutsideClick: () -> Void = {}
        private var monitor: Any?

        func start(monitoring view: NSView) {
            self.view = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                let eventWindowID = event.window.map(ObjectIdentifier.init)
                let eventLocation = event.locationInWindow
                Task { @MainActor [weak self] in
                    guard let self,
                          let view = self.view,
                          eventWindowID == view.window.map(ObjectIdentifier.init)
                    else {
                        return
                    }

                    let point = view.convert(eventLocation, from: nil)
                    if DashboardLayout.shouldDismissFilter(
                        at: point,
                        protectedFrames: self.protectedFrames
                    ) {
                        self.onOutsideClick()
                    }
                }
                return event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            view = nil
        }
    }
}

struct DashboardShellView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPage: DashboardPage = .usage
    @State private var openFilter: FilterDimension?
    @State private var expandedModelFamilies: Set<String> = []

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: DashboardLayout.sidebarWidth)

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
            sidebarItem("Vibe Usage", icon: "chart.bar.fill", selected: selectedPage == .usage) {
                selectedPage = .usage
            }
            sidebarItem("排行榜", icon: "list.number", selected: selectedPage == .leaderboard) {
                openFilter = nil
                selectedPage = .leaderboard
            }
            sidebarItem("数据详情", icon: "doc.text.magnifyingglass") {
                openURL("\(AppConfig.defaultApiUrl)/console/log")
            }

            sidebarSectionTitle("应用")
                .padding(.top, 22)
            sidebarItem("同步数据", icon: "arrow.triangle.2.circlepath") {
                refreshData()
            }
            sidebarItem("设置", icon: "gearshape", selected: selectedPage == .settings) {
                selectedPage = .settings
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

            switch selectedPage {
            case .usage:
                usagePage
            case .leaderboard:
                LeaderboardView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .settings:
                SettingsView(embedded: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(AppTheme.subtleSurface)
    }

    private var usagePage: some View {
        ZStack(alignment: .top) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DashboardLayout.contentSpacing) {
                    statusBanner

                    if appState.isInitialDataLoad || (!appState.hasLoadedUsageData && appState.buckets.isEmpty) {
                        loadingState
                    } else if !appState.hasAnyData {
                        emptyState
                    } else {
                        FilterTagsView(openFilter: $openFilter)
                            .zIndex(20)
                        SummaryCardsView()
                        analyticsSection
                        DistributionChartsView()
                        UsageRecordsView()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(appState.isRefreshingData ? 0.72 : 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if appState.isRefreshingData {
                loadingPill
                    .padding(.top, 80)
                    .zIndex(40)
            }
        }
        .overlayPreferenceValue(FilterButtonAnchorPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if let openFilter,
                   let anchor = anchors[openFilter],
                   !appState.isLoadingData
                {
                    let buttonFrame = proxy[anchor]
                    let viewport = CGRect(origin: .zero, size: proxy.size)
                    if buttonFrame.intersects(viewport) {
                        let requestedSize = CGSize(
                            width: FilterPanelLayout.preferredWidth,
                            height: FilterPanelLayout.panelHeight(
                                for: openFilter,
                                buckets: appState.buckets,
                                expandedModelFamilies: expandedModelFamilies
                            )
                        )
                        let panelFrame = DashboardLayout.filterOverlayFrame(
                            buttonFrame: buttonFrame,
                            panelSize: requestedSize,
                            viewportSize: proxy.size
                        )
                        let protectedFrames = anchors.values.map { proxy[$0] } + [panelFrame]

                        ZStack {
                            FilterOutsideClickMonitor(protectedFrames: protectedFrames) {
                                self.openFilter = nil
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height)

                            FilterPanelView(
                                dimension: openFilter,
                                expandedModelFamilies: $expandedModelFamilies,
                                height: panelFrame.height
                            )
                            .frame(width: panelFrame.width, height: panelFrame.height)
                            .position(x: panelFrame.midX, y: panelFrame.midY)
                            .transaction { transaction in
                                transaction.animation = nil
                            }
                            .zIndex(100)
                        }
                    }
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(selectedPage.title)
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

                Text(selectedPage.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.tertiaryText)
            }

            Spacer()

            if selectedPage == .usage {
                DashboardActionButton(title: "详情", icon: "arrow.up.right") {
                    openURL("\(AppConfig.defaultApiUrl)/console/log")
                }
                DashboardActionButton(title: "排行榜", icon: "list.number") {
                    openFilter = nil
                    selectedPage = .leaderboard
                }
                DashboardActionButton(title: "同步数据", icon: "arrow.clockwise", disabled: appState.syncStatus == .syncing) {
                    refreshData()
                }
                DashboardActionButton(title: "设置", icon: "gearshape") {
                    selectedPage = .settings
                }
            } else {
                DashboardActionButton(title: "返回仪表盘", icon: "arrow.left") {
                    selectedPage = .usage
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(AppTheme.subtleSurface)
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
        .id(appState.dashboardRenderGeneration)
        .transaction { transaction in
            transaction.animation = nil
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
            Text("当前账号在这个时间范围内没有使用记录")
                .font(.system(size: 12))
                .foregroundStyle(AppTheme.tertiaryText)
            Button("重新读取") { refreshData() }
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
            Text(appState.usageLoadingMessage)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 30)
            .background(selected ? AppTheme.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppTheme.separator, lineWidth: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private func refreshData() {
        Task { await appState.triggerSync() }
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
