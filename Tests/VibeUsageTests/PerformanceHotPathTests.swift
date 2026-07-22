import Foundation
import Testing
@testable import VibeUsage

struct PerformanceHotPathTests {
    @Test
    func singleEntryMemoizerBuildsOnlyWhenItsKeyChanges() {
        let memoizer = SingleEntryMemoizer<Int, String>()
        var builds = 0

        let first = memoizer.value(for: 1) {
            builds += 1
            return "one"
        }
        let repeated = memoizer.value(for: 1) {
            builds += 1
            return "rebuilt"
        }

        #expect(first == "one")
        #expect(repeated == "one")
        #expect(builds == 1)

        let changed = memoizer.value(for: 2) {
            builds += 1
            return "two"
        }
        #expect(changed == "two")
        #expect(builds == 2)

        memoizer.removeAll()
        _ = memoizer.value(for: 2) {
            builds += 1
            return "two again"
        }
        #expect(builds == 3)
    }

    @Test
    func dashboardHotPathsDoNotAllocateFormattersOrRepeatDerivedWork() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let parser = try source("VibeUsage/Utils/ISO8601Parser.swift", under: repositoryRoot)
        let formatters = try source("VibeUsage/Utils/Formatters.swift", under: repositoryRoot)
        let appState = try source("VibeUsage/Models/AppState.swift", under: repositoryRoot)
        let shell = try source("VibeUsage/Views/DashboardShellView.swift", under: repositoryRoot)
        let barChart = try source("VibeUsage/Views/BarChartView.swift", under: repositoryRoot)
        let records = try source("VibeUsage/Views/UsageRecordsView.swift", under: repositoryRoot)

        #expect(!parser.contains("ISO8601DateFormatter()"))
        #expect(!formatters.contains("DateFormatter()"))
        #expect(appState.contains("dashboardDataMemoizer.value"))
        #expect(appState.contains("activityHeatmapMemoizer.value"))
        #expect(shell.contains("LazyVStack(alignment: .leading, spacing: DashboardLayout.contentSpacing)"))
        #expect(shell.contains("DashboardPairLayout("))
        #expect(!shell.contains("ViewThatFits(in: .horizontal)"))
        #expect(barChart.contains("let data = chartData"))
        #expect(records.contains("appState.dashboardData.recentRows"))
        #expect(records.contains("LazyVStack(spacing: 0)"))
    }

    @Test
    func accountPagesHaveNoPollingOrSensitiveRequestLogging() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let paths = [
            "VibeUsage/Views/TokenManagementView.swift",
            "VibeUsage/Views/WalletManagementView.swift",
            "VibeUsage/Views/SubscriptionPurchaseSheet.swift",
            "VibeUsage/Views/PaymentQRCodeSheet.swift",
            "VibeUsage/Views/ActivityCenterView.swift",
            "VibeUsage/Models/TokenManagementStore.swift",
            "VibeUsage/Models/WalletManagementStore.swift",
        ]
        let combined = try paths.map { try source($0, under: repositoryRoot) }.joined()
        let apiClient = try source("VibeUsage/Services/APIClient.swift", under: repositoryRoot)
        let accountClient = try source(
            "VibeUsage/Services/AccountManagementClient.swift",
            under: repositoryRoot
        )

        #expect(!combined.contains("Timer.publish"))
        #expect(!combined.contains("Task.sleep"))
        #expect(!combined.contains("while true"))
        #expect(!accountClient.contains("debugLog"))
        #expect(!apiClient.contains("request.url?.absoluteString"))
        #expect(apiClient.contains("request.url?.path"))
    }

    private func source(_ path: String, under root: URL) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
