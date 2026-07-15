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
        #expect(window.contentRect(forFrameRect: window.frame).size == NSSize(width: 960, height: 720))
        #expect(window.contentMinSize == NSSize(width: 760, height: 560))
        #expect(window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.closable))
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.collectionBehavior.contains(.fullScreenPrimary))
        #expect(window.isReleasedWhenClosed == false)
        #expect(window.appearance?.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
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
}
