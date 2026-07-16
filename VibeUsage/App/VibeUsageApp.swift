import SwiftUI
import AppKit

@main
struct VibeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // AppDelegate owns the standard main window and menu-bar status item.
        // AppDelegate owns the standard window; settings is shown inside its sidebar shell.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var mainWindowController: MainWindowController?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ActivationCoordinator.shared.applyStandardApplicationPolicy()
        appState.initialize()

        Task {
            await appState.restoreSession()
        }

        let mainWindowController = MainWindowController(appState: appState)
        self.mainWindowController = mainWindowController
        menuBarController = MenuBarController(appState: appState) { [weak mainWindowController] in
            mainWindowController?.toggle()
        }
        mainWindowController.show()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard ActivationCoordinator.shared.canPresentDashboardForAppActivation else { return }
        mainWindowController?.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindowController?.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
