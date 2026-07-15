import AppKit

/// Tracks modal surfaces and applies the fixed activation policy required by a
/// standard macOS client.
@MainActor
final class ActivationCoordinator {
    static let shared = ActivationCoordinator()

    private var settingsVisible = false
    private var updateModalVisible = false
    private lazy var dockIcon: NSImage? = loadDockIcon()

    private init() {}

    func settingsDidOpen() {
        settingsVisible = true
    }

    func settingsDidClose() {
        settingsVisible = false
    }

    func updateModalVisibilityDidChange(_ visible: Bool) {
        updateModalVisible = visible
    }

    var canPresentDashboardForAppActivation: Bool {
        !settingsVisible && !updateModalVisible
    }

    func applyStandardApplicationPolicy() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.applicationIconImage = dockIcon
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
