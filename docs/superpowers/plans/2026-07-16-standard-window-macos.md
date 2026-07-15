# Standard Window macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the transient Vibe Usage menu-bar popover with a persistent standard macOS main window while keeping the menu-bar status item and background synchronization.

**Architecture:** Add a reusable `MainWindowController` that owns a standard `NSWindow` and hosts the existing SwiftUI dashboard. Reduce `MenuBarController` to status-item rendering plus a window-toggle action, route Dock/Cmd-Tab lifecycle events to the main window, and remove popover-only activation and settings behavior.

**Tech Stack:** Swift 6, SwiftUI, AppKit, Swift Package Manager, Swift Testing, Sparkle retained but disabled for the custom build.

---

### Task 1: Specify the standard window contract with failing tests

**Files:**
- Create: `Tests/VibeUsageTests/MainWindowControllerTests.swift`

- [ ] **Step 1: Write the failing configuration and lifecycle tests**

```swift
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
```

- [ ] **Step 2: Run the focused test and confirm RED**

Run: `./scripts/test.sh --filter MainWindowControllerTests`

Expected: compilation fails because `MainWindowController` does not exist.

- [ ] **Step 3: Commit the failing test**

```bash
git add Tests/VibeUsageTests/MainWindowControllerTests.swift
git commit -m "test: define standard macOS window behavior"
```

### Task 2: Implement the standard main window

**Files:**
- Create: `VibeUsage/Services/MainWindowController.swift`
- Test: `Tests/VibeUsageTests/MainWindowControllerTests.swift`

- [ ] **Step 1: Add the tested window configuration and controller**

```swift
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
        window.contentViewController = NSHostingController(rootView: rootView)
        window.contentMinSize = configuration.minimumContentSize
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !window.setFrameUsingName(configuration.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(configuration.frameAutosaveName)
        self.window = window
        return window
    }

    func show() {
        let window = makeWindowIfNeeded()
        if window.isMiniaturized { window.deminiaturize(nil) }
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
```

- [ ] **Step 2: Run the focused test and confirm GREEN**

Run: `./scripts/test.sh --filter MainWindowControllerTests`

Expected: 2 tests pass.

- [ ] **Step 3: Run the complete test suite**

Run: `./scripts/test.sh`

Expected: all existing and new tests pass with zero failures.

- [ ] **Step 4: Commit the controller**

```bash
git add VibeUsage/Services/MainWindowController.swift
git commit -m "feat: add persistent standard main window"
```

### Task 3: Route menu-bar and application lifecycle events to the main window

**Files:**
- Modify: `VibeUsage/Services/MenuBarController.swift`
- Modify: `VibeUsage/App/VibeUsageApp.swift`
- Modify: `VibeUsage/Services/ActivationCoordinator.swift`
- Modify: `VibeUsage/Models/AppState.swift`

- [ ] **Step 1: Reduce `MenuBarController` to a status item and toggle closure**

Keep `MenuBarLabel`, `PassthroughHostingView`, status-item sizing, and menu-bar
statistics. Replace all panel state and lifecycle code with:

```swift
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

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        onToggleWindow()
    }
}
```

Delete `PopoverPanel` ownership, animation code, screen positioning, global
event monitors, ESC dismissal, screenshot dismissal, and popup activation
methods.

- [ ] **Step 2: Make the app delegate own and present the standard window**

