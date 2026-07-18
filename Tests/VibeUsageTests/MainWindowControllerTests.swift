import AppKit
import SwiftUI
import Testing
@testable import VibeUsage

@Suite(.serialized)
@MainActor
struct MainWindowControllerTests {
    @Test
    func createsAStandardResizableMacWindow() {
        let controller = MainWindowController(rootView: EmptyView())
        let window = controller.makeWindowIfNeeded()

        #expect(window.title == "Vibe Usage")
        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 1280, height: 820))
        #expect(window.contentMinSize == NSSize(width: 1024, height: 680))
        #expect(MainWindowConfiguration.standard.frameAutosaveName == "VibeUsageDashboardWindowV3")
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(window.isReleasedWhenClosed == false)
        #expect(window.appearance == nil)
    }

    @Test
    func userCloseHidesTheWindowWithoutDestroyingIt() {
        let controller = MainWindowController(rootView: EmptyView())
        let window = controller.makeWindowIfNeeded()
        window.orderFrontRegardless()

        #expect(window.isVisible)
        #expect(controller.windowShouldClose(window) == false)
        #expect(window.isVisible == false)
        #expect(controller.makeWindowIfNeeded() === window)
    }

    @Test
    func reportsShowHideMinimizeAndRestoreVisibility() {
        var visibility: [Bool] = []
        let controller = MainWindowController(
            rootView: EmptyView(),
            onVisibilityChange: { visibility.append($0) }
        )
        let window = controller.makeWindowIfNeeded()

        controller.show()
        controller.windowDidMiniaturize(
            Notification(name: NSWindow.didMiniaturizeNotification, object: window)
        )
        controller.windowDidDeminiaturize(
            Notification(name: NSWindow.didDeminiaturizeNotification, object: window)
        )
        _ = controller.windowShouldClose(window)

        #expect(visibility == [true, false, true, false])
    }
}
