import SwiftUI
import AppKit

@main
struct VibeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // AppDelegate owns the menu bar status item and popover panel.
        // The Settings scene placeholder satisfies the App protocol; Settings itself
        // is still presented through SettingsWindowController.
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let updaterViewModel = UpdaterViewModel()
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.initialize()
        ActivationCoordinator.shared.configure(with: appState)
        configureDockPresentation()
        menuBarController = MenuBarController(appState: appState, updaterViewModel: updaterViewModel)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarController?.presentPanel()
        return true
    }

    private func configureDockPresentation() {
        let showInDock = appState.showInDock
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }

        if showInDock, let image = loadDockIcon() {
            NSApp.applicationIconImage = image
        }
    }

    private func loadDockIcon() -> NSImage? {
        let appIconPath = "Assets.xcassets/AppIcon.appiconset/icon_512x512"
        if let url = Bundle.appResources.url(forResource: appIconPath, withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 128, height: 128)
            return image
        }

        if let image = NSImage(named: "AppIcon") {
            return image
        }

        if let url = Bundle.appResources.url(forResource: "menubar-icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 128, height: 128)
            return image
        }

        return nil
    }
}
