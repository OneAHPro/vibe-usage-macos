import Testing
import CoreGraphics
import Foundation
@testable import VibeUsage

struct DashboardLayoutTests {
    @Test
    func usesDenseWideGridAndReadableCompactGrid() {
        #expect(DashboardLayout.summaryColumnCount(for: 920) == 5)
        #expect(DashboardLayout.summaryColumnCount(for: 760) == 2)
        #expect(DashboardLayout.analyticsColumnCount(for: 920) == 2)
        #expect(DashboardLayout.analyticsColumnCount(for: 760) == 1)
        #expect(DashboardLayout.sidebarWidth == 188)
    }

    @Test
    func walletOverviewIsSideBySideAtDefaultWidthAndStackedAtMinimumWidth() {
        let defaultContentWidth = MainWindowConfiguration.standard.defaultContentSize.width
            - DashboardLayout.sidebarWidth
            - DashboardLayout.walletHorizontalInset * 2
        let minimumContentWidth = MainWindowConfiguration.standard.minimumContentSize.width
            - DashboardLayout.sidebarWidth
            - DashboardLayout.walletHorizontalInset * 2

        #expect(DashboardLayout.walletOverviewColumnCount(for: defaultContentWidth) == 2)
        #expect(DashboardLayout.walletOverviewColumnCount(for: minimumContentWidth) == 1)
        #expect(DashboardLayout.walletRechargeControlsFit(for: defaultContentWidth))
        #expect(DashboardLayout.walletRechargeControlsFit(
            for: DashboardLayout.walletOverviewMinimumColumnWidth * 2
                + DashboardLayout.walletOverviewSpacing
        ))
    }

    @Test
    func leaderboardUsesOfficialSectionSpacing() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let layout = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/DashboardLayout.swift"),
            encoding: .utf8
        )
        let leaderboard = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/LeaderboardView.swift"),
            encoding: .utf8
        )

        #expect(layout.contains("static let leaderboardSectionSpacing: CGFloat = 48"))
        #expect(leaderboard.contains(
            "VStack(alignment: .leading, spacing: DashboardLayout.leaderboardSectionSpacing)"
        ))
        #expect(leaderboard.contains("VStack(alignment: .leading, spacing: 8)"))
    }

    @Test
    func leaderboardUsesReadableSectionTitlesAndTableInsets() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/LeaderboardView.swift"),
            encoding: .utf8
        )

        #expect(view.contains("private let leaderboardSectionTitleSize: CGFloat = 18"))
        #expect(view.contains("private let leaderboardTitleSpacing: CGFloat = 16"))
        #expect(view.contains("private let leaderboardContentInset: CGFloat = 20"))
        #expect(view.contains("VStack(alignment: .leading, spacing: leaderboardTitleSpacing)"))
        #expect(view.contains(".font(.system(size: leaderboardSectionTitleSize, weight: .bold))"))
        #expect(view.components(separatedBy: ".padding(.horizontal, leaderboardContentInset)").count - 1 == 3)
    }

    @Test
    func sidebarPagesProvideInlineNavigationTitles() {
        #expect(DashboardPage.usage.title == "Vibe Usage")
        #expect(DashboardPage.tokens.title == "令牌管理")
        #expect(DashboardPage.wallet.title == "钱包管理")
        #expect(DashboardPage.activity.title == "活动中心")
        #expect(DashboardPage.settings.title == "设置")
    }

    @Test
    func sidebarProvidesNativeAccountPagesWithoutBackgroundRefresh() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shell = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/DashboardShellView.swift"),
            encoding: .utf8
        )

        #expect(shell.contains("sidebarSectionTitle(\"账户\")"))
        #expect(shell.contains("selectedPage = .tokens"))
        #expect(shell.contains("selectedPage = .wallet"))
        #expect(shell.contains("selectedPage = .activity"))
        #expect(shell.contains("TokenManagementView("))
        #expect(shell.contains("WalletManagementView("))
        #expect(shell.contains("ActivityCenterView()"))
        #expect(shell.contains("case .tokens, .wallet, .activity, .settings: .none"))
        #expect(shell.contains("tokenStore.reset()"))
        #expect(shell.contains("walletStore.reset()"))
    }

    @Test
    func activityCenterUsesAnHonestNativeEmptyState() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let activityURL = repositoryRoot.appendingPathComponent(
            "VibeUsage/Views/ActivityCenterView.swift"
        )

        #expect(FileManager.default.fileExists(atPath: activityURL.path))
        guard FileManager.default.fileExists(atPath: activityURL.path) else { return }

        let activity = try String(contentsOf: activityURL, encoding: .utf8)
        #expect(activity.contains("暂无活动"))
        #expect(activity.contains("新活动上线后会在这里显示"))
        #expect(!activity.contains("Timer"))
        #expect(!activity.contains("URLSession"))
    }

    @Test
    func tokenManagementUsesNativeExplicitActionsAndNeverStoresFullKeys() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: root.appendingPathComponent("VibeUsage/Views/TokenManagementView.swift"),
            encoding: .utf8
        )

        #expect(view.contains("令牌总数"))
        #expect(view.contains("按名称搜索"))
        #expect(view.contains(".onSubmit"))
        #expect(view.contains("TokenEditorSheet"))
        #expect(view.contains("confirmationDialog"))
        #expect(view.contains("revealTokenKey"))
        #expect(view.contains("NSPasteboard.general"))
        #expect(view.contains("key.hasPrefix(\"sk-\")"))
        #expect(!view.contains("fullKey"))
        #expect(!view.contains("Timer"))
        #expect(!view.contains("onChange(of: store.searchText"))
    }

    @Test
    func walletManagementUsesNativeSubscriptionRechargeAndFundingSections() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: root.appendingPathComponent("VibeUsage/Views/WalletManagementView.swift"),
            encoding: .utf8
        )
        let purchaseSheet = try String(
            contentsOf: root.appendingPathComponent("VibeUsage/Views/SubscriptionPurchaseSheet.swift"),
            encoding: .utf8
        )

        #expect(view.contains("当前余额"))
        #expect(!view.contains("历史消耗"))
        #expect(!view.contains("请求次数"))
        #expect(view.contains("订阅套餐"))
        #expect(view.contains("余额充值"))
        #expect(view.contains("资金记录"))
        #expect(view.contains("private var walletOverviewGrid"))
        #expect(view.contains("当前订阅"))
        #expect(view.contains("可选套餐"))
        #expect(view.contains("SubscriptionPurchaseSheet"))
        #expect(view.contains("loadFundingRecordsIfNeeded"))
        #expect(view.contains("refreshOverview"))
        #expect(!view.contains("selectedSection"))
        #expect(!view.contains("sectionPicker"))
        #expect(!view.contains("Picker(\"钱包功能\""))
        #expect(!view.contains("private enum WalletSection"))
        #expect(!view.contains(".pickerStyle(.segmented)"))
        #expect(view.contains("在线充值"))
        #expect(view.contains("预计支付金额"))
        #expect(view.contains("计算实付"))
        #expect(view.contains("选择产品"))
        #expect(view.contains("selectedCreemProductID"))
        #expect(view.contains("Formatters.formatMoney(product.price, currency: product.currency)"))
        #expect(view.contains("product.quota"))
        #expect(view.contains("充值记录"))
        #expect(view.contains("ExternalPaymentLauncher"))
        #expect(purchaseSheet.contains("选择支付方式"))
        #expect(purchaseSheet.contains("createSubscriptionCheckout"))
        #expect(!view.contains("Timer"))
        #expect(!view.contains("WebView"))
        #expect(!purchaseSheet.contains("WebView"))
    }

    @Test
    func leaderboardUsesNativeNavigationFromBothEntryPoints() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shell = try String(
            contentsOf: root.appendingPathComponent("VibeUsage/Views/DashboardShellView.swift"),
            encoding: .utf8
        )

        #expect(DashboardPage.leaderboard.title == "排行榜")
        #expect(shell.contains("selectedPage = .leaderboard"))
        #expect(shell.components(separatedBy: "selectedPage = .leaderboard").count - 1 == 2)
        #expect(shell.contains("LeaderboardView()"))
        #expect(!shell.contains("openURL(\"\\(AppConfig.defaultApiUrl)/rankings\")"))
    }

    @Test
    func dashboardReportsTheSelectedRemoteRefreshTarget() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shell = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/DashboardShellView.swift"),
            encoding: .utf8
        )

        #expect(shell.contains("private var remoteRefreshTarget: RemoteRefreshTarget"))
        #expect(shell.contains("appState.setActiveRefreshTarget(remoteRefreshTarget)"))
        #expect(shell.contains("case .tokens, .wallet, .activity, .settings: .none"))
    }

    @Test
    func leaderboardAndAppStateHaveNoIndependentBackgroundSchedulers() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let leaderboard = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/LeaderboardView.swift"),
            encoding: .utf8
        )
        let appState = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Models/AppState.swift"),
            encoding: .utf8
        )

        #expect(!leaderboard.contains(".task {"))
        #expect(!appState.contains("SyncScheduler"))
        #expect(!appState.contains("startScheduler"))
    }

    @Test
    func rangeAndLeaderboardActionsUseCoordinatedRefreshAPIs() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let filterTags = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/FilterTagsView.swift"),
            encoding: .utf8
        )
        let leaderboard = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/LeaderboardView.swift"),
            encoding: .utf8
        )

        #expect(filterTags.contains("await appState.selectTimeRange(range)"))
        #expect(!filterTags.contains("await appState.fetchUsageData()"))
        #expect(leaderboard.contains("await appState.refreshLeaderboardManually()"))
        #expect(!leaderboard.contains("await appState.fetchLeaderboard()"))
    }

    @Test
    func timeRangeChangesAnimateDashboardRefreshAndCommittedData() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shell = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/DashboardShellView.swift"),
            encoding: .utf8
        )
        let appState = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Models/AppState.swift"),
            encoding: .utf8
        )

        #expect(shell.contains(".animation(.easeInOut(duration: 0.2), value: appState.isRefreshingData)"))
        #expect(shell.contains(".transition(.opacity.combined(with: .scale(scale: 0.98)))"))
        #expect(!shell.contains(".id(appState.dashboardRenderGeneration)\n        .transaction"))
        #expect(appState.contains("withAnimation(.easeInOut(duration: 0.22))"))
    }

    @Test
    func remoteRefreshHasNoBypassOrFanOutHelpers() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appState = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Models/AppState.swift"),
            encoding: .utf8
        )
        let apiClient = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Services/APIClient.swift"),
            encoding: .utf8
        )

        #expect(!appState.contains("func fetchUsageData()"))
        #expect(!appState.contains("func fetchUsageDataIfNeeded()"))
        #expect(!appState.contains("func fetchLeaderboard()"))
        #expect(!apiClient.contains("func fetchHourlyBuckets("))
    }

    @Test
    func nativeLeaderboardOmitsUnsupportedFiltersAndUsesRealSections() {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = (try? String(
            contentsOf: root.appendingPathComponent("VibeUsage/Views/LeaderboardView.swift"),
            encoding: .utf8
        )) ?? ""

        #expect(view.contains("今日消费排名"))
        #expect(view.contains("昨日消费排名"))
        #expect(view.contains("quotaDailyTop"))
        #expect(view.contains("quotaYesterdayTop"))
        #expect(view.contains("quotaTotalTop"))
        #expect(view.contains("usageSection(title: \"总排行\")"))
        #expect(!view.contains("累计榜"))
        #expect(view.contains("splitBoards(title: \"美金消耗\", rows: data.quotaDailyTop, firstCount: 5)"))
        #expect(view.contains("splitBoards(title: \"美金消耗\", rows: data.quotaYesterdayTop, firstCount: 10)"))
        #expect(view.contains("splitBoards(title: \"美金消耗\", rows: data.quotaTotalTop, firstCount: 10)"))
        #expect(!view.contains("data.tokenDailyTop"))
        #expect(!view.contains("data.tokenTotalTop"))
        #expect(!view.contains("24H"))
        #expect(!view.contains("7D"))
        #expect(!view.contains("30D"))
        #expect(!view.contains("分工具榜"))
        #expect(!view.contains("分模型榜"))
    }

    @Test
    func nativeLeaderboardShowsAllThreePersonalRanks() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/LeaderboardView.swift"),
            encoding: .utf8
        )

        #expect(view.contains("title: \"今日消费排名\""))
        #expect(view.contains("title: \"昨日消费排名\""))
        #expect(view.contains("title: \"总消费排名\""))
        #expect(view.contains("value: data.myTotalQuotaRank"))
        #expect(view.components(separatedBy: ".frame(width: 240)").count - 1 == 3)
    }

    @Test
    func nativeLeaderboardUsesAlignedTableColumns() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/LeaderboardView.swift"),
            encoding: .utf8
        )

        #expect(view.contains("private enum LeaderboardTableColumn"))
        #expect(view.contains("private var leaderboardColumns"))
        #expect(view.contains("private var leaderboardColumnHeader"))
        #expect(view.contains("case .rank: \"#\""))
        #expect(view.contains("case .user: \"用户\""))
        #expect(view.contains("case .tokens: \"Token\""))
        #expect(view.contains("case .cost: \"美金消耗\""))
        #expect(view.contains("splitBoards(title: \"美金消耗\""))
        #expect(!view.contains("预估消费"))
        #expect(!view.contains("预估费用"))
        #expect(view.contains("rows.contains(where: { $0.quota != nil })"))
        #expect(view.contains("return [.rank, .user, .tokens]"))
        #expect(view.components(separatedBy: ".frame(width: 240)").count - 1 == 3)
        #expect(view.contains("private let leaderboardRowHeight: CGFloat = 44"))
        #expect(view.components(separatedBy: ".frame(height: leaderboardRowHeight)").count - 1 >= 3)
        #expect(view.contains(".font(.system(size: 11, weight: .semibold, design: .monospaced))"))
        #expect(!view.contains(".background(AppTheme.subtleSurface.opacity(0.55))"))
        #expect(!view.contains("LeaderboardAvatar"))
    }

    @Test
    func sidebarNavigationUsesFullRowHitTargets() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shellSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/DashboardShellView.swift"),
            encoding: .utf8
        )

        #expect(shellSource.contains(".frame(maxWidth: .infinity, alignment: .leading)\n            .frame(height: 30)"))
        #expect(shellSource.contains(".contentShape(Rectangle())"))
        #expect(shellSource.contains(".buttonStyle(.plain)\n        .frame(maxWidth: .infinity)\n        .padding(.horizontal, 8)"))
    }

    @Test
    func heatmapUsesOneStableSquareSizeForEveryRow() {
        #expect(DashboardLayout.heatmapCellSize(for: 500) == 14)
        #expect(abs(DashboardLayout.heatmapCellSize(for: 280) - 6.4167) < 0.001)
    }

    @Test
    func dailyHeatmapPreservesTheTwentyFourColumnMatrix() {
        #expect(DashboardLayout.dailyHeatmapColumnCount(dataWeekCount: 6) == 24)
        #expect(DashboardLayout.dailyHeatmapColumnCount(dataWeekCount: 14) == 24)
        #expect(DashboardLayout.dailyHeatmapColumnCount(dataWeekCount: 30) == 30)
        #expect(DashboardLayout.dailyHeatmapLeadingColumnCount(dataWeekCount: 6) == 18)
        #expect(DashboardLayout.dailyHeatmapLeadingColumnCount(dataWeekCount: 14) == 10)
        #expect(DashboardLayout.dailyHeatmapLeadingColumnCount(dataWeekCount: 30) == 0)
    }

    @Test
    func dailyHeatmapHoverMapsTheTrackingRegionToItsCell() {
        let cellSize: CGFloat = 18

        #expect(DashboardLayout.dailyHeatmapCellTarget(
            at: CGPoint(x: 23, y: 1),
            cellSize: cellSize,
            columnCount: 24
        ) == DailyHeatmapCellTarget(row: 0, column: 0))

        #expect(DashboardLayout.dailyHeatmapCellTarget(
            at: CGPoint(x: 545, y: 149),
            cellSize: cellSize,
            columnCount: 24
        ) == DailyHeatmapCellTarget(row: 6, column: 23))

        #expect(DashboardLayout.dailyHeatmapCellTarget(
            at: CGPoint(x: 41, y: 8),
            cellSize: cellSize,
            columnCount: 24
        ) == nil)
    }

    @Test
    func monthlyHeatmapHoverMapsTheTwelveMonthMatrix() {
        let cellSize: CGFloat = 16

        #expect(DashboardLayout.monthlyHeatmapCellTarget(
            at: CGPoint(x: 40, y: 1),
            cellSize: cellSize,
            rowCount: 2
        ) == MonthlyHeatmapCellTarget(row: 0, column: 0))

        #expect(DashboardLayout.monthlyHeatmapCellTarget(
            at: CGPoint(x: 271, y: 24),
            cellSize: cellSize,
            rowCount: 2
        ) == MonthlyHeatmapCellTarget(row: 1, column: 11))

        #expect(DashboardLayout.monthlyHeatmapCellTarget(
            at: CGPoint(x: 56, y: 8),
            cellSize: cellSize,
            rowCount: 2
        ) == nil)
    }

    @Test
    func activityCardRendersTheDeclaredBucketGranularity() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/ActivityHeatmapView.swift"),
            encoding: .utf8
        )

        #expect(view.contains("appState.activityPresentation(for: metric)"))
        #expect(view.contains("case .hourly(let heatmap):"))
        #expect(view.contains("case .daily(let heatmap):"))
        #expect(view.contains("case .monthly(let heatmap):"))
        #expect(view.contains("DailyCalendarHeatmapGrid"))
        #expect(view.contains("MonthlyActivityHeatmapGrid"))
        let dailyView = view.components(separatedBy: "private struct DailyCalendarHeatmapGrid")[1]
            .components(separatedBy: "private struct MonthlyActivityHeatmapGrid")[0]
        #expect(dailyView.contains(".onContinuousHover"))
        #expect(dailyView.contains("dailyHeatmapCellTarget"))
        #expect(dailyView.contains("heatmap.monthLabel(forWeekIndex: weekIndex)"))
        #expect(!dailyView.contains("dayKey.hasSuffix(\"-01\")"))
        #expect(!dailyView.contains(".help(cellTooltip(cell))"))
        let monthlyView = view.components(separatedBy: "private struct MonthlyActivityHeatmapGrid")[1]
            .components(separatedBy: "private struct ActivityUnavailableView")[0]
        #expect(monthlyView.contains("heatmap.years"))
        #expect(monthlyView.contains("ScrollView(.vertical, showsIndicators: false)"))
        #expect(monthlyView.contains(".onContinuousHover"))
        #expect(monthlyView.contains("monthlyHeatmapCellTarget"))
        #expect(!monthlyView.contains(".help("))
        #expect(!view.contains("let heatmap = appState.activityHeatmap(for: metric)"))
    }

    @Test
    func heatmapHoverMapsOneTrackingRegionToTheCorrectCell() {
        let cellSize: CGFloat = 10

        #expect(DashboardLayout.heatmapCellTarget(
            at: CGPoint(x: 39, y: 5),
            cellSize: cellSize
        ) == HeatmapCellTarget(row: 0, hour: 0))

        #expect(DashboardLayout.heatmapCellTarget(
            at: CGPoint(x: 361, y: 107),
            cellSize: cellSize
        ) == HeatmapCellTarget(row: 6, hour: 23))
    }

    @Test
    func heatmapHoverIgnoresLabelsSpacingAndOutsidePoints() {
        let cellSize: CGFloat = 10

        #expect(DashboardLayout.heatmapCellTarget(
            at: CGPoint(x: 20, y: 5),
            cellSize: cellSize
        ) == nil)
        #expect(DashboardLayout.heatmapCellTarget(
            at: CGPoint(x: 46, y: 5),
            cellSize: cellSize
        ) == nil)
        #expect(DashboardLayout.heatmapCellTarget(
            at: CGPoint(x: 39, y: 13),
            cellSize: cellSize
        ) == nil)
        #expect(DashboardLayout.heatmapCellTarget(
            at: CGPoint(x: 376, y: 5),
            cellSize: cellSize
        ) == nil)
    }

    @Test
    func chartAxisKeepsDailyAndSampledTimeLabels() {
        #expect(DashboardLayout.visibleChartLabelIndices(count: 7, interval: 1) == Array(0..<7))
        #expect(DashboardLayout.visibleChartLabelIndices(count: 24, interval: 6) == [0, 6, 12, 18])
        #expect(DashboardLayout.chartAxisLabelWidth == 46)
    }

    @Test
    func openFilterPanelDoesNotChangeDashboardLayoutHeight() {
        #expect(DashboardLayout.filterContainerHeight(
            rowHeight: 28,
            panelHeight: nil,
            verticalGap: 6
        ) == 28)
        #expect(DashboardLayout.filterContainerHeight(
            rowHeight: 28,
            panelHeight: 260,
            verticalGap: 6
        ) == 28)
    }

    @Test
    func officialFilterPanelIsCenteredUnderItsButtonAndClampedToTheDashboard() {
        #expect(DashboardLayout.filterDropdownX(
            index: 0,
            buttonCount: 4,
            availableWidth: 1_000,
            gap: 8,
            panelWidth: 240
        ) == 2)
        #expect(DashboardLayout.filterDropdownX(
            index: 2,
            buttonCount: 4,
            availableWidth: 1_000,
            gap: 8,
            panelWidth: 240
        ) == 506)
        #expect(DashboardLayout.filterDropdownX(
            index: 2,
            buttonCount: 4,
            availableWidth: 200,
            gap: 8,
            panelWidth: 240
        ) == 0)
    }

    @Test
    func filterPanelIsHostedByTheDashboardViewportForReliableMouseHitTesting() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shellSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/DashboardShellView.swift"),
            encoding: .utf8
        )
        let filterSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/FilterTagsView.swift"),
            encoding: .utf8
        )

        #expect(shellSource.contains("overlayPreferenceValue(FilterButtonAnchorPreferenceKey.self)"))
        #expect(shellSource.contains("expandedModelFamilies: $expandedModelFamilies,\n                                height: panelFrame.height"))
        #expect(filterSource.contains("key: FilterButtonAnchorPreferenceKey.self"))
        #expect(!filterSource.contains("if let openFilter {\n                    filterPanel(for: openFilter)"))
    }

    @Test
    func filterSelectionColorIsConfinedToTheCheckbox() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let filterSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/FilterTagsView.swift"),
            encoding: .utf8
        )

        #expect(filterSource.contains(".fill(isSelected || isMixed ? AppTheme.primaryText : Color.clear)"))
        #expect(!filterSource.contains(".background(isSelected || isMixed ? AppTheme.selectionBackground : Color.clear)"))
    }

    @Test
    func mainDashboardHidesVerticalScrollIndicator() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shellSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/DashboardShellView.swift"),
            encoding: .utf8
        )

        #expect(shellSource.contains("ScrollView(.vertical, showsIndicators: false)"))
        #expect(!shellSource.contains("ScrollView(.vertical, showsIndicators: true)"))
    }

    @Test
    func settingsPageHidesVerticalScrollIndicator() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let settingsSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/SettingsView.swift"),
            encoding: .utf8
        )

        #expect(settingsSource.contains(".scrollIndicators(.hidden)"))
        #expect(settingsSource.contains(".background(SettingsScrollIndicatorHider())"))
        #expect(settingsSource.contains("scrollView.hasVerticalScroller = false"))
        #expect(settingsSource.contains("scrollView.verticalScroller?.isHidden = true"))
    }

    @Test
    func filterOverlayPlacementKeepsTheWholeInteractivePanelInsideTheViewport() {
        let below = DashboardLayout.filterOverlayFrame(
            buttonFrame: CGRect(x: 500, y: 110, width: 250, height: 28),
            panelSize: CGSize(width: 240, height: 260),
            viewportSize: CGSize(width: 1_000, height: 700)
        )
        #expect(below == CGRect(x: 505, y: 144, width: 240, height: 260))
        #expect(below.contains(CGPoint(x: 625, y: 390)))

        let above = DashboardLayout.filterOverlayFrame(
            buttonFrame: CGRect(x: 500, y: 620, width: 250, height: 28),
            panelSize: CGSize(width: 240, height: 260),
            viewportSize: CGSize(width: 1_000, height: 700)
        )
        #expect(above == CGRect(x: 505, y: 354, width: 240, height: 260))

        let compact = DashboardLayout.filterOverlayFrame(
            buttonFrame: CGRect(x: 100, y: 20, width: 180, height: 28),
            panelSize: CGSize(width: 240, height: 260),
            viewportSize: CGSize(width: 320, height: 120)
        )
        #expect(compact == CGRect(x: 70, y: 4, width: 240, height: 112))
    }

    @Test
    func filterOutsideClickDismissalExcludesPanelAndFilterButtons() {
        let protectedFrames = [
            CGRect(x: 100, y: 40, width: 180, height: 28),
            CGRect(x: 70, y: 74, width: 240, height: 260),
        ]

        #expect(!DashboardLayout.shouldDismissFilter(
            at: CGPoint(x: 150, y: 54),
            protectedFrames: protectedFrames
        ))
        #expect(!DashboardLayout.shouldDismissFilter(
            at: CGPoint(x: 200, y: 180),
            protectedFrames: protectedFrames
        ))
        #expect(DashboardLayout.shouldDismissFilter(
            at: CGPoint(x: 20, y: 400),
            protectedFrames: protectedFrames
        ))
    }

    @Test
    func dashboardInstallsPassthroughFilterOutsideClickMonitor() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let shellSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/DashboardShellView.swift"),
            encoding: .utf8
        )

        #expect(shellSource.contains("NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)"))
        #expect(shellSource.contains("DashboardLayout.shouldDismissFilter("))
        #expect(shellSource.contains("return event"))
        #expect(shellSource.contains("openFilter = nil"))
    }

    @Test
    func detailedRecordsUseEightRequestColumns() throws {
        #expect(DashboardLayout.recordColumnTitles == [
            "日期", "模型", "推理强度", "首字", "输入 TOKEN", "输出 TOKEN", "缓存 TOKEN", "预估费用",
        ])
        #expect(DashboardLayout.recordMinimumTableWidth == 860)
        #expect(DashboardLayout.recordTableHorizontalInset == 20)

        let compactWidths = DashboardLayout.recordColumnWidths(for: 760)
        #expect(compactWidths.count == 8)
        #expect(abs(compactWidths.reduce(0, +) - 820) < 0.001)

        let wideContentWidth = 1_200 - DashboardLayout.recordTableHorizontalInset * 2
        let wideWidths = DashboardLayout.recordColumnWidths(for: wideContentWidth)
        #expect(abs(wideWidths.reduce(0, +) - wideContentWidth) < 0.001)
        #expect(wideWidths[0] > compactWidths[0])
        #expect(wideWidths.last! > compactWidths.last!)
        #expect(wideWidths[1] + wideWidths[2] < 280)

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let view = try String(
            contentsOf: repositoryRoot.appendingPathComponent("VibeUsage/Views/UsageRecordsView.swift"),
            encoding: .utf8
        )
        #expect(!view.contains("终端"))
        #expect(!view.contains("工具"))
        #expect(view.contains("推理强度"))
        #expect(view.contains("首字"))
        #expect(view.contains(
            "headerCell(\"推理强度\", width: widths[2], alignment: .leading)"
        ))
        #expect(view.contains(
            "valueCell(row.reasoningEffort, width: widths[2], alignment: .leading)"
        ))
        #expect(
            view.components(
                separatedBy: ".padding(.horizontal, DashboardLayout.recordTableHorizontalInset)"
            ).count == 3
        )
        let firstResponseCell = view.components(separatedBy: "private func firstResponseBadge")[1]
            .components(separatedBy: "private func firstResponseForeground")[0]
        #expect(firstResponseCell.contains(".foregroundStyle(firstResponseForeground"))
        #expect(!firstResponseCell.contains(".background("))
        #expect(!firstResponseCell.contains(".clipShape("))
        #expect(!firstResponseCell.contains(".padding(.vertical"))
    }
}
