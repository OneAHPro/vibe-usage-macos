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
    func sidebarPagesProvideInlineNavigationTitles() {
        #expect(DashboardPage.usage.title == "Vibe Usage")
        #expect(DashboardPage.settings.title == "设置")
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
    func detailRecordsOmitTheProjectColumn() {
        #expect(DashboardLayout.recordColumnTitles == [
            "日期", "终端", "工具", "模型", "输入 TOKEN", "输出 TOKEN", "缓存 TOKEN", "预估费用",
        ])
        #expect(DashboardLayout.recordMinimumTableWidth == 950)
        #expect(DashboardLayout.recordEdgeInset == 16)

        let compactWidths = DashboardLayout.recordColumnWidths(for: 760)
        #expect(abs(compactWidths.reduce(0, +) - 950) < 0.001)

        let wideWidths = DashboardLayout.recordColumnWidths(for: 1_200)
        #expect(abs(wideWidths.reduce(0, +) - 1_200) < 0.001)
        #expect(wideWidths[3] == compactWidths[3])
        #expect(wideWidths[4] == compactWidths[4])
        #expect(wideWidths[0] > compactWidths[0])
        #expect(wideWidths.last! > compactWidths.last!)
    }
}
