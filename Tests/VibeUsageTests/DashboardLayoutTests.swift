import Testing
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
}
