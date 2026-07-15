import AppKit
import Observation
import SwiftUI

/// SwiftUI view rendered inside the NSStatusItem button.
private struct MenuBarLabel: View {
    let icon: NSImage
    let lines: [String]

    var body: some View {
        HStack(spacing: 7) {
            Image(nsImage: icon)
                .renderingMode(.template)

            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: lines.count > 1 ? -2 : 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: lines.count == 1 ? 13 : 10, weight: .medium, design: .monospaced))
                    }
                }
                .fixedSize()
            }
        }
        .foregroundColor(.primary)
        .padding(.horizontal, 4)
        .fixedSize()
    }
}

/// Passes mouse events through to the NSStatusBarButton so target-action fires.
private final class PassthroughHostingView<V: View>: NSHostingView<V> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { superview?.mouseUp(with: event) }
}

/// Owns the persistent menu-bar status item. Dashboard presentation belongs to
/// MainWindowController; the status item only forwards its click action.
@MainActor
final class MenuBarController: NSObject {
    private let appState: AppState
    private let onToggleWindow: () -> Void
    private let statusItem: NSStatusItem
    private var hostingView: PassthroughHostingView<MenuBarLabel>!

    init(appState: AppState, onToggleWindow: @escaping () -> Void) {
        self.appState = appState
        self.onToggleWindow = onToggleWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        observeStateChanges()
    }

    private static let iconSize = NSSize(width: 18, height: 18)

    private static let iconRaw: NSImage = {
        if let url = Bundle.appResources.url(forResource: "menubar-icon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = iconSize
            image.isTemplate = true
            return image
        }

        let fallback = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: nil)!
        fallback.size = iconSize
        fallback.isTemplate = true
        return fallback
    }()

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.title = ""
        button.image = nil
        button.target = self
        button.action = #selector(handleClick(_:))
        button.toolTip = "打开或隐藏 Vibe Usage"

        let host = PassthroughHostingView(rootView: MenuBarLabel(icon: Self.iconRaw, lines: []))
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            host.topAnchor.constraint(equalTo: button.topAnchor),
            host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        hostingView = host
    }

    private func observeStateChanges() {
        withObservationTracking {
            refreshStatusItem()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeStateChanges() }
        }
    }

    private func refreshStatusItem() {
        guard hostingView != nil else { return }
        hostingView.rootView = MenuBarLabel(icon: Self.iconRaw, lines: menuBarLines())
        hostingView.layoutSubtreeIfNeeded()
        let width = hostingView.fittingSize.width
        statusItem.length = width > 0 ? width : NSStatusItem.variableLength
    }

    private func menuBarLines() -> [String] {
        guard appState.isConfigured, !appState.buckets.isEmpty else { return [] }

        var lines: [String] = []
        if appState.showCostInMenuBar {
            lines.append(Formatters.formatCost(appState.menuBarCost))
        }
        if appState.showTokensInMenuBar {
            lines.append(Formatters.formatNumber(appState.menuBarTokens))
        }
        return lines
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        onToggleWindow()
    }
}
