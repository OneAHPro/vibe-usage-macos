import AppKit
import SwiftUI

struct MainWindowConfiguration {
    static let standard = MainWindowConfiguration(
        title: "Vibe Usage",
        defaultContentSize: NSSize(width: 960, height: 720),
        minimumContentSize: NSSize(width: 760, height: 560),
        frameAutosaveName: "VibeUsageMainWindow"
    )

    let title: String
    let defaultContentSize: NSSize
    let minimumContentSize: NSSize
    let frameAutosaveName: String
}

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let rootView: AnyView
    private let configuration: MainWindowConfiguration
    private let onPresent: () -> Void
    private var window: NSWindow?

    init<Content: View>(
        rootView: Content,
        configuration: MainWindowConfiguration = .standard,
        onPresent: @escaping () -> Void = {}
    ) {
        self.rootView = AnyView(rootView)
        self.configuration = configuration
        self.onPresent = onPresent
        super.init()
    }

    convenience init(appState: AppState) {
        self.init(rootView: PopoverView().environment(appState)) {
            Task { await appState.fetchUsageDataIfNeeded() }
            Task { await appState.refreshCodexRateLimitIfNeeded() }
            Task { await appState.refreshClaudeRateLimitIfNeeded() }
        }
    }

    func makeWindowIfNeeded() -> NSWindow {
        if let window { return window }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: configuration.defaultContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = configuration.title
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentViewController = NSHostingController(rootView: rootView)
        window.contentMinSize = configuration.minimumContentSize
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let restoredFrame = window.setFrameUsingName(configuration.frameAutosaveName)
        let restoredContentSize = window.contentRect(forFrameRect: window.frame).size
        let restoredSizeIsUsable = restoredContentSize.width >= configuration.minimumContentSize.width
            && restoredContentSize.height >= configuration.minimumContentSize.height
        if !restoredFrame || !restoredSizeIsUsable {
            window.setContentSize(configuration.defaultContentSize)
            window.center()
        }
        window.setFrameAutosaveName(configuration.frameAutosaveName)

        self.window = window
        return window
    }

    func show() {
        let window = makeWindowIfNeeded()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        onPresent()
    }

    func toggle() {
        guard let window else {
            show()
            return
        }

        if window.isVisible && !window.isMiniaturized {
            window.orderOut(nil)
        } else {
            show()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