Use a single `AppState`, create `MainWindowController`, pass its `toggle()` to
`MenuBarController`, open the main window after launch, reopen on Dock/Cmd-Tab,
and remove all deactivation dismissal:

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private var mainWindowController: MainWindowController?
    private var menuBarController: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ActivationCoordinator.shared.applyStandardApplicationPolicy()
        appState.initialize()

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
```

- [ ] **Step 3: Simplify activation policy for a standard client**

Keep the settings/update visibility flags and
`canPresentDashboardForAppActivation`. Replace the Dock preference machinery
with `applyStandardApplicationPolicy()`, which always applies `.regular` and
the bundled icon. Remove popup callbacks and deactivation dismissal policy.

- [ ] **Step 4: Remove the obsolete `showInDock` preference from `AppState`**

Delete the `showInDock` stored property and its initialization assignment.
Menu-bar cost and Token preferences remain unchanged.

- [ ] **Step 5: Run tests and build**

Run: `./scripts/test.sh && swift build`

Expected: all tests pass and the executable builds successfully.

- [ ] **Step 6: Commit lifecycle integration**

```bash
git add VibeUsage/App/VibeUsageApp.swift VibeUsage/Models/AppState.swift VibeUsage/Services/ActivationCoordinator.swift VibeUsage/Services/MenuBarController.swift
git commit -m "feat: open dashboard through standard window lifecycle"
```

### Task 4: Adapt dashboard and settings to the standard-window shell

**Files:**
- Modify: `VibeUsage/Views/PopoverView.swift`
- Modify: `VibeUsage/Views/SettingsView.swift`
- Modify: `VibeUsage/Services/SettingsWindowController.swift`

- [ ] **Step 1: Make the dashboard fill the main window**

Remove the fixed `.frame(width: 520)` and replace it with:

```swift
.frame(maxWidth: .infinity, maxHeight: .infinity)
.background(Color(white: 0.04))
```

Remove `UpdaterViewModel` from the environment, delete the “发现更新” badge,
change Settings presentation to `SettingsWindowController.shared.show(appState:
appState)`, and rename the footer quit action from “关闭” to “退出”.

- [ ] **Step 2: Remove popover-only settings**

Delete `UpdaterViewModel` from `SettingsView`, remove the “在 Dock 中显示”
toggle, keep “开机自启动”, keep the version row, and remove the “检查更新”
button.

- [ ] **Step 3: Simplify `SettingsWindowController.show`**

Change the signature to `show(appState: AppState)` and host:

```swift
let settingsView = SettingsView().environment(appState)
```

- [ ] **Step 4: Verify source no longer references removed UI state**

Run:

```bash
rg 'showInDock|updaterViewModel|presentPanel|dismissPanel|PopoverPanel' VibeUsage/App VibeUsage/Models VibeUsage/Services/MenuBarController.swift VibeUsage/Services/SettingsWindowController.swift VibeUsage/Views/PopoverView.swift VibeUsage/Views/SettingsView.swift
```

Expected: no matches in the listed standard-window surfaces.

- [ ] **Step 5: Run tests and build**

Run: `./scripts/test.sh && swift build`

Expected: all tests pass and the executable builds successfully.

- [ ] **Step 6: Commit the responsive dashboard changes**

```bash
git add VibeUsage/Services/SettingsWindowController.swift VibeUsage/Views/PopoverView.swift VibeUsage/Views/SettingsView.swift
git commit -m "feat: adapt dashboard for resizable main window"
```

### Task 5: Protect and package the custom application

**Files:**
- Modify: `VibeUsage/Info.plist`
- Modify: `VibeUsage/Models/AppConfig.swift`
- Modify: `scripts/build-app.sh`

- [ ] **Step 1: Set custom build identity and standard-app metadata**

Apply these values:

```text
CFBundleIdentifier = com.codsexradar.vibe-usage
CFBundleShortVersionString = 0.6.0
CFBundleVersion = 25
LSUIElement = false
SUEnableAutomaticChecks = false
```

Remove `SUFeedURL` so the custom build cannot install the official popover
release. Set `AppConfig.version` to `0.6.0` and the build-script `BUNDLE_ID` to
`com.codsexradar.vibe-usage`.

- [ ] **Step 2: Validate version and plist values**

Run:

```bash
./scripts/check-version.sh
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' VibeUsage/Info.plist)" = "com.codsexradar.vibe-usage"
test "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' VibeUsage/Info.plist)" = "false"
test "$(/usr/libexec/PlistBuddy -c 'Print :SUEnableAutomaticChecks' VibeUsage/Info.plist)" = "false"
! /usr/libexec/PlistBuddy -c 'Print :SUFeedURL' VibeUsage/Info.plist
```

Expected: version check succeeds; all shell assertions exit zero; the final
PlistBuddy lookup reports the key is absent.

- [ ] **Step 3: Run full tests and build the app bundle**

Run: `./scripts/test.sh && ./scripts/build-app.sh`

Expected: all tests pass and `dist/Vibe Usage.app` is produced with an ad-hoc
signature when the upstream Developer ID is unavailable.

- [ ] **Step 4: Verify the built bundle**

Run:

```bash
codesign --verify --deep --strict 'dist/Vibe Usage.app'
test "$(defaults read "$PWD/dist/Vibe Usage.app/Contents/Info" CFBundleIdentifier)" = "com.codsexradar.vibe-usage"
```

Expected: signature verification and bundle identifier assertion both pass.

- [ ] **Step 5: Commit packaging metadata**

```bash
git add VibeUsage/Info.plist VibeUsage/Models/AppConfig.swift scripts/build-app.sh
git commit -m "build: identify and protect custom macOS client"
```

### Task 6: Install and verify the finished Mac application

**Files:**
- Verify: `dist/Vibe Usage.app`
- Install: `/Applications/Vibe Usage.app`

- [ ] **Step 1: Install the verified app bundle**

Run:

```bash
pkill -x VibeUsage 2>/dev/null || true
rm -rf '/Applications/Vibe Usage.app'
cp -R 'dist/Vibe Usage.app' '/Applications/Vibe Usage.app'
open '/Applications/Vibe Usage.app'
```

Expected: the custom app process starts from `/Applications`.

- [ ] **Step 2: Verify process, bundle, and standard-window metadata**

Run:

```bash
pgrep -fl '/Applications/Vibe Usage.app/Contents/MacOS/VibeUsage'
codesign --verify --deep --strict '/Applications/Vibe Usage.app'
defaults read '/Applications/Vibe Usage.app/Contents/Info' CFBundleIdentifier
```

Expected: the process is running, signature verification passes, and the bundle
identifier is `com.codsexradar.vibe-usage`.

- [ ] **Step 3: Capture and inspect the installed window**

Use `CGWindowListCopyWindowInfo` to locate the on-screen `Vibe Usage` window,
record its bounds, capture it with `screencapture -l <window-number>`, and inspect
the image. Expected bounds are at least 760 x 560 with a standard title bar.

- [ ] **Step 4: Exercise the acceptance flow**

Verify that moving and resizing update the window bounds; minimizing and
restoring preserve the process; activating another application leaves the
window on screen; closing hides it without terminating; clicking the menu-bar
item or Dock icon restores the same window; Cmd-Q terminates the process.

- [ ] **Step 5: Run final repository verification**

Run:

```bash
./scripts/test.sh
./scripts/check-version.sh
git diff --check
git status --short --branch
```

Expected: all tests pass, version metadata is consistent, no whitespace errors
exist, and only intentional committed changes remain.
